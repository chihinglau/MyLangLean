"""AC-5：订阅幂等/404/退订，以及管理员查看用户订阅与计数。"""
import sys

import harness

ADMIN = harness.ADMIN_HEADERS
API = "/api/v1"


def _my_subs(client, token):
    r = client.get(f"{API}/me/subscriptions",
                   headers=harness.auth_header(token))
    assert r.status_code == 200, r.text
    return r.json()


def test_subscription_crud_and_404():
    with harness.fresh_client() as (client, _):
        token = harness.register(client)

        # 空列表
        body = _my_subs(client, token)
        assert body["items"] == []
        assert body["content_version"]

        # PUT 两次幂等 204，GET 为 1
        r = client.put(f"{API}/me/subscriptions/p1",
                       headers=harness.auth_header(token))
        assert r.status_code == 204, r.text
        r = client.put(f"{API}/me/subscriptions/p1",
                       headers=harness.auth_header(token))
        assert r.status_code == 204, r.text
        body = _my_subs(client, token)
        assert len(body["items"]) == 1
        assert body["items"][0]["id"] == "p1"
        assert body["items"][0]["feedUrl"]  # camelCase 完整播客对象

        # 不存在的播客 404
        r = client.put(f"{API}/me/subscriptions/no-such-id",
                       headers=harness.auth_header(token))
        assert r.status_code == 404, r.text

        # 下架播客订阅 404
        r = client.patch(f"{API}/admin/podcasts/p2", headers=ADMIN,
                         json={"published": False})
        assert r.status_code == 200
        r = client.put(f"{API}/me/subscriptions/p2",
                       headers=harness.auth_header(token))
        assert r.status_code == 404

        # DELETE 后为 0；重复 DELETE 仍 204（幂等）
        r = client.delete(f"{API}/me/subscriptions/p1",
                          headers=harness.auth_header(token))
        assert r.status_code == 204, r.text
        assert len(_my_subs(client, token)["items"]) == 0
        r = client.delete(f"{API}/me/subscriptions/p1",
                          headers=harness.auth_header(token))
        assert r.status_code == 204, r.text


def test_subscriptions_require_auth():
    with harness.fresh_client() as (client, _):
        assert client.get(f"{API}/me/subscriptions").status_code == 401
        assert client.put(f"{API}/me/subscriptions/p1").status_code == 401


def test_admin_views_user_subscriptions():
    with harness.fresh_client() as (client, _):
        token = harness.register(client, email="sub@x.com")
        me = client.get(f"{API}/me",
                        headers=harness.auth_header(token)).json()

        client.put(f"{API}/me/subscriptions/p4",
                   headers=harness.auth_header(token))
        client.put(f"{API}/me/subscriptions/p8",
                   headers=harness.auth_header(token))

        # 管理员用户列表带订阅数
        users = client.get(f"{API}/admin/users", headers=ADMIN).json()
        row = next(u for u in users["items"] if u["id"] == me["id"])
        assert row["subscription_count"] == 2
        assert row["disabled"] is False
        assert row["created_at"]

        # 管理员直接看该用户订阅
        r = client.get(
            f"{API}/admin/users/{me['id']}/subscriptions", headers=ADMIN)
        assert r.status_code == 200, r.text
        ids = {p["id"] for p in r.json()["items"]}
        assert ids == {"p4", "p8"}

        # 不存在用户 404
        assert client.get(
            f"{API}/admin/users/nope/subscriptions",
            headers=ADMIN).status_code == 404


if __name__ == "__main__":
    sys.exit(harness.run_module(__name__))
