"""一键执行全部服务端测试（每个模块独立子进程、独立临时数据目录）。

用法（仓库根）：
    .tools\\venvs\\mll\\Scripts\\python.exe server\\tests\\run_all.py

全部通过时退出码 0，任一失败退出码 1。包含：
  test_db_seed / test_auth / test_catalog / test_subscriptions /
  test_releases / test_admin + 既有 smoke_test 冒烟流程。
"""
import subprocess
import sys
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
PYTHON = sys.executable

MODULES = sorted(p.name for p in TESTS_DIR.glob("test_*.py"))
MODULES.append("smoke_test.py")


def main() -> int:
    results: list[tuple[str, int]] = []
    for name in MODULES:
        print("\n" + "=" * 70)
        print(f"RUN  {name}")
        print("=" * 70)
        proc = subprocess.run([PYTHON, str(TESTS_DIR / name)])
        results.append((name, proc.returncode))

    print("\n" + "#" * 70)
    print("# 测试汇总")
    print("#" * 70)
    passed = sum(1 for _, code in results if code == 0)
    for name, code in results:
        print(f"  {'PASS' if code == 0 else 'FAIL'}  {name} (exit {code})")
    print(f"\n合计 {passed}/{len(results)} 个模块通过")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
