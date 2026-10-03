#!/usr/bin/env python3
"""Region-by-region numbers for a frame (and the reference), at fixed places of a 16:9 picture.

    python tools/visual_gauntlet/regions.py REF.png OURS.png [--json out.json] [--overlay out.png]
    python tools/visual_gauntlet/regions.py FRAME.png              # one image
    python tools/visual_gauntlet/regions.py --selftest

The five regions were read off the reference's composition (normalised x0, y0, x1, y1 of the
16:9 frame; `--overlay` draws them). They are fixed places, not detected objects: the question is
"is OUR picture dark/bright/busy where the reference is?", so a statue standing elsewhere shows up.

  statue        the hooded figure right of centre, hood to plinth
  beam          the god-ray, stair-stepped from the oculus down past the statue to the pool of
                light on the carpet where the characters stand
  arch_passage  the pointed arch left of centre and the corridor and steps seen through it
  shelves       the two tall shelf walls, left and right, inside the outer ring
  frame         the outer ring: 6% of the width at the sides, 8% of the height at the top, 10% at
                the bottom (the dark foreground masses and the vault)

Earlier regions win where rects overlap, so every pixel belongs to at most one region (the oculus
counts as beam, not frame); the rest of the picture (the central bookcase, the vault wall, the
floor) belongs to none.

Both images are centre-cropped to 16:9 and resampled to 640x360 first (the size BAR.md measured at),
so resolution cannot move edge density or facet gradient. Per region:
  median_luma, p99      Rec.709 luma of display values (as metrics.py)
  saturation            mean HSV saturation of pixels brighter than 0.1 (as metrics.py)
  contrast              p95 - p5 of luma: the range most of the region spans
  edge_density          share of pixels on a Canny edge (sigma 1, fixed thresholds)
  facet_gradient        mean (|dx| + |dy|) / 2 * 100 of luma (metrics.py's facet_gradient)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from skimage import feature

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import metrics  # noqa: E402

SIZE = (640, 360)
ASPECT = 16 / 9
CANNY = {"sigma": 1.0, "low_threshold": 0.06, "high_threshold": 0.15}
STATS = ("median_luma", "p99", "saturation", "contrast", "edge_density", "facet_gradient")

# priority order: an earlier region keeps the pixels where it overlaps a later one
REGIONS = (
    ("statue", ((0.625, 0.37, 0.715, 0.80),)),
    ("beam", (
        (0.655, 0.03, 0.720, 0.12),   # the oculus and the mouth of the ray
        (0.615, 0.12, 0.705, 0.24),
        (0.585, 0.24, 0.680, 0.37),   # past the statue's crown
        (0.560, 0.37, 0.625, 0.78),   # the lit haze beside the statue
        (0.450, 0.78, 0.680, 0.90),   # the pool on the carpet
    )),
    ("arch_passage", ((0.245, 0.29, 0.445, 0.78),)),
    ("shelves", ((0.06, 0.08, 0.21, 0.76), (0.735, 0.08, 0.94, 0.78))),
    ("frame", ((0.0, 0.0, 1.0, 0.08), (0.0, 0.90, 1.0, 1.0), (0.0, 0.08, 0.06, 0.90), (0.94, 0.08, 1.0, 0.90))),
)
NAMES = tuple(name for name, _ in REGIONS)


def masks(w=SIZE[0], h=SIZE[1]):
    taken = np.zeros((h, w), dtype=bool)
    out = {}
    for name, rects in REGIONS:
        m = np.zeros((h, w), dtype=bool)
        for x0, y0, x1, y1 in rects:
            m[int(round(y0 * h)):int(round(y1 * h)), int(round(x0 * w)):int(round(x1 * w))] = True
        out[name] = m & ~taken
        taken |= m
    return out


def prepare(src):
    """Centre-crop to 16:9 and resample to 640x360, as float RGB."""
    a = metrics.rgb(src)
    h, w = a.shape[:2]
    if abs(w / h - ASPECT) > 1e-3:
        if w / h > ASPECT:
            cw = int(round(h * ASPECT))
            a = a[:, (w - cw) // 2:(w - cw) // 2 + cw]
        else:
            ch = int(round(w / ASPECT))
            a = a[(h - ch) // 2:(h - ch) // 2 + ch]
    if a.shape[1::-1] != SIZE:
        img = Image.fromarray(np.round(a * 255).astype(np.uint8)).resize(SIZE, Image.LANCZOS)
        a = np.asarray(img, dtype=np.float32) / 255.0
    return a


def measure(src):
    a = prepare(src)
    lum = metrics.luma(a)
    sat, _, mx = metrics.sat_hue(a)
    edges = feature.canny(lum.astype(np.float64), **CANNY)
    grad = metrics.gradient_map(lum)
    out = {}
    for name, m in masks(a.shape[1], a.shape[0]).items():
        v = lum[m]
        p5, p50, p95, p99 = np.percentile(v, [5, 50, 95, 99])
        bright = m & (mx > 0.1)
        out[name] = {
            "median_luma": round(float(p50), 3),
            "p99": round(float(p99), 3),
            "saturation": round(float(sat[bright].mean()), 3) if bright.any() else None,
            "contrast": round(float(p95 - p5), 3),
            "edge_density": round(float(edges[m].mean()), 3),
            "facet_gradient": round(float(grad[m].mean()), 2),
        }
    return out


def compare(ref, ours):
    r, o = measure(ref), measure(ours)
    delta = {n: {k: (None if r[n][k] is None or o[n][k] is None else round(o[n][k] - r[n][k], 3)) for k in STATS} for n in NAMES}
    return {"ref": r, "ours": o, "delta_ours_minus_ref": delta}


def table(result):
    head = "%-13s %-5s" % ("region", "") + "".join("%15s" % k for k in STATS)
    lines = [head, "-" * len(head)]
    rows = [("ref", result["ref"]), ("ours", result["ours"]), ("delta", result["delta_ours_minus_ref"])] if "ours" in result else [("", result["image"])]
    for name in NAMES:
        for i, (label, data) in enumerate(rows):
            cells = "".join("%15s" % ("-" if data[name][k] is None else ("%+.3f" % data[name][k] if label == "delta" else "%.3f" % data[name][k])) for k in STATS)
            lines.append("%-13s %-5s%s" % (name if i == 0 else "", label, cells))
    return "\n".join(lines)


def overlay(paths, out):
    """The regions drawn over each image, side by side (to check the rects by eye)."""
    colours = {"statue": (255, 60, 60), "beam": (255, 220, 0), "arch_passage": (0, 200, 255), "shelves": (60, 255, 90), "frame": (200, 80, 255)}
    tiles = []
    ms = masks()
    for p in paths:
        a = prepare(p)
        for name, m in ms.items():
            a[m] = a[m] * 0.55 + np.array(colours[name]) / 255.0 * 0.45
        img = Image.fromarray(np.round(a * 255).astype(np.uint8))
        d = ImageDraw.Draw(img)
        for name, rects in REGIONS:
            x0, y0 = rects[0][0] * SIZE[0], rects[0][1] * SIZE[1]
            d.text((x0 + 4, y0 + 3), name, fill=(0, 0, 0))
            d.text((x0 + 3, y0 + 2), name, fill=(255, 255, 255))
        tiles.append(img)
    canvas = Image.new("RGB", (SIZE[0] * len(tiles), SIZE[1]))
    for i, t in enumerate(tiles):
        canvas.paste(t, (SIZE[0] * i, 0))
    canvas.save(out)


def selftest():
    ms = masks()
    total = np.zeros(SIZE[::-1], dtype=int)
    for name, m in ms.items():
        assert m.mean() > 0.01, (name, m.mean())
        total += m
    assert total.max() == 1, "regions overlap"
    ring = ms["frame"]
    assert ring[0, 320] and ring[359, 320] and ring[180, 0] and ring[180, 639] and not ring[180, 320]
    assert ms["beam"][int(0.05 * 360), int(0.69 * 640)] and not ring[int(0.05 * 360), int(0.69 * 640)]

    # a flat grey frame: no edges, no facets, no contrast, no saturation anywhere
    flat = measure(np.full((720, 1280, 3), 0.5, dtype=np.float32))
    for name in NAMES:
        s = flat[name]
        assert abs(s["median_luma"] - 0.5) < 0.003 and s["contrast"] == 0 and s["edge_density"] == 0 and s["facet_gradient"] == 0, (name, s)

    # each region reports its own content: paint only the beam bright and only the shelves busy
    rng = np.random.RandomState(0)
    a = np.full((360, 640, 3), 0.1, dtype=np.float32)
    a[ms["beam"]] = (0.9, 0.8, 0.3)
    checker = ((np.indices((360, 640)).sum(axis=0) // 4) % 2).astype(np.float32)
    a[ms["shelves"]] = (0.15 + 0.5 * checker[ms["shelves"]])[:, None]
    a += rng.normal(0, 0.002, a.shape).astype(np.float32)
    m = measure(np.clip(a, 0, 1))
    assert m["beam"]["median_luma"] > 0.7 and m["beam"]["saturation"] > 0.5, m["beam"]
    assert m["frame"]["median_luma"] < 0.12 and m["statue"]["p99"] < 0.15, (m["frame"], m["statue"])
    assert m["shelves"]["edge_density"] > 0.1 and m["shelves"]["facet_gradient"] > 5, m["shelves"]
    assert m["arch_passage"]["edge_density"] == 0, m["arch_passage"]

    # resolution does not matter: the same picture at 4x the size measures the same
    big = np.asarray(Image.fromarray(np.round(np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((2560, 1440), Image.NEAREST))
    mb = measure(big)
    for name in NAMES:
        if name != "shelves":  # a 50/50 checker has no stable median
            assert abs(mb[name]["median_luma"] - m[name]["median_luma"]) < 0.01, (name, mb[name], m[name])
        assert abs(mb[name]["contrast"] - m[name]["contrast"]) < 0.05, (name, mb[name], m[name])
        assert abs(mb[name]["edge_density"] - m[name]["edge_density"]) < 0.03, (name, mb[name], m[name])

    # compare(): the delta is ours - ref
    c = compare(np.clip(a, 0, 1), np.clip(a * 0.5, 0, 1))
    assert c["delta_ours_minus_ref"]["beam"]["median_luma"] < -0.3
    assert "beam" in table(c)
    print("regions selftest OK", json.dumps({n: round(float(ms[n].mean()), 3) for n in NAMES}))


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("images", nargs="*", help="REF OURS, or one image")
    ap.add_argument("--json", help="also write the JSON here")
    ap.add_argument("--overlay", help="write the regions drawn over the image(s)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return
    if len(args.images) not in (1, 2):
        ap.error("give REF OURS, or one image")
    if len(args.images) == 2:
        result = compare(*args.images)
        result["files"] = {"ref": args.images[0], "ours": args.images[1]}
    else:
        result = {"image": measure(args.images[0]), "files": {"image": args.images[0]}}
    result["regions"] = {name: [list(r) for r in rects] for name, rects in REGIONS}
    print(table(result))
    print()
    print(json.dumps(result, indent=1))
    if args.json:
        with open(args.json, "w") as f:
            json.dump(result, f, indent=1)
    if args.overlay:
        overlay(args.images, args.overlay)


if __name__ == "__main__":
    main()
