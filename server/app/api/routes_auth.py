import uuid

from fastapi import APIRouter

from ..core.deps import store
from ..core.security import create_token
from ..models import DeviceLoginIn, EmailLoginIn, TokenOut

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post("/device", response_model=TokenOut)
def login_as_device(body: DeviceLoginIn) -> TokenOut:
    """Guest login: client sends a persistent device id, no password."""
    user = store.upsert_guest(body.device_id)
    token = create_token(user.id, is_guest=True)
    return TokenOut(access_token=token, is_guest=True)


@router.post("/login", response_model=TokenOut)
def login(body: EmailLoginIn) -> TokenOut:
    user = store.login_email(body.email, body.password)
    token = create_token(user.id, is_guest=False)
    return TokenOut(access_token=token, is_guest=False)
