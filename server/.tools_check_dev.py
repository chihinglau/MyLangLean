import json
import sys
import urllib.request

BASE = "http://127.0.0.1:8000"
TOKEN = "dev-admin-token"


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        headers={"X-Admin-Token": TOKEN,
                 "Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        raw = r.read().decode()
        return r.status, (json.loads(raw) if raw else None)


def find_user(email):
    data = call("GET", "/api/v1/admin/users")[1]
    items = data.get("items", data)
    matches = [u for u in items if u.get("email") == email]
    if not matches:
        raise SystemExit(f"user not found: {email}")
    return matches[0]


def main():
    email = sys.argv[1]
    action = sys.argv[2] if len(sys.argv) > 2 else "show"
    user = find_user(email)
    print("uid=", user["id"], "disabled=", user.get("disabled"))
    _, subs = call("GET", f"/api/v1/admin/users/{user['id']}/subscriptions")
    items = subs.get("items", subs) if isinstance(subs, dict) else subs
    print("sub_count=", len(items))
    for s in items:
        print("SUB:", s.get("id"), s.get("title"),
              "published=", s.get("published"))
    if action in ("disable", "enable"):
        disabled = action == "disable"
        st, _ = call("PATCH", f"/api/v1/admin/users/{user['id']}",
                     {"disabled": disabled})
        print("PATCH status=", st, "->", "disabled" if disabled else "enabled")


if __name__ == "__main__":
    main()
