from dataclasses import dataclass, field

from fastapi import Depends, Header, HTTPException, status

from .security import decode_token


@dataclass
class Principal:
    user_id: str
    is_guest: bool


# MVP in-memory stores. Swap for PostgreSQL/Redis behind the same interface.
@dataclass
class UserRow:
    id: str
    email: str | None
    is_guest: bool
    password: str | None = None
    used_sec: dict[str, int] = field(default_factory=dict)  # "YYYY-MM" -> sec


class UserStore:
    def __init__(self) -> None:
        self._rows: dict[str, UserRow] = {}
        self._by_email: dict[str, str] = {}

    def upsert_guest(self, device_id: str) -> UserRow:
        uid = f"guest:{device_id}"
        if uid not in self._rows:
            self._rows[uid] = UserRow(id=uid, email=None, is_guest=True)
        return self._rows[uid]

    def login_email(self, email: str, password: str) -> UserRow:
        email = email.strip().lower()
        uid = self._by_email.get(email)
        if uid is None:
            # Auto-register in MVP; real deploy adds verification + hashing.
            import hashlib

            uid = f"user:{email}"
            self._rows[uid] = UserRow(
                id=uid,
                email=email,
                is_guest=False,
                password=hashlib.sha256(password.encode()).hexdigest(),
            )
            self._by_email[email] = uid
        return self._rows[uid]

    def get(self, uid: str) -> UserRow | None:
        return self._rows.get(uid)


store = UserStore()


async def get_principal(
    authorization: str | None = Header(default=None),
) -> Principal:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing bearer token")
    payload = decode_token(authorization.split(" ", 1)[1])
    if payload is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid token")
    return Principal(user_id=payload["sub"],
                     is_guest=bool(payload.get("guest", False)))


CurrentUser = Depends(get_principal)
