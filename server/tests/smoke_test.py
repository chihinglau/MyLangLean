"""既有端到端冒烟流程（stub ASR，无需网络/GPU），适配持久化用户体系。

Run: .tools/venvs/mll/Scripts/python.exe -m pytest server/tests/smoke_test.py
or directly: python server/tests/smoke_test.py
"""
import sys
import time

import harness


def main() -> None:
    with harness.fresh_client() as (client, _):
        assert client.get("/health").json()["asr_backend"] == "stub"

        # 1. guest device login（游客落库）
        r = client.post("/api/v1/auth/device", json={"device_id": "dev-001"})
        assert r.status_code == 200, r.text
        token = r.json()["access_token"]
        assert r.json()["account"]["is_guest"] is True
        h = {"Authorization": f"Bearer {token}"}

        # 1b. 注册用户同样可走后续流程（持久化账号）
        r = client.post("/api/v1/auth/register",
                        json={"email": "smoke@x.com",
                              "password": "smoke-pass", "name": "冒烟"})
        assert r.status_code == 200, r.text
        reg_token = r.json()["access_token"]
        h_reg = {"Authorization": f"Bearer {reg_token}"}

        # 2. kick off a transcription（游客）
        r = client.post("/api/v1/transcriptions",
                        headers=h,
                        json={"audio_url": "https://x/sample.m4a",
                              "language": "en",
                              "target_lang": "zh",
                              "client_key": "k-1"})
        assert r.status_code == 202, r.text
        job_id = r.json()["id"]

        # 3. poll
        for _ in range(50):
            r = client.get(f"/api/v1/transcriptions/{job_id}", headers=h)
            job = r.json()
            if job["status"] == "done":
                break
            time.sleep(0.1)
        assert job["status"] == "done", job
        t = job["transcript"]
        assert t["segments"][0]["words"][0]["s"] >= 0
        assert t["segments"][0]["translation"]
        print("transcript segments:", len(t["segments"]),
              "billed_sec:", job["billed_sec"])

        # 4. idempotency - same client_key returns the same job, no double charge
        r = client.post("/api/v1/transcriptions",
                        headers=h,
                        json={"audio_url": "https://x/sample.m4a",
                              "client_key": "k-1"})
        assert r.json()["id"] == job_id

        # 5. quota billed once
        q = client.get("/api/v1/quota", headers=h).json()
        assert q["used_sec"] == job["billed_sec"], q
        print("guest quota:", q)

        # 5b. 注册用户额度独立且初始为 0
        q_reg = client.get("/api/v1/quota", headers=h_reg).json()
        assert q_reg["used_sec"] == 0, q_reg

        # 6. translate + score
        r = client.post("/api/v1/translate",
                        json={"language": "en", "target_lang": "zh",
                              "texts": ["hello world"]})
        assert r.json()["translations"][0]
        r = client.post("/api/v1/score",
                        json={"reference_duration_ms": 2100,
                              "attempt_duration_ms": 2300,
                              "pause_count": 1})
        assert 0 <= r.json()["overall"] <= 100
        print("score:", r.json())

        # 7. 新公开目录接口可用
        r = client.get("/api/v1/catalog/podcasts")
        assert r.json()["total"] == 8

        print("SMOKE TEST PASSED")


# pytest 形态
def test_smoke():
    main()


if __name__ == "__main__":
    main()
    print("SMOKE TEST PASSED (direct run)")
    sys.exit(0)
