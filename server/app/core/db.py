"""SQLite 持久化层（仅标准库 sqlite3）。

- 每次操作开短连接（WAL + 外键），全部 SQL 参数化。
- 首次启动建表并播种与 app MockCatalog 一致的 8 播客 × 2 单集。
- 重复 init 幂等：不重复播种、不重复复制媒体。
"""
from __future__ import annotations

import json
import re
import shutil
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from .config import REPO_ROOT, get_settings
from .security import hash_password

# ---------------------------------------------------------------------------
# 播种数据（与 app/lib/data/mock/mock_catalog.dart 的 MockCatalog 对齐）
# ---------------------------------------------------------------------------

SEED_PODCASTS: list[dict[str, Any]] = [
    {
        "id": "p1",
        "title": "Real English Voices",
        "author": "Language Lab",
        "feed_url": "https://example.com/feeds/real-english-voices.xml",
        "artwork_url": None,
        "language": "en",
        "level": "beginner",
        "description": "真实语速的日常英语对话，适合逐句精听与跟读。",
    },
    {
        "id": "p2",
        "title": "Tokyo Street Stories",
        "author": "Go! Go! Nihon",
        "feed_url": "https://example.com/feeds/tokyo-street-stories.xml",
        "artwork_url": None,
        "language": "ja",
        "level": "intermediate",
        "description": "东京街头实景录音，旅行日语听力与影子跟读。",
    },
    {
        "id": "p3",
        "title": "Coffee Break French",
        "author": "Radio Lingua",
        "feed_url": "https://example.com/feeds/coffee-break-french.xml",
        "artwork_url": None,
        "language": "fr",
        "level": "beginner",
        "description": "一杯咖啡时间的法语短节目，发音清晰。",
    },
    {
        "id": "p4",
        "title": "Slow German News",
        "author": "Nachrichten Langsam",
        "feed_url": "https://example.com/feeds/slow-german-news.xml",
        "artwork_url": None,
        "language": "de",
        "level": "advanced",
        "description": "慢速德语新闻，适合中高级学习者挑战。",
    },
    {
        "id": "p5",
        "title": "Hablemos Español",
        "author": "Radio Casa",
        "feed_url": "https://example.com/feeds/hablemos-espanol.xml",
        "artwork_url": None,
        "language": "es",
        "level": "beginner",
        "description": "生活化的西语对话，从点餐到旅行一路开口说。",
    },
    {
        "id": "p6",
        "title": "서울 스토리",
        "author": "한국어 스튜디오",
        "feed_url": "https://example.com/feeds/seoul-story.xml",
        "artwork_url": None,
        "language": "ko",
        "level": "intermediate",
        "description": "首尔日常场景韩语播客，练听力也练敬语语感。",
    },
    {
        "id": "p7",
        "title": "中文慢谈",
        "author": "慢声工作室",
        "feed_url": "https://example.com/feeds/chinese-slow-talk.xml",
        "artwork_url": None,
        "language": "zh",
        "level": "intermediate",
        "description": "用清晰普通话聊文化与生活，适合中文进阶学习者。",
    },
    {
        "id": "p8",
        "title": "Everyday English News",
        "author": "Global Talk",
        "feed_url": "https://example.com/feeds/everyday-english-news.xml",
        "artwork_url": None,
        "language": "en",
        "level": "advanced",
        "description": "常速英语新闻短评，词汇密度高，适合高级学习者。",
    },
]

SEED_EPISODE_TITLES = (
    "把喜欢的声音练进嘴里（示例单集）",
    "通勤路上的十分钟跟读训练（示例音频）",
)
SEED_EPISODE_DATES = ("2026-09-20", "2026-09-13")
SAMPLE_AUDIO_URL = "/media/sample.mp3"
SAMPLE_DURATION_MS = 17640

LANGUAGE_LABELS = {
    "en": "英语",
    "ja": "日语",
    "fr": "法语",
    "de": "德语",
    "es": "西班牙语",
    "ko": "韩语",
    "zh": "中文",
}
LEVEL_LABELS = {
    "beginner": "初级",
    "intermediate": "中级",
    "advanced": "高级",
}
VALID_LEVELS = tuple(LEVEL_LABELS)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# 连接 / 建表
# ---------------------------------------------------------------------------

def connect() -> sqlite3.Connection:
    settings = get_settings()
    Path(settings.data_dir).mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(settings.db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            TEXT PRIMARY KEY,
    email         TEXT UNIQUE,
    name          TEXT NOT NULL DEFAULT '',
    password_hash TEXT,
    is_guest      INTEGER NOT NULL DEFAULT 0,
    disabled      INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS usage (
    user_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    month    TEXT NOT NULL,
    used_sec INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, month)
);

CREATE TABLE IF NOT EXISTS podcasts (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    author      TEXT NOT NULL DEFAULT '',
    feed_url    TEXT NOT NULL DEFAULT '',
    artwork_url TEXT,
    language    TEXT NOT NULL DEFAULT 'en',
    level       TEXT NOT NULL DEFAULT 'beginner',
    description TEXT NOT NULL DEFAULT '',
    published   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS episodes (
    id          TEXT PRIMARY KEY,
    podcast_id  TEXT NOT NULL REFERENCES podcasts(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    audio_url   TEXT NOT NULL,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    pub_date    TEXT NOT NULL DEFAULT '',
    language    TEXT NOT NULL DEFAULT 'en',
    -- 随发布同步下发的逐词双语字幕 JSON（TranscriptOut 冻结帧格式）；
    -- 空串表示该单集暂无已发布字幕。
    transcript_json TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS subscriptions (
    user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    podcast_id TEXT NOT NULL REFERENCES podcasts(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    PRIMARY KEY (user_id, podcast_id)
);

CREATE TABLE IF NOT EXISTS releases (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    platform     TEXT NOT NULL,
    version      TEXT NOT NULL,
    build_no     INTEGER NOT NULL DEFAULT 0,
    channel      TEXT NOT NULL DEFAULT 'stable',
    notes        TEXT NOT NULL DEFAULT '',
    mandatory    INTEGER NOT NULL DEFAULT 0,
    filename     TEXT NOT NULL,
    size         INTEGER NOT NULL DEFAULT 0,
    sha256       TEXT NOT NULL,
    published_at TEXT NOT NULL
);

-- 内容采集（爬虫）：订阅源 / 待审批快照 / 抓取任务
CREATE TABLE IF NOT EXISTS crawl_sources (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL DEFAULT '',
    url             TEXT NOT NULL UNIQUE,
    enabled         INTEGER NOT NULL DEFAULT 1,
    last_crawled_at TEXT NOT NULL DEFAULT '',
    last_status     TEXT NOT NULL DEFAULT '',
    last_error      TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS crawl_candidates (
    id                  TEXT PRIMARY KEY,
    source_id           TEXT REFERENCES crawl_sources(id) ON DELETE SET NULL,
    feed_url            TEXT NOT NULL,
    title               TEXT NOT NULL DEFAULT '',
    author              TEXT NOT NULL DEFAULT '',
    artwork_url         TEXT,
    language            TEXT NOT NULL DEFAULT 'en',
    description         TEXT NOT NULL DEFAULT '',
    episode_count       INTEGER NOT NULL DEFAULT 0,
    episodes_json       TEXT NOT NULL DEFAULT '[]',
    content_hash        TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'pending',
    imported_podcast_id TEXT,
    discovered_at       TEXT NOT NULL,
    reviewed_at         TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_candidates_status
    ON crawl_candidates(status, discovered_at);
CREATE INDEX IF NOT EXISTS idx_candidates_feed
    ON crawl_candidates(feed_url, discovered_at);

CREATE TABLE IF NOT EXISTS crawl_jobs (
    id             TEXT PRIMARY KEY,
    trigger        TEXT NOT NULL,
    status         TEXT NOT NULL,
    sources_total  INTEGER NOT NULL DEFAULT 0,
    sources_ok     INTEGER NOT NULL DEFAULT 0,
    candidates_new INTEGER NOT NULL DEFAULT 0,
    message        TEXT NOT NULL DEFAULT '',
    started_at     TEXT NOT NULL,
    finished_at    TEXT NOT NULL DEFAULT ''
);
"""


def _ensure_sample_media() -> None:
    """把 app/assets/audio/sample.mp3 复制到 data/media/（幂等）。"""
    settings = get_settings()
    media_dir = settings.media_dir
    media_dir.mkdir(parents=True, exist_ok=True)
    dest = media_dir / "sample.mp3"
    if dest.exists():
        return
    src = REPO_ROOT / "app" / "assets" / "audio" / "sample.mp3"
    if src.exists():
        shutil.copyfile(src, dest)
    else:
        # 兜底：极小占位（正常仓库不会走到这里）。
        dest.write_bytes(b"")


def _seed_catalog(conn: sqlite3.Connection) -> None:
    count = conn.execute("SELECT COUNT(*) FROM podcasts").fetchone()[0]
    if count:
        return
    ts = now_iso()
    for pod in SEED_PODCASTS:
        conn.execute(
            "INSERT INTO podcasts (id, title, author, feed_url, artwork_url,"
            " language, level, description, published, created_at, updated_at)"
            " VALUES (?,?,?,?,?,?,?,?,1,?,?)",
            (pod["id"], pod["title"], pod["author"], pod["feed_url"],
             pod["artwork_url"], pod["language"], pod["level"],
             pod["description"], ts, ts),
        )
        for idx in range(2):
            eid = f"{pod['id']}-e{idx + 1}"
            conn.execute(
                "INSERT INTO episodes (id, podcast_id, title, audio_url,"
                " duration_ms, pub_date, language, created_at, updated_at)"
                " VALUES (?,?,?,?,?,?,?,?,?)",
                (eid, pod["id"], SEED_EPISODE_TITLES[idx], SAMPLE_AUDIO_URL,
                 SAMPLE_DURATION_MS, SEED_EPISODE_DATES[idx], "en", ts, ts),
            )


def _migrate(conn: sqlite3.Connection) -> None:
    """对旧库做增量加列（CREATE TABLE IF NOT EXISTS 不会补列）。幂等。"""
    ep_cols = {
        r["name"] for r in conn.execute("PRAGMA table_info(episodes)")
    }
    if "transcript_json" not in ep_cols:
        conn.execute(
            "ALTER TABLE episodes ADD COLUMN transcript_json"
            " TEXT NOT NULL DEFAULT ''")


def init_db() -> None:
    """建表 + 准备目录 + 首次播种。重复调用安全。"""
    settings = get_settings()
    Path(settings.data_dir).mkdir(parents=True, exist_ok=True)
    settings.media_dir.mkdir(parents=True, exist_ok=True)
    settings.releases_dir.mkdir(parents=True, exist_ok=True)
    _ensure_sample_media()
    conn = connect()
    try:
        conn.executescript(SCHEMA)
        _migrate(conn)
        _seed_catalog(conn)
        conn.commit()
    finally:
        conn.close()


def reseed_catalog() -> None:
    """删除全部播客（级联单集/订阅）后重新播种内置目录。"""
    conn = connect()
    try:
        conn.execute("DELETE FROM podcasts")
        conn.commit()
        _seed_catalog(conn)
        conn.commit()
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# 序列化（统一 camelCase 输出，直接匹配 App Podcast/Episode.fromJson）
# ---------------------------------------------------------------------------

def podcast_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "title": row["title"],
        "author": row["author"],
        "feedUrl": row["feed_url"],
        "artworkUrl": row["artwork_url"],
        "language": row["language"],
        "level": row["level"],
        "description": row["description"],
        "published": bool(row["published"]),
    }


def _row_transcript(row: sqlite3.Row) -> Any:
    """解析单集行内嵌的已发布字幕；旧连接缺列 / 坏 JSON 一律回退 None。"""
    if "transcript_json" not in row.keys():
        return None
    raw = row["transcript_json"]
    if not raw:
        return None
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        return None


def episode_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "podcastId": row["podcast_id"],
        "title": row["title"],
        "audioUrl": row["audio_url"],
        "durationMs": row["duration_ms"],
        "pubDate": row["pub_date"],
        "language": row["language"],
        # 随单集同步发布的逐词双语字幕；null 表示暂无（App 可走按需 ASR）。
        "transcript": _row_transcript(row),
    }


def account_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "email": row["email"],
        "name": row["name"],
        "is_guest": bool(row["is_guest"]),
        "disabled": bool(row["disabled"]),
        "created_at": row["created_at"],
    }


def content_version() -> str:
    """podcasts/episodes 的 max(updated_at) 秒级时间戳字符串。"""
    conn = connect()
    try:
        rows = conn.execute(
            "SELECT updated_at FROM podcasts UNION ALL"
            " SELECT updated_at FROM episodes"
        ).fetchall()
    finally:
        conn.close()
    latest = 0.0
    for r in rows:
        try:
            latest = max(latest,
                         datetime.strptime(r["updated_at"],
                                           "%Y-%m-%dT%H:%M:%SZ")
                         .replace(tzinfo=timezone.utc).timestamp())
        except (TypeError, ValueError):
            continue
    return str(int(latest))


# ---------------------------------------------------------------------------
# 用户仓储
# ---------------------------------------------------------------------------

def upsert_guest(device_id: str) -> sqlite3.Row:
    uid = f"guest:{device_id}"
    conn = connect()
    try:
        row = conn.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
        if row is None:
            ts = now_iso()
            conn.execute(
                "INSERT INTO users (id, email, name, password_hash, is_guest,"
                " disabled, created_at) VALUES (?,NULL,'',NULL,1,0,?)",
                (uid, ts),
            )
            conn.commit()
            row = conn.execute("SELECT * FROM users WHERE id=?",
                               (uid,)).fetchone()
        return row
    finally:
        conn.close()


def create_user(email: str, password: str, name: str = "") -> sqlite3.Row:
    uid = uuid.uuid4().hex
    ts = now_iso()
    conn = connect()
    try:
        conn.execute(
            "INSERT INTO users (id, email, name, password_hash, is_guest,"
            " disabled, created_at) VALUES (?,?,?,?,0,0,?)",
            (uid, email, name or "", hash_password(password), ts),
        )
        conn.commit()
        return conn.execute("SELECT * FROM users WHERE id=?",
                            (uid,)).fetchone()
    finally:
        conn.close()


def get_user(user_id: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM users WHERE id=?",
                            (user_id,)).fetchone()
    finally:
        conn.close()


def get_user_by_email(email: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM users WHERE email=?",
                            (email,)).fetchone()
    finally:
        conn.close()


def list_users() -> list[sqlite3.Row]:
    conn = connect()
    try:
        return conn.execute(
            "SELECT u.*, (SELECT COUNT(*) FROM subscriptions s"
            " WHERE s.user_id=u.id) AS subscription_count"
            " FROM users u ORDER BY u.created_at, u.id"
        ).fetchall()
    finally:
        conn.close()


def update_user(user_id: str, *, disabled: bool | None = None,
                name: str | None = None,
                password_hash: str | None = None) -> sqlite3.Row | None:
    sets: list[str] = []
    params: list[Any] = []
    if disabled is not None:
        sets.append("disabled=?")
        params.append(1 if disabled else 0)
    if name is not None:
        sets.append("name=?")
        params.append(name)
    if password_hash is not None:
        sets.append("password_hash=?")
        params.append(password_hash)
    if not sets:
        return get_user(user_id)
    params.append(user_id)
    conn = connect()
    try:
        conn.execute(f"UPDATE users SET {', '.join(sets)} WHERE id=?",
                     params)
        conn.commit()
        return conn.execute("SELECT * FROM users WHERE id=?",
                            (user_id,)).fetchone()
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# 额度
# ---------------------------------------------------------------------------

def current_month() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


def used_seconds(user_id: str, month: str | None = None) -> int:
    month = month or current_month()
    conn = connect()
    try:
        row = conn.execute(
            "SELECT used_sec FROM usage WHERE user_id=? AND month=?",
            (user_id, month),
        ).fetchone()
        return int(row["used_sec"]) if row else 0
    finally:
        conn.close()


def charge_quota(user_id: str, seconds: int, limit_sec: int,
                 month: str | None = None) -> int:
    """扣减月度额度；超额抛 ValueError（路由转 402）。返回新已用值。"""
    month = month or current_month()
    conn = connect()
    try:
        row = conn.execute(
            "SELECT used_sec FROM usage WHERE user_id=? AND month=?",
            (user_id, month),
        ).fetchone()
        used = int(row["used_sec"]) if row else 0
        if used + seconds > limit_sec:
            raise ValueError("monthly quota exhausted")
        used += seconds
        conn.execute(
            "INSERT INTO usage (user_id, month, used_sec) VALUES (?,?,?)"
            " ON CONFLICT(user_id, month) DO UPDATE SET used_sec=excluded.used_sec",
            (user_id, month, used),
        )
        conn.commit()
        return used
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# 播客 / 单集
# ---------------------------------------------------------------------------

PODCAST_WRITABLE = {
    "title": str,
    "author": str,
    "feed_url": str,
    "artwork_url": str,
    "language": str,
    "level": str,
    "description": str,
    "published": int,
}


def _pick_alias(data: dict[str, Any], snake: str, camel: str,
                default: Any = None) -> Any:
    if snake in data and data[snake] is not None:
        return data[snake]
    if camel in data and data[camel] is not None:
        return data[camel]
    return default


# (snake 名, camel 名, 全量创建时的默认值)
_PODCAST_FIELD_MAP = (
    ("title", "title", None),
    ("author", "author", ""),
    ("feed_url", "feedUrl", ""),
    ("artwork_url", "artworkUrl", None),
    ("language", "language", "en"),
    ("level", "level", "beginner"),
    ("description", "description", ""),
    ("published", "published", True),
)


def normalize_podcast_input(data: dict[str, Any],
                            partial: bool = False) -> dict[str, Any]:
    """管理 API 入参同时接受 snake_case 与 camelCase。

    partial=True（PATCH）时只返回请求中实际提供的字段，避免把
    未提及的列覆盖为 NULL。
    """
    fields: dict[str, Any] = {}
    for snake, camel, default in _PODCAST_FIELD_MAP:
        value, present = (data[snake], True) if snake in data else (
            (data[camel], True) if camel in data else (None, False))
        if not present:
            if partial:
                continue
            value = default
        # 显式传 null：除可空的 artwork_url 外回落到默认/跳过。
        if value is None and snake != "artwork_url":
            if partial:
                continue
            value = default
        fields[snake] = value

    if not partial and not fields.get("title"):
        raise ValueError("title 必填")
    if "level" in fields and fields["level"] not in VALID_LEVELS:
        raise ValueError(f"非法 level: {fields['level']}")
    lang = fields.get("language")
    if lang is not None and (
            not isinstance(lang, str) or len(lang) != 2
            or not lang.isalpha() or not lang.islower()):
        raise ValueError(f"非法 language: {lang}")
    if "published" in fields:
        fields["published"] = 1 if bool(fields["published"]) else 0
    return fields


def list_published_podcasts(q: str | None, language: str | None,
                            level: str | None, offset: int,
                            limit: int) -> tuple[list[sqlite3.Row], int]:
    where = ["published=1"]
    params: list[Any] = []
    if q:
        where.append("(title LIKE ? ESCAPE '\\' OR author LIKE ? ESCAPE '\\'"
                     " OR description LIKE ? ESCAPE '\\')")
        # 转义 LIKE 通配符，% 与 _ 按字面搜索。
        safe_q = q.replace("\\", "\\\\").replace("%", "\\%")\
                  .replace("_", "\\_")
        like = f"%{safe_q}%"
        params.extend([like, like, like])
    if language:
        where.append("language=?")
        params.append(language)
    if level:
        where.append("level=?")
        params.append(level)
    sql_where = " WHERE " + " AND ".join(where)
    conn = connect()
    try:
        total = conn.execute(
            f"SELECT COUNT(*) FROM podcasts{sql_where}", params).fetchone()[0]
        rows = conn.execute(
            f"SELECT * FROM podcasts{sql_where} ORDER BY id"
            " LIMIT ? OFFSET ?",
            [*params, limit, offset],
        ).fetchall()
        return rows, total
    finally:
        conn.close()


def get_podcast(podcast_id: str, *, only_published: bool = False
                ) -> sqlite3.Row | None:
    conn = connect()
    try:
        if only_published:
            return conn.execute(
                "SELECT * FROM podcasts WHERE id=? AND published=1",
                (podcast_id,)).fetchone()
        return conn.execute("SELECT * FROM podcasts WHERE id=?",
                            (podcast_id,)).fetchone()
    finally:
        conn.close()


def list_episodes(podcast_id: str) -> list[sqlite3.Row]:
    conn = connect()
    try:
        return conn.execute(
            "SELECT * FROM episodes WHERE podcast_id=? ORDER BY pub_date DESC,"
            " id", (podcast_id,)).fetchall()
    finally:
        conn.close()


def get_episode(episode_id: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM episodes WHERE id=?",
                            (episode_id,)).fetchone()
    finally:
        conn.close()


def create_podcast(data: dict[str, Any]) -> sqlite3.Row:
    fields = normalize_podcast_input(data)
    pid = uuid.uuid4().hex
    ts = now_iso()
    conn = connect()
    try:
        conn.execute(
            "INSERT INTO podcasts (id, title, author, feed_url, artwork_url,"
            " language, level, description, published, created_at, updated_at)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (pid, fields["title"], fields["author"], fields["feed_url"],
             fields["artwork_url"], fields["language"], fields["level"],
             fields["description"], fields["published"], ts, ts),
        )
        conn.commit()
        return conn.execute("SELECT * FROM podcasts WHERE id=?",
                            (pid,)).fetchone()
    finally:
        conn.close()


def update_podcast(podcast_id: str, data: dict[str, Any],
                   partial: bool = True) -> sqlite3.Row | None:
    row = get_podcast(podcast_id)
    if row is None:
        return None
    fields = normalize_podcast_input(data, partial=partial)
    sets = [f"{k}=?" for k in fields]
    sets.append("updated_at=?")
    params = [*fields.values(), now_iso(), podcast_id]
    conn = connect()
    try:
        conn.execute(f"UPDATE podcasts SET {', '.join(sets)} WHERE id=?",
                     params)
        conn.commit()
        return conn.execute("SELECT * FROM podcasts WHERE id=?",
                            (podcast_id,)).fetchone()
    finally:
        conn.close()


def delete_podcast(podcast_id: str) -> bool:
    conn = connect()
    try:
        cur = conn.execute("DELETE FROM podcasts WHERE id=?", (podcast_id,))
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


def normalize_episode_input(data: dict[str, Any]) -> dict[str, Any]:
    title = _pick_alias(data, "title", "title")
    audio_url = _pick_alias(data, "audio_url", "audioUrl",
                            SAMPLE_AUDIO_URL)
    duration_ms = _pick_alias(data, "duration_ms", "durationMs", 0)
    pub_date = _pick_alias(data, "pub_date", "pubDate", "")
    language = _pick_alias(data, "language", "language", "en")
    if not title:
        raise ValueError("title 必填")
    if not isinstance(duration_ms, int) or duration_ms < 0:
        raise ValueError("非法 durationMs")
    if (not isinstance(language, str) or len(language) != 2
            or not language.isalpha() or not language.islower()):
        raise ValueError(f"非法 language: {language}")
    return {
        "title": title,
        "audio_url": audio_url,
        "duration_ms": duration_ms,
        "pub_date": str(pub_date),
        "language": language,
    }


def create_episode(podcast_id: str, data: dict[str, Any]
                   ) -> sqlite3.Row | None:
    fields = normalize_episode_input(data)
    eid = uuid.uuid4().hex
    ts = now_iso()
    conn = connect()
    try:
        pod = conn.execute("SELECT 1 FROM podcasts WHERE id=?",
                           (podcast_id,)).fetchone()
        if pod is None:
            return None
        conn.execute(
            "INSERT INTO episodes (id, podcast_id, title, audio_url,"
            " duration_ms, pub_date, language, created_at, updated_at)"
            " VALUES (?,?,?,?,?,?,?,?,?)",
            (eid, podcast_id, fields["title"], fields["audio_url"],
             fields["duration_ms"], fields["pub_date"], fields["language"],
             ts, ts),
        )
        conn.execute("UPDATE podcasts SET updated_at=? WHERE id=?",
                     (ts, podcast_id))
        conn.commit()
        return conn.execute("SELECT * FROM episodes WHERE id=?",
                            (eid,)).fetchone()
    finally:
        conn.close()


def delete_episode(episode_id: str) -> bool:
    conn = connect()
    try:
        cur = conn.execute("DELETE FROM episodes WHERE id=?", (episode_id,))
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# 订阅
# ---------------------------------------------------------------------------

def add_subscription(user_id: str, podcast_id: str) -> bool:
    """返回 True 新增 / False 已存在；目标播客不存在返回 None。"""
    conn = connect()
    try:
        pod = conn.execute(
            "SELECT 1 FROM podcasts WHERE id=? AND published=1",
            (podcast_id,)).fetchone()
        if pod is None:
            return None
        exists = conn.execute(
            "SELECT 1 FROM subscriptions WHERE user_id=? AND podcast_id=?",
            (user_id, podcast_id)).fetchone()
        if exists:
            return False
        conn.execute(
            "INSERT INTO subscriptions (user_id, podcast_id, created_at)"
            " VALUES (?,?,?)",
            (user_id, podcast_id, now_iso()),
        )
        conn.commit()
        return True
    finally:
        conn.close()


def remove_subscription(user_id: str, podcast_id: str) -> None:
    conn = connect()
    try:
        conn.execute(
            "DELETE FROM subscriptions WHERE user_id=? AND podcast_id=?",
            (user_id, podcast_id))
        conn.commit()
    finally:
        conn.close()


def list_subscription_podcasts(user_id: str, *, include_unpublished: bool = False
                               ) -> list[sqlite3.Row]:
    extra = "" if include_unpublished else " AND p.published=1"
    conn = connect()
    try:
        return conn.execute(
            "SELECT p.* FROM podcasts p JOIN subscriptions s"
            " ON s.podcast_id=p.id WHERE s.user_id=?" + extra + " ORDER BY p.id",
            (user_id,)).fetchall()
    finally:
        conn.close()


def list_all_podcasts() -> list[sqlite3.Row]:
    """管理视角：含已下架内容，按上架状态与 id 排序。"""
    conn = connect()
    try:
        return conn.execute(
            "SELECT * FROM podcasts ORDER BY published DESC, id"
        ).fetchall()
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# 发布包
# ---------------------------------------------------------------------------

def create_release(*, platform: str, version: str, build_no: int,
                   channel: str, notes: str, mandatory: bool,
                   filename: str, size: int, sha256: str,
                   published_at: str | None = None) -> sqlite3.Row:
    conn = connect()
    try:
        cur = conn.execute(
            "INSERT INTO releases (platform, version, build_no, channel, notes,"
            " mandatory, filename, size, sha256, published_at)"
            " VALUES (?,?,?,?,?,?,?,?,?,?)",
            (platform, version, build_no, channel, notes,
             1 if mandatory else 0, filename, size, sha256,
             published_at or now_iso()),
        )
        conn.commit()
        return conn.execute("SELECT * FROM releases WHERE id=?",
                            (cur.lastrowid,)).fetchone()
    finally:
        conn.close()


def _release_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "platform": row["platform"],
        "version": row["version"],
        "build_no": row["build_no"],
        "channel": row["channel"],
        "notes": row["notes"],
        "mandatory": bool(row["mandatory"]),
        "size": row["size"],
        "sha256": row["sha256"],
        "url": f"/api/v1/releases/download/{row['id']}",
        "published_at": row["published_at"],
    }


def release_out(row: sqlite3.Row) -> dict[str, Any]:
    return _release_out(row)


def list_releases(platform: str | None = None,
                  channel: str | None = None) -> list[dict[str, Any]]:
    where: list[str] = []
    params: list[Any] = []
    if platform:
        where.append("platform=?")
        params.append(platform)
    if channel:
        where.append("channel=?")
        params.append(channel)
    sql = "SELECT * FROM releases"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY published_at DESC, id DESC"
    conn = connect()
    try:
        return [_release_out(r) for r in conn.execute(sql, params).fetchall()]
    finally:
        conn.close()


def get_release(release_id: int) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM releases WHERE id=?",
                            (release_id,)).fetchone()
    finally:
        conn.close()


def delete_release(release_id: int) -> sqlite3.Row | None:
    conn = connect()
    try:
        row = conn.execute("SELECT * FROM releases WHERE id=?",
                           (release_id,)).fetchone()
        if row is None:
            return None
        conn.execute("DELETE FROM releases WHERE id=?", (release_id,))
        conn.commit()
        return row
    finally:
        conn.close()


SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
BUILD_RE = re.compile(r"^\d+$")


def parse_version(text: str) -> tuple[tuple[int, ...], int | None] | None:
    """'0.4.1' / '0.4.1+5' -> ((0,4,1), 5)；非法串返回 None（绝不抛异常）。"""
    text = (text or "").strip()
    if not text:
        return None
    build: int | None = None
    if "+" in text:
        ver, build_str = text.split("+", 1)
        if not BUILD_RE.match(build_str):
            return None
        build = int(build_str)
    else:
        ver = text
    if not SEMVER_RE.match(ver):
        return None
    parts = tuple(int(p) for p in ver.split("."))
    return parts, build


def latest_release(platform: str, channel: str) -> dict[str, Any] | None:
    """语义版本优先、build_no 次序决胜；脏数据行跳过不影响全员。"""
    items = list_releases(platform=platform, channel=channel)
    valid = [it for it in items if parse_version(it["version"]) is not None]
    if not valid:
        return None

    def key(item: dict[str, Any]):
        parts, _ = parse_version(item["version"])  # type: ignore[misc]
        padded = (parts + (0, 0, 0))[:3]
        return padded + (int(item["build_no"]),)

    return max(valid, key=key)


def has_update(current: str, latest: dict[str, Any]) -> bool:
    parsed_current = parse_version(current)
    parsed_latest = parse_version(latest["version"])
    if parsed_current is None or parsed_latest is None:
        return False
    cur_parts, cur_build = parsed_current
    rel_parts, _ = parsed_latest
    c = (cur_parts + (0, 0, 0))[:3]
    r = (rel_parts + (0, 0, 0))[:3]
    if r > c:
        return True
    if r == c and cur_build is not None \
            and int(latest["build_no"]) > cur_build:
        return True
    return False


# ---------------------------------------------------------------------------
# 内容采集（爬虫）：订阅源 / 候选快照 / 抓取任务 / 审批导入
# ---------------------------------------------------------------------------

def source_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "name": row["name"],
        "url": row["url"],
        "enabled": bool(row["enabled"]),
        "last_crawled_at": row["last_crawled_at"],
        "last_status": row["last_status"],
        "last_error": row["last_error"],
        "created_at": row["created_at"],
    }


def candidate_out(row: sqlite3.Row) -> dict[str, Any]:
    try:
        episodes = json.loads(row["episodes_json"])
    except (TypeError, ValueError):
        episodes = []
    return {
        "id": row["id"],
        "sourceId": row["source_id"],
        "feedUrl": row["feed_url"],
        "title": row["title"],
        "author": row["author"],
        "artworkUrl": row["artwork_url"],
        "language": row["language"],
        "description": row["description"],
        "episodeCount": row["episode_count"],
        "episodes": episodes,
        "contentHash": row["content_hash"],
        "status": row["status"],
        "importedPodcastId": row["imported_podcast_id"],
        "discoveredAt": row["discovered_at"],
        "reviewedAt": row["reviewed_at"],
    }


def job_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "trigger": row["trigger"],
        "status": row["status"],
        "sourcesTotal": row["sources_total"],
        "sourcesOk": row["sources_ok"],
        "candidatesNew": row["candidates_new"],
        "message": row["message"],
        "startedAt": row["started_at"],
        "finishedAt": row["finished_at"],
    }


def create_source(name: str, url: str) -> sqlite3.Row:
    sid = uuid.uuid4().hex
    ts = now_iso()
    conn = connect()
    try:
        conn.execute(
            "INSERT INTO crawl_sources (id, name, url, enabled,"
            " last_crawled_at, last_status, last_error, created_at)"
            " VALUES (?,?,?,1,'','','',?)",
            (sid, (name or "").strip()[:120], url.strip(), ts),
        )
        conn.commit()
        return conn.execute("SELECT * FROM crawl_sources WHERE id=?",
                            (sid,)).fetchone()
    finally:
        conn.close()


def get_source_by_url(url: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM crawl_sources WHERE url=?",
                            (url.strip(),)).fetchone()
    finally:
        conn.close()


def list_sources() -> list[sqlite3.Row]:
    conn = connect()
    try:
        return conn.execute(
            "SELECT * FROM crawl_sources ORDER BY created_at, id"
        ).fetchall()
    finally:
        conn.close()


def get_source(source_id: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM crawl_sources WHERE id=?",
                            (source_id,)).fetchone()
    finally:
        conn.close()


def update_source(source_id: str, *, enabled: bool | None = None,
                  name: str | None = None) -> sqlite3.Row | None:
    sets: list[str] = []
    params: list[Any] = []
    if enabled is not None:
        sets.append("enabled=?")
        params.append(1 if enabled else 0)
    if name is not None:
        sets.append("name=?")
        params.append(name.strip()[:120])
    if not sets:
        return get_source(source_id)
    params.append(source_id)
    conn = connect()
    try:
        conn.execute(f"UPDATE crawl_sources SET {', '.join(sets)} WHERE id=?",
                     params)
        conn.commit()
        return conn.execute("SELECT * FROM crawl_sources WHERE id=?",
                            (source_id,)).fetchone()
    finally:
        conn.close()


def delete_source(source_id: str) -> bool:
    conn = connect()
    try:
        cur = conn.execute("DELETE FROM crawl_sources WHERE id=?",
                           (source_id,))
        conn.commit()
        return cur.rowcount > 0
    finally:
        conn.close()


def mark_source_crawled(source_id: str, ok: bool, error: str = "") -> None:
    conn = connect()
    try:
        conn.execute(
            "UPDATE crawl_sources SET last_crawled_at=?, last_status=?,"
            " last_error=? WHERE id=?",
            (now_iso(), "ok" if ok else "error", error[:500], source_id),
        )
        conn.commit()
    finally:
        conn.close()


# ---- 抓取任务 ----

def create_job(trigger: str) -> sqlite3.Row:
    jid = uuid.uuid4().hex
    ts = now_iso()
    conn = connect()
    try:
        conn.execute(
            "INSERT INTO crawl_jobs (id, trigger, status, sources_total,"
            " sources_ok, candidates_new, message, started_at, finished_at)"
            " VALUES (?,?, 'running',0,0,0,'',?, '')",
            (jid, trigger, ts),
        )
        conn.commit()
        return conn.execute("SELECT * FROM crawl_jobs WHERE id=?",
                            (jid,)).fetchone()
    finally:
        conn.close()


def finish_job(job_id: str, *, status: str, sources_total: int,
               sources_ok: int, candidates_new: int,
               message: str) -> sqlite3.Row:
    conn = connect()
    try:
        conn.execute(
            "UPDATE crawl_jobs SET status=?, sources_total=?, sources_ok=?,"
            " candidates_new=?, message=?, finished_at=? WHERE id=?",
            (status, sources_total, sources_ok, candidates_new,
             message[:2000], now_iso(), job_id),
        )
        conn.commit()
        return conn.execute("SELECT * FROM crawl_jobs WHERE id=?",
                            (job_id,)).fetchone()
    finally:
        conn.close()


def get_job(job_id: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM crawl_jobs WHERE id=?",
                            (job_id,)).fetchone()
    finally:
        conn.close()


def list_jobs(limit: int = 20) -> list[sqlite3.Row]:
    conn = connect()
    try:
        return conn.execute(
            "SELECT * FROM crawl_jobs ORDER BY started_at DESC, id DESC"
            " LIMIT ?", (max(1, min(limit, 100)),)).fetchall()
    finally:
        conn.close()


# ---- 待审批候选 ----

def latest_candidate(feed_url: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute(
            "SELECT * FROM crawl_candidates WHERE feed_url=?"
            " ORDER BY discovered_at DESC, id DESC LIMIT 1",
            (feed_url,)).fetchone()
    finally:
        conn.close()


def get_candidate(candidate_id: str) -> sqlite3.Row | None:
    conn = connect()
    try:
        return conn.execute("SELECT * FROM crawl_candidates WHERE id=?",
                            (candidate_id,)).fetchone()
    finally:
        conn.close()


def list_candidates(status: str | None = None) -> list[sqlite3.Row]:
    conn = connect()
    try:
        if status:
            rows = conn.execute(
                "SELECT * FROM crawl_candidates WHERE status=?"
                " ORDER BY discovered_at DESC, id DESC",
                (status,)).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM crawl_candidates"
                " ORDER BY discovered_at DESC, id DESC").fetchall()
        return rows
    finally:
        conn.close()


def insert_candidate(*, source_id: str | None, feed_url: str, title: str,
                     author: str, artwork_url: str | None, language: str,
                     description: str, episodes: list[dict[str, Any]],
                     content_hash: str) -> sqlite3.Row:
    cid = uuid.uuid4().hex
    ts = now_iso()
    conn = connect()
    try:
        conn.execute(
            "INSERT INTO crawl_candidates (id, source_id, feed_url, title,"
            " author, artwork_url, language, description, episode_count,"
            " episodes_json, content_hash, status, imported_podcast_id,"
            " discovered_at, reviewed_at)"
            " VALUES (?,?,?,?,?,?,?,?,?,?,?, 'pending', NULL, ?, '')",
            (cid, source_id, feed_url, title, author, artwork_url, language,
             description, len(episodes), json.dumps(episodes, ensure_ascii=False),
             content_hash, ts),
        )
        conn.commit()
        return conn.execute("SELECT * FROM crawl_candidates WHERE id=?",
                            (cid,)).fetchone()
    finally:
        conn.close()


def refresh_pending_candidate(candidate_id: str, *, feed_url: str,
                              title: str, author: str,
                              artwork_url: str | None, language: str,
                              description: str, episodes: list[dict[str, Any]],
                              content_hash: str) -> sqlite3.Row:
    """同一 feed 已有待审批快照时原地刷新（避免收件箱堆积重复项）。"""
    conn = connect()
    try:
        conn.execute(
            "UPDATE crawl_candidates SET feed_url=?, title=?, author=?,"
            " artwork_url=?, language=?, description=?, episode_count=?,"
            " episodes_json=?, content_hash=?, discovered_at=?"
            " WHERE id=? AND status='pending'",
            (feed_url, title, author, artwork_url, language, description,
             len(episodes), json.dumps(episodes, ensure_ascii=False),
             content_hash, now_iso(), candidate_id),
        )
        conn.commit()
        return conn.execute("SELECT * FROM crawl_candidates WHERE id=?",
                            (candidate_id,)).fetchone()
    finally:
        conn.close()


def mark_candidate_reviewed(candidate_id: str, status: str,
                            imported_podcast_id: str | None = None
                            ) -> sqlite3.Row | None:
    conn = connect()
    try:
        conn.execute(
            "UPDATE crawl_candidates SET status=?, imported_podcast_id=?,"
            " reviewed_at=? WHERE id=?",
            (status, imported_podcast_id, now_iso(), candidate_id),
        )
        conn.commit()
        return conn.execute("SELECT * FROM crawl_candidates WHERE id=?",
                            (candidate_id,)).fetchone()
    finally:
        conn.close()


def supersede_pending(feed_url: str, keep_id: str) -> int:
    """审批后，把同一 feed 的其它待审批快照标记为 rejected。"""
    conn = connect()
    try:
        cur = conn.execute(
            "UPDATE crawl_candidates SET status='rejected', reviewed_at=?"
            " WHERE feed_url=? AND status='pending' AND id<>?",
            (now_iso(), feed_url, keep_id),
        )
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


def _safe_lang(code: Any) -> str:
    """播客/单集 language 列要求两位小写字母，非法值回退 en。"""
    text = str(code or "").strip().lower()
    if len(text) >= 2 and text[:2].isalpha():
        return text[:2]
    return "en"


def _ep_transcript_json(ep: dict[str, Any]) -> str:
    """候选单集快照内嵌 transcript 对象 -> 可落库的 JSON 串。"""
    t = ep.get("transcript")
    if not isinstance(t, dict):
        return ""
    try:
        return json.dumps(t, ensure_ascii=False)
    except (TypeError, ValueError):
        return ""


def import_candidate(candidate_id: str, *, publish: bool = True,
                     level: str = "beginner") -> dict[str, Any]:
    """审批通过：导入为正式播客 + 单集（同 feed 二次导入只补新增单集）。

    以 enclosure 的 audio_url 作为单集去重键（RSS guid 不落库）。
    """
    if level not in VALID_LEVELS:
        raise ValueError(f"非法 level: {level}")
    cand = get_candidate(candidate_id)
    if cand is None:
        return None  # type: ignore[return-value]
    episodes = []
    try:
        episodes = json.loads(cand["episodes_json"])
    except (TypeError, ValueError):
        episodes = []
    ts = now_iso()
    conn = connect()
    try:
        pid = cand["imported_podcast_id"]
        pod = conn.execute("SELECT * FROM podcasts WHERE id=?",
                           (pid,)).fetchone() if pid else None
        if pod is None:
            # 后续快照本身不带 imported_podcast_id：按 feed_url 找回
            # 之前已导入的播客，做“只补新增单集”的增量同步。
            pod = conn.execute("SELECT * FROM podcasts WHERE feed_url=?",
                               (cand["feed_url"],)).fetchone()
        if pod is None:
            pid = uuid.uuid4().hex
            conn.execute(
                "INSERT INTO podcasts (id, title, author, feed_url, artwork_url,"
                " language, level, description, published, created_at, updated_at)"
                " VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (pid, cand["title"], cand["author"], cand["feed_url"],
                 cand["artwork_url"], _safe_lang(cand["language"]), level,
                 cand["description"], 1 if publish else 0, ts, ts),
            )
        else:
            pid = pod["id"]
            # 已导入过：刷新元数据，但保留管理员后续设置的 published/level。
            conn.execute(
                "UPDATE podcasts SET title=?, author=?, artwork_url=?,"
                " language=?, description=?, updated_at=? WHERE id=?",
                (cand["title"], cand["author"], cand["artwork_url"],
                 _safe_lang(cand["language"]), cand["description"], ts, pid),
            )

        existing = {
            r["audio_url"] for r in conn.execute(
                "SELECT audio_url FROM episodes WHERE podcast_id=?", (pid,))
        }
        inserted = 0
        backfilled = 0
        for ep in episodes:
            audio_url = str(ep.get("audioUrl") or "").strip()
            if not audio_url:
                continue
            transcript_json = _ep_transcript_json(ep)
            if audio_url in existing:
                # 已在库的旧单集：仅在其尚无字幕时补填候选里带来的字幕，
                # 不覆盖后续可能已人工维护过的字幕。
                if transcript_json:
                    cur = conn.execute(
                        "UPDATE episodes SET transcript_json=?,"
                        " updated_at=? WHERE podcast_id=? AND audio_url=?"
                        " AND transcript_json=''",
                        (transcript_json, ts, pid, audio_url))
                    backfilled += cur.rowcount
                continue
            conn.execute(
                "INSERT INTO episodes (id, podcast_id, title, audio_url,"
                " duration_ms, pub_date, language, transcript_json,"
                " created_at, updated_at)"
                " VALUES (?,?,?,?,?,?,?,?,?,?)",
                (uuid.uuid4().hex, pid, str(ep.get("title") or "未命名单集"),
                 audio_url, int(ep.get("durationMs") or 0),
                 str(ep.get("pubDate") or "")[:10],
                 _safe_lang(ep.get("language") or cand["language"]),
                 transcript_json, ts, ts),
            )
            existing.add(audio_url)
            inserted += 1
        conn.execute("UPDATE podcasts SET updated_at=? WHERE id=?", (ts, pid))
        conn.execute(
            "UPDATE crawl_candidates SET status='approved',"
            " imported_podcast_id=?, reviewed_at=? WHERE id=?",
            (pid, ts, candidate_id),
        )
        conn.execute(
            "UPDATE crawl_candidates SET status='rejected', reviewed_at=?"
            " WHERE feed_url=? AND status='pending' AND id<>?",
            (ts, cand["feed_url"], candidate_id),
        )
        conn.commit()
        pod_row = conn.execute("SELECT * FROM podcasts WHERE id=?",
                               (pid,)).fetchone()
        ep_rows = conn.execute(
            "SELECT * FROM episodes WHERE podcast_id=? ORDER BY pub_date DESC, id",
            (pid,)).fetchall()
        return {
            "podcast": podcast_out(pod_row),
            "episodes": [episode_out(r) for r in ep_rows],
            "inserted_episodes": inserted,
            "backfilled_transcripts": backfilled,
        }
    finally:
        conn.close()
