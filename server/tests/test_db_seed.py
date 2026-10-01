"""AC-1/TR-1：建表、首次播种、幂等、媒体复制、密码哈希自验。"""
import sqlite3
import sys

import harness

from app.core import db
from app.core.config import REPO_ROOT
from app.core.security import hash_password, verify_password


def test_tables_seed_counts_and_idempotency():
    with harness.fresh_client() as (client, data_dir):
        conn = sqlite3.connect(data_dir / "mll.db")
        names = {
            r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'")
        }
        conn.close()
        for table in ("users", "podcasts", "episodes", "subscriptions",
                      "releases"):
            assert table in names, names

        conn = sqlite3.connect(data_dir / "mll.db")
        assert conn.execute("SELECT COUNT(*) FROM podcasts").fetchone()[0] == 8
        assert conn.execute("SELECT COUNT(*) FROM episodes").fetchone()[0] == 16
        conn.close()

        # 重复 init / create_app 不重复播种。
        db.init_db()
        db.init_db()
        conn = sqlite3.connect(data_dir / "mll.db")
        assert conn.execute("SELECT COUNT(*) FROM podcasts").fetchone()[0] == 8
        assert conn.execute("SELECT COUNT(*) FROM episodes").fetchone()[0] == 16
        conn.close()


def test_media_served_and_identical_to_asset():
    with harness.fresh_client() as (client, data_dir):
        dest = data_dir / "media" / "sample.mp3"
        assert dest.exists()
        source = REPO_ROOT / "app" / "assets" / "audio" / "sample.mp3"
        assert dest.read_bytes() == source.read_bytes()

        r = client.get("/media/sample.mp3")
        assert r.status_code == 200, r.text
        assert r.content == source.read_bytes()


def test_seed_episode_fields_match_mock_catalog():
    with harness.fresh_client() as (client, _):
        r = client.get("/api/v1/catalog/podcasts/p1/episodes")
        assert r.status_code == 200, r.text
        eps = r.json()
        assert len(eps) == 2
        assert eps[0]["id"] == "p1-e1"
        assert eps[0]["podcastId"] == "p1"
        assert eps[0]["audioUrl"] == "/media/sample.mp3"
        assert eps[0]["durationMs"] == 17640
        assert eps[0]["pubDate"] == "2026-09-20"
        assert eps[1]["pubDate"] == "2026-09-13"


def test_pbkdf2_password_hashing():
    h1 = hash_password("secret123")
    h2 = hash_password("secret123")
    assert h1.startswith("pbkdf2$")
    assert h1 != h2  # 盐不同
    assert h1 != "secret123"
    assert verify_password("secret123", h1)
    assert verify_password("secret123", h2)
    assert not verify_password("wrong-pass", h1)
    assert not verify_password("secret123", None)
    assert not verify_password("secret123", "garbage")


if __name__ == "__main__":
    sys.exit(harness.run_module(__name__))
