"""PodcastIndex proxy.

Keeps apiKey/apiSecret on the server and signs requests per
https://podcastindex-org.github.io/docs-api/
Returns 503 when credentials are not configured.
"""
import time

import httpx
from fastapi import APIRouter, HTTPException, status

from ..core.config import get_settings

router = APIRouter(prefix="/api/v1/discover", tags=["discover"])


@router.get("/proxy")
async def podcast_index_search(q: str, max: int = 20) -> dict:
    settings = get_settings()
    if not settings.podcast_index_api_key:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "PODCASTINDEX credentials not configured",
        )
    epoch = int(time.time())
    # sha1(apiSecret + epoch) is required by PodcastIndex auth.
    import hashlib

    sha1 = hashlib.sha1(
        f"{settings.podcast_index_api_secret}{epoch}".encode()).hexdigest()
    headers = {
        "X-Auth-Date": str(epoch),
        "X-Auth-Key": settings.podcast_index_api_key,
        "Authorization": sha1,
        "User-Agent": "MyLangLean/0.1",
    }
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.get(
            "https://api.podcastindex.org/api/1.0/search/byterm",
            params={"q": q, "max": max},
            headers=headers,
        )
        return resp.json()
