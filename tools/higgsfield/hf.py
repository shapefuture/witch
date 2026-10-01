#!/usr/bin/env python3
"""Higgsfield API client for the art pipeline (image, video and audio generation).

Wraps the official SDK (higgsfield-client) with what a build tool needs:
  * credentials from <repo>/.env.local (HF_KEY=key-id:key-secret, git-ignored; a real environment
    variable wins over the file). The SDK also accepts HF_API_KEY + HF_API_SECRET.
  * a cost estimate before every paid request (POST /estimate/<model>), refused above --max-usd
  * an Idempotency-Key on every submit, written to the job's manifest BEFORE submitting, so the SDK's
    own retries and a later `resume` can never be charged twice
  * polling with backoff until a terminal status: completed, failed, nsfw, canceled
    (failed, nsfw and canceled requests are not charged)
  * outputs downloaded at once (Higgsfield keeps them about 7 days), next to a job.json manifest:
    model, arguments, estimate, request id, status, result, files with sha256

Commands
  check                                         credentials load (prints the key id only, no network)
  estimate MODEL (--args JSON | --args-file F)  price of one request; nothing is charged
  run MODEL (--args JSON | --args-file F) --max-usd N [--out DIR] [--upload FIELD=PATH ...]
  resume JOB_DIR                                re-submit with the same key, keep polling, download
  status REQUEST_ID                             the raw status JSON
  upload PATH                                   upload a local file, print the URL to pass as input

MODEL is the API path of a model, e.g. bytedance/seedance-2.5/text-to-video (console.higgsfield.ai/models).
Jobs go to build/higgsfield/ (git-ignored) unless --out says otherwise; copy what you keep into assets/.
"""
import argparse
import datetime as dt
import hashlib
import json
import mimetypes
import os
import re
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / ".env.local"
DEFAULT_OUT = ROOT / "build" / "higgsfield"
TERMINAL = ("completed", "failed", "nsfw", "canceled")
NOT_CHARGED = ("failed", "nsfw", "canceled")


def load_env(path=ENV_FILE):
    try:
        from dotenv import load_dotenv
    except ImportError:
        raise SystemExit("missing dependency: pip install -r tools/higgsfield/requirements.txt")
    load_dotenv(path, override=False)


def key_id():
    """The public half of the credentials, for messages. Never print the secret."""
    key = os.getenv("HF_KEY") or os.getenv("HF_API_KEY") or ""
    return key.split(":", 1)[0]


class Api:
    """The few calls the pipeline makes, on top of the SDK's authenticated, retrying transport."""

    def __init__(self, sdk=None, timeout=90.0):
        if sdk is None:
            try:
                import higgsfield_client
            except ImportError:
                raise SystemExit("missing dependency: pip install -r tools/higgsfield/requirements.txt")
            load_env()
            sdk = higgsfield_client.SyncClient(timeout=timeout)
        self.sdk = sdk

    def _request(self, method, url, **kwargs):
        # The SDK transport adds the Authorization header and retries 408/429/5xx with backoff.
        # It is private API, which is why requirements.txt pins the SDK version.
        return self.sdk._transport.request(method, url, **kwargs)

    def estimate(self, model, arguments):
        return self._request("POST", "/estimate/" + model_path(model), json=arguments).json()

    def submit(self, model, arguments, idempotency_key):
        # The SDK's submit sends no Idempotency-Key, and its retries would then submit twice.
        response = self._request("POST", "/" + model_path(model), json=arguments,
                                 headers={"Idempotency-Key": idempotency_key})
        return response.json()

    def status(self, status_url):
        return self._request("GET", status_url).json()

    def cancel(self, cancel_url):
        self._request("POST", cancel_url)

    def upload(self, path):
        return self.sdk.upload_file(str(path))

    def download(self, url, dest):
        # Output URLs are public storage links: fetch them WITHOUT our Authorization header.
        client = self.sdk._upload_client
        with client.stream("GET", url, follow_redirects=True) as response:
            response.raise_for_status()
            tmp = dest.with_suffix(dest.suffix + ".part")
            with open(tmp, "wb") as f:
                for chunk in response.iter_bytes():
                    f.write(chunk)
            tmp.replace(dest)
            return response.headers.get("content-type", "")


def model_path(model):
    return model.strip().strip("/")


def wait(api, status_url, on_status=None, first_delay=1.0, max_delay=15.0, timeout=3600.0, sleep=time.sleep):
    """Polls until a terminal status and returns the final JSON (it carries the outputs)."""
    delay = first_delay
    started = time.monotonic()
    last = None
    while True:
        data = api.status(status_url)
        status = str(data.get("status", ""))
        if status != last and on_status is not None:
            on_status(status, data)
        last = status
        if status in TERMINAL:
            return data
        if time.monotonic() - started > timeout:
            raise TimeoutError("still %s after %.0f s: resume the job later" % (status, timeout))
        sleep(delay)
        delay = min(max_delay, delay * 1.5)


def output_urls(result):
    """[(kind, url)] from a completed result: images[] for image models, video.url for video,
    audio / audios[] for audio."""
    def url_of(item):
        if isinstance(item, str):
            return item
        if isinstance(item, dict):
            return item.get("url") or ""
        return ""

    found = []
    for item in result.get("images") or []:
        found.append(("image", url_of(item)))
    if result.get("video"):
        found.append(("video", url_of(result["video"])))
    if result.get("audio"):
        found.append(("audio", url_of(result["audio"])))
    for item in result.get("audios") or []:
        found.append(("audio", url_of(item)))
    return [(kind, url) for kind, url in found if url]


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def save_job(job_dir, job):
    tmp = job_dir / "job.json.part"
    tmp.write_text(json.dumps(job, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(job_dir / "job.json")


def new_job_dir(out_root, model):
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    slug = re.sub(r"[^a-z0-9]+", "-", model_path(model).lower()).strip("-")[:60]
    job_dir = Path(out_root) / ("%s_%s" % (stamp, slug))
    suffix = 1
    while job_dir.exists():
        suffix += 1
        job_dir = Path(out_root) / ("%s_%s_%d" % (stamp, slug, suffix))
    job_dir.mkdir(parents=True)
    if Path(out_root).resolve() == DEFAULT_OUT.resolve():
        # Raw generations are not game assets: keep Godot from importing them.
        (DEFAULT_OUT / ".gdignore").touch()
    return job_dir


def download_outputs(api, job_dir, job, log):
    files = job.setdefault("files", [])
    have = {entry["url"] for entry in files}
    for index, (kind, url) in enumerate(output_urls(job.get("result") or {})):
        if url in have:
            continue
        ext = Path(urlparse(url).path).suffix.lower()
        dest = job_dir / ("%s_%d%s" % (kind, index, ext))
        content_type = api.download(url, dest)
        if not ext:
            guessed = mimetypes.guess_extension((content_type or "").split(";")[0].strip()) or ".bin"
            dest = dest.rename(dest.with_suffix(guessed))
        files.append({"kind": kind, "url": url, "path": dest.name, "sha256": sha256(dest),
                      "bytes": dest.stat().st_size})
        save_job(job_dir, job)
        log("  saved %s" % dest)
    return files


def follow(api, job_dir, job, log, sleep=time.sleep):
    """Submit if not yet submitted (same key), poll to a terminal status, download the outputs."""
    if not job.get("request_id"):
        accepted = api.submit(job["model"], job["arguments"], job["idempotency_key"])
        job.update({"request_id": accepted["request_id"], "status_url": accepted["status_url"],
                    "cancel_url": accepted.get("cancel_url", ""), "status": accepted.get("status", "queued")})
        save_job(job_dir, job)
        log("submitted %s (%s)" % (job["request_id"], job["status"]))

    def on_status(status, _data):
        log("  %s" % status)

    final = wait(api, job["status_url"], on_status=on_status, sleep=sleep)
    job["status"] = final.get("status")
    job["result"] = final
    job["finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    save_job(job_dir, job)
    if job["status"] == "completed":
        download_outputs(api, job_dir, job, log)
    elif job["status"] in NOT_CHARGED:
        log("ended %s (not charged): %s" % (job["status"], final.get("error") or final.get("detail") or ""))
    return job


def run(api, model, arguments, max_usd, out_root=DEFAULT_OUT, log=print, sleep=time.sleep):
    estimate = api.estimate(model, arguments)
    usd = float(estimate.get("usd", "nan"))
    log("estimate: %s credits, $%s" % (estimate.get("credits"), estimate.get("usd")))
    if not usd <= max_usd:
        raise SystemExit("refused: estimate $%s is above --max-usd %.2f" % (estimate.get("usd"), max_usd))
    job_dir = new_job_dir(out_root, model)
    job = {"model": model_path(model), "arguments": arguments, "estimate": estimate,
           "idempotency_key": str(uuid.uuid4()),
           "created_at": dt.datetime.now(dt.timezone.utc).isoformat()}
    save_job(job_dir, job)
    log("job %s" % job_dir)
    return job_dir, follow(api, job_dir, job, log, sleep=sleep)


def parse_arguments(args, api=None):
    if args.args_file:
        arguments = json.loads(Path(args.args_file).read_text(encoding="utf-8"))
    elif args.args:
        arguments = json.loads(args.args)
    else:
        raise SystemExit("give the model's input as --args JSON or --args-file FILE")
    for spec in getattr(args, "upload", None) or []:
        field, _, path = spec.partition("=")
        if not field or not path:
            raise SystemExit("--upload wants FIELD=PATH, got %r" % spec)
        arguments[field] = api.upload(path)
        print("uploaded %s -> %s" % (path, field))
    return arguments


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    for name in ("estimate", "run"):
        p = sub.add_parser(name)
        p.add_argument("model")
        p.add_argument("--args")
        p.add_argument("--args-file")
        if name == "run":
            p.add_argument("--max-usd", type=float, required=True,
                           help="refuse the request if the estimate is above this many dollars")
            p.add_argument("--out", default=str(DEFAULT_OUT))
            p.add_argument("--upload", action="append", metavar="FIELD=PATH",
                           help="upload a local file and pass its URL as FIELD")
    p = sub.add_parser("resume")
    p.add_argument("job_dir")
    p = sub.add_parser("status")
    p.add_argument("request_id")
    p = sub.add_parser("upload")
    p.add_argument("path")
    args = parser.parse_args(argv)

    if args.command == "check":
        load_env()
        if not (os.getenv("HF_KEY") or (os.getenv("HF_API_KEY") and os.getenv("HF_API_SECRET"))):
            raise SystemExit("no credentials: put HF_KEY=key-id:key-secret in %s" % ENV_FILE)
        if os.getenv("HF_KEY") and ":" not in os.getenv("HF_KEY"):
            raise SystemExit("HF_KEY must be key-id:key-secret")
        print("credentials loaded for key id %s" % key_id())
        return 0

    try:
        import httpx
        from higgsfield_client import HiggsfieldClientError
    except ImportError:
        raise SystemExit("missing dependency: pip install -r tools/higgsfield/requirements.txt")
    api = Api()
    try:
        if args.command == "estimate":
            print(json.dumps(api.estimate(args.model, parse_arguments(args)), indent=2))
        elif args.command == "run":
            job_dir, job = run(api, args.model, parse_arguments(args, api), args.max_usd, args.out)
            return 0 if job.get("status") == "completed" else 1
        elif args.command == "resume":
            job_dir = Path(args.job_dir)
            job = json.loads((job_dir / "job.json").read_text(encoding="utf-8"))
            job = follow(api, job_dir, job, print)
            return 0 if job.get("status") == "completed" else 1
        elif args.command == "status":
            print(json.dumps(api.status("/requests/%s/status" % args.request_id), indent=2))
        elif args.command == "upload":
            print(api.upload(args.path))
    except HiggsfieldClientError as error:
        raise SystemExit("Higgsfield API error: %s" % error)
    except (httpx.ProxyError, httpx.ConnectError) as error:
        raise SystemExit("cannot reach api.higgsfield.ai (%s): is the host allowed by the network policy?" % error)
    return 0


if __name__ == "__main__":
    sys.exit(main())
