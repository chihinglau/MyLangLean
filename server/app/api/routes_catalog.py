"""公开目录接口 + 管理员对播客/单集的 CRUD 与上下架。

目录输出统一 camelCase（feedUrl/artworkUrl/durationMs/pubDate），
管理入参同时接受 snake_case 与 camelCase。
"""
from fastapi import APIRouter, HTTPException, Request, status

from ..core import db
from ..core.deps import AdminAuth

router = APIRouter(prefix="/api/v1", tags=["catalog"])


def _bad_request(exc: ValueError) -> HTTPException:
    # 入参非法（level/language/必填缺失）统一 422，与 pydantic 校验一致。
    return HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc))


# ---------------------------------------------------------------------------
# 公开目录
# ---------------------------------------------------------------------------

@router.get("/catalog/meta")
def catalog_meta() -> dict:
    return {
        "languages": [{"code": c, "label": db.LANGUAGE_LABELS[c]}
                      for c in db.LANGUAGE_LABELS],
        "levels": [{"name": n, "label": db.LEVEL_LABELS[n]}
                   for n in db.VALID_LEVELS],
        "content_version": db.content_version(),
    }


@router.get("/catalog/podcasts")
def list_podcasts(q: str | None = None, language: str | None = None,
                  level: str | None = None, page: int = 1,
                  size: int = 50) -> dict:
    page = max(1, page)
    size = min(max(1, size), 200)
    rows, total = db.list_published_podcasts(
        q=q, language=language, level=level,
        offset=(page - 1) * size, limit=size)
    return {
        "items": [db.podcast_out(r) for r in rows],
        "page": page,
        "size": size,
        "total": total,
        "content_version": db.content_version(),
    }


@router.get("/catalog/podcasts/{podcast_id}")
def get_podcast(podcast_id: str) -> dict:
    row = db.get_podcast(podcast_id, only_published=True)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "播客不存在或已下架")
    return db.podcast_out(row)


@router.get("/catalog/podcasts/{podcast_id}/episodes")
def list_episodes(podcast_id: str) -> list:
    row = db.get_podcast(podcast_id, only_published=True)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "播客不存在或已下架")
    return [db.episode_out(e) for e in db.list_episodes(podcast_id)]


# ---------------------------------------------------------------------------
# 管理员：播客 / 单集维护
# ---------------------------------------------------------------------------

@router.get("/admin/podcasts", dependencies=[AdminAuth])
def admin_list_podcasts() -> dict:
    """管理视角：含已下架内容（公开 /catalog 仅返回上架项）。"""
    rows = db.list_all_podcasts()
    return {"items": [db.podcast_out(r) for r in rows], "total": len(rows)}


@router.post("/admin/podcasts", dependencies=[AdminAuth])
async def admin_create_podcast(request: Request) -> dict:
    try:
        row = db.create_podcast(await request.json())
    except ValueError as exc:
        raise _bad_request(exc)
    return db.podcast_out(row)


@router.put("/admin/podcasts/{podcast_id}", dependencies=[AdminAuth])
async def admin_replace_podcast(podcast_id: str, request: Request) -> dict:
    try:
        row = db.update_podcast(podcast_id, await request.json(),
                                partial=False)
    except ValueError as exc:
        raise _bad_request(exc)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "播客不存在或已下架")
    return db.podcast_out(row)


# PATCH 支持局部更新，常用于上下架（{"published": false}）。
@router.patch("/admin/podcasts/{podcast_id}", dependencies=[AdminAuth])
async def admin_patch_podcast(podcast_id: str, request: Request) -> dict:
    try:
        row = db.update_podcast(podcast_id, await request.json(),
                                partial=True)
    except ValueError as exc:
        raise _bad_request(exc)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "播客不存在或已下架")
    return db.podcast_out(row)


@router.delete("/admin/podcasts/{podcast_id}",
               status_code=204, dependencies=[AdminAuth])
def admin_delete_podcast(podcast_id: str):
    if not db.delete_podcast(podcast_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "播客不存在或已下架")


@router.post("/admin/podcasts/{podcast_id}/episodes",
             dependencies=[AdminAuth])
async def admin_create_episode(podcast_id: str, request: Request) -> dict:
    try:
        row = db.create_episode(podcast_id, await request.json())
    except ValueError as exc:
        raise _bad_request(exc)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "播客不存在或已下架")
    return db.episode_out(row)


@router.delete("/admin/episodes/{episode_id}",
               status_code=204, dependencies=[AdminAuth])
def admin_delete_episode(episode_id: str):
    if not db.delete_episode(episode_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "单集不存在")


@router.post("/admin/catalog/reseed", dependencies=[AdminAuth])
def admin_reseed_catalog() -> dict:
    """重置为内置目录：删除全部播客（级联单集与订阅）后重新播种。"""
    db.reseed_catalog()
    return {"ok": True, "content_version": db.content_version()}
