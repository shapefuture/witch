#!/usr/bin/env python3
"""Lifts an object out of a painted room so it can move and answer a tap (game/world/painted/painted_prop.gd).

    python tools/painted/lift_prop.py --room assets/painted/hall_clean --without without_globe.png \
        --id globe --rect 0,295,200,285 --pivot 95,575 --reactions press=wobble,hop,spin

--without is the same painting with the object removed (an image edit: "remove the globe, continue the shelf
behind it"). Inside --rect, the pixels that changed are the object: they become <id>_mask.png, and the edited
pixels under them go into plate_empty.png (the painting the room shows behind its props; cumulative across
props). Outside the rect nothing of the edit is used, so the rest of the painting stays exact.
When the object can't be told from what replaced it, draw it instead: --ellipse / --polygon (painting pixels).
The prop is added to (or replaced in) props.json with its rect, mask, pivot and reactions.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

THRESHOLD = 0.07     # mean absolute RGB change (0..1) that counts as "the object was here"


def parse_ints(text, n):
    values = [int(v) for v in text.split(",")]
    if len(values) != n:
        raise SystemExit("expected %d comma-separated numbers, got %r" % (n, text))
    return values


def object_mask(plate, without, rect):
    x, y, w, h = rect
    a = np.asarray(plate.crop((x, y, x + w, y + h)), np.float32) / 255.0
    b = np.asarray(without.crop((x, y, x + w, y + h)), np.float32) / 255.0
    diff = np.abs(a - b).mean(axis=2)
    diff = ndimage.gaussian_filter(diff, 1.5)
    mask = diff > THRESHOLD
    mask = ndimage.binary_closing(mask, iterations=4)
    mask = ndimage.binary_opening(mask, iterations=2)
    labels, count = ndimage.label(mask)
    if count == 0:
        raise SystemExit("nothing changed inside the rect: is --without the same painting minus the object?")
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    mask = labels == (int(np.argmax(sizes)) + 1)
    mask = ndimage.binary_fill_holes(mask)
    return ndimage.binary_dilation(mask, iterations=2)


def hint_mask(rect, ellipses, polygons):
    """A lasso drawn by hand (painting pixels), for objects the diff can't separate from what replaced them
    (a dark globe in front of a dark shelf that the edit also redrew)."""
    x, y, w, h = rect
    canvas = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(canvas)
    for spec in ellipses:
        cx, cy, rx, ry = (float(v) for v in spec.split(","))
        draw.ellipse((cx - rx - x, cy - ry - y, cx + rx - x, cy + ry - y), fill=255)
    for spec in polygons:
        points = [tuple(float(v) for v in pair.split(",")) for pair in spec.split()]
        draw.polygon([(px - x, py - y) for px, py in points], fill=255)
    return np.asarray(canvas) > 127


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--room", required=True)
    parser.add_argument("--without", required=True)
    parser.add_argument("--id", required=True)
    parser.add_argument("--rect", required=True, help="x,y,w,h in the room's 1280x720 frame")
    parser.add_argument("--pivot", help="x,y: the point it turns and hops about (its base); default the rect's bottom centre")
    parser.add_argument("--reactions", action="append", default=[], metavar="TRIGGER=a,b,c")
    parser.add_argument("--ellipse", action="append", default=[], metavar="CX,CY,RX,RY",
                        help="hand lasso (repeatable, with --polygon): used instead of the diff")
    parser.add_argument("--polygon", action="append", default=[], metavar="'X,Y X,Y ...'")
    args = parser.parse_args(argv)

    room = Path(args.room)
    plate = Image.open(room / "plate.png").convert("RGB")
    without = Image.open(args.without).convert("RGB").resize(plate.size, Image.LANCZOS)
    rect = parse_ints(args.rect, 4)
    x, y, w, h = rect
    if args.ellipse or args.polygon:
        mask = hint_mask(rect, args.ellipse, args.polygon)
    else:
        mask = object_mask(plate, without, rect)

    Image.fromarray((mask * 255).astype(np.uint8)).save(room / ("%s_mask.png" % args.id))
    empty_path = room / "plate_empty.png"
    empty = Image.open(empty_path).convert("RGB") if empty_path.exists() else plate.copy()
    # The behind-pixels reach a little past the mask, feathered, so no rim of the object shows when it moves.
    reach = ndimage.binary_dilation(mask, iterations=6)
    alpha = Image.fromarray((reach * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    empty.paste(without.crop((x, y, x + w, y + h)), (x, y), alpha)
    empty.save(empty_path)

    ys, xs = np.nonzero(mask)
    pivot = parse_ints(args.pivot, 2) if args.pivot else [int(x + xs.mean()), int(y + ys.max())]
    reactions = {}
    for spec in args.reactions or ["press=wobble"]:
        trigger, _, names = spec.partition("=")
        reactions[trigger] = [n for n in names.split(",") if n]

    props_path = room / "props.json"
    props = json.loads(props_path.read_text(encoding="utf-8")) if props_path.exists() else {}
    props["plate_empty"] = "plate_empty.png"
    entries = [p for p in props.get("props", []) if p.get("id") != args.id]
    entries.append({"id": args.id, "kind": "cutout", "rect": rect, "mask": "%s_mask.png" % args.id,
                    "pivot": pivot, "reactions": reactions})
    props["props"] = entries
    props_path.write_text(json.dumps(props, indent=1) + "\n", encoding="utf-8")
    print("lifted %s: %d px, pivot %s, reactions %s" % (args.id, int(mask.sum()), pivot, reactions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
