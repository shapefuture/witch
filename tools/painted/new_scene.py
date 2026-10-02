#!/usr/bin/env python3
"""One command from an idea to a playable painted scene: a room, a street, a garden, a cellar, a view through a window ...
(an experiment; the pieces are documented in docs/art/painted_room.md, the scene plan in docs/art/scenes.md).

    python tools/painted/new_scene.py street                            # a brief of tools/painted/scenes/street.json
    python tools/painted/new_scene.py street --variant quiet            # the same place changed (a state of the world), same camera
    python tools/painted/new_scene.py NAME --kind interior --prompt "a round chamber with a stone table ..."   # an ad-hoc scene
    python tools/painted/new_scene.py NAME --image picture.png --kind street   # skip the generation: build from a picture you have
    python tools/painted/new_scene.py --list                            # the briefs, their kinds and which are built
    python tools/painted/new_scene.py --all --budget 1.0                # every unbuilt brief, stopping before the budget is spent

A *kind* (scenes/kinds.json) says how a sort of place is composed, calibrated and lit: its horizon, where the bare ground is, whether
the light is a source in the picture or a fixed direction (a dusk, a night), whether it gets a beam, what counts as a lamp, where the
characters stand. A *brief* (scenes/<id>.json) is one scene of the game: a kind, a prompt, notes, and named variants. Both can be
overridden from the command line; every choice is printed.

1. **Generate** (unless --image): `hf.py run xai/grok-imagine-image-2.0` with the brief's prompt in the house style, the hall plate as the
   style reference, capped by --max-usd (estimated first by hf.py). A variant is an edit of the base scene's plate asked for the same
   camera, and is built with the base's horizon, floor box and light, so the two depth meshes agree. Provenance: job_room.json, brief.json.
2. **Calibrate**: Depth Anything on the plate. The horizon is the kind's (the prompt asks for it; the generator keeps within a few percent:
   the hall 0.65, the chamber 0.62, a hallway asked for 0.667 came out 0.70). A floor fit over the bare ground is printed as a sanity
   check; --fit-horizon searches with it (weak). Give --horizon when the picture's horizon is visibly elsewhere.
3. **Build** (`build_painted.py`): room.json, light_map.png, depth_preview.png, the plate; the characters on the foreground ground.
4. **Life** (life.json): the plate's bright-against-surroundings blobs become glow lights (large ones above the horizon a breath, violet
   ones magic, the rest candles; ground highlights are not lamps; a sky too large to be a lamp is ignored); a kind with `beam` also
   gets a beam from the largest source onto the brightest ground. A draft: edit by hand.
5. **Walkable**: `walkable.py` writes the standable ground into room.json.
6. **Capture** (--godot or $GODOT, and xvfb-run): the standard views and a contact sheet, build/rooms/NAME/sheet.png.
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
SCENES = HERE / "scenes"
DEFAULT_REFS = [ROOT / "assets/painted/hall_clean/plate_empty.png"]
ASK_HORIZON = 0.62
DEFAULT_PALETTE = "olive, ochre and purple, warm dusty low-key light"
# The look of the game (docs/art/painted_room.md), and what a plate must never contain. The characters, the visitors and the
# citizens are actors in the engine, so a painted plate has nobody in it.
STYLE = ("Painting style: faceted low-poly papercraft, mottled dry matte colour, visible facets, slightly crooked broken-PS1 geometry, "
         "a dark foreground frame, NO black outline or inked edge. The reference picture shows the painting style only: draw the new "
         "place described, not the reference's room. Horizontal 16:9. Eye height low, the horizon about {pct} percent of the way down "
         "the frame, and a large clear area of ground, unobstructed, in the foreground to walk on. No people, no witch, no raccoon, "
         "no animals, no text, no letters.")
VARIANT_STYLE = ("Same painting style. Horizontal 16:9. No people, no witch, no raccoon, no animals, no text, no letters, "
                 "no black outline or inked edge.")


def load_kinds():
    kinds = json.loads((SCENES / "kinds.json").read_text(encoding="utf-8"))
    return {k: v for k, v in kinds.items() if not k.startswith("_")}


def load_brief(brief_id):
    path = SCENES / ("%s.json" % brief_id)
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def list_briefs():
    out = []
    for path in sorted(SCENES.glob("*.json")):
        if path.name != "kinds.json":
            out.append(json.loads(path.read_text(encoding="utf-8")))
    return out


def resolve(kind_name, brief=None, **overrides):
    """The kind's settings, then the brief's own, then explicit overrides (None means not given)."""
    kinds = load_kinds()
    if kind_name not in kinds:
        sys.exit("unknown kind %r (kinds: %s)" % (kind_name, ", ".join(sorted(kinds))))
    spec = dict(kinds[kind_name])
    for key in ("palette", "horizon", "floor", "actors", "sun", "beam", "life", "frame"):
        if brief and key in brief:
            spec[key] = brief[key]
    for key, value in overrides.items():
        if value is not None:
            spec[key] = value
    spec["kind"] = kind_name
    return spec


def compose_prompt(spec, scene_prompt):
    style = STYLE.format(pct=int(round(spec["horizon"] * 100)))
    return "%s %s Palette: %s. %s" % (scene_prompt.strip(), spec["composition"], spec.get("palette") or DEFAULT_PALETTE, style)


def compose_variant_prompt(change):
    return ("The same place from exactly the same camera position, angle and framing: the same layout, the same walls, ground and "
            "horizon height. Change only this: %s. %s" % (change.strip().rstrip("."), VARIANT_STYLE))


# ---- 1. generate -------------------------------------------------------------------------------------------------------
def generate(prompt, refs, max_usd, out_dir):
    """Returns the job's folder. `prompt` is complete (compose_prompt / compose_variant_prompt)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    args = {"prompt": prompt.strip(), "aspect_ratio": "16:9", "resolution": "2k", "quality": "medium"}
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
def floor_box_for(horizon, floor=None, w=bp.W, h=bp.H):
    """The bare ground in the foreground, in the 1280x720 frame: the kind's `floor` (x range, and the start and end of the span
    from the horizon to the bottom edge), by default the lower half of the ground's span in the middle 40 % of the width."""
    floor = floor or {"x": [0.30, 0.70], "from": 0.50, "to": 0.98}
    y0 = int((horizon + floor["from"] * (1.0 - horizon)) * h)
    y1 = int(min(floor["to"], 0.99) * h)
    return (int(floor["x"][0] * w), y0, int(floor["x"][1] * w), max(y1, y0 + 16))


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
def find_lights(plate, horizon, life=None, max_lights=14):
    """Bright blobs of the plate as glow lights; `life` is the kind's detection settings."""
    life = life or {}
    rgb = np.asarray(plate.resize((bp.W, bp.H)), np.float32) / 255.0
    luma = ndimage.gaussian_filter(rgb @ np.array([0.3, 0.55, 0.15], np.float32), 2.0)
    # bright against its surroundings (a window in a dark wall, a candle on a shelf), not merely bright (a lit carpet)
    mask = (luma > life.get("luma_min", 0.45)) & (luma - ndimage.gaussian_filter(luma, 45.0) > life.get("contrast", 0.20))
    labels, count = ndimage.label(mask)
    blobs = []
    for i in range(1, count + 1):
        ys, xs = np.nonzero(labels == i)
        if len(ys) < 18 or len(ys) > life.get("max_area", 6000):      # too large to be a lamp: a sky, a lit wall
            continue
        cx, cy = float(xs.mean()), float(ys.mean())
        colour = rgb[ys, xs].mean(axis=0)
        colour = colour / max(float(colour.max()), 1e-3)
        blobs.append(dict(x=cx, y=cy, area=len(ys), colour=colour, luma=float(luma[ys, xs].mean())))
    blobs.sort(key=lambda b: -b["luma"] * math.sqrt(b["area"]))
    # a lit patch of floor is not a lamp; the panes of one window are one light
    floor_y = (horizon + life.get("floor_cut", 0.35) * (1.0 - horizon)) * bp.H
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


def make_life(plate, horizon, light_map_luma_peak, spec=None):
    spec = spec or {}
    lights = find_lights(plate, horizon, spec.get("life"))
    source = next((l for l in lights if l.get("_big")), None)
    for l in lights:
        l.pop("_big", None)
    life = {"_about": "Drafted by tools/painted/new_scene.py from the plate's bright blobs: edit by hand (see docs/art/painted_room.md, Light and life).",
            "fps": 8, "glow": {"levels": 6, "depth": 0.97, "spare": 6}, "lights": lights,
            "frame": dict({"strength": 0.12, "breath": 0.5, "tint": [0.34, 0.24, 0.4]}, **spec.get("frame", {})),
            "occluders": {"witch": {"radius": 0.26, "height": 1.2}, "raccoon": {"radius": 0.2, "height": 0.5}},
            "actors": {"follow": 1.0}}
    if source and spec.get("beam", True):
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
def job_cost(job):
    try:
        return float(json.loads((job / "job.json").read_text(encoding="utf-8"))["estimate"]["usd"])
    except (OSError, KeyError, ValueError, TypeError):
        return 0.0


def make(name, spec, picture, source_note, *, horizon=None, floor_box=None, sun=None, sun_pixel=None, life=True, godot=None,
         brief=None, fit_horizon=False):
    """Calibrate, build, draft the life, mark the walkable ground and capture. Returns the report."""
    out = ROOT / "assets/painted" / name
    scratch = ROOT / "build/rooms" / name
    scratch.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    if brief:
        (out / "brief.json").write_text(json.dumps(brief, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")

    plate = Image.open(picture).convert("RGB").resize((bp.W, bp.H), Image.LANCZOS)
    print("depth ...")
    disparity = bp.run_depth(plate)
    if fit_horizon and not horizon:
        horizon, res = find_horizon(disparity, spec["horizon"])
    else:
        horizon = horizon or spec["horizon"]
        res = fit_floor(disparity, horizon, tuple(floor_box) if floor_box else floor_box_for(horizon, spec.get("floor")))[2]
    box = tuple(floor_box) if floor_box else floor_box_for(horizon, spec.get("floor"))
    print("%s: horizon %.3f (floor-fit residual %.3f%s), floor box %s" % (
        spec["kind"], horizon, res, "" if res < 0.15 else "  <- LOOK AT THE PICTURE", box))

    mode = spec.get("sun", {"mode": "source"})
    luma = ndimage.gaussian_filter(np.asarray(plate, np.float32) @ np.array([0.3, 0.55, 0.15], np.float32) / 255.0, 6.0)
    above = luma.copy()
    above[int(horizon * bp.H):] = 0
    sy, sx = np.unravel_index(np.argmax(above), above.shape)
    sun_pixel = sun_pixel or (float(sx), float(sy))

    build = ["--plate", str(picture), "--out", str(out), "--horizon", str(horizon), "--floor-box"] + [str(v) for v in box]
    if sun:
        build += ["--sun"] + [str(v) for v in sun]
    elif mode.get("mode") == "fixed":
        build += ["--sun"] + [str(v) for v in mode["dir"]]
    else:
        build += ["--sun-pixel", str(sun_pixel[0]), str(sun_pixel[1])]
    for actor, (fx, t) in spec.get("actors", {}).items():
        build += ["--actor", "%s=%d,%d" % (actor, bp.W * fx, bp.H * (horizon + t * (1 - horizon)))]
    build += ["--source", source_note]
    if bp.main(build):
        sys.exit("build_painted failed")
    room = json.loads((out / "room.json").read_text(encoding="utf-8"))
    if not sun and mode.get("mode") != "fixed" and room["sun_dir"][2] > -0.1:
        # the brightest ground can lie beyond the source (a lit ring of carpet): light from a source in the picture falls toward
        # the viewer, so keep the beam's horizontal part pointing away from the camera
        sd = np.array(room["sun_dir"], float)
        sd[2] = -abs(sd[2]) - 0.2
        room["sun_dir"] = [round(float(v), 3) for v in sd / np.linalg.norm(sd)]
        (out / "room.json").write_text(json.dumps(room) + "\n", encoding="utf-8")
        print("sun_dir turned to fall toward the viewer: %s (override with --sun X Y Z)" % room["sun_dir"])

    lights = 0
    if life:
        lm = Image.open(out / "light_map.png").convert("L")
        peak = np.unravel_index(np.argmax(np.asarray(lm.filter(ImageFilter.GaussianBlur(2)))), (bp.LIGHT_RES, bp.LIGHT_RES))
        # the light map's brightest cell back to a pixel of the plate: its ground point projected through the camera
        x0, z0, x1, z1 = bp.LIGHT_RECT
        wx = x0 + (x1 - x0) * peak[1] / (bp.LIGHT_RES - 1)
        wz = z0 + (z1 - z0) * peak[0] / (bp.LIGHT_RES - 1)
        f, pitch = bp.camera()
        up = np.array([0.0, math.cos(pitch), math.sin(pitch)])
        fwd = np.array([0.0, math.sin(pitch), -math.cos(pitch)])
        p = np.array([wx, -bp.EYE_H, wz])
        depth = max(float(p @ fwd), 0.3)
        ground_px = (float(np.clip(bp.W / 2 + f * p[0] / depth, 60, bp.W - 60)), float(np.clip(bp.H / 2 - f * (p @ up) / depth, 40, bp.H - 40)))
        drafted, src = make_life(plate, horizon, ground_px, spec)
        (out / "life.json").write_text(json.dumps(drafted, indent=1) + "\n", encoding="utf-8")
        lights = len(drafted["lights"])
        print("life.json: %d lights%s" % (lights, ", a beam from %s" % src["id"] if "beam" in drafted else ", no beam"))

    if "witch" in room["actors"]:       # (a first-person view has nobody to walk: the camera is the player)
        import walkable
        walkable.main([str(out)])

    report = {"name": name, "kind": spec["kind"], "horizon": horizon, "floor_fit_residual": round(res, 4), "floor_box": list(box),
              "sun_dir": room["sun_dir"], "actors": room["actors"], "lights": lights}
    (scratch / "report.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    if godot and shutil.which("xvfb-run"):
        capture(godot, name, scratch)
    else:
        print("no Godot given (--godot or $GODOT): skipped the capture")
    print("ready: assets/painted/%s  (report: build/rooms/%s/report.json)" % (name, name))
    return report


def build_one(name, *, brief=None, kind=None, prompt=None, variant=None, image=None, refs=(), max_usd=0.20, godot=None, **kw):
    """One scene (or one variant of one). Returns (report, cost in USD)."""
    scratch = ROOT / "build/rooms" / name
    base_dir = ROOT / "assets/painted" / name
    cost = 0.0
    if variant:
        if not brief or variant not in brief.get("variants", {}):
            sys.exit("%s has no variant %r (it has: %s)" % (name, variant, ", ".join((brief or {}).get("variants", {})) or "none"))
        if not (base_dir / "room.json").exists():
            sys.exit("build %s first: a variant is an edit of its plate" % name)
        base = json.loads((base_dir / "room.json").read_text(encoding="utf-8"))
        spec = resolve(kind or brief["kind"], brief)
        kw.setdefault("horizon", base.get("horizon", spec["horizon"]))
        kw.setdefault("floor_box", base["calibration"]["floor_box"])
        kw.setdefault("sun", base["sun_dir"])
        target = "%s_%s" % (name, variant)
        scratch = ROOT / "build/rooms" / target
        if image:
            picture, note = Path(image), "built from %s" % Path(image).name
        else:
            job = generate(compose_variant_prompt(brief["variants"][variant]), [base_dir / "plate.png"], max_usd, scratch)
            picture, cost = job / "image_0.png", job_cost(job)
            (ROOT / "assets/painted" / target).mkdir(parents=True, exist_ok=True)
            shutil.copy(job / "job.json", ROOT / "assets/painted" / target / "job_room.json")
            note = "%s: variant %r of %s: %s (job_room.json)" % (MODEL, variant, name, brief["variants"][variant][:140])
        return make(target, spec, picture, note, godot=godot, brief=brief, **kw), cost
    spec = resolve(kind or (brief or {}).get("kind", "interior"), brief)
    text = prompt or (brief or {}).get("prompt")
    if image:
        picture, note = Path(image), "built from %s" % Path(image).name
    else:
        if not text:
            sys.exit("give a brief id, --prompt, or --image")
        job = generate(compose_prompt(spec, text), [Path(r) for r in refs] or DEFAULT_REFS, max_usd, scratch)
        picture, cost = job / "image_0.png", job_cost(job)
        base_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy(job / "job.json", base_dir / "job_room.json")
        note = "%s: %s (job_room.json)" % (MODEL, text.strip()[:160])
    return make(name, spec, picture, note, godot=godot, brief=brief, **kw), cost


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("name", nargs="?", help="a brief's id (scenes/<id>.json), or the id of an ad-hoc scene: assets/painted/NAME/")
    ap.add_argument("--list", action="store_true", help="the briefs, their kinds, and which are built")
    ap.add_argument("--all", action="store_true", help="build every brief not built yet")
    ap.add_argument("--budget", type=float, default=1.0, help="--all: stop before the estimated total would pass this (USD)")
    ap.add_argument("--variants", action="store_true", help="--all: also build every variant")
    ap.add_argument("--kind", help="a kind of scenes/kinds.json (default: the brief's)")
    ap.add_argument("--prompt", help="what the place is (the kind's composition and the house style are added)")
    ap.add_argument("--variant", help="a named change of the brief's scene, same camera (an edit of the base plate)")
    ap.add_argument("--image", help="build from this picture instead of generating one")
    ap.add_argument("--ref", action="append", default=[], help="reference images (default: the hall plate, for the style)")
    ap.add_argument("--max-usd", type=float, default=0.20)
    ap.add_argument("--horizon", type=float, help="override the horizon (fraction of the height)")
    ap.add_argument("--fit-horizon", action="store_true", help="search for the horizon with the ground fit (weak, see above)")
    ap.add_argument("--floor-box", type=int, nargs=4, metavar=("X0", "Y0", "X1", "Y1"))
    ap.add_argument("--sun-pixel", type=float, nargs=2, metavar=("X", "Y"))
    ap.add_argument("--sun", type=float, nargs=3, metavar=("X", "Y", "Z"), help="the light's direction (default: the kind's)")
    ap.add_argument("--no-life", action="store_true")
    ap.add_argument("--godot", default=os.environ.get("GODOT"), help="Godot binary for the capture (default: $GODOT)")
    args = ap.parse_args(argv)

    if args.list:
        kinds = load_kinds()
        for b in list_briefs():
            built = (ROOT / "assets/painted" / b["id"] / "room.json").exists()
            variants = ", ".join("%s%s" % (v, "*" if (ROOT / "assets/painted" / ("%s_%s" % (b["id"], v)) / "room.json").exists() else "")
                                 for v in b.get("variants", {}))
            print("%-12s %-11s %-6s %s%s" % (b["id"], b["kind"], "built" if built else "-", b["title"], "   variants: " + variants if variants else ""))
        print("kinds: " + ", ".join(sorted(kinds)) + "   (* = variant built)")
        return 0

    common = dict(godot=args.godot, max_usd=args.max_usd, life=not args.no_life, fit_horizon=args.fit_horizon)
    if args.all:
        spent, built = 0.0, []
        todo = [(b, None) for b in list_briefs() if not (ROOT / "assets/painted" / b["id"] / "room.json").exists()]
        if args.variants:
            todo += [(b, v) for b in list_briefs() for v in b.get("variants", {})
                     if not (ROOT / "assets/painted" / ("%s_%s" % (b["id"], v)) / "room.json").exists()]
        for b, v in todo:
            if spent + args.max_usd * 0.6 > args.budget:       # a generation is estimated at about USD 0.09, capped at --max-usd
                print("budget: stopping before %s%s (spent %.2f of %.2f)" % (b["id"], "/" + v if v else "", spent, args.budget))
                break
            if v and not (ROOT / "assets/painted" / b["id"] / "room.json").exists():
                continue
            try:
                _, cost = build_one(b["id"], brief=b, variant=v, refs=args.ref, **common)
            except SystemExit as e:
                print("skipped %s%s: %s" % (b["id"], "/" + v if v else "", e))
                continue
            spent += cost
            built.append(b["id"] + ("/" + v if v else ""))
        print("built %d: %s; spent about USD %.2f" % (len(built), ", ".join(built), spent))
        return 0

    if not args.name:
        ap.error("give a scene name, --list or --all")
    brief = load_brief(args.name)
    if not brief and not args.prompt and not args.image:
        ap.error("%r is not a brief (see --list); give --prompt or --image for an ad-hoc scene" % args.name)
    if not brief and not args.kind and not args.variant:
        args.kind = "interior"
    _, cost = build_one(args.name, brief=brief, kind=args.kind, prompt=args.prompt, variant=args.variant, image=args.image,
                        refs=args.ref, horizon=args.horizon, floor_box=args.floor_box, sun=args.sun, sun_pixel=args.sun_pixel, **common)
    print("generation cost about USD %.2f" % cost)
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
