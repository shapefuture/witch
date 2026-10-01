#!/usr/bin/env python3
"""Higgsfield API client for the art pipeline (image and video generation).

Wraps the official SDK (higgsfield-client) with what a build tool needs:
  * credentials from <repo>/.env.local (HF_KEY=key-id:key-secret, git-ignored; a real environment
    variable wins over the file). The SDK also accepts HF_API_KEY + HF_API_SECRET.
  * arguments checked against the model's input schema before anything is sent
  * a cost estimate before every paid request (POST /estimate/<model>), refused above --max-usd;
    models priced per second/token return a description instead, and need --allow-unpriced
  * an Idempotency-Key on every submit, written to the job's manifest BEFORE submitting, so the SDK's
    own retries and a later `resume` can never be charged twice
  * polling as the docs recommend (2 s growing to 10 s, with jitter; network errors retried) until
    a terminal status: completed, failed, nsfw, canceled (only completed is charged)
  * outputs downloaded at once (Higgsfield keeps them at least 7 days), next to a job.json manifest:
    model, arguments, estimate, request id, correlation id, status, result, files with sha256

Commands
  check                                         credentials load (prints the key id only, no network)
  models [SEARCH]                               list models (slug, output, operation)
  schema MODEL                                  a model's input schema
  catalog [--no-estimates]                      refresh tools/higgsfield/catalog/ (models, schemas,
                                                docs links, baseline prices); estimates are free
  estimate MODEL (--args JSON | --args-file F)  price of one request; nothing is charged
  run MODEL (--args JSON | --args-file F) --max-usd N [--allow-unpriced] [--out DIR] [--upload FIELD=PATH ...]
  resume JOB_DIR                                re-submit with the same key, keep polling, download
  status REQUEST_ID                             the raw status JSON
  upload PATH                                   upload a local file, print the URL to pass as input

MODEL is the API path of a model, e.g. alibaba/qwen-image-3/edit (see catalog/CATALOG.md).
Jobs go to build/higgsfield/ (git-ignored) unless --out says otherwise; copy what you keep into assets/.
"""
import argparse
import datetime as dt
import hashlib
import json
import mimetypes
import os
import random
import re
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

import httpx

ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / ".env.local"
DEFAULT_OUT = ROOT / "build" / "higgsfield"
CATALOG_DIR = Path(__file__).resolve().parent / "catalog"
DOCS = "https://docs.higgsfield.ai"
TERMINAL = ("completed", "failed", "nsfw", "canceled")
NOT_CHARGED = ("failed", "nsfw", "canceled")
# Stand-ins for required media inputs when asking for a baseline price (estimates don't fetch them).
PLACEHOLDER_MEDIA = {"image": "https://cdn.example.com/input/example.jpeg",
                     "video": "https://cdn.example.com/input/example.mp4",
                     "audio": "https://cdn.example.com/input/example.wav"}


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


def now():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


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

    def models(self, search=None, include_schema=False):
        params = {"limit": 500, "include_schema": "true" if include_schema else "false"}
        if search:
            params["search"] = search
        return self._request("GET", "/models", params=params).json().get("items", [])

    def schema(self, model):
        """The model's input schema, or None when the listing doesn't know the model."""
        slug = model_path(model)
        for item in self.models(search=slug, include_schema=True):
            if item.get("slug") == slug:
                return item.get("input_schema") or {}
        return None

    def estimate(self, model, arguments):
        return self._request("POST", "/estimate/" + model_path(model), json=arguments).json()

    def submit(self, model, arguments, idempotency_key):
        """Returns (acceptance JSON, X-Correlation-ID). The SDK's own submit sends no Idempotency-Key,
        and its retries would then submit twice."""
        response = self._request("POST", "/" + model_path(model), json=arguments,
                                 headers={"Idempotency-Key": idempotency_key})
        return response.json(), response.headers.get("x-correlation-id", "")

    def status(self, status_url):
        return self._request("GET", status_url).json()

    def cancel(self, cancel_url):
        self._request("POST", cancel_url)

    def upload(self, path):
        # The SDK sends the presigned upload headers and keeps our key off the storage URL.
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


def price(estimate):
    """Dollars for a fixed-price estimate; None when the model is priced by a description
    (per second, per token) instead of a number."""
    try:
        return float(estimate["usd"])
    except (KeyError, TypeError, ValueError):
        return None


def check_arguments(schema, arguments):
    """Problems that would waste a request: missing required fields, values outside an enum, and
    unknown fields (a typo'd option would otherwise silently fall back to its default)."""
    problems = []
    properties = schema.get("properties") or {}
    for field in schema.get("required") or []:
        if field not in arguments:
            problems.append("missing required field %r" % field)
    for field, value in arguments.items():
        spec = properties.get(field)
        if spec is None:
            if properties:
                problems.append("unknown field %r (known: %s)" % (field, ", ".join(sorted(properties))))
            continue
        if "enum" in spec and value not in spec["enum"]:
            problems.append("%s=%r is not one of %s" % (field, value, spec["enum"]))
    return problems


def wait(api, status_url, on_status=None, first_delay=2.0, max_delay=10.0, timeout=3600.0,
         network_retries=5, sleep=time.sleep):
    """Polls until a terminal status and returns the final JSON (it carries the outputs)."""
    delay = first_delay
    started = time.monotonic()
    last = None
    failures = 0
    while True:
        try:
            data = api.status(status_url)
            failures = 0
        except httpx.TransportError:
            failures += 1
            if failures > network_retries:
                raise
            data = {"status": last or ""}
        status = str(data.get("status", ""))
        if status != last and on_status is not None:
            on_status(status, data)
        last = status
        if status in TERMINAL:
            return data
        if time.monotonic() - started > timeout:
            raise TimeoutError("still %s after %.0f s: resume the job later" % (status, timeout))
        sleep(delay + random.uniform(0.0, 0.5))
        delay = min(max_delay, delay * 1.5)


def output_urls(result):
    """[(kind, url)] from a completed result: images[] for image models, video.url for video,
    audio / audios[] for audio (the same file can appear in both; it is fetched once)."""
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
    seen = set()
    unique = []
    for kind, url in found:
        if url and url not in seen:
            seen.add(url)
            unique.append((kind, url))
    return unique


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
        accepted, correlation_id = api.submit(job["model"], job["arguments"], job["idempotency_key"])
        job.update({"request_id": accepted["request_id"], "status_url": accepted["status_url"],
                    "cancel_url": accepted.get("cancel_url", ""), "status": accepted.get("status", "queued"),
                    "correlation_id": correlation_id})
        save_job(job_dir, job)
        log("submitted %s (%s)" % (job["request_id"], job["status"]))

    def on_status(status, _data):
        log("  %s" % status)

    final = wait(api, job["status_url"], on_status=on_status, sleep=sleep)
    job["status"] = final.get("status")
    job["result"] = final
    job["finished_at"] = now()
    save_job(job_dir, job)
    if job["status"] == "completed":
        download_outputs(api, job_dir, job, log)
    elif job["status"] in NOT_CHARGED:
        log("ended %s (not charged): %s" % (job["status"], final.get("error") or final.get("detail") or ""))
    return job


def guarded_estimate(api, model, arguments, max_usd, allow_unpriced, log):
    estimate = api.estimate(model, arguments)
    usd = price(estimate)
    if usd is None:
        log("no fixed price: %s" % (estimate.get("pricing_description") or json.dumps(estimate)))
        if not allow_unpriced:
            raise SystemExit("refused: this model has no fixed estimate; read the pricing above and rerun "
                             "with --allow-unpriced")
    else:
        log("estimate: %s credits, $%s" % (estimate.get("credits"), estimate.get("usd")))
        if usd > max_usd:
            raise SystemExit("refused: estimate $%s is above --max-usd %.2f" % (estimate.get("usd"), max_usd))
    return estimate


def run(api, model, arguments, max_usd, out_root=DEFAULT_OUT, allow_unpriced=False, log=print,
        sleep=time.sleep):
    estimate = guarded_estimate(api, model, arguments, max_usd, allow_unpriced, log)
    job_dir = new_job_dir(out_root, model)
    job = {"model": model_path(model), "arguments": arguments, "estimate": estimate,
           "idempotency_key": str(uuid.uuid4()), "created_at": now()}
    save_job(job_dir, job)
    log("job %s" % job_dir)
    return job_dir, follow(api, job_dir, job, log, sleep=sleep)


# ---- catalog -------------------------------------------------------------------------------------

def placeholder_arguments(schema):
    """The smallest valid-looking request: required fields only, defaults elsewhere."""
    properties = schema.get("properties") or {}
    arguments = {}
    for field in schema.get("required") or []:
        spec = properties.get(field, {})
        kind = spec.get("type")
        media = next((m for m in PLACEHOLDER_MEDIA if m in field), "image")
        if "enum" in spec:
            arguments[field] = spec.get("default", spec["enum"][0])
        elif kind == "array":
            arguments[field] = [PLACEHOLDER_MEDIA[media]] if "url" in field else ["estimate"]
        elif "url" in field:
            arguments[field] = PLACEHOLDER_MEDIA[media]
        elif kind in ("integer", "number"):
            arguments[field] = spec.get("default", spec.get("minimum", 1))
        elif kind == "boolean":
            arguments[field] = spec.get("default", False)
        else:
            arguments[field] = spec.get("default", "estimate")
    return arguments


def docs_links(log):
    """{endpoint slug: [docs page]} crawled from the public docs (best effort: {} on failure)."""
    client = httpx.Client(timeout=30, follow_redirects=True)
    links = {}
    try:
        families = set()
        for category in ("image-generation", "video-generation"):
            text = client.get("%s/docs/models/%s.md" % (DOCS, category)).text
            families |= set(re.findall(r'href="(/docs/models/[a-z0-9.\-]+)"', text))
        pages = {}
        for family in sorted(families):
            text = client.get("%s%s.md" % (DOCS, family)).text
            pages[family] = text
            for page in sorted(set(re.findall(r"(/docs/models/[a-z0-9.\-]+/[a-z0-9.\-]+)", text))):
                response = client.get("%s%s.md" % (DOCS, page))
                if response.status_code != 200:
                    continue
                for endpoint in set(re.findall(r"api\.higgsfield\.ai/([a-z0-9][a-z0-9./\-]+?)(?=[\s\"'`\\)]|$)",
                                               response.text)):
                    endpoint = endpoint.rstrip("/.")
                    if not endpoint.startswith(("requests", "estimate", "files", "models")):
                        links.setdefault(endpoint, []).append(DOCS + page)
        links["__families__"] = pages
    except httpx.HTTPError as error:
        log("docs crawl failed (%s): catalog written without docs links" % error)
    return links


def build_catalog(api, out_dir=CATALOG_DIR, with_estimates=True, log=print):
    items = sorted(api.models(include_schema=True), key=lambda m: m["slug"])
    links = docs_links(log)
    families = links.pop("__families__", {})
    for item in items:
        slug = item["slug"]
        pages = links.get(slug)
        if not pages:
            # Fall back to the family page that mentions the endpoint.
            pages = [DOCS + family for family, text in families.items() if slug in text]
        item["docs"] = sorted(set(pages))
        item["console"] = "https://console.higgsfield.ai/models/%s" % slug
        if with_estimates:
            arguments = placeholder_arguments(item.get("input_schema") or {})
            try:
                item["baseline"] = {"arguments": arguments, "estimate": api.estimate(slug, arguments)}
            except Exception as error:  # noqa: BLE001 - the catalog records any refusal
                item["baseline"] = {"arguments": arguments, "error": str(error)}
    out_dir.mkdir(parents=True, exist_ok=True)
    helper_endpoints = sorted(e for e in links if e not in {i["slug"] for i in items})
    payload = {"fetched_at": now(), "source": "GET https://api.higgsfield.ai/models?include_schema=true",
               "count": len(items), "helper_endpoints_in_docs": helper_endpoints, "models": items}
    (out_dir / "models.json").write_text(json.dumps(payload, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / "CATALOG.md").write_text(render_catalog(payload), encoding="utf-8")
    log("wrote %s (%d models)" % (out_dir, len(items)))
    return payload


def _options(schema):
    properties = schema.get("properties") or {}
    shown = []
    for field in ("resolution", "aspect_ratio", "duration", "quality", "batch_size", "rendering_speed"):
        spec = properties.get(field)
        if not spec:
            continue
        if "enum" in spec:
            shown.append("%s: %s" % (field, "/".join(str(v) for v in spec["enum"])))
        elif "minimum" in spec and "maximum" in spec:
            shown.append("%s: %s-%s" % (field, spec["minimum"], spec["maximum"]))
    for field, spec in properties.items():
        if spec.get("type") == "array" and "maxItems" in spec:
            shown.append("%s: up to %d" % (field, spec["maxItems"]))
    return "; ".join(shown)


def _baseline(item):
    baseline = item.get("baseline")
    if not baseline:
        return ""
    if "error" in baseline:
        # Some schemas under-report what is required; the estimate's refusal names the missing input.
        reason = baseline["error"].strip(" :")
        return "needs real inputs (%s)" % reason[:70] if reason else "needs real inputs"
    estimate = baseline["estimate"]
    usd = price(estimate)
    if usd is not None:
        return "$%.3f" % usd
    description = estimate.get("pricing_description") or ""
    match = re.search(r"\$[0-9.]+[^.,;]*", description)
    return ("by usage: " + match.group(0)) if match else "by usage"


def render_catalog(payload):
    lines = [
        "# Higgsfield model catalog",
        "",
        "Generated by `python tools/higgsfield/hf.py catalog` on %s from %s. Do not edit by hand:" % (
            payload["fetched_at"], payload["source"]),
        "rerun the command. Full input schemas, docs links and the raw estimates are in `models.json`.",
        "",
        "**Baseline price** is `/estimate` for the required fields only (placeholder media URLs, every option at",
        "its default). The real price depends on the options: estimate your exact arguments before running.",
        "\"By usage\" models answer with a pricing description (per second or per token) instead of a number.",
        "",
    ]
    by_output = {}
    for item in payload["models"]:
        by_output.setdefault(item.get("output_type") or "other", []).append(item)
    for output in sorted(by_output):
        items = by_output[output]
        lines += ["## %s (%d)" % (output.capitalize(), len(items)), "",
                  "| Model path | Title | Operation | Required | Options | Baseline price | Docs |",
                  "|---|---|---|---|---|---|---|"]
        for item in items:
            schema = item.get("input_schema") or {}
            docs = " ".join("[%d](%s)" % (n + 1, url) for n, url in enumerate(item.get("docs") or []))
            lines.append("| `%s` | %s | %s | %s | %s | %s | %s |" % (
                item["slug"], item.get("title", ""), ", ".join(item.get("operation_type") or []),
                ", ".join(schema.get("required") or []), _options(schema), _baseline(item),
                docs or "[console](%s)" % item["console"]))
        lines.append("")
    if payload.get("helper_endpoints_in_docs"):
        lines += ["## Other endpoints named in the docs", "",
                  "Not generation models (presets, style lists, Soul ID references) or not enabled for this account:",
                  ""]
        lines += ["- `%s`" % endpoint for endpoint in payload["helper_endpoints_in_docs"]]
        lines.append("")
    return "\n".join(lines)


# ---- command line --------------------------------------------------------------------------------

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
        url = api.upload(path)
        if field.endswith("_urls"):
            arguments.setdefault(field, []).append(url)
        else:
            arguments[field] = url
        print("uploaded %s -> %s" % (path, field))
    return arguments


def validate(api, model, arguments, skip):
    if skip:
        return
    schema = api.schema(model)
    if schema is None:
        print("warning: %s is not in the model listing; sending unchecked" % model_path(model))
        return
    problems = check_arguments(schema, arguments)
    if problems:
        raise SystemExit("arguments rejected before sending (use --no-validate to override):\n  " + "\n  ".join(problems))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    p = sub.add_parser("models")
    p.add_argument("search", nargs="?")
    p = sub.add_parser("schema")
    p.add_argument("model")
    p = sub.add_parser("catalog")
    p.add_argument("--no-estimates", action="store_true")
    for name in ("estimate", "run"):
        p = sub.add_parser(name)
        p.add_argument("model")
        p.add_argument("--args")
        p.add_argument("--args-file")
        p.add_argument("--no-validate", action="store_true", help="skip the input-schema check")
        if name == "run":
            p.add_argument("--max-usd", type=float, required=True,
                           help="refuse the request if the estimate is above this many dollars")
            p.add_argument("--allow-unpriced", action="store_true",
                           help="accept a model whose estimate is a pricing description, not a number")
            p.add_argument("--out", default=str(DEFAULT_OUT))
            p.add_argument("--upload", action="append", metavar="FIELD=PATH",
                           help="upload a local file and pass its URL as FIELD (appended for *_urls fields)")
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
        from higgsfield_client import HiggsfieldClientError
    except ImportError:
        raise SystemExit("missing dependency: pip install -r tools/higgsfield/requirements.txt")
    api = Api()
    try:
        if args.command == "models":
            for item in api.models(search=args.search):
                print("%-6s %-24s %s" % (item.get("output_type"), ",".join(item.get("operation_type") or []), item["slug"]))
        elif args.command == "schema":
            schema = api.schema(args.model)
            if schema is None:
                raise SystemExit("no model %r in the listing" % args.model)
            print(json.dumps(schema, indent=2))
        elif args.command == "catalog":
            build_catalog(api, with_estimates=not args.no_estimates)
        elif args.command == "estimate":
            arguments = parse_arguments(args)
            validate(api, args.model, arguments, args.no_validate)
            print(json.dumps(api.estimate(args.model, arguments), indent=2))
        elif args.command == "run":
            arguments = parse_arguments(args, api)
            validate(api, args.model, arguments, args.no_validate)
            _job_dir, job = run(api, args.model, arguments, args.max_usd, args.out, args.allow_unpriced)
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
