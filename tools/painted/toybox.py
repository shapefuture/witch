#!/usr/bin/env python3
"""Rebuilds a painted room's toy box from props.json: every mask, every card rect and plate_empty.png.

    python tools/painted/toybox.py --room assets/painted/hall_clean \
        --without gs=build/higgsfield/<job>/image_0.png --without a=... --without b=... --without c=... \
        [--preview out_dir]

props.json is the single source. A prop may carry a "lift" block that says where its pixels come from:

  cutout   "lift": {"without": "a", "ellipses": [[cx, cy, rx, ry]], "polygons": [[[x, y], ...]],
                    "refine": true, "grow": 2, "search": [x, y, w, h]}
           `without` names an image edit of the plate with the object removed (--without NAME=PATH); the lasso
           (hand-drawn, painting pixels) says what to cut and `refine` keeps only what the edit also changed.
           {"without": "a", "keep_mask": true} keeps the prop's existing mask file and only refreshes the fill.
  hotspot  "polygon": [[x, y], ...]   (no moving part: the tool writes the soft-edged mask its ripple card uses)

Everything is computed from plate.png and the edits, in props.json order, so rerunning gives the same files;
outside every cutout's mask plate_empty.png is the plate bit for bit (the room at rest is the painting).
The cards' rects are aligned outward to the 8 px grid of the room mesh (see lift_prop.py).
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lift_prop as lp  # noqa: E402


def lasso_of(plate_size, lift, polygon=None):
    ellipses = [tuple(float(v) for v in e) for e in lift.get("ellipses", [])]
    polygons = [[tuple(float(v) for v in p) for p in poly] for poly in lift.get("polygons", [])]
    if polygon:
        polygons.append([tuple(float(v) for v in p) for p in polygon])
    if not ellipses and not polygons:
        return None
    return lp.lasso_mask(plate_size, ellipses, polygons)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--room", required=True)
    parser.add_argument("--without", action="append", default=[], metavar="NAME=PATH")
    parser.add_argument("--preview", help="write overlay images of every mask here")
    args = parser.parse_args(argv)

    room = Path(args.room)
    plate = Image.open(room / "plate.png").convert("RGB")
    plate_a = np.asarray(plate, np.float32)
    empty = plate_a.copy()
    withouts = {}
    for spec in args.without:
        name, _, path = spec.partition("=")
        withouts[name] = np.asarray(lp.load_without(path, plate.size), np.float32)
    props_path = room / "props.json"
    props = json.loads(props_path.read_text(encoding="utf-8"))
    masks = {}

    for entry in props["props"]:
        pid, lift = entry["id"], entry.get("lift")
        if entry.get("kind") == "hotspot":
            mask = lasso_of(plate.size, {}, entry["polygon"])
            rect = lp.aligned_rect(mask, pad=12)
            entry["rect"] = rect
            entry["mask"] = lp.save_mask(room, pid, mask, rect, soft=True)
            masks[pid] = mask
            print("hotspot %-12s rect %s" % (pid, rect))
            continue
        if lift is None:
            print("cutout  %-12s no lift block, left as it is" % pid)
            continue
        fill = withouts.get(lift["without"])
        if fill is None:
            raise SystemExit("%s: no --without %s given" % (pid, lift["without"]))
        if lift.get("keep_mask"):
            x, y, w, h = entry["rect"]
            small = np.asarray(Image.open(room / entry["mask"]).convert("L")) > 127
            mask = np.zeros(plate_a.shape[:2], bool)
            mask[y:y + h, x:x + w] = small
        else:
            search = lift.get("search") or [0, 0, plate.width, plate.height]
            mask = lp.object_mask(plate, Image.fromarray(fill.astype(np.uint8)), search, lasso_of(plate.size, lift),
                                  lift.get("refine", False), lift.get("grow", 2))
        rect = lp.aligned_rect(mask)
        entry["rect"] = rect
        entry["mask"] = lp.save_mask(room, pid, mask, rect)
        if "pivot" not in entry:
            ys, xs = np.nonzero(mask)
            entry["pivot"] = [int(xs.mean()), int(ys.max())]
        lp.paste_fill(empty, plate_a, fill, mask)
        masks[pid] = mask
        print("cutout  %-12s rect %s  %d px  pivot %s" % (pid, rect, int(mask.sum()), entry["pivot"]))

    props["plate_empty"] = "plate_empty.png"
    Image.fromarray(np.clip(empty + 0.5, 0, 255).astype(np.uint8)).save(room / "plate_empty.png")
    props_path.write_text(json.dumps(props, indent=1) + "\n", encoding="utf-8")

    if args.preview:
        out = Path(args.preview)
        out.mkdir(parents=True, exist_ok=True)
        overlay = plate.copy()
        draw = ImageDraw.Draw(overlay)
        for entry in props["props"]:
            x, y, w, h = entry["rect"]
            draw.rectangle((x, y, x + w, y + h), outline=(0, 255, 255) if entry["kind"] == "cutout" else (255, 120, 255))
            draw.text((x + 2, y + 2), entry["id"], fill=(255, 255, 0))
        overlay.save(out / "rects.png")
        shade = plate_a.copy()
        for pid, mask in masks.items():
            shade[mask] = shade[mask] * 0.45 + np.array([255, 40, 40]) * 0.55
        Image.fromarray(shade.astype(np.uint8)).save(out / "masks.png")
        changed = np.abs(empty - plate_a).mean(axis=2)
        Image.fromarray(np.clip(changed * 4, 0, 255).astype(np.uint8)).save(out / "plate_empty_diff.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
