"""账号鉴权：游客设备登录、邮箱注册、邮箱登录。"""
import re
import sqlite3

from fastapi import APIRouter, HTTPException, status

from ..core import db
from ..core.security import create_token, verify_password
from ..models import (
    AccountOut,
    DeviceLoginIn,
    EmailLoginIn,
    RegisterIn,
    TokenOut,
)

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

# 简单邮箱正则：本地名@域名.顶级域（不允许空白）。
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def token_for(user) -> TokenOut:
    account = AccountOut(**db.account_out(user))
    token = create_token(user["id"], is_guest=bool(user["is_guest"]))
    return TokenOut(
        access_token=token,
        is_guest=bool(user["is_guest"]),
        account=account,
    )


@router.post("/device", response_model=TokenOut)
def login_as_device(body: DeviceLoginIn) -> TokenOut:
    """Guest login: client sends a persistent device id, no password."""
    user = db.upsert_guest(body.device_id)
    return token_for(user)


@router.post("/register", response_model=TokenOut)
def register(body: RegisterIn) -> TokenOut:
    email = body.email.strip().lower()
    if not EMAIL_RE.match(email):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "邮箱格式不正确")
    if db.get_user_by_email(email) is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "邮箱已注册")
    try:
        user = db.create_user(email, body.password, body.name or "")
    except sqlite3.IntegrityError:
        # 并发同邮箱注册的竞态窗口。
        raise HTTPException(status.HTTP_409_CONFLICT, "邮箱已注册")
    return token_for(user)


@router.post("/login", response_model=TokenOut)
def login(body: EmailLoginIn) -> TokenOut:
    email = body.email.strip().lower()
    user = db.get_user_by_email(email)
    if user is None or not verify_password(body.password,
                                          user["password_hash"]):
        # 不区分“未注册/错密码”，避免账号枚举。
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "邮箱或密码错误")
    if user["disabled"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "账号已被禁用")
    return token_for(user)
