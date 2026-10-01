"""管理员：用户列表/禁用启用/改名/重置密码、查看任意用户订阅。"""
from fastapi import APIRouter, HTTPException, Request, status

from ..core import db
from ..core.deps import AdminAuth
from ..core.security import hash_password
from ..models import AccountOut

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])


@router.get("/users", dependencies=[AdminAuth])
def admin_list_users() -> dict:
    items = []
    for row in db.list_users():
        account = db.account_out(row)
        items.append({
            **account,
            "subscription_count": row["subscription_count"],
        })
    return {"items": items, "total": len(items)}


@router.patch("/users/{user_id}", dependencies=[AdminAuth])
async def admin_update_user(user_id: str, request: Request) -> dict:
    body = await request.json()
    if not isinstance(body, dict):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "body 必须是对象")

    updates: dict = {}
    if "disabled" in body and body["disabled"] is not None:
        updates["disabled"] = bool(body["disabled"])
    if body.get("name") is not None:
        new_name = str(body["name"])
        if len(new_name) > 64:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY, "昵称最长 64 个字符")
        updates["name"] = new_name
    new_password = body.get("reset_password")
    password_hash = None
    if new_password is not None:
        if not isinstance(new_password, str) or len(new_password) < 6:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "新密码长度至少 6 位")
        password_hash = hash_password(new_password)

    row = db.update_user(user_id, password_hash=password_hash, **updates)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "用户不存在")
    return db.account_out(row)


@router.get("/users/{user_id}/subscriptions", dependencies=[AdminAuth])
def admin_user_subscriptions(user_id: str) -> dict:
    user = db.get_user(user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "用户不存在")
    items = [db.podcast_out(r)
             for r in db.list_subscription_podcasts(
                 user_id, include_unpublished=True)]
    return {"items": items, "total": len(items),
            "content_version": db.content_version()}
