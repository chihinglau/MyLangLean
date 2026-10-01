"""AC-2：注册/重复/错密/正确登录/me/禁用/游客/无 Token/哈希落库。"""
import sqlite3
import sys

import harness

from app.core.config import get_settings

ADMIN = harness.ADMIN_HEADERS
EMAIL = "a@x.com"
PASSWORD = "secret123"


def test_full_auth_flow():
    with harness.fresh_client() as (client, _):
        # 注册 200 + JWT + account
        r = client.post("/api/v1/auth/register",
                        json={"email": EMAIL, "password": PASSWORD,
                              "name": "阿雅"})
        assert r.status_code == 200, r.text
        data = r.json()
        token = data["access_token"]
        assert token and data["token_type"] == "bearer"
        assert data["is_guest"] is False
        account = data["account"]
        assert account["email"] == EMAIL
        assert account["name"] == "阿雅"
        assert account["is_guest"] is False
        assert account["created_at"]

        # 重复注册 409
        r = client.post("/api/v1/auth/register",
                        json={"email": "A@X.com", "password": PASSWORD})
        assert r.status_code == 409, r.text

        # 错误密码 401；未注册邮箱 401
        assert client.post("/api/v1/auth/login",
                           json={"email": EMAIL,
                                 "password": "bad-pass"}).status_code == 401
        assert client.post("/api/v1/auth/login",
                           json={"email": "nobody@x.com",
                                 "password": PASSWORD}).status_code == 401

        # 正确登录 200 + JWT
        r = client.post("/api/v1/auth/login",
                        json={"email": EMAIL, "password": PASSWORD})
        assert r.status_code == 200, r.text
        login_token = r.json()["access_token"]
        assert login_token

        # /me 资料正确
        r = client.get("/api/v1/me", headers=harness.auth_header(token))
        assert r.status_code == 200, r.text
        me = r.json()
        assert me["email"] == EMAIL
        assert me["id"] == account["id"]

        # 管理员禁用后，被禁用用户登录 403
        r = client.patch(f"/api/v1/admin/users/{account['id']}",
                         headers=ADMIN, json={"disabled": True})
        assert r.status_code == 200, r.text
        r = client.post("/api/v1/auth/login",
                        json={"email": EMAIL, "password": PASSWORD})
        assert r.status_code == 403, r.text

        # 被禁用后旧 Token 访问 /me 也 403
        r = client.get("/api/v1/me", headers=harness.auth_header(token))
        assert r.status_code == 403, r.text

        # 无 Token / 坏 Token 访问 /me 401
        assert client.get("/api/v1/me").status_code == 401
        assert client.get(
            "/api/v1/me",
            headers={"Authorization": "Bearer not-a-jwt"}).status_code == 401

        # 密码落库为 pbkdf2 串且非明文
        conn = sqlite3.connect(get_settings().db_path)
        row = conn.execute(
            "SELECT password_hash FROM users WHERE email=?", (EMAIL,)).fetchone()
        conn.close()
        assert row and row[0].startswith("pbkdf2$")
        assert row[0] != PASSWORD


def test_invalid_register_inputs():
    with harness.fresh_client() as (client, _):
        # 邮箱格式错误 400
        r = client.post("/api/v1/auth/register",
                        json={"email": "not-an-email", "password": PASSWORD})
        assert r.status_code == 400, r.text
        # 密码不足 6 位 -> pydantic 422
        r = client.post("/api/v1/auth/register",
                        json={"email": "b@x.com", "password": "123"})
        assert r.status_code == 422, r.text


def test_guest_device_persisted():
    with harness.fresh_client() as (client, _):
        r = client.post("/api/v1/auth/device",
                        json={"device_id": "dev-xyz"})
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["is_guest"] is True
        assert data["account"]["is_guest"] is True
        guest_id = data["account"]["id"]

        # 同一设备重复登录：命中同一持久游客行
        r2 = client.post("/api/v1/auth/device",
                         json={"device_id": "dev-xyz"})
        assert r2.json()["account"]["id"] == guest_id

        # 游客也能访问 /me
        r = client.get("/api/v1/me",
                       headers=harness.auth_header(data["access_token"]))
        assert r.status_code == 200, r.text
        assert r.json()["is_guest"] is True


if __name__ == "__main__":
    sys.exit(harness.run_module(__name__))
