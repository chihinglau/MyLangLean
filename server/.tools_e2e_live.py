# -*- coding: utf-8 -*-
"""PC 服务端 live E2E：对运行中的 uvicorn (127.0.0.1:8000) 跑全链路。
零三方依赖。发布用 APK 为 app/build/.../app-debug.apk。"""
import hashlib
import io
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = "http://127.0.0.1:8000/api/v1"
ADMIN_TOKEN = "dev-admin-token"
APK_PATH = (
    r"D:\ai\prj\trae\HuaWei\MyLangLean\app\build\app\outputs"
    r"\flutter-apk\app-debug.apk"
)

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))
    print(f"[{'PASS' if cond else 'FAIL'}] {name} {detail}")
    if not cond:
        raise SystemExit(f"E2E 失败: {name} {detail}")


def call(method, path, token=None, body=None, raw=None, ctype=None):
    url = path if path.startswith("http") else BASE + path
    headers = {}
    data = None
    if raw is not None:
        data = raw
        if ctype:
            headers["Content-Type"] = ctype
    elif body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
    if token and "/admin/" in path:
        headers["X-Admin-Token"] = token
    elif token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = resp.read()
            return resp.status, dict(resp.headers), payload
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def j(method, path, token=None, body=None):
    status, _, payload = call(method, path, token, body)
    if not payload:
        return status, None
    try:
        return status, json.loads(payload.decode("utf-8"))
    except json.JSONDecodeError:
        raise SystemExit(f"非 JSON 响应 {status}: {payload[:200]!r}")


def multipart(fields: dict, file_field: str, filename: str, content: bytes,
              content_type="application/octet-stream"):
    boundary = "----mllboundary" + uuid.uuid4().hex
    buf = io.BytesIO()
    for k, v in fields.items():
        buf.write(f"--{boundary}\r\n".encode())
        buf.write(
            f'Content-Disposition: form-data; name="{k}"\r\n\r\n'.encode())
        buf.write(f"{v}\r\n".encode("utf-8"))
    buf.write(f"--{boundary}\r\n".encode())
    buf.write(
        f'Content-Disposition: form-data; name="{file_field}"; '
        f'filename="{filename}"\r\n'.encode())
    buf.write(f"Content-Type: {content_type}\r\n\r\n".encode())
    buf.write(content)
    buf.write(f"\r\n--{boundary}--\r\n".encode())
    return buf.getvalue(), f"multipart/form-data; boundary={boundary}"


ts = int(time.time())
email = f"e2e_{ts}@mll.test"

# 1. 游客
st, guest = j("POST", "/auth/device", body={"device_id": f"e2e-dev-{ts}"})
check("游客登录 200", st == 200 and guest["access_token"], st)

# 2. 注册
st, reg = j("POST", "/auth/register", body={
    "email": email, "password": "passw0rd123", "name": "E2E用户"})
check("注册 200 且返回账号", st == 200 and reg["account"]["email"] == email, st)
token = reg["access_token"]
uid = reg["account"]["id"]

# 3. /me
st, me = j("GET", "/me", token)
check("GET /me 身份一致", st == 200 and me["email"] == email, st)

# 4. 错误密码注册 409 / 登录 401
st, _ = j("POST", "/auth/register", body={
    "email": email, "password": "passw0rd123"})
check("重复邮箱注册 409", st == 409, st)
st, _ = j("POST", "/auth/login", body={"email": email, "password": "bad"})
check("错误密码登录 401", st == 401, st)

# 5. 订阅 p1
st, _, _ = call("PUT", "/me/subscriptions/p1", token)
check("订阅 p1 204", st == 204, st)
st, subs = j("GET", "/me/subscriptions", token)
check("订阅列表含 p1", st == 200 and any(i["id"] == "p1" for i in subs["items"]), st)

# 订阅不存在目标 404
st, _, _ = call("PUT", "/me/subscriptions/nope-xyz", token)
check("订阅不存在播客 404", st == 404, st)

# 6. 管理端查用户/订阅
st, users = j("GET", "/admin/users", ADMIN_TOKEN)
found = any(u["id"] == uid for u in users["items"])
check("管理台用户列表含新用户", st == 200 and found, f"total={users['total']}")
st, usubs = j("GET", f"/admin/users/{uid}/subscriptions", ADMIN_TOKEN)
check("管理台查看用户订阅含 p1",
      st == 200 and any(i["id"] == "p1" for i in usubs["items"]), st)

# 7. 发布独家播客 + 单集
exclusive_title = f"E2E 独家英语频道 {ts}"
st, pod = j("POST", "/admin/podcasts", ADMIN_TOKEN, {
    "title": exclusive_title, "author": "E2E 测试台", "language": "en",
    "level": "beginner",
    "description": "仅由 PC 管理台发布的独家内容，用于发现页网络同步验证",
    "feedUrl": "", "published": True})
check("管理台创建独家播客", st == 200 and pod["id"], st)
pid = pod["id"]
st, ep = j("POST", f"/admin/podcasts/{pid}/episodes", ADMIN_TOKEN, {
    "title": "独家首播 Episode", "audioUrl": "/media/sample.mp3",
    "durationMs": 120000, "language": "en"})
check("管理台为独家播客添加单集", st == 200 and ep["id"], st)
check("单集音频地址为绝对/可拼接 URL",
      ep["audioUrl"].endswith("/media/sample.mp3"), ep["audioUrl"])

# 8. 发现页网络同步命中独家内容（匿名即可）
st, cat = j("GET", "/catalog/podcasts?q=" + urllib.parse.quote("独家"))
hit = any(i["id"] == pid for i in cat["items"])
check("发现页搜索命中服务端独家内容", st == 200 and hit,
      f"items={len(cat['items'])}")
st, eps = j("GET", f"/catalog/podcasts/{pid}/episodes")
check("独家播客单集可拉取", st == 200 and len(eps) == 1, st)

# 9. 用户订阅独家内容并在管理台可见
call("PUT", f"/me/subscriptions/{pid}", token)
st, usubs = j("GET", f"/admin/users/{uid}/subscriptions", ADMIN_TOKEN)
check("管理台可见用户订阅的独家频道",
      any(i["id"] == pid for i in usubs["items"]), st)

# 10. “重装”：全新会话重新登录，订阅仍在（服务端持久化）
st, relog = j("POST", "/auth/login",
              body={"email": email, "password": "passw0rd123"})
check("重装后重新登录", st == 200, st)
st, subs2 = j("GET", "/me/subscriptions", relog["access_token"])
ids = {i["id"] for i in subs2["items"]}
check("重装后订阅服务端仍在 (p1+独家)", "p1" in ids and pid in ids,
      str(sorted(ids)))

# 11. 下架后发现页不可见，重新上架可见
j("PATCH", f"/admin/podcasts/{pid}", ADMIN_TOKEN, {"published": False})
st, cat2 = j("GET", "/catalog/podcasts?q=" + urllib.parse.quote("独家"))
check("下架后发现页不可见", not any(i["id"] == pid for i in cat2["items"]), st)
j("PATCH", f"/admin/podcasts/{pid}", ADMIN_TOKEN, {"published": True})
st, cat3 = j("GET", "/catalog/podcasts?q=" + urllib.parse.quote("独家"))
check("重新上架后发现页恢复", any(i["id"] == pid for i in cat3["items"]), st)

# 12. 用户禁用/启用
j("PATCH", f"/admin/users/{uid}", ADMIN_TOKEN, {"disabled": True})
st, _, _ = call("GET", "/me", token)
check("禁用用户旧 token 被拒 (401/403)", st in (401, 403), st)
st, _ = j("POST", "/auth/login",
          body={"email": email, "password": "passw0rd123"})
check("禁用用户无法登录", st in (401, 403), st)
j("PATCH", f"/admin/users/{uid}", ADMIN_TOKEN, {"disabled": False})
st, relog2 = j("POST", "/auth/login",
               body={"email": email, "password": "passw0rd123"})
check("重新启用后可登录", st == 200, st)

# 13. 发布升级：非 apk 必须 400
bogus, ct = multipart(
    {"platform": "android", "version": "9.9.9", "buildNo": "99",
     "channel": "stable"}, "file", "evil.bin", b"x")
st, _, _ = call("POST", "/admin/releases", ADMIN_TOKEN,
                raw=bogus, ctype=ct)
check("非 APK 文件拒绝 400", st == 400, st)

# 14. 上传真实 debug APK 为 0.4.1+5
with open(APK_PATH, "rb") as f:
    apk_bytes = f.read()
apk_sha = hashlib.sha256(apk_bytes).hexdigest()
apk_size = len(apk_bytes)
print(f"APK {apk_size} bytes sha256={apk_sha[:16]}...")
body, ct = multipart({
    "platform": "android", "version": "0.4.1", "buildNo": "5",
    "channel": "stable",
    "notes": "E2E 测试版本：发现页网络同步与应用内升级", "mandatory": "false",
}, "file", "mll-0.4.1+5-debug.apk", apk_bytes,
    "application/vnd.android.package-archive")
st, hdrs, payload = call("POST", "/admin/releases", ADMIN_TOKEN,
                         raw=body, ctype=ct)
rel = json.loads(payload.decode("utf-8"))
check("发布 APK 200 且元数据正确",
      st == 200 and rel["version"] == "0.4.1" and rel["build_no"] == 5
      and rel["sha256"] == apk_sha and rel["size"] == apk_size,
      f"{st} {rel.get('version')}")
rid = rel["id"]
dl_url = "http://127.0.0.1:8000" + rel["url"]

# 15. 版本比较矩阵（query 中 + 必须编码为 %2B）
st, latest = j("GET", "/releases/latest?platform=android&channel=stable"
                     "&current=0.4.0%2B4")
check("0.4.0+4 检测到更新", latest["has_update"] and latest["build_no"] == 5, st)
st, latest2 = j("GET", "/releases/latest?current=0.4.1%2B5")
check("0.4.1+5 无更新", not latest2["has_update"], st)
st, latest3 = j("GET", "/releases/latest?current=0.4.0")
check("0.4.0(无构建号) 按 semver 仍有更新", latest3["has_update"], st)
st, latest4 = j("GET", "/releases/latest?current=0.9.9%2B99")
check("更高版本无更新", not latest4["has_update"], st)
st, admin_rels = j("GET", "/admin/releases", ADMIN_TOKEN)
check("管理台发布列表含新版本",
      any(r["id"] == rid for r in admin_rels["items"]), admin_rels["total"])

# 16. Range 206
req = urllib.request.Request(dl_url, headers={"Range": "bytes=0-1023"})
with urllib.request.urlopen(req, timeout=60) as resp:
    chunk = resp.read()
    cr = resp.headers.get("Content-Range")
check("Range 请求 206 且首块 1024 字节",
      resp.status == 206 and len(chunk) == 1024
      and cr and cr.startswith("bytes 0-1023/"),
      f"{resp.status} {cr}")

# 17. 全量下载 sha256 一致（模拟端侧下载完整性）
h = hashlib.sha256()
with urllib.request.urlopen(dl_url, timeout=300) as resp, \
        io.BytesIO() as sink:
    check("下载入口 200", resp.status == 200, resp.status)
    while True:
        b = resp.read(1024 * 1024)
        if not b:
            break
        sink.write(b)
        h.update(b)
    downloaded = sink.getvalue()
check("全量下载大小一致", len(downloaded) == apk_size,
      f"{len(downloaded)}=={apk_size}")
check("全量下载 sha256 一致", h.hexdigest() == apk_sha, h.hexdigest()[:16])

print("\n=== E2E 全部通过：%d 项 ===" % len(results))
print(json.dumps({
    "email": email, "user_id": uid,
    "exclusive_podcast_id": pid, "exclusive_title": exclusive_title,
    "release_id": rid, "version": "0.4.1+5",
    "sha256": apk_sha, "size": apk_size,
    "download_url": dl_url,
}, ensure_ascii=False, indent=2))
