"""AC-4：meta/搜索/语言/难度/下架/单集/媒体，以及管理 CRUD。"""
import sys

import harness

ADMIN = harness.ADMIN_HEADERS
API = "/api/v1"


def test_meta_languages_levels():
    with harness.fresh_client() as (client, _):
        meta = client.get(f"{API}/catalog/meta")
        assert meta.status_code == 200, meta.text
        body = meta.json()
        assert len(body["languages"]) == 7
        assert {x["code"] for x in body["languages"]} == {
            "en", "ja", "fr", "de", "es", "ko", "zh"}
        assert [x["name"] for x in body["levels"]] == [
            "beginner", "intermediate", "advanced"]
        assert body["content_version"]


def test_list_search_filter_pagination():
    with harness.fresh_client() as (client, _):
        r = client.get(f"{API}/catalog/podcasts")
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["total"] == 8
        assert len(body["items"]) == 8
        assert body["page"] == 1 and body["size"] == 50
        assert body["content_version"]

        # camelCase 输出
        p1 = body["items"][0]
        for key in ("id", "title", "author", "feedUrl", "artworkUrl",
                    "language", "level", "description", "published"):
            assert key in p1, key

        # 分页
        page1 = client.get(f"{API}/catalog/podcasts?page=1&size=3").json()
        page2 = client.get(f"{API}/catalog/podcasts?page=2&size=3").json()
        ids1 = {p["id"] for p in page1["items"]}
        ids2 = {p["id"] for p in page2["items"]}
        assert len(ids1) == 3 and len(ids2) == 3 and not (ids1 & ids2)

        assert client.get(f"{API}/catalog/podcasts?q=coffee").json()["total"] == 1
        assert client.get(f"{API}/catalog/podcasts?q=COFFEE").json()["total"] == 1
        assert client.get(
            f"{API}/catalog/podcasts?language=ja").json()["total"] == 1
        beginners = client.get(
            f"{API}/catalog/podcasts?level=beginner").json()
        assert beginners["total"] == 3
        assert {p["id"] for p in beginners["items"]} == {"p1", "p3", "p5"}

        # 组合筛选
        assert client.get(
            f"{API}/catalog/podcasts?language=en&level=advanced"
        ).json()["total"] == 1


def test_detail_episodes_and_audio():
    with harness.fresh_client() as (client, _):
        r = client.get(f"{API}/catalog/podcasts/p2")
        assert r.status_code == 200
        assert r.json()["title"] == "Tokyo Street Stories"

        r = client.get(f"{API}/catalog/podcasts/p1/episodes")
        assert r.status_code == 200
        eps = r.json()
        assert len(eps) == 2
        for e in eps:
            assert e["audioUrl"] == "/media/sample.mp3"
        audio = client.get(eps[0]["audioUrl"])
        assert audio.status_code == 200
        assert len(audio.content) > 0


def test_admin_auth_required():
    with harness.fresh_client() as (client, _):
        assert client.get(f"{API}/admin/users").status_code == 401
        assert client.get(
            f"{API}/admin/users",
            headers={"X-Admin-Token": "wrong"}).status_code == 401
        assert client.post(f"{API}/admin/podcasts",
                           json={"title": "x"}).status_code == 401
        assert client.post(f"{API}/admin/catalog/reseed").status_code == 401


def test_admin_podcast_crud_and_validation():
    with harness.fresh_client() as (client, _):
        # 非法 level/language 422
        r = client.post(f"{API}/admin/podcasts", headers=ADMIN,
                        json={"title": "X", "level": "nope"})
        assert r.status_code == 422, r.text
        r = client.post(f"{API}/admin/podcasts", headers=ADMIN,
                        json={"title": "X", "language": "xx!!"})
        assert r.status_code == 422, r.text
        # 缺标题 422
        r = client.post(f"{API}/admin/podcasts", headers=ADMIN,
                        json={"author": "匿名"})
        assert r.status_code == 422, r.text

        # 创建（camelCase 入参）
        r = client.post(f"{API}/admin/podcasts", headers=ADMIN, json={
            "title": "独家测试频道", "author": "运维",
            "feedUrl": "https://x.test/feed.xml",
            "artworkUrl": "https://x.test/a.png",
            "language": "en", "level": "intermediate",
            "description": "仅测试可见"})
        assert r.status_code == 200, r.text
        pid = r.json()["id"]
        assert r.json()["published"] is True

        # 公开接口可见
        assert client.get(
            f"{API}/catalog/podcasts?q=独家测试频道").json()["total"] == 1

        # PUT 全量改 + snake_case 入参
        r = client.put(f"{API}/admin/podcasts/{pid}", headers=ADMIN,
                       json={"title": "改名频道", "language": "en",
                             "level": "advanced"})
        assert r.status_code == 200
        assert r.json()["title"] == "改名频道"

        # 新增单集
        r = client.post(f"{API}/admin/podcasts/{pid}/episodes",
                        headers=ADMIN, json={
                            "title": "新单集", "audioUrl": "/media/sample.mp3",
                            "durationMs": 1234, "pubDate": "2026-10-01",
                            "language": "en"})
        assert r.status_code == 200, r.text
        eid = r.json()["id"]
        assert r.json()["durationMs"] == 1234
        assert len(client.get(
            f"{API}/catalog/podcasts/{pid}/episodes").json()) == 1

        # 删单集
        assert client.delete(
            f"{API}/admin/episodes/{eid}", headers=ADMIN).status_code == 204
        assert client.delete(
            f"{API}/admin/episodes/{eid}", headers=ADMIN).status_code == 404

        # 删播客后 404
        assert client.delete(
            f"{API}/admin/podcasts/{pid}", headers=ADMIN).status_code == 204
        assert client.get(
            f"{API}/catalog/podcasts/{pid}").status_code == 404


def test_unpublish_hides_and_reseed_restores():
    with harness.fresh_client() as (client, _):
        # 下架 p3
        r = client.patch(f"{API}/admin/podcasts/p3", headers=ADMIN,
                         json={"published": False})
        assert r.status_code == 200
        assert r.json()["published"] is False

        assert client.get(f"{API}/catalog/podcasts").json()["total"] == 7
        assert client.get(f"{API}/catalog/podcasts?q=coffee").json()["total"] == 0
        assert client.get(f"{API}/catalog/podcasts/p3").status_code == 404
        assert client.get(
            f"{API}/catalog/podcasts/p3/episodes").status_code == 404

        # 重新上架
        r = client.patch(f"{API}/admin/podcasts/p3", headers=ADMIN,
                         json={"published": True})
        assert r.status_code == 200
        assert client.get(f"{API}/catalog/podcasts/p3").status_code == 200

        # reseed 后仍为 8 播客 16 单集
        r = client.post(f"{API}/admin/catalog/reseed", headers=ADMIN)
        assert r.status_code == 200, r.text
        assert client.get(f"{API}/catalog/podcasts").json()["total"] == 8
        assert len(client.get(
            f"{API}/catalog/podcasts/p3/episodes").json()) == 2


if __name__ == "__main__":
    sys.exit(harness.run_module(__name__))
