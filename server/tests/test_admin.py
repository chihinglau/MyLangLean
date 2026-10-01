"""AC-3/AC-7：管理员鉴权、用户管理、管理台页面。"""
import re
import sys

import harness

ADMIN = harness.ADMIN_HEADERS
API = "/api/v1"


def test_admin_users_auth():
    with harness.fresh_client() as (client, _):
        # 无/错/对 Token
        assert client.get(f"{API}/admin/users").status_code == 401
        assert client.get(
            f"{API}/admin/users",
            headers={"X-Admin-Token": "nope"}).status_code == 401
        r = client.get(f"{API}/admin/users", headers=ADMIN)
        assert r.status_code == 200, r.text
        assert r.json()["total"] >= 0


def test_admin_user_lifecycle():
    with harness.fresh_client() as (client, _):
        token = harness.register(client, email="ops@x.com", name="小运维")
        me = client.get(f"{API}/me",
                        headers=harness.auth_header(token)).json()

        # 改名 + 禁用
        r = client.patch(f"{API}/admin/users/{me['id']}", headers=ADMIN,
                         json={"name": "新名字", "disabled": True})
        assert r.status_code == 200, r.text
        assert r.json()["name"] == "新名字"
        assert r.json()["disabled"] is True
        assert client.post("/api/v1/auth/login",
                           json={"email": "ops@x.com",
                                 "password": "secret123"}).status_code == 403

        # 启用 + 重置密码
        r = client.patch(f"{API}/admin/users/{me['id']}", headers=ADMIN,
                         json={"disabled": False,
                               "reset_password": "new-pass-1"})
        assert r.status_code == 200, r.text
        # 旧密码失败、新密码成功
        assert client.post("/api/v1/auth/login",
                           json={"email": "ops@x.com",
                                 "password": "secret123"}).status_code == 401
        r = client.post("/api/v1/auth/login",
                        json={"email": "ops@x.com",
                              "password": "new-pass-1"})
        assert r.status_code == 200, r.text

        # 过短重置密码 422；不存在用户 404
        r = client.patch(f"/api/v1/admin/users/{me['id']}", headers=ADMIN,
                         json={"reset_password": "123"})
        assert r.status_code == 422, r.text
        assert client.patch(
            f"{API}/admin/users/missing", headers=ADMIN,
            json={"name": "x"}).status_code == 404


def test_admin_page_served_offline():
    with harness.fresh_client() as (client, _):
        # /admin 与 /admin/ 均应返回同一单文件页面
        for url in ("/admin", "/admin/"):
            r = client.get(url, follow_redirects=True)
            assert r.status_code == 200, (url, r.status_code)
            html = r.text
            assert "<!DOCTYPE html>" in html or "<!doctype html>" in html
            # 四个功能区标记 + token 登录输入
            for section in ("users", "content", "subscriptions", "releases"):
                assert f'data-section="{section}"' in html
            assert 'id="admin-token"' in html
            # 无外部 CDN / 外网资源
            assert "cdn." not in html
            assert not re.search(r'(src|href)="https?://', html)


def test_discover_proxy_still_present():
    with harness.fresh_client() as (client, _):
        # 未配置 PodcastIndex 凭据时保持原有 503 行为。
        r = client.get(f"{API}/discover/proxy?q=hello")
        assert r.status_code == 503, r.text


if __name__ == "__main__":
    sys.exit(harness.run_module(__name__))
