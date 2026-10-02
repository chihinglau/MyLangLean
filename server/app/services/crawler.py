"""内容采集服务（零新依赖：httpx + 标准库 xml/threading/hashlib）。

职责：
- 抓取并解析管理员配置的 RSS 2.0 / Atom 播客源；
- 通过 iTunes Search API 按关键词检索播客（网络检索，不落库，供一键采集）；
- 内容指纹去重，仅在首次发现或内容变化时生成“待审批”候选快照；
- 管理员审批后由 db.import_candidate 导入正式播客/单集并发布；
- 守护线程按 MLL_CRAWL_INTERVAL_MINUTES 定时执行，手动触发与定时触发
  共用同一单实例队列，绝不并发抓取。

安全：订阅源由管理员手工添加；解析前拒绝任何带 DTD/ENTITY 的文档，
防止 XML 外部实体（XXE）类问题。
"""
from __future__ import annotations

import email.utils
import hashlib
import json
import re
import threading
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urlparse

import httpx

from ..core import db
from ..core.config import get_settings

USER_AGENT = "MyLangLeanBot/0.4 (+admin content review)"
ITUNES_SEARCH_URL = "https://itunes.apple.com/search"

NS_ITUNES = "http://www.itunes.com/dtds/podcast-1.0.dtd"
NS_ATOM = "http://www.w3.org/2005/Atom"
NS_CONTENT = "http://purl.org/rss/1.0/modules/content/"


class CrawlError(Exception):
    """抓取/解析失败的统一异常（消息可直接展示给管理员）。"""


# ---------------------------------------------------------------------------
# 网络
# ---------------------------------------------------------------------------

def validate_url(url: str) -> str:
    text = (url or "").strip()
    parsed = urlparse(text)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise CrawlError("URL 非法：仅支持 http/https 的订阅源地址")
    return text


def fetch_url(url: str) -> bytes:
    """下载订阅源内容；任何网络/HTTP 错误统一转 CrawlError。"""
    url = validate_url(url)
    settings = get_settings()
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": ("application/rss+xml, application/atom+xml,"
                   " application/xml, text/xml;q=0.9, */*;q=0.8"),
    }
    try:
        with httpx.Client(timeout=settings.crawl_timeout_sec,
                          follow_redirects=True, headers=headers) as client:
            resp = client.get(url)
            resp.raise_for_status()
            return resp.content
    except httpx.HTTPError as exc:
        raise CrawlError(f"抓取失败：{exc}") from exc


def search_itunes(term: str, limit: int = 15) -> list[dict[str, Any]]:
    """iTunes 关键词检索播客；返回可直接采集的 feed 列表。"""
    term = (term or "").strip()
    if not term:
        raise CrawlError("检索关键词不能为空")
    settings = get_settings()
    try:
        with httpx.Client(timeout=settings.crawl_timeout_sec,
                          follow_redirects=True,
                          headers={"User-Agent": USER_AGENT}) as client:
            resp = client.get(
                ITUNES_SEARCH_URL,
                params={"term": term, "entity": "podcast",
                        "limit": max(1, min(int(limit), 30))},
            )
            resp.raise_for_status()
            payload = resp.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise CrawlError(f"iTunes 检索失败：{exc}") from exc

    items: list[dict[str, Any]] = []
    for r in payload.get("results", []):
        feed_url = r.get("feedUrl")
        if not feed_url or urlparse(feed_url).scheme not in ("http", "https"):
            continue
        items.append({
            "title": r.get("collectionName") or "",
            "author": r.get("artistName") or "",
            "feedUrl": feed_url,
            "artworkUrl": r.get("artworkUrl600") or r.get("artworkUrl100"),
            "language": _safe_lang(r.get("country")),
            "genres": [g for g in r.get("genres", []) if isinstance(g, str)],
        })
    return items


# ---------------------------------------------------------------------------
# 解析（RSS 2.0 + Atom，带 itunes 扩展）
# ---------------------------------------------------------------------------

def _qn(ns: str, tag: str) -> str:
    return f"{{{ns}}}{tag}"


def _findtext(el: ET.Element | None, paths: list[tuple[str | None, str]]
              ) -> str:
    """按 (命名空间, 标签) 顺序取第一个非空文本。"""
    if el is None:
        return ""
    for ns, tag in paths:
        found = el.find(_qn(ns, tag) if ns else tag)
        if found is not None and (found.text or "").strip():
            return found.text.strip()
    return ""


def _clean(text: str | None, limit: int = 1000) -> str:
    if not text:
        return ""
    # 去 HTML 标签与折叠空白，避免候选描述里塞整页标记。
    no_tags = re.sub(r"<[^>]+>", " ", text)
    collapsed = re.sub(r"\s+", " ", no_tags).strip()
    return collapsed[:limit]


def _safe_lang(code: Any, default: str = "en") -> str:
    match = re.match(r"\s*([A-Za-z]{2})", str(code or ""))
    return match.group(1).lower() if match else default


def _pub_day(text: str | None) -> str:
    """RSS RFC822 / Atom ISO8601 日期 -> YYYY-MM-DD；无法解析返回原值前 10 位。"""
    if not text:
        return ""
    text = text.strip()
    try:
        dt = email.utils.parsedate_to_datetime(text)
        if dt is not None:
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")
    except (TypeError, ValueError, IndexError):
        pass
    try:
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")
    except ValueError:
        return text[:10]


def _duration_ms(text: str | None) -> int:
    """itunes:duration：秒数或 HH:MM:SS / MM:SS -> 毫秒。"""
    if not text:
        return 0
    text = text.strip()
    try:
        if ":" in text:
            total = 0.0
            for part in text.split(":"):
                total = total * 60 + float(part)
            return int(total * 1000)
        return int(float(text) * 1000)
    except ValueError:
        return 0


def _reject_dtd(content: bytes) -> None:
    lowered = content.lower()
    if b"<!doctype" in lowered or b"<!entity" in lowered:
        raise CrawlError("订阅源包含 DTD/ENTITY 声明，出于安全已拒绝解析")


def _itunes_image(el: ET.Element | None) -> str:
    if el is None:
        return ""
    img = el.find(_qn(NS_ITUNES, "image"))
    if img is not None and img.get("href"):
        return img.get("href").strip()
    return ""


def _parse_rss(root: ET.Element, feed_url: str) -> dict[str, Any]:
    channel = root.find("channel")
    if channel is None:
        raise CrawlError("RSS 文档缺少 channel 节点")
    title = _findtext(channel, [(None, "title")]) or feed_url
    author = _findtext(channel, [(NS_ITUNES, "author"),
                                 (None, "managingEditor")])
    language = _safe_lang(channel.findtext("language"))
    artwork = _itunes_image(channel)
    if not artwork:
        img = channel.find("image")
        artwork = (img.findtext("url") or "").strip() if img is not None else ""
    description = _clean(_findtext(
        channel, [(NS_ITUNES, "summary"), (NS_CONTENT, "encoded"),
                  (None, "description")]))

    episodes: list[dict[str, Any]] = []
    for item in channel.findall("item"):
        enclosure = item.find("enclosure")
        audio_url = (enclosure.get("url") or "").strip() \
            if enclosure is not None else ""
        if not audio_url:
            # 少数源用 atom:link rel=enclosure
            for link in item.findall(_qn(NS_ATOM, "link")):
                if link.get("rel") == "enclosure" and link.get("href"):
                    audio_url = link.get("href").strip()
                    break
        if not audio_url:
            continue
        guid = (item.findtext("guid") or audio_url).strip()
        episodes.append({
            "guid": guid,
            "title": _findtext(item, [(None, "title")]) or "未命名单集",
            "audioUrl": audio_url,
            "durationMs": _duration_ms(
                _findtext(item, [(NS_ITUNES, "duration")])),
            "pubDate": _pub_day(item.findtext("pubDate")),
            "language": _safe_lang(
                item.findtext(_qn(NS_ITUNES, "language")), language),
            "artworkUrl": _itunes_image(item),
            "description": _clean(_findtext(
                item, [(NS_ITUNES, "summary"), (NS_ITUNES, "subtitle"),
                       (None, "description")]), 300),
        })
    return _payload(feed_url, title, author, artwork, language, description,
                    episodes)


def _parse_atom(root: ET.Element, feed_url: str) -> dict[str, Any]:
    title = _findtext(root, [(NS_ATOM, "title")]) or feed_url
    author = _findtext(root, [(NS_ATOM, "name")])
    author_el = root.find(_qn(NS_ATOM, "author"))
    if not author and author_el is not None:
        name_el = author_el.find(_qn(NS_ATOM, "name"))
        author = (name_el.text or "").strip() if name_el is not None else ""
    artwork = (root.findtext(_qn(NS_ATOM, "logo")) or "").strip()
    language = _safe_lang(root.get("{http://www.w3.org/XML/1998/namespace}lang"))
    description = _clean(_findtext(root, [(NS_ATOM, "subtitle"),
                                          (NS_ATOM, "tagline")]))

    episodes: list[dict[str, Any]] = []
    for entry in root.findall(_qn(NS_ATOM, "entry")):
        audio_url = ""
        for link in entry.findall(_qn(NS_ATOM, "link")):
            href = (link.get("href") or "").strip()
            if not href:
                continue
            rel = link.get("rel") or "alternate"
            mime = link.get("type") or ""
            if rel == "enclosure" and (not mime or mime.startswith("audio")):
                audio_url = href
                break
            if not audio_url and rel == "alternate" and href.endswith(
                    (".mp3", ".m4a", ".aac", ".ogg")):
                audio_url = href
        if not audio_url:
            continue
        guid = (_findtext(entry, [(NS_ATOM, "id")]) or audio_url)
        episodes.append({
            "guid": guid,
            "title": _findtext(entry, [(NS_ATOM, "title")]) or "未命名单集",
            "audioUrl": audio_url,
            "durationMs": 0,
            "pubDate": _pub_day(_findtext(
                entry, [(NS_ATOM, "published"), (NS_ATOM, "updated")])),
            "language": language,
            "artworkUrl": "",
            "description": _clean(_findtext(
                entry, [(NS_ATOM, "summary"), (NS_ATOM, "subtitle")]), 300),
        })
    return _payload(feed_url, title, author, artwork, language, description,
                    episodes)


def _payload(feed_url: str, title: str, author: str, artwork: str,
             language: str, description: str,
             episodes: list[dict[str, Any]]) -> dict[str, Any]:
    settings = get_settings()
    episodes = episodes[: max(1, int(settings.crawl_max_episodes))]
    payload = {
        "feed_url": feed_url,
        "title": title[:200],
        "author": author[:120],
        "artwork_url": artwork or None,
        "language": language,
        "description": description,
        "episodes": episodes,
    }
    payload["content_hash"] = _content_hash(payload)
    return payload


def _content_hash(payload: dict[str, Any]) -> str:
    """元数据 + 单集（guid/地址/标题/时长/发布日）指纹；未变化则不产生待办。"""
    basis = {
        "feed_url": payload["feed_url"],
        "title": payload["title"],
        "author": payload["author"],
        "language": payload["language"],
        "artwork_url": payload["artwork_url"],
        "description": payload["description"],
        "episodes": [
            {k: ep.get(k) for k in
             ("guid", "audioUrl", "title", "durationMs", "pubDate")}
            for ep in payload["episodes"]
        ],
    }
    raw = json.dumps(basis, ensure_ascii=False, sort_keys=True,
                     separators=(",", ":"))
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def parse_feed(content: bytes, feed_url: str = "") -> dict[str, Any]:
    """把 RSS/Atom 字节流解析为统一候选负载（含 content_hash）。"""
    if not content or not content.strip():
        raise CrawlError("订阅源内容为空")
    _reject_dtd(content)
    try:
        root = ET.fromstring(content)
    except ET.ParseError as exc:
        raise CrawlError(f"订阅源 XML 解析失败：{exc}") from exc
    tag = root.tag.lower()
    if tag.endswith("}rss") or tag == "rss":
        return _parse_rss(root, feed_url)
    if tag.endswith("}feed") or tag == "feed":
        return _parse_atom(root, feed_url)
    raise CrawlError(f"未识别的订阅源格式（根节点 {root.tag}），需 RSS 或 Atom")


# ---------------------------------------------------------------------------
# 入库（去重 / 变更检测）
# ---------------------------------------------------------------------------

def ingest_content(feed_url: str, content: bytes,
                   source_id: str | None = None) -> tuple[dict[str, Any], bool]:
    """解析并写入候选。返回 (候选 dict, 是否新增了收件箱条目)。

    - 指纹未变：不产生新待办；
    - 最新条目仍处于 pending：原地刷新快照（收件箱不增加）；
    - 其余（首次抓取 / 上次已审批或驳回后有更新）：新增一条 pending。
    """
    feed_url = validate_url(feed_url)
    payload = parse_feed(content, feed_url)
    latest = db.latest_candidate(feed_url)
    common = dict(
        feed_url=feed_url, title=payload["title"], author=payload["author"],
        artwork_url=payload["artwork_url"], language=payload["language"],
        description=payload["description"], episodes=payload["episodes"],
        content_hash=payload["content_hash"],
    )
    if latest is not None and latest["content_hash"] == payload["content_hash"]:
        return db.candidate_out(latest), False
    if latest is not None and latest["status"] == "pending":
        # 已在收件箱里等待审批：原地刷新快照，不增加重复条目。
        row = db.refresh_pending_candidate(latest["id"], **common)
        return db.candidate_out(row), False
    row = db.insert_candidate(source_id=source_id, **common)
    return db.candidate_out(row), True


def fetch_and_ingest(feed_url: str, source_id: str | None = None
                     ) -> tuple[dict[str, Any], bool]:
    return ingest_content(feed_url, fetch_url(feed_url), source_id=source_id)


# ---------------------------------------------------------------------------
# 任务执行（手动 / 定时，单实例）与调度线程
# ---------------------------------------------------------------------------

_run_lock = threading.Lock()
_current_job_id: str | None = None
_scheduler_started = False


def current_job() -> dict[str, Any] | None:
    if not _current_job_id:
        return None
    row = db.get_job(_current_job_id)
    return db.job_out(row) if row else None


def run_crawl(*, trigger: str = "manual",
              source_ids: list[str] | None = None) -> dict[str, Any]:
    """抓取全部启用源（或指定源）。并发触发时直接返回进行中的任务。"""
    global _current_job_id
    if not _run_lock.acquire(blocking=False):
        running = current_job()
        if running is not None:
            return running
        # 锁被占用但任务行已结束（极端竞态）：报一个明确的忙状态。
        return {"id": "", "trigger": trigger, "status": "running",
                "sourcesTotal": 0, "sourcesOk": 0, "candidatesNew": 0,
                "message": "已有抓取任务在执行", "startedAt": "",
                "finishedAt": ""}
    try:
        if source_ids:
            sources = []
            for sid in source_ids:
                row = db.get_source(sid)
                if row is None:
                    raise CrawlError(f"订阅源不存在：{sid}")
                sources.append(row)
        else:
            sources = [s for s in db.list_sources() if s["enabled"]]

        job = db.create_job(trigger)
        _current_job_id = job["id"]
        errors: list[str] = []
        new_count = 0
        ok_count = 0
        for src in sources:
            label = src["name"] or src["url"]
            try:
                _, created = fetch_and_ingest(src["url"], src["id"])
                new_count += int(created)
                ok_count += 1
                db.mark_source_crawled(src["id"], True)
            except CrawlError as exc:
                errors.append(f"{label}: {exc}")
                db.mark_source_crawled(src["id"], False, str(exc))
            except Exception as exc:  # noqa: BLE001 - 单源失败不拖垮整批
                errors.append(f"{label}: 未预期错误 {exc}")
                db.mark_source_crawled(src["id"], False, str(exc))

        total = len(sources)
        if total == 0:
            status, message = "ok", "没有启用的订阅源"
        elif ok_count == 0:
            status, message = "error", "；".join(errors)
        else:
            status = "ok"
            message = (f"新增待审批 {new_count} 条"
                       + (f"；失败 {len(errors)} 个源：{'；'.join(errors)}"
                          if errors else ""))
        row = db.finish_job(
            job["id"], status=status, sources_total=total,
            sources_ok=ok_count, candidates_new=new_count, message=message)
        return db.job_out(row)
    finally:
        _run_lock.release()


def start_scheduler() -> None:
    """启动后台定时抓取守护线程（进程内仅一次）。"""
    global _scheduler_started
    if _scheduler_started:
        return
    _scheduler_started = True
    thread = threading.Thread(target=_scheduler_loop, daemon=True,
                              name="mll-crawl-scheduler")
    thread.start()


def _scheduler_loop() -> None:
    while True:
        try:
            minutes = max(5, int(get_settings().crawl_interval_minutes))
        except (TypeError, ValueError):
            minutes = 360
        time.sleep(minutes * 60)
        if not get_settings().crawl_enabled:
            continue
        try:
            run_crawl(trigger="schedule")
        except Exception:  # noqa: BLE001 - 调度线程永不因异常退出
            continue
