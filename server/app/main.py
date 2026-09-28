from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import (
    routes_auth,
    routes_discover,
    routes_score,
    routes_transcriptions,
    routes_translate,
    routes_quota,
)
from .core.config import get_settings

settings = get_settings()

app = FastAPI(title=settings.app_name, version="0.1.0")

# HarmonyOS / iOS clients call from devices; lock down in production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(routes_auth.router)
app.include_router(routes_quota.router)
app.include_router(routes_transcriptions.router)
app.include_router(routes_translate.router)
app.include_router(routes_score.router)
app.include_router(routes_discover.router)


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "asr_backend": settings.asr_backend}
