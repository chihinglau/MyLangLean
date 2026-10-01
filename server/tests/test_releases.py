"""AC-6：发布包鉴权/类型校验/上传/版本比较/Range 下载/删除。"""
import hashlib
import sys

import harness

ADMIN = harness.ADMIN_HEADERS
API = "/api/v1"

FAKE_APK = bytes((i * 37 + 11) % 256 for i in range(4096))  # 任意字节
SHA = hashlib.sha256(FAKE_APK).hexdigest()


def _upload(client, *, token_headers=ADMIN, filename="app-0.4.1.apk",
            version="0.4.1", build_no=5, channel="stable",
            platform="android",
            mandatory="true", notes="修复下载与订阅问题"):
    return client.post(
        f"{API}/admin/releases",
        headers=token_headers,
        files={"file": (filename, FAKE_APK,
                        "application/vnd.android.package-archive")},
        data={"platform": platform, "version": version,
              "buildNo": str(build_no), "channel": channel,
              "notes": notes, "mandatory": mandatory},
    )


def test_upload_auth_and_extension():
    with harness.fresh_client() as (client, _):
        # 无 Token 401
        r = _upload(client, token_headers={})
        assert r.status_code == 401, r.text

        # 非 apk 400
        r = _upload(client, filename="notes.txt")
        assert r.status_code == 400, r.text

        # 正确 Token 上传成功，size/sha256 正确
        r = _upload(client)
        assert r.status_code == 200, r.text
        item = r.json()
        assert item["size"] == len(FAKE_APK)
        assert item["sha256"] == SHA
        assert item["version"] == "0.4.1"
        assert item["build_no"] == 5
        assert item["mandatory"] is True
        assert item["notes"] == "修复下载与订阅问题"
        assert item["url"].endswith(f"/download/{item['id']}")
        assert item["published_at"]


def test_latest_comparison():
    with harness.fresh_client() as (client, _):
        assert _upload(client).status_code == 200

        # 无更新渠道时 has_update false
        r = client.get(f"{API}/releases/latest?platform=android"
                       "&channel=beta&current=0.1.0")
        assert r.status_code == 200
        assert r.json() == {"has_update": False}

        # current=0.4.0 -> 有更新，字段透传
        r = client.get(f"{API}/releases/latest?platform=android"
                       "&channel=stable&current=0.4.0")
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["has_update"] is True
        assert body["version"] == "0.4.1"
        assert body["build_no"] == 5
        assert body["mandatory"] is True
        assert body["size"] == len(FAKE_APK)
        assert body["sha256"] == SHA
        assert body["url"]
        assert body["notes"]

        # current=0.4.1（不带 buildNo）-> 无更新（AC-6 约定）
        r = client.get(f"{API}/releases/latest?platform=android"
                       "&channel=stable&current=0.4.1")
        assert r.json()["has_update"] is False

        # current 更高 -> 无更新；缺失/非法 current -> 422
        assert client.get(
            f"{API}/releases/latest?platform=android&channel=stable"
            "&current=1.0.0").json()["has_update"] is False
        assert client.get(
            f"{API}/releases/latest?platform=android&channel=stable"
        ).status_code == 422
        assert client.get(
            f"{API}/releases/latest?platform=android&channel=stable"
            "&current=abc").status_code == 422
        assert client.get(
            f"{API}/releases/latest?platform=windows&channel=stable"
            "&current=0.1.0").status_code == 422


def test_upload_field_validation():
    with harness.fresh_client() as (client, _):
        # 白名单之外的 platform / channel、非法语义版本、负 buildNo 全部 422
        assert _upload(client, platform="windows").status_code == 422
        assert _upload(client, channel="nightly").status_code == 422
        assert _upload(client, version="1.0").status_code == 422
        assert _upload(client, version="0.4.1-beta").status_code == 422
        assert _upload(client, build_no=-1).status_code == 422
        # 路径穿越不能借 platform/version 落盘
        assert _upload(client, platform="../etc").status_code == 422
        # 合法请求仍成功
        assert _upload(client).status_code == 200


def test_build_no_tiebreak():
    with harness.fresh_client() as (client, _):
        assert _upload(client, version="0.4.1", build_no=5).status_code == 200
        # 同版本更大 build
        assert _upload(client, version="0.4.1", build_no=6,
                       mandatory="false").status_code == 200
        r = client.get(f"{API}/releases/latest?platform=android"
                       "&channel=stable&current=0.4.1%2B5")
        body = r.json()
        assert body["has_update"] is True, body
        assert body["build_no"] == 6
        # current 0.4.1+6 -> 无更新
        r = client.get(f"{API}/releases/latest?platform=android"
                       "&channel=stable&current=0.4.1%2B6")
        assert r.json()["has_update"] is False


def test_download_full_and_range():
    with harness.fresh_client() as (client, _):
        item = _upload(client).json()
        rid = item["id"]

        # 全量下载，哈希与记录一致
        r = client.get(f"{API}/releases/download/{rid}")
        assert r.status_code == 200, r.text
        assert hashlib.sha256(r.content).hexdigest() == SHA
        assert r.headers["content-type"].startswith(
            "application/vnd.android.package-archive")

        # Range 首字节 -> 206
        r = client.get(f"{API}/releases/download/{rid}",
                       headers={"Range": "bytes=0-0"})
        assert r.status_code == 206, r.text
        assert r.content == FAKE_APK[:1]
        assert r.headers["content-range"] == f"bytes 0-0/{len(FAKE_APK)}"
        assert r.headers["accept-ranges"] == "bytes"

        # 不存在的发布 404
        assert client.get(
            f"{API}/releases/download/99999").status_code == 404


def test_list_and_delete_release():
    with harness.fresh_client() as (client, _):
        item = _upload(client).json()

        r = client.get(f"{API}/releases?platform=android&channel=stable")
        assert r.status_code == 200
        assert r.json()["total"] == 1

        r = client.get(f"{API}/admin/releases", headers=ADMIN)
        assert r.status_code == 200
        assert r.json()["total"] == 1

        assert client.delete(
            f"{API}/admin/releases/{item['id']}",
            headers=ADMIN).status_code == 204
        assert client.get(
            f"{API}/releases/download/{item['id']}").status_code == 404
        assert client.delete(
            f"{API}/admin/releases/{item['id']}",
            headers=ADMIN).status_code == 404


if __name__ == "__main__":
    sys.exit(harness.run_module(__name__))
