from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="MLL_")

    app_name: str = "MyLangLean API"
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_days: int = 30

    # Free monthly transcription quota per account (seconds = 100 minutes).
    monthly_quota_sec: int = 6000
    # Guest free preview window (seconds).
    guest_preview_sec: int = 300

    # PodcastIndex keys (optional; endpoint returns 503 if unset).
    podcast_index_api_key: str = ""
    podcast_index_api_secret: str = ""

    # ASR backend: "stub" (offline dev) or "faster_whisper".
    asr_backend: str = "stub"
    asr_model: str = "large-v3-turbo"
    asr_device: str = "cpu"
    asr_compute_type: str = "int8"


@lru_cache
def get_settings() -> Settings:
    return Settings()
