from fastapi import APIRouter, HTTPException, status

from ..core import db
from ..core.config import get_settings
from ..core.deps import CurrentUser, Principal
from ..models import QuotaOut
from ..services.quota import current_month, used_seconds

router = APIRouter(prefix="/api/v1/quota", tags=["quota"])


@router.get("", response_model=QuotaOut)
def get_quota(principal: Principal = CurrentUser) -> QuotaOut:
    user = db.get_user(principal.user_id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "登录已失效，请重新登录")
    settings = get_settings()
    used = used_seconds(user["id"])
    limit = settings.monthly_quota_sec
    return QuotaOut(
        month=current_month(),
        used_sec=used,
        limit_sec=limit,
        remaining_sec=max(0, limit - used),
    )
