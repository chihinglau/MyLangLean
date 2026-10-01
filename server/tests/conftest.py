"""pytest 收集前准备：保证 server/ 在 sys.path，并预置临时数据目录环境。"""
import sys
import tempfile
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
SERVER_DIR = TESTS_DIR.parent
if str(SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(SERVER_DIR))
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

import os  # noqa: E402

# 在任何 app.* 模块被导入前设置默认临时数据目录，避免污染 server/data。
os.environ.setdefault(
    "MLL_DATA_DIR", tempfile.mkdtemp(prefix="mll-pytest-"))
