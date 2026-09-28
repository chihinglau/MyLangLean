"""End-to-end API smoke test (stub ASR, no network/GPU needed).

Run: .tools/venvs/mll/Scripts/python.exe -m pytest server/tests/smoke_test.py
or directly: python server/tests/smoke_test.py
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def main() -> None:
    assert client.get("/health").json()["asr_backend"] == "stub"

    # 1. guest device login
    r = client.post("/api/v1/auth/device", json={"device_id": "dev-001"})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}

    # 2. kick off a transcription
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
    print("quota:", q)

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

    print("SMOKE TEST PASSED")


if __name__ == "__main__":
    main()
