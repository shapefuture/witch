#!/usr/bin/env python3
"""One command from an idea to a playable painted room (an experiment; the pieces are documented in docs/art/painted_room.md).

    python tools/painted/new_room.py NAME --prompt "a round chamber with a stone table ..." [--ref IMG ...] [--max-usd 0.2]
    python tools/painted/new_room.py NAME --image picture.png          # skip the generation: build from a picture you have
    python tools/painted/new_room.py NAME --image p.png --horizon 0.62 --floor-box 384 565 960 704 --sun-pixel 740 280   # overrides

What it does, in order (each step prints what it chose; every choice has an override):

1. **Generate** (unless --image): `hf.py run xai/grok-imagine-image-2.0` with the prompt wrapped in the house style, the hall plate
   (and any --ref) as references, capped by --max-usd (estimated first by hf.py). The job's provenance is kept as job_room.json.
2. **Calibrate**: Depth Anything on the plate. The horizon is the 0.62 the prompt asks for (the models keep to it within a few
   percent: the hall's is 0.65, the chamber's 0.62, a hallway asked for 0.667 came out 0.70); a floor fit over the bare foreground
   floor is printed as a sanity check, and --fit-horizon searches for the horizon with it (weak: the fit barely depends on the
   horizon, so it is pulled toward 0.62). When the picture's horizon is visibly elsewhere, give --horizon. The floor box follows.
3. **Build** (`build_painted.py`): room.json, light_map.png, depth_preview.png, the plate. The sun is the brightest light source
   above the horizon; the witch and raccoon are put on the foreground floor.
4. **Life** (life.json): the bright blobs of the plate become glow lights (warm ones candles, violet ones magic, large ones a breath);
   the largest one above the horizon also gets a beam onto the brightest floor. Edit the file by hand afterwards; it is a draft.
5. **Walkable**: `walkable.py` writes the standable floor into room.json.
6. **Capture** (with --godot or $GODOT, and xvfb-run): the standard views and a contact sheet, build/rooms/NAME/sheet.png.
"""
import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import build_painted as bp  # noqa: E402

MODEL = "xai/grok-imagine-image-2.0"
DEFAULT_REFS = [ROOT / "assets/painted/hall_clean/plate_empty.png"]
ASK_HORIZON = 0.62
STYLE = ("Keep exactly the same painting style as the reference pictures: faceted low-poly papercraft, olive, ochre and purple "
         "colours, mottled stone, warm dusty low-key light, a dark foreground frame. Eye height low, the horizon (where the floor "
         "meets the far wall) about two thirds down the frame, and a large clear area of floor, unobstructed, in the foreground "
         "to walk on. No people, no witch, no raccoon, no animals, no text, no letters.")


# ---- 1. generate -------------------------------------------------------------------------------------------------------
def generate(prompt, refs, max_usd, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    args = {"prompt": prompt.strip() + " " + STYLE, "aspect_ratio": "16:9", "resolution": "2k", "quality": "medium"}
    args_file = out_dir / "args.json"
    args_file.write_text(json.dumps(args, indent=2) + "\n", encoding="utf-8")
    cmd = [sys.executable, str(ROOT / "tools/higgsfield/hf.py"), "run", MODEL, "--args-file", str(args_file), "--max-usd", str(max_usd)]
    for ref in refs:
        cmd += ["--upload", "image_urls=%s" % ref]
    print("generating (%s, at most USD %.2f, %d references) ..." % (MODEL, max_usd, len(refs)))
    with open(ROOT / ".hf.lock", "w") as lock:       # one job at a time: the account's concurrency is 2
        try:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        except ImportError:
            pass
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    print(proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else "")
    (ROOT / ".hf.lock").unlink(missing_ok=True)
    m = re.search(r"^job (\S+)$", proc.stdout, re.M)
    if proc.returncode != 0 or not m:
        sys.exit("generation failed:\n" + proc.stdout[-800:] + proc.stderr[-800:])
    job = Path(m.group(1))
    if not (job / "image_0.png").exists():
        sys.exit("the job made no image: %s" % job)
    return job


# ---- 2. calibrate ------------------------------------------------------------------------------------------------------
def floor_box_for(horizon, w=bp.W, h=bp.H):
    """The bare floor in the foreground: the lower half of the floor's span, the middle 40 % of the width."""
    y0 = int((horizon + 0.5 * (1.0 - horizon)) * h)
    return (int(0.30 * w), y0, int(0.70 * w), int(0.98 * h))


def fit_floor(disparity, horizon, box=None):
    """Trimmed least squares of disparity = a / z + b over the floor box, z from the camera's geometry at this horizon.
    Returns (a, b, residual): residual is the RMS error over the spread of the box's disparity."""
    old = bp.HORIZON_FRAC
    bp.HORIZON_FRAC = horizon
    try:
        f, pitch = bp.camera()
    finally:
        bp.HORIZON_FRAC = old
    x0, y0, x1, y1 = box or floor_box_for(horizon)
    ys, xs = np.mgrid[y0:y1:4, x0:x1:4].astype(np.float64)
    d = bp.rays(xs, ys, f, pitch)
    inv = (1.0 / (bp.EYE_H / np.maximum(-d[..., 1], 1e-3))).ravel()
    disp = disparity[ys.astype(int), xs.astype(int)].ravel()
    keep = np.ones_like(inv, dtype=bool)
    for _ in range(4):
        a, b = np.polyfit(inv[keep], disp[keep], 1)
        resid = np.abs(disp - (a * inv + b))
        keep = resid <= np.quantile(resid, 0.8)
    rms = float(np.sqrt(np.mean((disp[keep] - (a * inv[keep] + b)) ** 2)))
    return float(a), float(b), rms / max(float(np.ptp(disp)), 1e-6)


def find_horizon(disparity, prior=ASK_HORIZON, weight=0.8):
    best = None
    for h in np.arange(0.50, 0.801, 0.005):
        a, b, res = fit_floor(disparity, h)
        if a <= 0:
            continue
        score = res + weight * (h - prior) ** 2
        if best is None or score < best[0]:
            best = (score, float(h), res)
    if best is None:
        return prior, 1.0
    return round(best[1], 3), best[2]


# ---- 4. life ---------------------------------------------------------------------------------------------------------
def find_lights(plate, horizon, max_lights=14):
    """Bright blobs of the plate as glow lights."""
    rgb = np.asarray(plate.resize((bp.W, bp.H)), np.float32) / 255.0
    luma = ndimage.gaussian_filter(rgb @ np.array([0.3, 0.55, 0.15], np.float32), 2.0)
    # bright against its surroundings (a window in a dark wall, a candle on a shelf), not merely bright (a lit carpet)
    mask = (luma > 0.45) & (luma - ndimage.gaussian_filter(luma, 45.0) > 0.20)
    labels, count = ndimage.label(mask)
    blobs = []
    for i in range(1, count + 1):
        ys, xs = np.nonzero(labels == i)
        if len(ys) < 18:
            continue
        cx, cy = float(xs.mean()), float(ys.mean())
        colour = rgb[ys, xs].mean(axis=0)
        colour = colour / max(float(colour.max()), 1e-3)
        blobs.append(dict(x=cx, y=cy, area=len(ys), colour=colour, luma=float(luma[ys, xs].mean())))
    blobs.sort(key=lambda b: -b["luma"] * math.sqrt(b["area"]))
    # a lit patch of floor is not a lamp; the panes of one window are one light
    floor_y = (horizon + 0.35 * (1.0 - horizon)) * bp.H
    kept = []
    for b in blobs:
        if b["y"] > floor_y:
            continue
        if any(math.hypot(b["x"] - k["x"], b["y"] - k["y"]) < 40 + 0.9 * math.sqrt(k["area"] / math.pi) * 2.4 for k in kept):
            continue
        kept.append(b)
    lights = []
    for n, b in enumerate(kept[:max_lights]):
        big = b["area"] > 500 and b["y"] < horizon * bp.H
        violet = b["colour"][2] > b["colour"][0] * 0.95
        radius = float(np.clip(math.sqrt(b["area"] / math.pi) * 2.4, 26, 170))
        if big:
            kind, amount, strength, shift = "breath", 0.14, 0.26, 0.12
        elif violet:
            kind, amount, strength, shift = "magic", 0.35, 0.40, 0.0
        else:
            kind, amount, strength, shift = "candle", 0.32, 0.30, 0.40
        colour = np.clip(0.55 * b["colour"] + 0.45 * np.array([1.0, 0.8, 0.5]), 0, 1) if not violet else np.clip(b["colour"], 0, 1)
        lights.append({"id": "%s_%d" % (kind, n), "pixel": [int(b["x"]), int(b["y"])], "radius": int(radius),
                       "core": 0.14 if big else 0.25, "color": [round(float(c), 2) for c in colour], "strength": strength,
                       **({"depth_mode": "near"} if big else {}),
                       "flicker": {"kind": kind, "amount": amount, "seed": 3 + 11 * n, "shift": shift}, "_big": big})
    return lights


def make_life(plate, horizon, light_map_luma_peak):
    lights = find_lights(plate, horizon)
    source = next((l for l in lights if l.pop("_big")), None)
    for l in lights:
        l.pop("_big", None)
    life = {"_about": "Drafted by tools/painted/new_room.py from the plate's bright blobs: edit by hand (see docs/art/painted_room.md, Light and life).",
            "fps": 8, "glow": {"levels": 6, "depth": 0.97, "spare": 6}, "lights": lights,
            "frame": {"strength": 0.12, "breath": 0.5, "tint": [0.34, 0.24, 0.4]},
            "occluders": {"witch": {"radius": 0.26, "height": 1.2}, "raccoon": {"radius": 0.2, "height": 0.5}},
            "actors": {"follow": 1.0}}
    if source:
        sx, sy = source["pixel"]
        px, py = light_map_luma_peak
        r = source["radius"] * 0.35
        life["beam"] = {
            "source": source["id"], "color": [1.0, 0.88, 0.58], "shade": [0.16, 0.1, 0.2],
            "flicker": {"kind": "breath", "amount": 0.1, "seed": 3},
            "shaft": {"polygon": [[sx - r, sy - r], [sx + r, sy - r], [px + 70, py - 20], [px - 70, py - 20]], "feather": 36,
                      "base": 0.05, "gain": 1.1, "taper": 0.5, "shadow": 0.35, "taper_rows": [int(sy), int(py)]},
            "pool": {"polygon": [[px - 150, py], [px - 40, py - 14], [px + 90, py - 12], [px + 170, py + 6], [px + 110, py + 38],
                                 [px - 20, py + 46], [px - 130, py + 34]], "feather": 40, "base": 0.04, "gain": 1.0, "shadow": 0.6},
            "motes": {"cell": 9, "density": 0.3, "speed": 0.16, "strength": 0.6, "color": [1.0, 0.93, 0.7]}}
    return life, source


# ---- the whole thing ---------------------------------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("name", help="the room's id: assets/painted/NAME/")
    ap.add_argument("--prompt", help="what the room is (the house style is added)")
    ap.add_argument("--image", help="build from this picture instead of generating one")
    ap.add_argument("--ref", action="append", default=[], help="extra reference images (default: the hall plate)")
    ap.add_argument("--max-usd", type=float, default=0.20)
    ap.add_argument("--horizon", type=float, help="override the fitted horizon (fraction of the height)")
    ap.add_argument("--fit-horizon", action="store_true", help="search for the horizon with the floor fit (weak, see above)")
    ap.add_argument("--floor-box", type=int, nargs=4, metavar=("X0", "Y0", "X1", "Y1"))
    ap.add_argument("--sun", type=float, nargs=3, metavar=("X", "Y", "Z"), help="the light's direction (default: toward the source)")
    ap.add_argument("--sun-pixel", type=float, nargs=2, metavar=("X", "Y"))
    ap.add_argument("--no-life", action="store_true")
    ap.add_argument("--godot", default=os.environ.get("GODOT"), help="Godot binary for the capture (default: $GODOT)")
    args = ap.parse_args(argv)
    if not args.image and not args.prompt:
        ap.error("give --prompt (generate) or --image (build from a picture)")
    out = ROOT / "assets/painted" / args.name
    scratch = ROOT / "build/rooms" / args.name
    scratch.mkdir(parents=True, exist_ok=True)

    source_note = ""
    if args.image:
        picture = Path(args.image)
        source_note = "built from %s" % picture.name
    else:
        refs = [Path(r) for r in args.ref] or DEFAULT_REFS
        job = generate(args.prompt, refs, args.max_usd, scratch)
        picture = job / "image_0.png"
        out.mkdir(parents=True, exist_ok=True)
        shutil.copy(job / "job.json", out / "job_room.json")
        source_note = "%s: %s (job_room.json)" % (MODEL, args.prompt.strip()[:160])

    plate = Image.open(picture).convert("RGB").resize((bp.W, bp.H), Image.LANCZOS)
    print("depth ...")
    disparity = bp.run_depth(plate)
    if args.fit_horizon and not args.horizon:
        horizon, res = find_horizon(disparity)
    else:
        horizon = args.horizon or ASK_HORIZON
        res = fit_floor(disparity, horizon, tuple(args.floor_box) if args.floor_box else None)[2]
    box = tuple(args.floor_box) if args.floor_box else floor_box_for(horizon)
    print("horizon %.3f (floor-fit residual %.3f%s), floor box %s" % (horizon, res, "" if res < 0.15 else "  <- LOOK AT THE PICTURE" , box))

    # the brightest source above the horizon
    luma = ndimage.gaussian_filter(np.asarray(plate, np.float32) @ np.array([0.3, 0.55, 0.15], np.float32) / 255.0, 6.0)
    above = luma.copy()
    above[int(horizon * bp.H):] = 0
    sy, sx = np.unravel_index(np.argmax(above), above.shape)
    sun_pixel = tuple(args.sun_pixel) if args.sun_pixel else (float(sx), float(sy))

    witch = (bp.W * 0.50, bp.H * (horizon + 0.72 * (1 - horizon)))
    raccoon = (bp.W * 0.60, bp.H * (horizon + 0.80 * (1 - horizon)))
    build = ["--plate", str(picture), "--out", str(out), "--horizon", str(horizon), "--floor-box"] + [str(v) for v in box] + [
        "--sun-pixel", str(sun_pixel[0]), str(sun_pixel[1]),
        "--actor", "witch=%d,%d" % witch, "--actor", "raccoon=%d,%d" % raccoon, "--source", source_note]
    if args.sun:
        build += ["--sun"] + [str(v) for v in args.sun]
    if bp.main(build):
        sys.exit("build_painted failed")
    room = json.loads((out / "room.json").read_text(encoding="utf-8"))
    if not args.sun and room["sun_dir"][2] > -0.1:
        # the brightest floor can lie beyond the source (a lit ring of carpet): light from a source in the picture falls toward
        # the viewer, so keep the beam's horizontal part pointing away from the camera
        sd = np.array(room["sun_dir"], float)
        sd[2] = -abs(sd[2]) - 0.2
        room["sun_dir"] = [round(float(v), 3) for v in sd / np.linalg.norm(sd)]
        (out / "room.json").write_text(json.dumps(room) + "\n", encoding="utf-8")
        print("sun_dir turned to fall toward the viewer: %s (override with --sun X Y Z)" % room["sun_dir"])

    if not args.no_life:
        lm = Image.open(out / "light_map.png").convert("L")
        peak = np.unravel_index(np.argmax(np.asarray(lm.filter(ImageFilter.GaussianBlur(2)))), (bp.LIGHT_RES, bp.LIGHT_RES))
        # the light map's brightest cell back to a pixel of the plate: its floor point projected through the camera
        x0, z0, x1, z1 = bp.LIGHT_RECT
        wx = x0 + (x1 - x0) * peak[1] / (bp.LIGHT_RES - 1)
        wz = z0 + (z1 - z0) * peak[0] / (bp.LIGHT_RES - 1)
        f, pitch = bp.camera()
        up = np.array([0.0, math.cos(pitch), math.sin(pitch)])
        fwd = np.array([0.0, math.sin(pitch), -math.cos(pitch)])
        p = np.array([wx, -bp.EYE_H, wz])
        depth = max(float(p @ fwd), 0.3)
        floor_px = (float(np.clip(bp.W / 2 + f * p[0] / depth, 60, bp.W - 60)), float(np.clip(bp.H / 2 - f * (p @ up) / depth, 40, bp.H - 40)))
        life, src = make_life(plate, horizon, floor_px)
        (out / "life.json").write_text(json.dumps(life, indent=1) + "\n", encoding="utf-8")
        print("life.json: %d lights%s" % (len(life["lights"]), ", a beam from %s" % src["id"] if src else ", no beam (no large light above the horizon)"))

    import walkable
    walkable.main([str(out)])

    report = {"name": args.name, "horizon": horizon, "floor_fit_residual": round(res, 4), "floor_box": list(box),
              "sun_pixel": [round(v) for v in sun_pixel], "sun_dir": room["sun_dir"], "witch": room["actors"].get("witch"),
              "lights": 0 if args.no_life else len(life["lights"])}
    (scratch / "report.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")

    if args.godot and shutil.which("xvfb-run"):
        capture(args.godot, args.name, scratch)
    else:
        print("no Godot given (--godot or $GODOT): skipped the capture")
    print("room ready: assets/painted/%s  (report: build/rooms/%s/report.json)" % (args.name, args.name))
    return 0


def capture(godot, name, scratch):
    subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], capture_output=True, cwd=ROOT)
    frames = scratch / "frames"
    cmd = ["xvfb-run", "-a", godot, "--path", str(ROOT), "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--resolution", "1280x720", "--script", "res://tools/painted/capture_painted.gd", "--", str(frames),
           "res://assets/painted/%s" % name, "views"]
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    errors = [l for l in proc.stdout.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    if errors:
        print("capture errors:\n" + "\n".join(errors[:5]))
    shots = [frames / n for n in ("psx.png", "psx_step_right.png", "psx_step_in.png", "psx_roll.png")]
    shots = [s for s in shots if s.exists()]
    if not shots:
        print("the capture made no frames")
        return
    ims = [Image.open(s).convert("RGB").resize((640, 360)) for s in shots]
    sheet = Image.new("RGB", (1280, 360 * ((len(ims) + 1) // 2)))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % 2) * 640, (i // 2) * 360))
    sheet.save(scratch / "sheet.png")
    print("contact sheet: %s" % (scratch / "sheet.png"))


if __name__ == "__main__":
    sys.exit(main())
