"""管理员内容采集 API：订阅源管理 / 定时与手动抓取 / 关键词检索 / 审批导入。

全部接口需要 X-Admin-Token（AdminAuth）。流程：
    订阅源(RSS/Atom) 或 iTunes 关键词检索
        -> 定时/手动抓取 -> 待审批候选（内容指纹去重）
        -> 管理员审批 -> 导入正式播客与单集（默认直接上架发布）。
"""
from __future__ import annotations

import sqlite3
import threading
import time

from fastapi import APIRouter, HTTPException, Request, status

from ..core import db
from ..core.deps import AdminAuth
from ..services import crawler

router = APIRouter(prefix="/api/v1/admin/crawl", tags=["admin-crawl"])


def _crawl_http_error(exc: crawler.CrawlError) -> HTTPException:
    # 入参类问题 400；网络/解析类问题 502（上游不可用）。
    code = (status.HTTP_400_BAD_REQUEST
            if str(exc).startswith("URL 非法")
            or str(exc).endswith("不能为空")
            else status.HTTP_502_BAD_GATEWAY)
    return HTTPException(code, str(exc))


# ---------------------------------------------------------------------------
# 订阅源
# ---------------------------------------------------------------------------

@router.get("/sources", dependencies=[AdminAuth])
def list_sources() -> dict:
    rows = db.list_sources()
    return {"items": [db.source_out(r) for r in rows], "total": len(rows)}


@router.post("/sources", dependencies=[AdminAuth])
async def add_source(request: Request) -> dict:
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "body 必须是对象")
    url = str(body.get("url") or "").strip()
    try:
        url = crawler.validate_url(url)
    except crawler.CrawlError as exc:
        raise _crawl_http_error(exc)
    if db.get_source_by_url(url) is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "该订阅源已存在")
    row = db.create_source(str(body.get("name") or ""), url)
    if body.get("enabled") is False:
        row = db.update_source(row["id"], enabled=False) or row
    return db.source_out(row)


@router.patch("/sources/{source_id}", dependencies=[AdminAuth])
async def patch_source(source_id: str, request: Request) -> dict:
    if db.get_source(source_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "订阅源不存在")
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "body 必须是对象")
    enabled = body.get("enabled")
    name = body.get("name")
    row = db.update_source(
        source_id,
        enabled=None if enabled is None else bool(enabled),
        name=None if name is None else str(name),
    )
    return db.source_out(row)


@router.delete("/sources/{source_id}", status_code=204,
               dependencies=[AdminAuth])
def remove_source(source_id: str):
    if not db.delete_source(source_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "订阅源不存在")


# ---------------------------------------------------------------------------
# 抓取任务
# ---------------------------------------------------------------------------

@router.post("/run", dependencies=[AdminAuth])
async def run_crawl(request: Request) -> dict:
    """手动触发抓取。

    body: {"sourceIds": ["..."] 可选, "wait": false 默认}
    wait=false（默认）：后台线程执行，立即返回 running 任务供轮询；
    wait=true：同步执行完毕后返回（便于自动化/测试）。
    """
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001 - 无 body 也允许
        body = {}
    body = body if isinstance(body, dict) else {}
    source_ids = body.get("sourceIds")
    if source_ids is not None and not isinstance(source_ids, list):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "sourceIds 必须是数组")
    wait = bool(body.get("wait"))

    if wait:
        try:
            return crawler.run_crawl(trigger="manual", source_ids=source_ids)
        except crawler.CrawlError as exc:
            raise _crawl_http_error(exc)

    threading.Thread(
        target=crawler.run_crawl,
        kwargs={"trigger": "manual", "source_ids": source_ids},
        daemon=True, name="mll-crawl-manual",
    ).start()
    # 等待任务行落地（最多 2 秒），让前端拿到可轮询的 jobId。
    job = None
    deadline = time.time() + 2
    while time.time() < deadline:
        job = crawler.current_job()
        if job:
            break
        time.sleep(0.05)
    if job is None:
        rows = db.list_jobs(1)
        if rows:
            return db.job_out(rows[0])
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE,
                            "抓取任务启动失败，请稍后重试")
    return job


@router.get("/jobs", dependencies=[AdminAuth])
def list_jobs(limit: int = 20) -> dict:
    rows = db.list_jobs(limit)
    return {"items": [db.job_out(r) for r in rows], "total": len(rows),
            "running": crawler.current_job()}


@router.get("/jobs/{job_id}", dependencies=[AdminAuth])
def get_job(job_id: str) -> dict:
    row = db.get_job(job_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "任务不存在")
    return db.job_out(row)


# ---------------------------------------------------------------------------
# 网络检索 & 单次抓取
# ---------------------------------------------------------------------------

@router.get("/search", dependencies=[AdminAuth])
def search_podcasts(q: str, limit: int = 15) -> dict:
    try:
        items = crawler.search_itunes(q, limit)
    except crawler.CrawlError as exc:
        raise _crawl_http_error(exc)
    return {"items": items, "total": len(items),
            "existing": [r["url"] for r in db.list_sources()]}


@router.post("/fetch", dependencies=[AdminAuth])
async def fetch_one(request: Request) -> dict:
    """不建订阅源，直接抓取任意 RSS/Atom 地址并生成待审批候选。"""
    body = await request.json()
    url = str(body.get("url") or "").strip() if isinstance(body, dict) else ""
    try:
        candidate, created = crawler.fetch_and_ingest(url, None)
    except crawler.CrawlError as exc:
        raise _crawl_http_error(exc)
    return {"candidate": candidate, "created": created}


# ---------------------------------------------------------------------------
# 待审批候选：审批导入 / 驳回
# ---------------------------------------------------------------------------

@router.get("/candidates", dependencies=[AdminAuth])
def list_candidates(status: str | None = None) -> dict:
    if status and status not in ("pending", "approved", "rejected"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST,
                            "status 仅支持 pending/approved/rejected")
    rows = db.list_candidates(status)
    return {"items": [db.candidate_out(r) for r in rows], "total": len(rows)}


@router.post("/candidates/{candidate_id}/approve", dependencies=[AdminAuth])
async def approve_candidate(candidate_id: str, request: Request) -> dict:
    cand = db.get_candidate(candidate_id)
    if cand is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "待审批内容不存在")
    try:
        body = await request.json()
    except Exception:  # noqa: BLE001 - 允许空 body（使用默认发布配置）
        body = {}
    if not isinstance(body, dict):
        body = {}
    level = str(body.get("level") or "beginner")
    publish = bool(body.get("publish", True))
    if level not in db.VALID_LEVELS:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                            f"非法 level: {level}")
    try:
        result = db.import_candidate(candidate_id, publish=publish,
                                     level=level)
    except ValueError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc))
    except sqlite3.Error as exc:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR,
                            f"导入失败：{exc}")
    return result


@router.post("/candidates/{candidate_id}/reject", dependencies=[AdminAuth])
def reject_candidate(candidate_id: str) -> dict:
    cand = db.get_candidate(candidate_id)
    if cand is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "待审批内容不存在")
    if cand["status"] == "approved":
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "该内容已导入发布；如需下线请到“内容发布”下架")
    row = db.mark_candidate_reviewed(candidate_id, "rejected")
    return db.candidate_out(row)
