#!/usr/bin/env python3
"""Offline tests for hf.py against a mock of the Higgsfield API (no network, nothing charged).

    python tools/higgsfield/test_hf.py
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hf  # noqa: E402

BASE = "https://api.higgsfield.ai"
MODEL = "bytedance/seedance-2.5/text-to-video"


class FakeHiggsfield:
    """Queued -> in_progress -> completed; the first submit answers 503 so the SDK retries it."""

    def __init__(self, final="completed", estimate_usd="0.094"):
        self.final = final
        self.estimate_usd = estimate_usd
        self.submits = []
        self.polls = 0
        self.auth_on_download = None

    def handle(self, request):
        path = request.url.path
        if request.method == "POST" and path == "/estimate/" + MODEL:
            return httpx.Response(200, json={"credits": "1.500", "usd": self.estimate_usd})
        if request.method == "POST" and path == "/" + MODEL:
            self.submits.append(request.headers.get("Idempotency-Key"))
            if len(self.submits) == 1:
                return httpx.Response(503, json={"detail": "busy"})
            return httpx.Response(200, json={
                "status": "queued", "request_id": "r1",
                "status_url": BASE + "/requests/r1/status", "cancel_url": BASE + "/requests/r1/cancel"})
        if request.method == "GET" and path == "/requests/r1/status":
            self.polls += 1
            if self.polls < 3:
                return httpx.Response(200, json={"status": "queued" if self.polls == 1 else "in_progress"})
            if self.final != "completed":
                return httpx.Response(200, json={"status": self.final, "error": "nope"})
            return httpx.Response(200, json={"status": "completed",
                                             "video": {"url": "https://cdn.example/out/clip.mp4"}})
        if request.method == "GET" and request.url.host == "cdn.example":
            self.auth_on_download = request.headers.get("Authorization")
            return httpx.Response(200, content=b"fake-mp4", headers={"content-type": "video/mp4"})
        return httpx.Response(404, json={"detail": "unexpected %s %s" % (request.method, request.url)})


def make_api(fake):
    import higgsfield_client
    sdk = higgsfield_client.SyncClient(api_key="kid:secret")
    transport = httpx.MockTransport(fake.handle)
    # The SDK builds these lazily (cached_property); pre-seeding them swaps in the mock.
    sdk.__dict__["_client"] = httpx.Client(transport=transport, base_url=BASE,
                                           headers={"Authorization": "Key kid:secret"})
    sdk.__dict__["_upload_client"] = httpx.Client(transport=transport)
    return hf.Api(sdk)


class RunTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name)
        self.log = []

    def tearDown(self):
        self.tmp.cleanup()

    def run_job(self, fake, max_usd=1.0):
        return hf.run(make_api(fake), MODEL, {"prompt": "a crooked library"}, max_usd, self.out,
                      log=self.log.append, sleep=lambda _s: None)

    def test_completed_job_is_downloaded_with_a_manifest(self):
        fake = FakeHiggsfield()
        job_dir, job = self.run_job(fake)
        self.assertEqual(job["status"], "completed")
        clip = job_dir / "video_0.mp4"
        self.assertEqual(clip.read_bytes(), b"fake-mp4")
        manifest = json.loads((job_dir / "job.json").read_text())
        self.assertEqual(manifest["request_id"], "r1")
        self.assertEqual(manifest["files"][0]["sha256"], hf.sha256(clip))
        self.assertEqual(manifest["estimate"]["usd"], "0.094")

    def test_retried_submit_reuses_one_idempotency_key(self):
        fake = FakeHiggsfield()
        _job_dir, job = self.run_job(fake)
        self.assertEqual(len(fake.submits), 2)
        self.assertEqual(fake.submits[0], fake.submits[1])
        self.assertEqual(fake.submits[0], job["idempotency_key"])

    def test_downloads_do_not_carry_credentials(self):
        fake = FakeHiggsfield()
        self.run_job(fake)
        self.assertIsNone(fake.auth_on_download)

    def test_estimate_above_the_cap_is_refused_before_submitting(self):
        fake = FakeHiggsfield(estimate_usd="3.20")
        with self.assertRaises(SystemExit):
            self.run_job(fake, max_usd=1.0)
        self.assertEqual(fake.submits, [])
        self.assertEqual(list(self.out.iterdir()), [])

    def test_failed_job_downloads_nothing(self):
        fake = FakeHiggsfield(final="failed")
        job_dir, job = self.run_job(fake)
        self.assertEqual(job["status"], "failed")
        self.assertEqual(sorted(p.name for p in job_dir.iterdir()), ["job.json"])

    def test_resume_keeps_the_key_and_skips_what_is_downloaded(self):
        fake = FakeHiggsfield()
        job_dir, job = self.run_job(fake)
        again = hf.follow(make_api(FakeHiggsfield()), job_dir, job, self.log.append, sleep=lambda _s: None)
        self.assertEqual(len(again["files"]), 1)


class OutputsTest(unittest.TestCase):
    def test_every_output_shape(self):
        result = {"images": [{"url": "https://x/a.png"}, "https://x/b.png"],
                  "video": {"url": "https://x/c.mp4"}, "audio": {"url": "https://x/d.mp3"},
                  "audios": [{"url": "https://x/e.wav"}]}
        self.assertEqual([kind for kind, _ in hf.output_urls(result)],
                         ["image", "image", "video", "audio", "audio"])


if __name__ == "__main__":
    unittest.main()
