from datetime import datetime, timedelta, timezone
from hashlib import pbkdf2_hmac
from hmac import compare_digest
import secrets

from jose import JWTError, jwt

from .config import get_settings

PBKDF2_ITERS = 200_000
PBKDF2_PREFIX = "pbkdf2"


def create_token(subject: str, is_guest: bool) -> str:
    settings = get_settings()
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "guest": is_guest,
        "iat": now,
        "exp": now + timedelta(days=settings.jwt_expire_days),
    }
    return jwt.encode(payload, settings.jwt_secret,
                      algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict | None:
    settings = get_settings()
    try:
        return jwt.decode(token, settings.jwt_secret,
                          algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None


# ---------------------------------------------------------------------------
# 密码哈希：PBKDF2-HMAC-SHA256，每用户独立 16 字节盐，存储格式
# pbkdf2$<iters>$<salt_hex>$<hash_hex>
# ---------------------------------------------------------------------------

def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("ascii"),
        PBKDF2_ITERS,
    ).hex()
    return f"{PBKDF2_PREFIX}${PBKDF2_ITERS}${salt}${digest}"


def verify_password(password: str, stored: str | None) -> bool:
    if not stored:
        return False
    try:
        scheme, iters_str, salt, digest = stored.split("$", 3)
        if scheme != PBKDF2_PREFIX:
            return False
        iters = int(iters_str)
    except (ValueError, AttributeError):
        return False
    candidate = pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("ascii"), iters,
    ).hex()
    return compare_digest(candidate, digest)
