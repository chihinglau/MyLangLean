from datetime import datetime, timezone

from fastapi import HTTPException, status

from ..core.config import get_settings
from ..core.deps import UserRow


def current_month() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


def used_seconds(user: UserRow, month: str | None = None) -> int:
    return user.used_sec.get(month or current_month(), 0)


def charge(user: UserRow, seconds: int) -> int:
    """Charges quota; raises 402 when exhausted. Returns new used total."""
    settings = get_settings()
    month = current_month()
    used = used_seconds(user, month)
    if used + seconds > settings.monthly_quota_sec:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            f"monthly quota exhausted: {settings.monthly_quota_sec // 60} min",
        )
    user.used_sec[month] = used + seconds
    return user.used_sec[month]
