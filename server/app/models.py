import re

from pydantic import BaseModel, Field, field_validator

_DEVICE_ID_RE = re.compile(r"^[A-Za-z0-9._:\-]{1,128}$")


class DeviceLoginIn(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)

    @field_validator("device_id")
    @classmethod
    def _safe_device_id(cls, value: str) -> str:
        # 白名单字符，杜绝设备 ID 中的注入/XSS 载荷。
        if not _DEVICE_ID_RE.match(value):
            raise ValueError("device_id 仅允许字母、数字与 . _ : -")
        return value


class EmailLoginIn(BaseModel):
    email: str
    password: str = Field(min_length=1)


class RegisterIn(BaseModel):
    email: str
    password: str = Field(min_length=6, max_length=128)
    name: str | None = Field(default=None, max_length=64)


class AccountOut(BaseModel):
    id: str
    email: str | None
    name: str
    is_guest: bool
    created_at: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    is_guest: bool
    account: AccountOut | None = None


class QuotaOut(BaseModel):
    month: str
    used_sec: int
    limit_sec: int
    remaining_sec: int


class TranscriptionIn(BaseModel):
    # Either a reachable media URL or an uploaded file (multipart route).
    audio_url: str | None = None
    language: str = "en"
    target_lang: str | None = None
    # Idempotency key prevents double quota charge on retries.
    client_key: str | None = None


class WordOut(BaseModel):
    w: str
    s: float
    e: float
    p: float | None = None


class SegmentOut(BaseModel):
    id: int
    start: float
    end: float
    text: str
    translation: str | None = None
    words: list[WordOut]


class TranscriptOut(BaseModel):
    version: int = 1
    language: str
    duration: float
    segments: list[SegmentOut]


class TranscriptionJobOut(BaseModel):
    id: str
    status: str  # queued | processing | done | error
    transcript: TranscriptOut | None = None
    billed_sec: int = 0
    error: str | None = None


class TranslateIn(BaseModel):
    language: str = "en"
    target_lang: str = "zh"
    texts: list[str] = Field(min_length=1, max_length=200)


class TranslateOut(BaseModel):
    translations: list[str]


class ScoreIn(BaseModel):
    reference_duration_ms: int
    attempt_duration_ms: int
    pause_count: int = 0


class ScoreOut(BaseModel):
    overall: int
    rhythm: int
    fluency: int
    intonation: int
    suggestions: list[str]
