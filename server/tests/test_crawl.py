"""内容采集（爬虫）服务测试：

- RSS/Atom 解析、日期/时长、无 enclosure 单集过滤、语言归一；
- DTD/ENTITY 安全拒绝；
- 订阅源 CRUD 与管理鉴权；
- 抓取去重（未变不新增 / pending 原地刷新 / 已审批后更新产生新待办）；
- 审批导入发布、二次审批只补新增单集；驳回与状态保护；
- 单次抓取 /fetch、非法 URL 400、抓取失败 502。

网络被完全隔离：crawler.fetch_url 在测试内替换为本地 XML。
直跑：.tools\\venvs\\mll\\Scripts\\python.exe server\\tests\\test_crawl.py
"""
from __future__ import annotations

from harness import ADMIN_HEADERS, fresh_client, run_module

from app.services import crawler

RSS_BYTES = b"""<?xml version='1.0' encoding='UTF-8'?>
<rss xmlns:itunes='http://www.itunes.com/dtds/podcast-1.0.dtd' version='2.0'>
<channel>
<title>Smoke Spanish</title>
<itunes:author>Radio Humo</itunes:author>
<language>es-MX</language>
<itunes:image href='https://example.test/cover.jpg'/>
<description>Aprende esanlol</description>
<item>
  <title>Episodio uno</title><guid>ep1</guid>
  <pubDate>Tue, 01 Sep 2026 08:00:00 GMT</pubDate>
  <itunes:duration>10:30</itunes:duration>
  <enclosure url='https://cdn.example.test/e1.mp3' type='audio/mpeg' length='100'/>
</item>
<item>
  <title>Episodio dos</title><guid>ep2</guid>
  <pubDate>Mon, 25 Aug 2026 08:00:00 GMT</pubDate>
  <itunes:duration>1234</itunes:duration>
  <enclosure url='https://cdn.example.test/e2.m4a' type='audio/x-m4a'/>
</item>
<item><title>no audio skip me</title></item>
</channel></rss>"""

ATOM_BYTES = b"""<?xml version='1.0' encoding='UTF-8'?>
<feed xmlns='http://www.w3.org/2005/Atom' xml:lang='fr'>
<title>Le Journal Lent</title>
<author><name>Studio Lent</name></author>
<logo>https://example.test/logo.png</logo>
<subtitle>actualites francaises</subtitle>
<entry>
  <id>tag:example.test,2026:1</id>
  <title>Entree un</title>
  <published>2026-09-02T08:00:00Z</published>
  <link rel='enclosure' type='audio/mpeg' href='https://cdn.example.test/f1.mp3'/>
</entry>
</feed>"""

FEED_URL = "https://example.test/feed.xml"
BASE = "/api/v1/admin/crawl"


# ---------------------------------------------------------------------------
# 纯解析单元测试
# ---------------------------------------------------------------------------

def test_parse_rss_fields():
    p = crawler.parse_feed(RSS_BYTES, FEED_URL)
    assert p["title"] == "Smoke Spanish"
    assert p["author"] == "Radio Humo"
    assert p["language"] == "es"
    assert p["artwork_url"] == "https://example.test/cover.jpg"
    assert len(p["episodes"]) == 2  # 无 enclosure 的单集被过滤
    first = p["episodes"][0]
    assert first["pubDate"] == "2026-09-01"
    assert first["durationMs"] == 630_000  # 10:30
    assert p["episodes"][1]["durationMs"] == 1_234_000
    assert len(p["content_hash"]) == 40


def test_parse_atom_fields():
    p = crawler.parse_feed(ATOM_BYTES, "https://example.test/atom.xml")
    assert p["title"] == "Le Journal Lent"
    assert p["author"] == "Studio Lent"
    assert p["language"] == "fr"
    assert p["artwork_url"] == "https://example.test/logo.png"
    assert len(p["episodes"]) == 1
    ep = p["episodes"][0]
    assert ep["audioUrl"] == "https://cdn.example.test/f1.mp3"
    assert ep["pubDate"] == "2026-09-02"


def test_reject_dtd_and_garbage():
    dtd = (b'<?xml version="1.0"?><!DOCTYPE rss [<!ENTITY x "y">]>'
           b'<rss version="2.0"><channel><title>x</title></channel></rss>')
    try:
        crawler.parse_feed(dtd, FEED_URL)
        raise AssertionError("DTD 文档必须被拒绝")
    except crawler.CrawlError:
        pass
    try:
        crawler.parse_feed(b"<html>not a feed</html>", FEED_URL)
        raise AssertionError("非 RSS/Atom 文档必须报错")
    except crawler.CrawlError:
        pass
    try:
        crawler.validate_url("ftp://example.test/feed")
        raise AssertionError("非 http(s) URL 必须拒绝")
    except crawler.CrawlError:
        pass


def test_ingest_dedup_states():
    with fresh_client():
        cand, created = crawler.ingest_content(FEED_URL, RSS_BYTES, None)
        assert created is True and cand["status"] == "pending"
        # 内容未变：无新条目
        _, created2 = crawler.ingest_content(FEED_URL, RSS_BYTES, None)
        assert created2 is False
        # 仍是 pending：原地刷新（不新增）
        changed = RSS_BYTES.replace(b"<description>",
                                    b"<description>updated ")
        cand3, created3 = crawler.ingest_content(FEED_URL, changed, None)
        assert created3 is False and "updated" in cand3["description"]


# ---------------------------------------------------------------------------
# API：鉴权 / 源管理 / 抓取 / 审批
# ---------------------------------------------------------------------------

def test_admin_auth_required():
    with fresh_client() as (client, _dir):
        assert client.get(f"{BASE}/sources").status_code == 401
        assert client.post(f"{BASE}/run", json={}).status_code == 401
        assert client.get(f"{BASE}/candidates").status_code == 401
        # 管理 ping 口
        assert client.get("/api/v1/admin/ping").status_code == 401
        assert client.get("/api/v1/admin/ping",
                          headers=ADMIN_HEADERS).json() == {"ok": True}


def test_source_crud_and_validation():
    with fresh_client() as (client, _dir):
        r = client.post(f"{BASE}/sources", headers=ADMIN_HEADERS,
                        json={"name": "Humo", "url": FEED_URL})
        assert r.status_code == 200, r.text
        sid = r.json()["id"]
        # 重复 URL -> 409
        dup = client.post(f"{BASE}/sources", headers=ADMIN_HEADERS,
                          json={"url": FEED_URL})
        assert dup.status_code == 409
        # 非法 URL -> 400
        bad = client.post(f"{BASE}/sources", headers=ADMIN_HEADERS,
                          json={"url": "not-a-url"})
        assert bad.status_code == 400
        # 禁用
        patch = client.patch(f"{BASE}/sources/{sid}", headers=ADMIN_HEADERS,
                             json={"enabled": False})
        assert patch.json()["enabled"] is False
        # 删除
        assert client.delete(f"{BASE}/sources/{sid}",
                             headers=ADMIN_HEADERS).status_code == 204
        assert client.delete(f"{BASE}/sources/{sid}",
                             headers=ADMIN_HEADERS).status_code == 404


def test_run_crawl_approve_import_publish():
    with fresh_client() as (client, _dir):
        client.post(f"{BASE}/sources", headers=ADMIN_HEADERS,
                    json={"name": "Humo", "url": FEED_URL})
        orig_fetch = crawler.fetch_url
        crawler.fetch_url = lambda url: RSS_BYTES
        try:
            job = client.post(f"{BASE}/run", headers=ADMIN_HEADERS,
                              json={"wait": True}).json()
            assert job["status"] == "ok"
            assert job["sourcesTotal"] == 1
            assert job["sourcesOk"] == 1
            assert job["candidatesNew"] == 1

            # 源状态回写
            src = client.get(f"{BASE}/sources",
                             headers=ADMIN_HEADERS).json()["items"][0]
            assert src["last_status"] == "ok" and src["last_crawled_at"]

            # 未变化再抓 -> 0 新增
            job2 = client.post(f"{BASE}/run", headers=ADMIN_HEADERS,
                               json={"wait": True}).json()
            assert job2["candidatesNew"] == 0

            pending = client.get(f"{BASE}/candidates?status=pending",
                                 headers=ADMIN_HEADERS).json()["items"]
            assert len(pending) == 1
            cid = pending[0]["id"]
            assert pending[0]["episodeCount"] == 2

            # 审批并发布（默认 publish=true, level=beginner）
            approved = client.post(
                f"{BASE}/candidates/{cid}/approve",
                headers=ADMIN_HEADERS, json={"level": "beginner"}).json()
            pid = approved["podcast"]["id"]
            assert approved["podcast"]["published"] is True
            assert approved["inserted_episodes"] == 2
            eps = client.get(
                f"/api/v1/catalog/podcasts/{pid}/episodes").json()
            assert len(eps) == 2

            # 已审批再驳回 -> 409
            assert client.post(f"{BASE}/candidates/{cid}/reject",
                               headers=ADMIN_HEADERS).status_code == 409
        finally:
            crawler.fetch_url = orig_fetch


def test_change_after_approval_creates_new_then_syncs_episodes():
    with fresh_client() as (client, _dir):
        client.post(f"{BASE}/sources", headers=ADMIN_HEADERS,
                    json={"url": FEED_URL})
        orig_fetch = crawler.fetch_url
        feeds = {"v": RSS_BYTES}
        crawler.fetch_url = lambda url: feeds["v"]
        try:
            client.post(f"{BASE}/run", headers=ADMIN_HEADERS,
                        json={"wait": True})
            cid = client.get(f"{BASE}/candidates?status=pending",
                             headers=ADMIN_HEADERS).json()["items"][0]["id"]
            approved = client.post(
                f"{BASE}/candidates/{cid}/approve",
                headers=ADMIN_HEADERS).json()
            pid = approved["podcast"]["id"]
            assert len(approved["episodes"]) == 2

            # 源新增单集 -> 产生新的 pending 候选
            feeds["v"] = RSS_BYTES.replace(
                b"</channel>",
                b"<item><title>Episodio tres</title><guid>ep3</guid>"
                b"<enclosure url='https://cdn.example.test/e3.mp3'"
                b" type='audio/mpeg'/></item></channel>")
            job = client.post(f"{BASE}/run", headers=ADMIN_HEADERS,
                              json={"wait": True}).json()
            assert job["candidatesNew"] == 1
            cid2 = client.get(f"{BASE}/candidates?status=pending",
                              headers=ADMIN_HEADERS).json()["items"][0]["id"]
            out = client.post(f"{BASE}/candidates/{cid2}/approve",
                              headers=ADMIN_HEADERS).json()
            # 只补新增的 1 集，原 2 集不重复
            assert out["inserted_episodes"] == 1
            eps = client.get(
                f"/api/v1/catalog/podcasts/{pid}/episodes").json()
            assert len(eps) == 3
        finally:
            crawler.fetch_url = orig_fetch


def test_fetch_one_shot_and_reject_flow():
    with fresh_client() as (client, _dir):
        orig_fetch = crawler.fetch_url
        crawler.fetch_url = lambda url: RSS_BYTES
        try:
            r = client.post(f"{BASE}/fetch", headers=ADMIN_HEADERS,
                            json={"url": FEED_URL})
            assert r.status_code == 200, r.text
            cid = r.json()["candidate"]["id"]
            assert r.json()["created"] is True
            # 驳回
            rj = client.post(f"{BASE}/candidates/{cid}/reject",
                             headers=ADMIN_HEADERS)
            assert rj.status_code == 200 and rj.json()["status"] == "rejected"
            assert client.get(
                f"{BASE}/candidates?status=pending",
                headers=ADMIN_HEADERS).json()["total"] == 0
        finally:
            crawler.fetch_url = orig_fetch


def test_fetch_errors_mapped():
    with fresh_client() as (client, _dir):
        # 非法 URL -> 400
        bad = client.post(f"{BASE}/fetch", headers=ADMIN_HEADERS,
                          json={"url": "javascript:alert(1)"})
        assert bad.status_code == 400
        # 网络/解析失败 -> 502
        orig_fetch = crawler.fetch_url

        def boom(url):
            raise crawler.CrawlError("抓取失败：connection refused")

        crawler.fetch_url = boom
        try:
            r = client.post(f"{BASE}/fetch", headers=ADMIN_HEADERS,
                            json={"url": FEED_URL})
            assert r.status_code == 502
        finally:
            crawler.fetch_url = orig_fetch


def test_disabled_source_not_crawled_and_empty_job():
    with fresh_client() as (client, _dir):
        add = client.post(f"{BASE}/sources", headers=ADMIN_HEADERS,
                          json={"url": FEED_URL}).json()
        client.patch(f"{BASE}/sources/{add['id']}", headers=ADMIN_HEADERS,
                     json={"enabled": False})
        job = client.post(f"{BASE}/run", headers=ADMIN_HEADERS,
                          json={"wait": True}).json()
        assert job["sourcesTotal"] == 0
        assert job["status"] == "ok"
        assert "没有启用的订阅源" in job["message"]
        jobs = client.get(f"{BASE}/jobs", headers=ADMIN_HEADERS).json()
        assert jobs["total"] >= 1


if __name__ == "__main__":
    raise SystemExit(run_module(__name__))
