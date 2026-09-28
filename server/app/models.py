from pydantic import BaseModel, Field


class DeviceLoginIn(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)


class EmailLoginIn(BaseModel):
    email: str
    password: str = Field(min_length=4)


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    is_guest: bool


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
