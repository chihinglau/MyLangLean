from fastapi import APIRouter

from ..core.config import get_settings
from ..core.deps import CurrentUser, Principal, store
from ..models import QuotaOut
from ..services.quota import current_month, used_seconds

router = APIRouter(prefix="/api/v1/quota", tags=["quota"])


@router.get("", response_model=QuotaOut)
def get_quota(principal: Principal = CurrentUser) -> QuotaOut:
    settings = get_settings()
    user = store.get(principal.user_id)
    used = used_seconds(user) if user else 0
    limit = settings.monthly_quota_sec
    return QuotaOut(
        month=current_month(),
        used_sec=used,
        limit_sec=limit,
        remaining_sec=max(0, limit - used),
    )
