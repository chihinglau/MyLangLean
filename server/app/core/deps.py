"""鉴权依赖：JWT 解析 + 持久化用户校验 + 管理员令牌。"""
from dataclasses import dataclass
from hmac import compare_digest

from fastapi import Depends, Header, HTTPException, status

from . import db
from .config import get_settings
from .security import decode_token


@dataclass
class Principal:
    user_id: str
    is_guest: bool


async def get_principal(
    authorization: str | None = Header(default=None),
) -> Principal:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "登录已失效，请重新登录")
    payload = decode_token(authorization.split(" ", 1)[1])
    if payload is None or not payload.get("sub"):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "登录已失效，请重新登录")
    user = db.get_user(payload["sub"])
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "登录已失效，请重新登录")
    if user["disabled"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "账号已被禁用，请联系管理员")
    return Principal(user_id=user["id"],
                     is_guest=bool(user["is_guest"]))


CurrentUser = Depends(get_principal)


async def require_admin(
    x_admin_token: str | None = Header(default=None),
) -> str:
    """管理接口守卫：X-Admin-Token 缺失/错误一律 401。"""
    settings = get_settings()
    if not x_admin_token or not compare_digest(
            x_admin_token, settings.admin_token):
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "管理令牌缺失或无效",
            headers={"WWW-Authenticate": "AdminToken"},
        )
    return x_admin_token


AdminAuth = Depends(require_admin)
