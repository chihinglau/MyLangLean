"""安装包发布 / OTA 版本检查 / 下载（支持 Range）。"""
import hashlib
import re
import time
import uuid

from fastapi import (
    APIRouter,
    File,
    Form,
    HTTPException,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse

from ..core import db
from ..core.config import get_settings
from ..core.deps import AdminAuth

router = APIRouter(prefix="/api/v1", tags=["releases"])

APK_MEDIA_TYPE = "application/vnd.android.package-archive"
ALLOWED_PLATFORMS = {"android", "ohos"}
ALLOWED_CHANNELS = {"stable", "beta", "alpha"}
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")


def _validate_release_fields(platform: str, channel: str,
                             version: str, build_no: int) -> None:
    if platform not in ALLOWED_PLATFORMS:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"platform 仅支持 {sorted(ALLOWED_PLATFORMS)}")
    if channel not in ALLOWED_CHANNELS:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"channel 仅支持 {sorted(ALLOWED_CHANNELS)}")
    if not SEMVER_RE.match(version or ""):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "version 必须是语义版本号，形如 0.4.1")
    if build_no < 0:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "buildNo 不能为负数")


@router.post("/admin/releases", dependencies=[AdminAuth])
async def upload_release(
    file: UploadFile = File(...),
    platform: str = Form("android"),
    version: str = Form(...),
    buildNo: int = Form(...),
    channel: str = Form("stable"),
    notes: str = Form(""),
    mandatory: bool = Form(False),
) -> dict:
    filename = file.filename or ""
    if not filename.lower().endswith(".apk"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "仅支持 .apk 文件")
    platform = platform.strip()
    channel = channel.strip()
    version = version.strip()
    _validate_release_fields(platform, channel, version, buildNo)

    settings = get_settings()
    settings.releases_dir.mkdir(parents=True, exist_ok=True)
    # 落盘文件名只由白名单字段 + 随机 ID 组成，杜绝路径穿越。
    safe_name = (f"{platform}-{version}-{buildNo}-{uuid.uuid4().hex[:8]}.apk")
    dest = (settings.releases_dir / safe_name).resolve()
    releases_root = settings.releases_dir.resolve()
    if not str(dest).startswith(str(releases_root) + "\\") \
            and dest != releases_root:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "非法存储路径")

    sha = hashlib.sha256()
    size = 0
    try:
        with dest.open("wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
                sha.update(chunk)
                size += len(chunk)
    except Exception:
        # 写入失败不留半成品。
        dest.unlink(missing_ok=True)
        raise

    row = db.create_release(
        platform=platform, version=version, build_no=buildNo,
        channel=channel, notes=notes, mandatory=mandatory,
        filename=safe_name, size=size, sha256=sha.hexdigest(),
    )
    return db.release_out(row)


@router.get("/admin/releases", dependencies=[AdminAuth])
def admin_list_releases() -> dict:
    items = db.list_releases()
    return {"items": items, "total": len(items)}


@router.delete("/admin/releases/{release_id}",
               status_code=204, dependencies=[AdminAuth])
def admin_delete_release(release_id: int):
    row = db.delete_release(release_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "发布版本不存在")
    # 连带删除磁盘文件（不存在也忽略）。
    path = get_settings().releases_dir / row["filename"]
    try:
        path.unlink()
    except FileNotFoundError:
        pass


@router.get("/releases/latest")
def latest(platform: str = "android", channel: str = "stable",
           current: str = "") -> dict:
    if platform not in ALLOWED_PLATFORMS or channel not in ALLOWED_CHANNELS:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                            "platform/channel 不支持")
    if db.parse_version(current) is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                            "current 版本号格式不正确，应为 0.4.0+4 形式")
    item = db.latest_release(platform=platform, channel=channel)
    if item is None or not db.has_update(current, item):
        return {"has_update": False}
    return {"has_update": True, **item}


@router.get("/releases")
def public_list_releases(platform: str | None = None,
                         channel: str | None = None) -> dict:
    items = db.list_releases(platform=platform, channel=channel)
    return {"items": items, "total": len(items)}


@router.get("/releases/download/{release_id}")
def download_release(release_id: int):
    row = db.get_release(release_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "发布版本不存在")
    settings = get_settings()
    path = settings.releases_dir / row["filename"]
    if not path.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "安装包文件在服务器上已不存在")
    # starlette FileResponse 原生支持 Range/206 断点续传。
    return FileResponse(
        path,
        media_type=APK_MEDIA_TYPE,
        filename=row["filename"],
    )
