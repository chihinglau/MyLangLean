from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .api import (
    routes_admin,
    routes_auth,
    routes_catalog,
    routes_crawl,
    routes_discover,
    routes_me,
    routes_quota,
    routes_releases,
    routes_score,
    routes_transcriptions,
    routes_translate,
)
from .core import db
from .core.config import SERVER_DIR, get_settings
from .services import crawler

STATIC_ADMIN_DIR = SERVER_DIR / "static" / "admin"


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # 定时内容采集守护线程（间隔由 MLL_CRAWL_INTERVAL_MINUTES 控制）。
    crawler.start_scheduler()
    yield


def create_app() -> FastAPI:
    settings = get_settings()

    # 启动即建表/播种，并确保静态目录存在（StaticFiles 要求目录已存在）。
    db.init_db()
    settings.media_dir.mkdir(parents=True, exist_ok=True)
    settings.releases_dir.mkdir(parents=True, exist_ok=True)
    STATIC_ADMIN_DIR.mkdir(parents=True, exist_ok=True)

    app = FastAPI(
        title=settings.app_name,
        version="0.5.0",
        lifespan=lifespan,
        description=(
            "MyLangLean 服务端。管理接口需 X-Admin-Token"
            "（MLL_ADMIN_TOKEN，开发默认 dev-admin-token）。"
        ),
    )

    # HarmonyOS / iOS clients call from devices; lock down in production
    # via MLL_CORS_ORIGINS.
    cors_origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins or ["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(routes_auth.router)
    app.include_router(routes_me.router)
    app.include_router(routes_quota.router)
    app.include_router(routes_transcriptions.router)
    app.include_router(routes_translate.router)
    app.include_router(routes_score.router)
    app.include_router(routes_discover.router)
    app.include_router(routes_catalog.router)
    app.include_router(routes_admin.router)
    app.include_router(routes_crawl.router)
    app.include_router(routes_releases.router)

    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "asr_backend": settings.asr_backend}

    # 运营管理台：/admin 直接返回单文件页面，其余静态资源走挂载。
    @app.get("/admin", include_in_schema=False)
    def admin_index() -> FileResponse:
        return FileResponse(
            STATIC_ADMIN_DIR / "index.html",
            headers={"Cache-Control": "no-store, must-revalidate"})

    # /media 与下载路由（/api/v1/releases/...）路径不重叠，不会冲突。
    app.mount("/media",
              StaticFiles(directory=str(settings.media_dir)),
              name="media")
    app.mount("/admin",
              StaticFiles(directory=str(STATIC_ADMIN_DIR), html=True),
              name="admin-static")

    @app.middleware("http")
    async def admin_security_headers(request: Request, call_next):
        response = await call_next(request)
        if request.url.path.startswith("/admin"):
            response.headers["Cache-Control"] = "no-store, must-revalidate"
            # 管理台为纯内联单文件页面、零外网资源：默认禁止外部来源。
            response.headers["Content-Security-Policy"] = (
                "default-src 'none'; img-src 'self' data: https:; "
                "style-src 'self' 'unsafe-inline'; "
                "script-src 'self' 'unsafe-inline'; "
                "connect-src 'self'; base-uri 'none'; frame-ancestors 'none'")
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["Referrer-Policy"] = "no-referrer"
        return response

    return app


app = create_app()
