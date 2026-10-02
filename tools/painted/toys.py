#!/usr/bin/env python3
"""Makes a generated scene's objects alive: lifts them out of the painting so a poke can move them (docs/art/scenes.md, Toys).

    python tools/painted/toys.py prompt garden                        # the toys a brief marks and the edit's prompt (free)
    python tools/painted/toys.py build assets/painted/garden [--brief garden] [--image EDIT.png] [--no-spheres] [--max-usd 0.12]
    python tools/painted/toys.py check assets/painted/garden          # the toy box's invariants (free)

A layout element marked `"toy": "<type>"` (types: scenes/toys.json) is a toy. ONE editing call (Marketing Studio, about USD 0.06) takes the
cutout toys out of the room's plate and, in the same picture, paints the two calibration spheres of sphere_probe.py, so the lighting costs
nothing extra. The pixels the edit changed inside each toy's box become its cutout (lift_prop.py: a mask, a card at the object's depth, the
painting behind it from the edit); a toy that did not come off, or an object that is a hotspot by type, answers with the painting itself.
Everything is registered to the plate: an edit that drifts (Qwen's larger edits stretched the frame 1.6 %) is refused, its toys become hotspots.
Run walkable.py after this (lifted objects are not floor); new_scene.py does it all in order.
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import lift_prop as lp  # noqa: E402
import scene_layout as sl  # noqa: E402
import walkable  # noqa: E402
import sphere_probe  # noqa: E402
import toybox  # noqa: E402

TYPES_FILE = HERE / "scenes" / "toys.json"
EDIT_MODEL = "marketing-studio/image"          # the editor (docs/art/lighting_from_image.md: it keeps the frame registered, Qwen's larger edits drift)
EDIT_ARGS = dict(aspect_ratio="16:9", resolution="1k", quality="medium")
MAX_SHIFT = 2.5          # px the edit may be off the plate before it cannot be lifted from
REMOVED = 0.12           # share of a toy's box the edit must have changed for the object to count as taken away
MIN_PX = 150             # a mask smaller than this is not an object
MIN_COVER, MAX_COVER = 0.06, 3.0   # the mask's area against the box's
FILLS_WINDOW = 0.85      # a mask this much of its search window is the edit redrawing everything there, not the object
SEARCH_MARGIN = 0.12     # the box is searched this much bigger on every side (8 to 16 px): the edit also redraws what is around a removed object, so a wide
                         # window takes that in. A box is the guide's guess where the generator put the object: look at toys_preview.png and move `toy_at`
RAISED = 0.08            # m above the floor: what stands on the ground is taller than this, the gravel the edit redrew behind it is not
VOCABULARY_FILE = ROOT / "game/world/painted/painted_prop.gd"
SFX_DIR = ROOT / "assets/painted/sfx"


# ---- the toys of a layout ---------------------------------------------------------------------------------------------
def load_types():
    return json.loads(TYPES_FILE.read_text(encoding="utf-8"))["types"]


def toys_of(layout, types=None):
    """The toys a layout marks, in order: id, type, kind, noun, note (where it is, in words), box (fractions), shape, points, press, pivot."""
    types = types or load_types()
    toys, seen = [], {}
    for e in layout["elements"]:
        name = e.get("toy")
        if not name:
            continue
        if name not in types:
            raise ValueError("%s: unknown toy type %r (types: %s)" % (e["label"], name, ", ".join(sorted(types))))
        spec = types[name]
        seen[name] = seen.get(name, 0) + 1
        shape = e.get("shape", "rect")
        if e.get("toy_at"):
            box, shape, points = e["toy_at"], e.get("toy_shape", "rect"), None
        else:
            box, points = sl._bbox(e), e.get("points") if shape == "poly" else None
        if shape == "line":
            shape = "rect"
        toys.append(dict(id=name if seen[name] == 1 else "%s_%d" % (name, seen[name]), type=name, kind=spec["kind"], noun=spec.get("noun", name.replace("_", " ")),
                         box=[float(v) for v in box], shape=shape, points=points, press=json.loads(json.dumps(spec["press"])), pivot=spec.get("pivot", "base"),
                         label=e["label"], note=e.get("toy_note", "")))
    return toys


def place(box):
    """'in the lower left of the picture': where a box is, in words."""
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    h = "left" if cx < 0.36 else "right" if cx > 0.64 else "centre"
    v = "upper" if cy < 0.36 else "lower" if cy > 0.64 else "middle"
    if v == "middle":
        return "in the middle of the picture" if h == "centre" else "on the %s of the picture" % h
    return "in the %s %s of the picture" % (v, h)


def _join(items):
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def edit_prompt(toys, layout, spheres=True):
    """One positive instruction (a prompt that forbids things may make the model draw them): the cutout toys taken away and the calibration spheres painted in."""
    cut = [t for t in toys if t["kind"] == "cutout"]
    if not cut and not spheres:
        raise ValueError("nothing to edit: no cutout toys and no spheres")
    head = "The same scene from exactly the same camera position, angle and framing, with identical layout, colours and light"
    parts = []
    if cut:
        named = _join(["the %s%s %s" % (t["noun"], " " + t["note"] if t["note"] else "", place(t["box"])) for t in cut])
        head += ", with %s taken away: the ground, the plants, the walls and the sky that were behind each of them continue where it stood." % named
    else:
        head += "."
    parts.append(head)
    if spheres:
        ground = layout.get("ground")
        where = "on the open ground %s" % place(ground) if ground else "on the ground in the foreground"
        parts.append("Two large perfectly smooth, perfectly round spheres of exactly the same size rest %s, in one row with a gap between them: on the left a "
                     "matte mid-grey sphere with a chalky even surface, and on the right a mirror-polished chrome sphere that reflects its surroundings and the sky. "
                     "Each sphere is about the size of a beach ball and sits in the same light as everything else, casting a soft shadow on the ground." % where)
    return " ".join(parts)


def sphere_zone(layout):
    """Where the balls' centres may be (fractions): the guide's open ground, a little bigger (the balls stand on it and rise above it)."""
    g = layout.get("ground")
    if not g:
        return (0.2, 0.45, 0.85, 0.95)
    return (max(0.0, g[0] - 0.1), max(0.0, g[1] - 0.13), min(1.0, g[2] + 0.1), min(1.0, g[3] + 0.04))


# ---- the paid edit ------------------------------------------------------------------------------------------------------
def make_edit(plate_path, prompt, out_dir, max_usd=0.12):
    """Returns (the picture's path, the job folder). One call: the account runs two jobs at a time, so it waits for the lock."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    args_file = out_dir / "args.json"
    args_file.write_text(json.dumps(dict(EDIT_ARGS, prompt=prompt.strip()), indent=2) + "\n", encoding="utf-8")
    cmd = [sys.executable, str(ROOT / "tools/higgsfield/hf.py"), "run", EDIT_MODEL, "--args-file", str(args_file), "--upload", "image_urls=%s" % plate_path,
           "--max-usd", str(max_usd), "--out", str(out_dir)]
    print("editing the plate (%s, at most USD %.2f) ..." % (EDIT_MODEL, max_usd))
    with open(ROOT / ".hf.lock", "w") as lock:
        try:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        except ImportError:
            pass
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    (ROOT / ".hf.lock").unlink(missing_ok=True)
    m = re.search(r"^job (\S+)$", proc.stdout, re.M)
    if proc.returncode != 0 or not m:
        sys.exit("the edit failed:\n" + proc.stdout[-800:] + proc.stderr[-800:])
    job = Path(m.group(1))
    if not (job / "image_0.png").exists():
        sys.exit("the edit made no picture: %s" % job)
    return job / "image_0.png", job


def job_cost(job):
    try:
        return float(json.loads((Path(job) / "job.json").read_text(encoding="utf-8"))["estimate"]["usd"])
    except (OSError, KeyError, ValueError):
        return 0.0


# ---- registration -------------------------------------------------------------------------------------------------------
def registration(edit, plate, windows=((0.0, 0.0, 0.35, 0.4), (0.6, 0.0, 1.0, 0.4), (0.3, 0.05, 0.7, 0.35))):
    """The largest sideways or vertical shift (px) of the edit against the plate, by phase correlation in windows that mostly stayed as they were.
    None when no window correlates well enough to say."""
    a = np.asarray(plate.convert("L"), np.float32)
    b = np.asarray(edit.convert("L").resize(plate.size, Image.LANCZOS), np.float32)
    H, W = a.shape
    worst = None
    for w in windows:
        x0, y0, x1, y1 = int(w[0] * W), int(w[1] * H), int(w[2] * W), int(w[3] * H)
        A, B = a[y0:y1, x0:x1], b[y0:y1, x0:x1]
        A, B = A - A.mean(), B - B.mean()
        hann = np.outer(np.hanning(A.shape[0]), np.hanning(A.shape[1]))
        F = np.fft.fft2(A * hann) * np.conj(np.fft.fft2(B * hann))
        c = np.fft.ifft2(F / (np.abs(F) + 1e-6)).real
        iy, ix = np.unravel_index(np.argmax(c), c.shape)
        if c.max() < 0.15:
            continue
        dy, dx = (iy - A.shape[0] if iy > A.shape[0] // 2 else iy), (ix - A.shape[1] if ix > A.shape[1] // 2 else ix)
        worst = max(worst or 0.0, float(max(abs(dx), abs(dy))))
    return worst


# ---- lifting ------------------------------------------------------------------------------------------------------------
def _px(box, size):
    return [box[0] * size[0], box[1] * size[1], box[2] * size[0], box[3] * size[1]]


def polygon_px(toy, size):
    """The toy's shape in painting pixels: a polygon (the hotspot's region, or the hint the diff is searched in)."""
    x0, y0, x1, y1 = _px(toy["box"], size)
    if toy["points"]:
        return [[round(x * size[0]), round(y * size[1])] for x, y in toy["points"]]
    if toy["shape"] == "ellipse":
        cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
        return [[round(cx + rx * np.cos(t)), round(cy + ry * np.sin(t))] for t in np.linspace(0, 2 * np.pi, 20, endpoint=False)]
    return [[round(x0), round(y0)], [round(x1), round(y0)], [round(x1), round(y1)], [round(x0), round(y1)]]


def _window(toy, size):
    x0, y0, x1, y1 = _px(toy["box"], size)
    mx, my = (min(max(8.0, SEARCH_MARGIN * (x1 - x0)), 16.0), min(max(8.0, SEARCH_MARGIN * (y1 - y0)), 16.0))
    mask = np.zeros((size[1], size[0]), bool)
    mask[max(int(y0 - my), 0):min(int(y1 + my), size[1]), max(int(x0 - mx), 0):min(int(x1 + mx), size[0])] = True
    return mask


def _pick(changed, hint, window):
    """The object's pixels: what the edit changed in the window, as the components that lie mostly inside the toy's box (a neighbour's change that
    reaches into the window is not this object's)."""
    m = lp.clean(changed & window, keep=0.05)
    labels, count = ndimage.label(m)
    out = np.zeros_like(m)
    for i in range(1, count + 1):
        comp = labels == i
        inside = int((comp & hint).sum())
        if inside >= 0.5 * comp.sum() or inside >= 0.10 * hint.sum():
            out |= comp
    return ndimage.binary_dilation(out, iterations=2) if out.any() else out


def raised_map(room_dir, grow=6):
    """Pixels that rise above the floor, from the room's calibrated depth (walkable.py's lifting), grown a little: the depth is coarse at edges. The
    edit redraws the ground behind a removed object, so the picture's change alone cannot tell an object from the gravel under it; its height can."""
    room = json.loads((Path(room_dir) / "room.json").read_text(encoding="utf-8"))
    cam = walkable.Camera(room)
    points, rays = walkable.lift(room, cam)
    smooth, _ = walkable.surface_normals(points, rays)
    return ndimage.binary_dilation(smooth[..., 1] > RAISED, iterations=grow)


def _pivot(mask, how):
    ys, xs = np.nonzero(mask)
    if how == "top":
        return [int(xs.mean()), int(ys.min() + 0.08 * (ys.max() - ys.min()))]
    if how == "centre":
        return [int(xs.mean()), int(ys.mean())]
    return [int(xs.mean()), int(ys.max())]


def lift(room_dir, edit_path, toys, circles=(), scratch=None):
    """Lifts the toys into room_dir/props.json (masks, plate_empty.png). `circles`: the calibration balls (x, y, r) that must not be read as objects.
    Returns a report: one dict per toy with what it became and why."""
    room_dir = Path(room_dir)
    plate = Image.open(room_dir / "plate.png").convert("RGB")
    size = plate.size
    edit = Image.open(edit_path).convert("RGB")
    shift = registration(edit, plate)
    registered = shift is None or shift <= MAX_SHIFT
    if not registered:
        print("the edit is %.1f px off the plate (more than %.1f): its objects cannot be lifted, every toy becomes a hotspot" % (shift, MAX_SHIFT))
    without = np.asarray(edit.resize(size, Image.LANCZOS), np.float32)
    plate_a = np.asarray(plate, np.float32)
    yy, xx = np.mgrid[0:size[1], 0:size[0]]
    for cx, cy, r in circles:                                   # the balls are the edit's, not objects: show the plate there
        disc = (xx - cx) ** 2 + (yy - cy) ** 2 < (1.12 * r) ** 2
        without[disc] = plate_a[disc]
    scratch = Path(scratch) if scratch else room_dir
    scratch.mkdir(parents=True, exist_ok=True)
    clean_path = scratch / "edit_clean.png"
    Image.fromarray(np.clip(without + 0.5, 0, 255).astype(np.uint8)).save(clean_path)
    changed = lp.changed_mask(plate, Image.fromarray(np.clip(without + 0.5, 0, 255).astype(np.uint8)))
    depth_image = walkable.depth_image(json.loads((room_dir / "room.json").read_text(encoding="utf-8"))) if (room_dir / "room.json").exists() else None
    raised = raised_map(room_dir) if any(t["pivot"] == "base" and t["kind"] == "cutout" for t in toys) and (room_dir / "room.json").exists() else None
    report, entries, masks = [], [], {}
    for toy in toys:
        hint = lp.lasso_mask(size, polygons=[[tuple(p) for p in polygon_px(toy, size)]])
        result = dict(id=toy["id"], type=toy["type"], asked=toy["kind"], kind="hotspot", why="")
        entry = dict(id=toy["id"], reactions={"press": toy["press"]})
        mask = None
        if toy["kind"] == "cutout":
            if not registered:
                result["why"] = "the edit is not registered to the plate"
            elif (changed & hint).sum() < REMOVED * hint.sum():
                result["why"] = "the edit did not take it away (%.0f%% of its box changed)" % (100.0 * (changed & hint).sum() / hint.sum())
            else:
                found = changed & raised if raised is not None and toy["pivot"] == "base" else changed       # what stands on the ground rises above it
                window = _window(toy, size)
                mask = _pick(found, hint, window)
                area = int(mask.sum())
                if area < MIN_PX or area < MIN_COVER * hint.sum() or area > MAX_COVER * hint.sum():
                    result["why"] = "its changed area (%d px) does not look like the object (its box is %d px)" % (area, int(hint.sum()))
                    mask = None
                elif area > FILLS_WINDOW * window.sum():
                    result["why"] = "the edit redrew everything around it: the changed area fills its window, the object cannot be told from its surroundings"
                    mask = None
        if mask is not None:
            rect = lp.aligned_rect(mask)
            entry.update(kind="cutout", rect=rect, mask=lp.save_mask(room_dir, toy["id"], mask, rect), pivot=_pivot(mask, toy["pivot"]),
                         lift={"without": "edit", "keep_mask": True})
            if depth_image is not None:
                # the card is flat, at one depth: the engine's default (a low percentile) leaves the nearest corner of a long object, a
                # wheelbarrow, behind the room's own mesh, where its pixels would show the ground instead. The nearest pixels, bar noise, are safe.
                entry["depth"] = round(float(np.percentile(depth_image[mask], 0.5)), 3)
            changed &= ~mask
            masks[toy["id"]] = mask
            result.update(kind="cutout", rect=rect, px=int(mask.sum()))
        else:
            entry.update(kind="hotspot", polygon=polygon_px(toy, size))
        entries.append(entry)
        report.append(result)
    props_path = room_dir / "props.json"
    props = json.loads(props_path.read_text(encoding="utf-8")) if props_path.exists() else {}
    mine = {e["id"] for e in entries}
    props["props"] = [p for p in props.get("props", []) if p["id"] not in mine] + entries
    props["plate_empty"] = "plate_empty.png"
    props_path.write_text(json.dumps(props, indent=1) + "\n", encoding="utf-8")
    toybox.main(["--room", str(room_dir), "--without", "edit=%s" % clean_path])
    preview(plate, toys, entries, masks, scratch / "toys_preview.png")
    return report


def preview(plate, toys, entries, masks, path):
    """The plate with every toy's box (cyan: cutout, magenta: hotspot) and what became of it (a red tint over a cutout's mask): to see at once
    which box sits off its object, or which object the edit left alone."""
    from PIL import ImageDraw
    a = np.asarray(plate, np.float32).copy()
    for mask in masks.values():
        a[mask] = a[mask] * 0.5 + np.array([255.0, 40.0, 40.0]) * 0.5
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(out)
    for t, e in zip(toys, entries):
        points = polygon_px(t, plate.size)
        d.polygon([tuple(p) for p in points], outline=(0, 255, 255) if e["kind"] == "cutout" else (255, 80, 255))
        d.text((points[0][0] + 3, points[0][1] + 3), "%s (%s)" % (t["id"], e["kind"]), fill=(255, 255, 0))
    out.save(path)


# ---- checks -------------------------------------------------------------------------------------------------------------
def vocabulary():
    text = VOCABULARY_FILE.read_text(encoding="utf-8")
    block = re.search(r"const VOCABULARY := \{(.*?)\}", text, re.S).group(1)
    return set(re.findall(r'"(\w+)":', block))


def check(room_dir):
    """The toy box's invariants (the same ones tests/render/test_painted_toybox.gd runs in the engine): a list of problems, empty when sound."""
    room_dir = Path(room_dir)
    problems = []
    path = room_dir / "props.json"
    if not path.exists():
        return ["no props.json"]
    data = json.loads(path.read_text(encoding="utf-8"))
    words, sounds = vocabulary(), {p.stem for p in SFX_DIR.glob("*.wav")}
    plate = np.asarray(Image.open(room_dir / "plate.png").convert("RGB"), np.int16)
    empty = np.asarray(Image.open(room_dir / data["plate_empty"]).convert("RGB"), np.int16)
    inside = np.zeros(plate.shape[:2], bool)
    ids = [p["id"] for p in data["props"]]
    if len(ids) != len(set(ids)):
        problems.append("an id is listed twice")
    for p in data["props"]:
        if not p.get("reactions", {}).get("press"):
            problems.append("%s: no press reactions" % p["id"])
        for r in p.get("reactions", {}).get("press", []):
            if r.get("do") not in words:
                problems.append("%s: unknown reaction %r" % (p["id"], r.get("do")))
            if r.get("sound") and r["sound"] not in sounds:
                problems.append("%s: unknown sound %r" % (p["id"], r["sound"]))
        if p["kind"] == "hotspot":
            if len(p.get("polygon", [])) < 3:
                problems.append("%s: a hotspot needs a polygon" % p["id"])
            continue
        x, y, w, h = p["rect"]
        if (x % 8, y % 8, w % 8, h % 8) != (0, 0, 0, 0):
            problems.append("%s: the card is off the mesh grid" % p["id"])
        mask_file = room_dir / p["mask"]
        if not mask_file.exists():
            problems.append("%s: the mask file is missing" % p["id"])
            continue
        mask = np.asarray(Image.open(mask_file).convert("L")) > 127
        if mask.shape != (h, w):
            problems.append("%s: the mask is %s, its rect %dx%d" % (p["id"], mask.shape, w, h))
            continue
        inside[y:y + h, x:x + w] |= mask
    outside = ~inside
    differing = int((np.abs(empty - plate).max(axis=2)[outside] > 0).sum())
    if differing:
        problems.append("plate_empty differs from the plate outside the masks in %d px" % differing)
    return problems


# ---- the whole step -----------------------------------------------------------------------------------------------------
def run(room_dir, scratch, layout, spheres=True, max_usd=0.12, edit=None):
    """The edit (paid unless `edit` is a picture you made), the lighting measured from its balls, the toys lifted. Returns
    {"edit", "cost", "measured" (None without spheres), "circles", "toys"}, or None when the layout marks no toys and no spheres are wanted."""
    room_dir, scratch = Path(room_dir), Path(scratch)
    toys = toys_of(layout)
    cutouts = [t for t in toys if t["kind"] == "cutout"]
    if not toys and not spheres:
        return None
    if not cutouts and not spheres:                              # hotspots only: nothing to take away, nothing to pay for
        report = lift(room_dir, room_dir / "plate.png", toys, scratch=scratch)
        return dict(edit=None, cost=0.0, measured=None, circles=[], toys=report)
    cost = 0.0
    if edit is None:
        edit, job = make_edit(room_dir / "plate.png", edit_prompt(toys, layout, spheres), scratch, max_usd)
        cost = job_cost(job)
        shutil.copy(job / "job.json", room_dir / "job_toys.json")
    measured, circles = None, []
    if spheres:
        measured = sphere_probe.measure_auto(edit, room_dir / "plate.png", zone=sphere_zone(layout))
        circles = [tuple(measured[k]) for k in ("grey_circle", "chrome_circle") if k in measured]
        print("spheres: %s" % ("measured, trusted" if measured.get("ok") else "not trusted (%s)" % measured.get("why")))
    report = lift(room_dir, edit, toys, circles, scratch) if toys else []
    problems = check(room_dir) if toys else []
    for line in report:
        print("toy %-14s %-8s%s" % (line["id"], line["kind"], "" if line["kind"] == line["asked"] else "  (asked %s: %s)" % (line["asked"], line["why"])))
    if problems:
        print("toy box problems:\n  " + "\n  ".join(problems))
    return dict(edit=str(edit), cost=cost, measured=measured, circles=circles, toys=report, problems=problems)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prompt"); p.add_argument("brief"); p.add_argument("--no-spheres", action="store_true")
    b = sub.add_parser("build"); b.add_argument("room"); b.add_argument("--brief"); b.add_argument("--image", help="a picture made by this edit already (free)")
    b.add_argument("--no-spheres", action="store_true"); b.add_argument("--max-usd", type=float, default=0.12)
    c = sub.add_parser("check"); c.add_argument("room")
    args = ap.parse_args(argv)

    if args.cmd == "prompt":
        brief = json.loads((HERE / "scenes" / ("%s.json" % args.brief)).read_text(encoding="utf-8"))
        layout = sl.with_defaults(brief["layout"])
        toys = toys_of(layout)
        for t in toys:
            print("%-14s %-8s %s" % (t["id"], t["kind"], t["label"]))
        print()
        print(edit_prompt(toys, layout, not args.no_spheres))
        return 0
    if args.cmd == "check":
        problems = check(args.room)
        print("\n".join(problems) if problems else "the toy box is sound")
        return 1 if problems else 0
    room = Path(args.room)
    brief_path = HERE / "scenes" / ("%s.json" % args.brief) if args.brief else room / "brief.json"
    brief = json.loads(brief_path.read_text(encoding="utf-8"))
    layout = sl.with_defaults(brief["layout"])
    out = run(room, ROOT / "build/rooms" / room.name / "toys", layout, spheres=not args.no_spheres, max_usd=args.max_usd, edit=args.image)
    if out is None:
        print("the layout marks no toys")
    else:
        print("edit cost about USD %.3f" % out["cost"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
