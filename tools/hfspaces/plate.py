#!/usr/bin/env python3
"""Room plates from free Hugging Face ZeroGPU Spaces: a picture from a prompt, and an image edit for a variant (an experiment).

    python tools/hfspaces/plate.py doctor                                # token set?, account tier, ZeroGPU quota, the Spaces (free)
    python tools/hfspaces/plate.py gen "PROMPT" --out DIR/NAME [--space auto|schnell|qwen|dev] [--seed 7] [--size 1536x864]
    python tools/hfspaces/plate.py gen --prompt-file PROMPT.txt --out DIR/NAME ...
    python tools/hfspaces/plate.py edit IMAGE "INSTRUCTION" --out DIR/NAME [--space kontext|qwen-edit] [--seed 7]
    python tools/hfspaces/plate.py fit IN.png OUT.png [--size 1280x720]   # centre-crop to the aspect and resize (local, free)
    python tools/hfspaces/plate.py erase IN.png OUT.png --box X0,Y0,X1,Y1 ...   # paint out stray numerals/letters (local, free)

Writes DIR/NAME.png (the Space's picture as PNG; when it sent another format, DIR/NAME.<ext> keeps its bytes too) and DIR/NAME.json:
the Space and its git revision, every call with its arguments, prompt, seed, size, date, latency, and the ZeroGPU quota before and
after. --dry-run checks the token, the Space and the quota, and sends nothing.

`--space auto` (gen's default) tries schnell, then qwen, then dev, ONCE each, and stops at the first picture; a Space that is down,
refuses (quota) or fails is recorded in NAME.json and the next is tried. Nothing loops. A run is spent whether a call works or not.

The quota (a free account, measured: README.md): 300 GPU-seconds and 8 runs a day, 24 h from the first call; an `xlarge` Space
counts double. A call is refused here, before it is sent, when less is left than the Space asks ZeroGPU for (its @spaces.GPU
duration, read from its app.py; `doctor` re-reads it).

Token: HUGGINGFACE_TOKEN from the environment, else from .env.local at the repo root (HF_ENV_FILE names another file). It goes only to
huggingface.co and to the Space (the ZeroGPU identity) and is never printed or written. Only ZeroGPU Spaces: no paid Inference Providers.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKEN_NAME = "HUGGINGFACE_TOKEN"
HUB = "https://huggingface.co"
UA = "witch-hfspaces-plate/1"

# Each Space: what it does, what it asks ZeroGPU for (its @spaces.GPU duration in its app.py, 2026-10-29) and the quota rate
# (`xlarge` counts double). Licences are the models' own (their model cards).
FLUX_DEV_LICENCE = "FLUX.1 [dev] Non-Commercial License; its Outputs clause allows any use of the outputs"
SPACES = {
    "schnell": {"id": "black-forest-labs/FLUX.1-schnell", "modes": ("gen",), "gpu": 60, "rate": 1, "licence": "Apache-2.0"},
    "qwen": {"id": "Qwen/Qwen-Image-2512", "modes": ("gen",), "gpu": 120, "rate": 2, "licence": "Apache-2.0"},
    "dev": {"id": "black-forest-labs/FLUX.1-dev", "modes": ("gen",), "gpu": 75, "rate": 1, "licence": FLUX_DEV_LICENCE},
    "kontext": {"id": "black-forest-labs/FLUX.1-Kontext-Dev", "modes": ("edit",), "gpu": 60, "rate": 1, "licence": FLUX_DEV_LICENCE},
    "qwen-edit": {"id": "Qwen/Qwen-Image-Edit", "modes": ("edit",), "gpu": 120, "rate": 1, "licence": "Apache-2.0"},
}
GEN_ORDER = ("schnell", "qwen", "dev")
QWEN_ASPECTS = {"1:1": 1.0, "16:9": 16 / 9, "9:16": 9 / 16, "4:3": 4 / 3, "3:4": 3 / 4, "3:2": 1.5, "2:3": 2 / 3}
QUOTA_WORDS = re.compile(r"quota|exceeded|GPU duration", re.I)


class PlateError(Exception):
    def __init__(self, message, record=None):
        super().__init__(message)
        self.record = record or {}


class Refused(PlateError):
    """Not sent: a guard said no (no token, the Space is not running, too little quota)."""


class QuotaError(PlateError):
    """The Space refused the call for ZeroGPU quota."""


class SpaceError(PlateError):
    """The call failed: inside the Space, or on the way."""


# ---- the token ---------------------------------------------------------------------------------------------------------------
_secret = {"value": ""}


def env_file():
    return Path(os.environ.get("HF_ENV_FILE") or ROOT / ".env.local")


def load_token():
    """(token, where it came from). The environment wins over the file; the value is never shown."""
    value, where = os.environ.get(TOKEN_NAME, "").strip(), "environment"
    if not value:
        where = "missing"
        path = env_file()
        if path.is_file():
            for line in path.read_text(encoding="utf-8").splitlines():
                key, sep, val = line.strip().partition("=")
                key = key.strip()
                key = key[len("export "):].strip() if key.startswith("export ") else key
                if sep and key == TOKEN_NAME:
                    value, where = val.strip().strip("\"'"), path.name
                    break
    _secret["value"] = value
    return value, where


def scrub(text):
    text = str(text)
    secret = _secret["value"]
    return text.replace(secret, "<%s>" % TOKEN_NAME) if len(secret) >= 8 else text


def say(message):
    print(scrub(message), flush=True)


# ---- the Hub (plain HTTP: no quota) ------------------------------------------------------------------------------------------
def hub(path, as_json=True):
    headers = {"User-Agent": UA}
    if _secret["value"]:
        headers["Authorization"] = "Bearer " + _secret["value"]
    with urllib.request.urlopen(urllib.request.Request(HUB + path, headers=headers), timeout=30) as response:
        body = response.read().decode("utf-8")
    return json.loads(body) if as_json else body


def quota():
    """The ZeroGPU quota left to this account: seconds, runs, and when the window resets."""
    q = hub("/api/spaces/zero-gpu/quota")
    runs = q.get("runs") or {}
    return {"seconds": float(q.get("current", 0.0)), "of": float(q.get("base", 0.0)), "runs": int(runs.get("remaining", 0)),
            "runs_of": int(runs.get("limit", 0)), "resets_at": q.get("resetsAt") or runs.get("resetsAt")}


def space_state(space_id):
    info = hub("/api/spaces/" + space_id)
    runtime = info.get("runtime") or {}
    return {"stage": runtime.get("stage"), "hardware": (runtime.get("hardware") or {}).get("current"), "sha": info.get("sha")}


GPU_DECORATOR = re.compile(r"@spaces\.GPU(?:\(([^)]*)\))?")


def declared_gpu(source):
    """What an app.py asks ZeroGPU for, from its first @spaces.GPU: (duration: seconds or a function's name, size). Text only."""
    m = GPU_DECORATOR.search(source)
    if not m:
        return None, None
    inside = m.group(1) or ""
    duration = re.search(r"duration\s*=\s*([\w.]+)", inside)
    size = re.search(r"size\s*=\s*['\"](\w+)['\"]", inside)
    return (duration.group(1) if duration else "60"), (size.group(1) if size else "large")


# ---- the calls (one per Space; each returns the Space's answer and the calls made, for the provenance) --------------------------
def _send(client, api_name, args, timeout):
    return client.submit(api_name=api_name, **args).result(timeout=timeout)


def _file(path):
    from gradio_client import handle_file
    return handle_file(str(path))


def call_schnell(client, a, timeout):
    args = dict(prompt=a["prompt"], seed=a["seed"], randomize_seed=False, width=a["size"][0], height=a["size"][1],
                num_inference_steps=a.get("steps") or 4)
    return _send(client, "/infer", args, timeout), [("/infer", args)]


def call_qwen(client, a, timeout):
    aspect = a["size"][0] / a["size"][1]
    ratio = min(QWEN_ASPECTS, key=lambda k: abs(QWEN_ASPECTS[k] - aspect))
    args = dict(prompt=a["prompt"], seed=a["seed"], randomize_seed=False, aspect_ratio=ratio, guidance_scale=4.0,
                num_inference_steps=a.get("steps") or 50, prompt_enhance=False)     # True loops on a DashScope key it lacks
    return _send(client, "/infer", args, timeout), [("/infer", args)]


def call_dev(client, a, timeout):
    args = dict(prompt=a["prompt"], seed=a["seed"], randomize_seed=False, width=a["size"][0], height=a["size"][1],
                guidance_scale=3.5, num_inference_steps=a.get("steps") or 28)
    return _send(client, "/infer", args, timeout), [("/infer", args)]


def call_kontext(client, a, timeout):
    args = dict(input_image=_file(a["image"]), prompt=a["prompt"], seed=a["seed"], randomize_seed=False, guidance_scale=2.5,
                steps=min(a.get("steps") or 28, 30))
    return _send(client, "/infer", args, timeout), [("/infer", args)]


def call_qwen_edit(client, a, timeout):
    args = dict(image=_file(a["image"]), prompt=a["prompt"], seed=a["seed"], randomize_seed=False, true_guidance_scale=4.0,
                num_inference_steps=a.get("steps") or 50, rewrite_prompt=False)      # True loops on a DashScope key it lacks
    return _send(client, "/infer", args, timeout), [("/infer", args)]


CALLS = {"schnell": call_schnell, "qwen": call_qwen, "dev": call_dev, "kontext": call_kontext, "qwen-edit": call_qwen_edit}


def picture_of(answer):
    """The local path of the picture in a Space's answer (a path, a FileData dict, or a tuple/list whose first item is one)."""
    if isinstance(answer, (list, tuple)) and answer:
        answer = answer[0]
    if isinstance(answer, dict):
        answer = answer.get("path") or answer.get("value") or answer.get("name")
        if isinstance(answer, dict):
            answer = answer.get("path")
    if not answer or not Path(str(answer)).is_file():
        raise SpaceError("the Space answered without a picture: %s" % scrub(repr(answer))[:200])
    return Path(str(answer))


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _for_json(args):
    """Call arguments as recorded: an uploaded file becomes its name and hash."""
    out = {}
    for k, v in args.items():
        if isinstance(v, dict) and "path" in v and ("meta" in v or "orig_name" in v):
            out[k] = {"file": Path(v["path"]).name}
        else:
            out[k] = v
    return out


def _spent(before):
    time.sleep(2.0)                     # the quota endpoint lags the call a little
    try:
        after = quota()
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"before": before, "after": None, "error": scrub(e)[:200]}
    return {"before": before, "after": after, "used_seconds": round(before["seconds"] - after["seconds"], 1),
            "used_runs": before["runs"] - after["runs"]}


def save_picture(raw, png):
    """The picture as PNG; the Space's own bytes kept beside it when they were another format. Returns (format, [w, h])."""
    fmt, size = raw.suffix.lstrip(".").lower() or "bin", None
    try:
        from PIL import Image
    except ImportError:
        shutil.copyfile(raw, png.with_name(png.stem + "." + fmt))
        return fmt, size
    with Image.open(raw) as im:
        fmt, size = (im.format or fmt).lower(), list(im.size)
        im.convert("RGB").save(png)
    if fmt != "png":
        shutil.copyfile(raw, png.with_name(png.stem + "." + {"jpeg": "jpg"}.get(fmt, fmt)))
    return fmt, size


def run_one(key, mode, a, out, *, dry_run=False, guard=True, timeout=900.0):
    """One call to one Space. Returns the provenance record; raises Refused / QuotaError / SpaceError (each carries what it cost)."""
    spec = SPACES[key]
    if mode not in spec["modes"]:
        raise Refused("%s does not do %s (it does %s)" % (key, mode, ", ".join(spec["modes"])))
    state = space_state(spec["id"])
    need = spec["gpu"] * spec["rate"]
    record = {"tool": "tools/hfspaces/plate.py", "ok": False, "mode": mode, "space": spec["id"], "space_key": key,
              "space_sha": state["sha"], "hardware": state["hardware"], "licence": spec["licence"], "prompt": a["prompt"],
              "seed": a["seed"], "size_asked": list(a["size"]) if mode == "gen" else None,
              "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    if a.get("image"):
        record["input_image"] = {"file": str(a["image"]), "sha256": sha256(a["image"])}
    if state["stage"] != "RUNNING":
        raise Refused("%s is %s, not RUNNING" % (spec["id"], state["stage"]), record)
    before = quota()
    record["zerogpu"] = {"asks_seconds": spec["gpu"], "rate": spec["rate"], "before": before}
    if guard and (before["runs"] < 1 or before["seconds"] < need):
        raise Refused("ZeroGPU quota: %.0f s and %d runs left, %s asks for %d s%s (window resets %s)" % (
            before["seconds"], before["runs"], spec["id"], spec["gpu"], " at 2x" if spec["rate"] == 2 else "",
            before["resets_at"] or "24 h after its first call"), record)
    if dry_run:
        record["dry_run"] = True
        return record

    from gradio_client import Client
    downloads = out.parent / (out.name + ".download")
    t0 = time.time()
    try:
        client = Client(spec["id"], token=_secret["value"] or None, verbose=False, download_files=str(downloads),
                        analytics_enabled=False)
        answer, calls = CALLS[key](client, a, timeout)
        raw = picture_of(answer)
    except PlateError as e:
        shutil.rmtree(downloads, ignore_errors=True)
        e.record = dict(record, latency_s=round(time.time() - t0, 1), zerogpu=dict(record["zerogpu"], **_spent(before)))
        raise
    except Exception as e:                                       # gradio_client raises its own and plain exceptions
        shutil.rmtree(downloads, ignore_errors=True)
        message = scrub("%s: %s" % (type(e).__name__, e))[:600]
        failed = dict(record, latency_s=round(time.time() - t0, 1), zerogpu=dict(record["zerogpu"], **_spent(before)))
        raise (QuotaError if QUOTA_WORDS.search(message) else SpaceError)(message, failed)
    latency = time.time() - t0
    png = out.parent / (out.name + ".png")
    fmt, size = save_picture(raw, png)
    shutil.rmtree(downloads, ignore_errors=True)
    record.update(ok=True, calls=[{"endpoint": ep, "arguments": _for_json(args)} for ep, args in calls], returned_format=fmt,
                  size=size, latency_s=round(latency, 1), png=png.name, sha256=sha256(png))
    record["zerogpu"].update(_spent(before))
    return record


def write_json(path, data):
    path.write_text(scrub(json.dumps(data, indent=1, ensure_ascii=False)) + "\n", encoding="utf-8")


def chain(mode, order, a, out, *, dry_run=False, guard=True, timeout=900.0):
    """Each Space of `order` once, until one makes a picture. Writes OUT.json either way. Returns 0, or 1 if none did."""
    token, where = load_token()
    if not token:
        say("no %s: export it, or put it in %s (HF_ENV_FILE names another file)" % (TOKEN_NAME, env_file()))
        return 2
    out.parent.mkdir(parents=True, exist_ok=True)
    attempts = []
    for key in order:
        say("%s on %s ..." % (mode, SPACES[key]["id"]))
        try:
            record = run_one(key, mode, a, out, dry_run=dry_run, guard=guard, timeout=timeout)
        except (PlateError, urllib.error.URLError, OSError) as e:
            outcome = type(e).__name__ if isinstance(e, PlateError) else "SpaceError"
            attempts.append(dict(getattr(e, "record", {}), outcome=outcome, error=scrub(e)[:600]))
            say("  %s: %s" % (outcome, scrub(e)))
            continue
        if dry_run:
            say("  dry run: would send to %s (quota %.0f s, %d runs left; it asks for %d s)" % (
                record["space"], record["zerogpu"]["before"]["seconds"], record["zerogpu"]["before"]["runs"], SPACES[key]["gpu"]))
            return 0
        record["attempts"] = [{"space": t.get("space"), "outcome": t["outcome"], "error": t["error"]} for t in attempts] + \
                             [{"space": record["space"], "outcome": "ok"}]
        write_json(out.parent / (out.name + ".json"), record)
        z = record["zerogpu"]
        say("  %s: %s %s, %.1f s; ZeroGPU used %s s and %s run(s), %s s and %s runs left" % (
            out.parent / record["png"], record["returned_format"], "x".join(map(str, record["size"] or [])), record["latency_s"],
            z.get("used_seconds"), z.get("used_runs"), (z.get("after") or {}).get("seconds"), (z.get("after") or {}).get("runs")))
        return 0
    if not dry_run:
        write_json(out.parent / (out.name + ".json"), {"tool": "tools/hfspaces/plate.py", "ok": False, "mode": mode,
                                                       "prompt": a["prompt"], "seed": a["seed"], "attempts": attempts})
    say("no Space made a picture (%s)" % ", ".join("%s: %s" % (t.get("space", "?"), t["outcome"]) for t in attempts))
    return 1


# ---- local -------------------------------------------------------------------------------------------------------------------
def fit(src, dst, size=(1280, 720)):
    """Centre-crop to the aspect of `size`, then resize to it (the painted pipeline's plate is 1280x720, 16:9)."""
    from PIL import Image
    tw, th = size
    with Image.open(src) as im:
        im = im.convert("RGB")
        w, h = im.size
        if w * th > h * tw:                                      # wider than the target: trim the sides
            nw = round(h * tw / th)
            im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        elif w * th < h * tw:                                    # taller: trim top and bottom
            nh = round(w * th / tw)
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        im.resize((tw, th), Image.LANCZOS).save(dst)
    return Path(dst)


def erase(src, dst, boxes, darker=0.5, grow=1, iterations=300):
    """Paint out small dark marks a generator drew where a plate must have no writing (a clock's numerals, letters on a sign):
    in each box (x0, y0, x1, y1) the pixels darker than `darker` times the box's median luma are masked, grown by `grow` px, and
    filled from the paint around them by diffusion. Everything outside the boxes is untouched. Returns the pixels changed."""
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(src).convert("RGB"), np.float32)
    h, w = a.shape[:2]
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    inside = np.zeros((h, w), bool)
    mask = np.zeros((h, w), bool)
    for x0, y0, x1, y1 in boxes:
        inside[y0:y1, x0:x1] = True
        mask[y0:y1, x0:x1] |= lum[y0:y1, x0:x1] < darker * float(np.median(lum[y0:y1, x0:x1]))
    for _ in range(grow):
        grown = mask.copy()
        grown[1:] |= mask[:-1]
        grown[:-1] |= mask[1:]
        grown[:, 1:] |= mask[:, :-1]
        grown[:, :-1] |= mask[:, 1:]
        mask = grown & inside
    for x0, y0, x1, y1 in boxes:
        X0, Y0, X1, Y1 = max(x0 - 1, 0), max(y0 - 1, 0), min(x1 + 1, w), min(y1 + 1, h)
        win, m = a[Y0:Y1, X0:X1], mask[Y0:Y1, X0:X1]
        if not m.any() or m.all():
            continue
        win[m] = np.median(win[~m], axis=0)
        for _ in range(iterations):                              # Jacobi: a masked pixel becomes the mean of its 4 neighbours
            p = np.pad(win, ((1, 1), (1, 1), (0, 0)), mode="edge")
            win[m] = ((p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4.0)[m]
    Image.fromarray(np.clip(np.round(a), 0, 255).astype(np.uint8)).save(dst)
    return int(mask.sum())


def box_arg(text):
    parts = [p for p in re.split(r"[,\s]+", text.strip()) if p]
    if len(parts) != 4 or not all(p.isdigit() for p in parts):
        raise argparse.ArgumentTypeError("a box is X0,Y0,X1,Y1 in pixels")
    x0, y0, x1, y1 = (int(p) for p in parts)
    if x1 <= x0 or y1 <= y0:
        raise argparse.ArgumentTypeError("a box needs X1 > X0 and Y1 > Y0")
    return x0, y0, x1, y1


def size_arg(text):
    m = re.fullmatch(r"\s*(\d+)\s*[xX]\s*(\d+)\s*", text)
    if not m:
        raise argparse.ArgumentTypeError("a size is WxH, e.g. 1536x864")
    return int(m.group(1)), int(m.group(2))


# ---- commands ----------------------------------------------------------------------------------------------------------------
def cmd_doctor(_args):
    token, where = load_token()
    say("%-14s %s" % (TOKEN_NAME, ("set (from %s)" % where) if token else "MISSING (export it, or .env.local; HF_ENV_FILE for another file)"))
    if token:
        try:
            who = hub("/api/whoami-v2")
            say("%-14s PRO %s, can be billed %s" % ("account", bool(who.get("isPro")), bool(who.get("canPay"))))
            q = quota()
            say("%-14s %.0f of %.0f GPU-seconds and %d of %d runs left; resets %s" % (
                "ZeroGPU", q["seconds"], q["of"], q["runs"], q["runs_of"], q["resets_at"] or "24 h after the first call"))
        except (urllib.error.URLError, OSError, ValueError) as e:
            say("%-14s cannot read the account or quota: %s" % ("account", scrub(e)[:160]))
    for key, spec in SPACES.items():
        try:
            state = space_state(spec["id"])
            duration, size = declared_gpu(hub("/spaces/%s/raw/main/app.py" % spec["id"], as_json=False))
        except (urllib.error.URLError, OSError, ValueError) as e:
            say("%-9s %-38s unreachable: %s" % (key, spec["id"], scrub(e)[:120]))
            continue
        stale = str(duration) != str(spec["gpu"]) or (size == "xlarge") != (spec["rate"] == 2)
        say("%-9s %-38s %-9s %-10s asks %s s, %s%s" % (key, spec["id"], state["stage"], state["hardware"], duration, size,
                                                     "   <- SPACES says %s s x%d: update it" % (spec["gpu"], spec["rate"]) if stale else ""))
    return 0


def cmd_gen(args):
    prompt = args.prompt if args.prompt else Path(args.prompt_file).read_text(encoding="utf-8").strip()
    if not prompt:
        raise SystemExit("give a prompt, or --prompt-file")
    order = GEN_ORDER if args.space == "auto" else (args.space,)
    a = {"prompt": prompt, "seed": args.seed, "size": args.size, "steps": args.steps}
    return chain("gen", order, a, _out(args.out), dry_run=args.dry_run, guard=not args.no_guard, timeout=args.timeout)


def cmd_edit(args):
    image = Path(args.image)
    if not image.is_file():
        raise SystemExit("no such picture: %s" % image)
    prompt = args.prompt if args.prompt else Path(args.prompt_file).read_text(encoding="utf-8").strip()
    if not prompt:
        raise SystemExit("give an instruction, or --prompt-file")
    a = {"prompt": prompt, "seed": args.seed, "size": (0, 0), "steps": args.steps, "image": image}
    return chain("edit", (args.space,), a, _out(args.out), dry_run=args.dry_run, guard=not args.no_guard, timeout=args.timeout)


def cmd_fit(args):
    say("wrote %s" % fit(args.src, args.dst, args.size))
    return 0


def cmd_erase(args):
    changed = erase(args.src, args.dst, args.box, darker=args.darker, grow=args.grow)
    say("wrote %s: %d pixels painted out in %d box(es)" % (args.dst, changed, len(args.box)))
    return 0


def _out(text):
    out = Path(text)
    return out.with_suffix("") if out.suffix.lower() in (".png", ".json") else out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("doctor", help="token, account, quota, Spaces (free)").set_defaults(fn=cmd_doctor)
    for name, fn, spaces, default in (("gen", cmd_gen, ("auto",) + GEN_ORDER, "auto"), ("edit", cmd_edit, ("kontext", "qwen-edit"), "kontext")):
        p = sub.add_parser(name)
        if name == "edit":
            p.add_argument("image", help="the picture to edit")
        p.add_argument("prompt", nargs="?", help="the prompt (gen) or the instruction (edit)")
        p.add_argument("--prompt-file", help="read the prompt from this file")
        p.add_argument("--out", required=True, help="DIR/NAME: writes DIR/NAME.png and DIR/NAME.json")
        p.add_argument("--space", choices=spaces, default=default)
        p.add_argument("--seed", type=int, default=7)
        p.add_argument("--steps", type=int, help="override the Space's default step count")
        p.add_argument("--timeout", type=float, default=900.0, help="seconds to wait for the Space's answer")
        p.add_argument("--dry-run", action="store_true", help="check token, Space and quota; send nothing")
        p.add_argument("--no-guard", action="store_true", help="send even when the quota looks too low (ZeroGPU then decides)")
        if name == "gen":
            p.add_argument("--size", type=size_arg, default=(1536, 864), help="WxH asked of the FLUX Spaces (Qwen takes the nearest aspect)")
        p.set_defaults(fn=fn)
    p = sub.add_parser("fit", help="centre-crop to the aspect, resize (local)")
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--size", type=size_arg, default=(1280, 720))
    p.set_defaults(fn=cmd_fit)
    p = sub.add_parser("erase", help="paint out small dark marks (stray numerals, letters) inside boxes (local)")
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--box", type=box_arg, action="append", required=True, help="X0,Y0,X1,Y1 around one mark (repeat)")
    p.add_argument("--darker", type=float, default=0.5, help="a mark is darker than this times the box's median luma")
    p.add_argument("--grow", type=int, default=1, help="pixels the mask grows by (the mark's anti-aliased edge)")
    p.set_defaults(fn=cmd_erase)
    args = ap.parse_args(argv)
    if getattr(args, "prompt", None) is None and getattr(args, "prompt_file", None) is None and args.cmd in ("gen", "edit"):
        ap.error("give a prompt or --prompt-file")
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
