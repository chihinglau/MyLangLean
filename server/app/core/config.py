from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# server/app/core/config.py -> parents[2] == server/
SERVER_DIR = Path(__file__).resolve().parents[2]
# 仓库根（app/assets 在该目录下）
REPO_ROOT = SERVER_DIR.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="MLL_")

    app_name: str = "MyLangLean API"
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_days: int = 30

    # 持久化数据目录：sqlite 库、media/、releases/ 均在其下。
    # 默认 <repo>/server/data，可用环境变量 MLL_DATA_DIR 覆盖。
    data_dir: str = str(SERVER_DIR / "data")
    # 管理接口令牌（请求头 X-Admin-Token），默认仅用于本地开发。
    admin_token: str = "dev-admin-token"

    # 浏览器跨域白名单，逗号分隔；默认 * 仅供本地开发，
    # 生产部署请设置 MLL_CORS_ORIGINS=https://your.domain
    cors_origins: str = "*"

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

    @property
    def db_path(self) -> Path:
        return Path(self.data_dir) / "mll.db"

    @property
    def media_dir(self) -> Path:
        return Path(self.data_dir) / "media"

    @property
    def releases_dir(self) -> Path:
        return Path(self.data_dir) / "releases"


@lru_cache
def get_settings() -> Settings:
    return Settings()
