from datetime import datetime, timezone

from fastapi import HTTPException, status

from ..core import db
from ..core.config import get_settings


def current_month() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


def used_seconds(user_id: str, month: str | None = None) -> int:
    return db.used_seconds(user_id, month)


def charge(user_id: str, seconds: int) -> int:
    """Charges quota; raises 402 when exhausted. Returns new used total."""
    settings = get_settings()
    month = current_month()
    used = db.used_seconds(user_id, month)
    if used + seconds > settings.monthly_quota_sec:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            f"monthly quota exhausted: {settings.monthly_quota_sec // 60} min",
        )
    return db.charge_quota(user_id, seconds, settings.monthly_quota_sec, month)
