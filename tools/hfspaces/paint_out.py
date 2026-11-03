#!/usr/bin/env python3
"""Paints a polygon out of a picture: a local, free fix for something a generator drew where the brief has none.

The pixels inside the polygon become the average of their neighbours over many passes (a harmonic fill), so the surroundings'
own gradient runs across the gap; a little noise is added, and the edge is feathered. Everything outside is untouched.

    python tools/hfspaces/paint_out.py IN.png OUT.png --polygon "52,528 150,482 300,478 ..." [--passes 900] [--pad 16] [--seed 7]

Writes OUT.png and OUT.png.json (the polygon, the box, the passes, the input's and the output's hashes).
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def parse_polygon(text):
    points = [tuple(int(v) for v in pair.split(",")) for pair in text.split()]
    if len(points) < 3:
        raise argparse.ArgumentTypeError("a polygon needs three points: x,y x,y x,y ...")
    return points


def paint_out(src, dst, polygon, passes=900, pad=16, seed=7):
    img = Image.open(src).convert("RGB")
    arr = np.asarray(img, np.float32)
    h, w = arr.shape[:2]
    mask_img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask_img).polygon(polygon, fill=255)
    mask = np.asarray(mask_img) > 127
    if not mask.any():
        raise SystemExit("the polygon covers no pixel of %s" % src)
    ys, xs = np.where(mask)
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, w)
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, h)
    crop = arr[y0:y1, x0:x1].copy()
    inside = mask[y0:y1, x0:x1]
    crop[inside] = np.median(crop[~inside], axis=0)              # a start near the surroundings' colour
    for _ in range(passes):                                      # each masked pixel: the mean of its four neighbours
        p = np.pad(crop, ((1, 1), (1, 1), (0, 0)), mode="edge")
        avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4.0
        crop[inside] = avg[inside]
    rng = np.random.default_rng(seed)
    crop[inside] = np.clip(crop[inside] + rng.normal(0.0, 1.5, size=(int(inside.sum()), 3)), 0, 255)
    filled = arr.copy()
    filled[y0:y1, x0:x1] = crop
    alpha = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), np.float32)[..., None] / 255.0
    out = arr * (1.0 - alpha) + filled * alpha
    Image.fromarray(np.round(out).astype(np.uint8)).save(dst)
    record = {"tool": "tools/hfspaces/paint_out.py", "source": str(src), "source_sha256": sha256_file(src),
              "polygon": [list(p) for p in polygon], "box": [int(x0), int(y0), int(x1), int(y1)], "passes": passes, "pad": pad,
              "seed": seed, "pixels": int(mask.sum()), "out_sha256": sha256_file(dst)}
    Path(str(dst) + ".json").write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8")
    return record


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--polygon", type=parse_polygon, required=True, help='"x,y x,y x,y ..." in the picture\'s pixels')
    ap.add_argument("--passes", type=int, default=900)
    ap.add_argument("--pad", type=int, default=16)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args(argv)
    record = paint_out(args.src, args.dst, args.polygon, passes=args.passes, pad=args.pad, seed=args.seed)
    print("wrote %s: %d pixels painted out" % (args.dst, record["pixels"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
