"""测试公共工具：每个用例使用独立临时 MLL_DATA_DIR 与全新 FastAPI app。

- 直接 `python test_xxx.py` 与 `pytest` 两种形态均可用。
- 在导入 app.main 之前先放入临时 MLL_DATA_DIR，避免模块级 app 污染仓库。
"""
from __future__ import annotations

import os
import sys
import tempfile
import traceback
from contextlib import contextmanager
from pathlib import Path

SERVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_DIR))

# 仅用于 app.main 模块级默认 app（测试不会真正使用它）。
_SESSION_DIR = tempfile.mkdtemp(prefix="mll-session-")
os.environ.setdefault("MLL_DATA_DIR", _SESSION_DIR)

from fastapi.testclient import TestClient  # noqa: E402

from app.core import db  # noqa: E402
from app.core.config import get_settings  # noqa: E402
from app.main import create_app  # noqa: E402

ADMIN_TOKEN = "dev-admin-token"
ADMIN_HEADERS = {"X-Admin-Token": ADMIN_TOKEN}


@contextmanager
def fresh_client():
    """yield (TestClient, data_dir: Path)，每个用例独立数据目录。"""
    data_dir = Path(tempfile.mkdtemp(prefix="mll-test-"))
    os.environ["MLL_DATA_DIR"] = str(data_dir)
    get_settings.cache_clear()
    db.init_db()
    application = create_app()
    with TestClient(application) as client:
        yield client, data_dir


def auth_header(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def register(client, email: str = "learner@example.com",
             password: str = "secret123", name: str | None = None) -> str:
    body = {"email": email, "password": password}
    if name is not None:
        body["name"] = name
    r = client.post("/api/v1/auth/register", json=body)
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def run_module(module_name: str) -> int:
    """直跑入口：顺序执行本模块内全部 test_* 函数。"""
    module = sys.modules[module_name]
    failures = 0
    tests = sorted(
        name for name in dir(module)
        if name.startswith("test_") and callable(getattr(module, name))
    )
    for name in tests:
        try:
            getattr(module, name)()
            print(f"PASS {name}")
        except Exception:  # noqa: BLE001
            failures += 1
            print(f"FAIL {name}")
            traceback.print_exc()
    print(f"\n{len(tests) - failures}/{len(tests)} passed")
    return 1 if failures else 0
