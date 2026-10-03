#!/usr/bin/env python3
"""Lifts an object out of a painted room so it can move and answer a tap (game/world/painted/painted_prop.gd).

    python tools/painted/lift_prop.py --room assets/painted/hall_clean --without without_globe.png \
        --id globe --rect 0,295,200,285 --pivot 95,575 --reactions press=wobble,hop,spin

--without is the same painting with the object removed (an image edit: "remove the globe, continue the shelf
behind it"). Inside --rect, the pixels that changed are the object: they become <id>_mask.png, and the edited
pixels under them go into plate_empty.png (the painting the room shows behind its props; cumulative across
props). Outside the mask nothing of the edit is used, so at rest the painting is EXACTLY the plate: the card
shows the object where the mask is, the room shows the plate everywhere else.
When the object can't be told from what replaced it, draw it instead: --ellipse / --polygon (painting pixels);
add --refine to keep only what the edit also changed inside that lasso. The card's rect is aligned outward to
the 8 px grid of the room mesh, so its corners sit on mesh vertices and the PSX vertex snap treats card and
painting alike. The prop is added to (or replaced in) props.json with its rect, mask, pivot and reactions.

Many props at once, from the "lift" blocks of props.json: tools/painted/toybox.py (it uses this module).
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

THRESHOLD = 0.07     # mean absolute RGB change (0..1) that counts as "the object was here"
GRID = 8             # the room mesh's vertex spacing in painting pixels (room.json grid_step)
FEATHER = 3          # px inside the mask over which the edit's fill fades into the plate
TONE_SIGMA = 14.0    # px: scale of the colour correction that makes the fill match the plate around the hole


def parse_ints(text, n):
    values = [int(v) for v in text.split(",")]
    if len(values) != n:
        raise SystemExit("expected %d comma-separated numbers, got %r" % (n, text))
    return values


def lasso_mask(size, ellipses=(), polygons=()):
    """Full-frame boolean mask of hand-drawn shapes (painting pixels). An ellipse is (cx, cy, rx, ry),
    a polygon a list of (x, y)."""
    canvas = Image.new("L", size, 0)
    draw = ImageDraw.Draw(canvas)
    for cx, cy, rx, ry in ellipses:
        draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    for points in polygons:
        draw.polygon([(float(x), float(y)) for x, y in points], fill=255)
    return np.asarray(canvas) > 127


def changed_mask(plate, without, threshold=THRESHOLD, sigma=1.5):
    """Full-frame boolean mask of where the edit changed the painting."""
    a = np.asarray(plate, np.float32) / 255.0
    b = np.asarray(without, np.float32) / 255.0
    diff = ndimage.gaussian_filter(np.abs(a - b).mean(axis=2), sigma)
    return diff > threshold


def clean(mask, keep=0.15):
    """Close small gaps, drop specks and fill holes; keep the components at least `keep` of the biggest."""
    pad = 6   # morphology treats the frame's edge as empty, which would eat a mask that touches it
    mask = np.pad(mask, pad, mode="edge")
    mask = ndimage.binary_closing(mask, iterations=3)
    mask = ndimage.binary_opening(mask, iterations=1)
    mask = mask[pad:-pad, pad:-pad]
    labels, count = ndimage.label(mask)
    if count == 0:
        return mask
    sizes = np.asarray(ndimage.sum(mask, labels, range(1, count + 1)))
    wanted = [i + 1 for i, s in enumerate(sizes) if s >= keep * sizes.max()]
    return ndimage.binary_fill_holes(np.isin(labels, wanted))


def object_mask(plate, without, rect, lasso=None, refine=False, grow=2, threshold=THRESHOLD):
    """The object's mask, full-frame. Without a lasso: what the edit changed inside rect. With a lasso: the
    lasso itself, or (refine) what the edit changed inside it."""
    x, y, w, h = rect
    if lasso is not None and not refine:
        mask = lasso.copy()
    else:
        changed = changed_mask(plate, without, threshold)
        window = np.zeros_like(changed)
        window[y:y + h, x:x + w] = True
        if lasso is not None:
            window &= lasso
        mask = clean(changed & window)
        if lasso is not None:
            mask &= ndimage.binary_dilation(lasso, iterations=grow)
    if not mask.any():
        raise SystemExit("nothing changed inside the region: is --without the same painting minus the object?")
    return ndimage.binary_dilation(mask, iterations=grow) if grow else mask


def aligned_rect(mask, grid=GRID, pad=1):
    """The mask's bounding box, grown by pad and then outward to the room mesh's grid: (x, y, w, h)."""
    ys, xs = np.nonzero(mask)
    h, w = mask.shape
    x0 = max(0, (int(xs.min()) - pad) // grid * grid)
    y0 = max(0, (int(ys.min()) - pad) // grid * grid)
    x1 = min(w, -(-(int(xs.max()) + 1 + pad) // grid) * grid)
    y1 = min(h, -(-(int(ys.max()) + 1 + pad) // grid) * grid)
    return [x0, y0, x1 - x0, y1 - y0]


def soft_mask(mask, blur=3.0):
    """A hotspot overlay mask: the polygon with soft edges (0..255), wide enough for a ripple to fade out."""
    return (np.clip(ndimage.gaussian_filter(mask.astype(np.float32), blur), 0.0, 1.0) * 255).astype(np.uint8)


def paste_fill(empty, plate, fill, mask, feather=FEATHER, tone_sigma=TONE_SIGMA):
    """Writes the edit's fill into `empty` (float array, modified in place) under `mask`. The fill is first
    corrected towards the plate's colours in the ring around the hole, then faded in over `feather` px, so the
    hole's rim is the plate's own pixels and no seam shows when the object moves. Outside the mask `empty`
    stays the plate, bit for bit."""
    ring = ndimage.binary_dilation(mask, iterations=16) & ~ndimage.binary_dilation(mask, iterations=3)
    corrected = fill.copy()
    if ring.any() and tone_sigma > 0:
        weight = ndimage.gaussian_filter(ring.astype(np.float32), tone_sigma)
        for c in range(3):
            delta = ndimage.gaussian_filter(((plate[..., c] - fill[..., c]) * ring).astype(np.float32), tone_sigma)
            corrected[..., c] = fill[..., c] + delta / np.maximum(weight, 1e-4)
    alpha = (np.clip(ndimage.distance_transform_edt(mask) / max(feather, 1), 0.0, 1.0) * mask)[..., None]
    empty[...] = empty * (1.0 - alpha) + np.clip(corrected, 0, 255) * alpha


def load_without(path, size):
    return Image.open(path).convert("RGB").resize(size, Image.LANCZOS)


def save_mask(room, prop_id, mask, rect, soft=False):
    x, y, w, h = rect
    crop = mask[y:y + h, x:x + w]
    data = soft_mask(crop) if soft else (crop * 255).astype(np.uint8)
    name = "%s_mask.png" % prop_id
    Image.fromarray(data).save(room / name)
    return name


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--room", required=True)
    parser.add_argument("--without", required=True)
    parser.add_argument("--id", required=True)
    parser.add_argument("--rect", required=True, help="x,y,w,h in the room's 1280x720 frame: where to look for the object")
    parser.add_argument("--pivot", help="x,y: the point it turns and hops about (its base); default the mask's bottom centre")
    parser.add_argument("--reactions", action="append", default=[], metavar="TRIGGER=a,b,c")
    parser.add_argument("--ellipse", action="append", default=[], metavar="CX,CY,RX,RY",
                        help="hand lasso (repeatable, with --polygon): used instead of the diff")
    parser.add_argument("--polygon", action="append", default=[], metavar="'X,Y X,Y ...'")
    parser.add_argument("--refine", action="store_true", help="keep only what the edit changed inside the lasso")
    parser.add_argument("--grow", type=int, default=2, help="px the mask is dilated by, so no rim of the object stays behind")
    args = parser.parse_args(argv)

    room = Path(args.room)
    plate = Image.open(room / "plate.png").convert("RGB")
    without = load_without(args.without, plate.size)
    rect = parse_ints(args.rect, 4)
    lasso = None
    if args.ellipse or args.polygon:
        ellipses = [tuple(float(v) for v in spec.split(",")) for spec in args.ellipse]
        polygons = [[tuple(float(v) for v in pair.split(",")) for pair in spec.split()] for spec in args.polygon]
        lasso = lasso_mask(plate.size, ellipses, polygons)
    mask = object_mask(plate, without, rect, lasso, args.refine, args.grow)
    box = aligned_rect(mask)
    mask_name = save_mask(room, args.id, mask, box)

    empty_path = room / "plate_empty.png"
    plate_a = np.asarray(plate, np.float32)
    empty = np.asarray(Image.open(empty_path).convert("RGB"), np.float32) if empty_path.exists() else plate_a.copy()
    paste_fill(empty, plate_a, np.asarray(without, np.float32), mask)
    Image.fromarray(np.clip(empty + 0.5, 0, 255).astype(np.uint8)).save(empty_path)

    ys, xs = np.nonzero(mask)
    pivot = parse_ints(args.pivot, 2) if args.pivot else [int(xs.mean()), int(ys.max())]
    reactions = {}
    for spec in args.reactions or ["press=wobble"]:
        trigger, _, names = spec.partition("=")
        reactions[trigger] = [n for n in names.split(",") if n]

    props_path = room / "props.json"
    props = json.loads(props_path.read_text(encoding="utf-8")) if props_path.exists() else {}
    props["plate_empty"] = "plate_empty.png"
    entries = [p for p in props.get("props", []) if p.get("id") != args.id]
    entries.append({"id": args.id, "kind": "cutout", "rect": box, "mask": mask_name,
                    "pivot": pivot, "reactions": reactions})
    props["props"] = entries
    props_path.write_text(json.dumps(props, indent=1) + "\n", encoding="utf-8")
    print("lifted %s: %d px, rect %s, pivot %s, reactions %s" % (args.id, int(mask.sum()), box, pivot, reactions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
