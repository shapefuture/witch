#!/usr/bin/env python3
"""The squint test: do two pictures share the same big value masses?

    python tools/visual_gauntlet/squint.py A.png B.png [--aspect 16:9]    # prints JSON
    python tools/visual_gauntlet/squint.py --selftest

A painter squints to see a picture as a few masses of dark, mid and light. This does the same: both
images are centre-cropped to one aspect (by default the narrower of the two, because the game keeps
360 rows and only widens with the screen), turned to luma, and area-averaged to a tiny grid. Detail,
resolution, colour and pixel art drop out; composition and value structure stay.

`score(a, b)` returns:
  ssim_32x18, ssim_64x36  SSIM of luma on an 18-row and a 36-row grid (32x18 and 64x36 for 16:9;
                          for another aspect the rows stay and the width follows: see `grid`).
                          Gaussian window, sigma 1.5 cells, averaged over every cell including the
                          border (the dark outer frame is part of the composition). 1 = identical.
  value_corr              Spearman correlation of the 32x18 grids: are the darks and lights in the
                          same places, whatever the exposure or tone curve? 1 same, 0 unrelated.
  notan_agree             share of 32x18 cells in the same third (dark / mid / light) of their own
                          image's values: the notan sketch, as a number.
  squint                  mean of ssim_32x18, ssim_64x36 and value_corr: the one number to track.
  aspect, grid            the common aspect and the two grids, [width, height].

`load(src)` takes a path, a PIL image or an array and returns float32 RGB in [0, 1].
Other tools import `score` and `load`: keep those names and keys stable.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage, stats

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import metrics  # noqa: E402

ROWS = (18, 36)
SIGMA = 1.5


def load(src):
    return metrics.rgb(src)


def aspect_of(a):
    return a.shape[1] / a.shape[0]


def centre_crop(a, aspect):
    """The largest centred window of `aspect` (width / height)."""
    h, w = a.shape[:2]
    if w / h > aspect:
        cw = max(1, int(round(h * aspect)))
        x0 = (w - cw) // 2
        return a[:, x0:x0 + cw]
    ch = max(1, int(round(w / aspect)))
    y0 = (h - ch) // 2
    return a[y0:y0 + ch]


def grid_luma(a, rows, aspect):
    """Area-averaged luma on a rows x round(rows * aspect) grid."""
    cols = max(1, int(round(rows * aspect)))
    lum = np.ascontiguousarray(metrics.luma(a), dtype=np.float32)
    return np.asarray(Image.fromarray(lum).resize((cols, rows), Image.BOX), dtype=np.float64)


def ssim(x, y, sigma=SIGMA):
    """Mean SSIM (Wang et al. 2004, data range 1) over the whole map; borders are reflected, not dropped."""
    c1, c2 = 0.01 ** 2, 0.03 ** 2
    blur = lambda z: ndimage.gaussian_filter(z, sigma, mode="reflect", truncate=3.5)  # noqa: E731
    mx, my = blur(x), blur(y)
    vx = blur(x * x) - mx * mx
    vy = blur(y * y) - my * my
    cxy = blur(x * y) - mx * my
    s = ((2 * mx * my + c1) * (2 * cxy + c2)) / ((mx * mx + my * my + c1) * (vx + vy + c2))
    return float(s.mean())


def rank_corr(x, y):
    x, y = x.ravel(), y.ravel()
    if np.ptp(x) == 0 or np.ptp(y) == 0:
        return 1.0 if np.array_equal(x, y) else 0.0
    return float(stats.spearmanr(x, y).statistic)


def notan(g):
    lo, hi = np.percentile(g, [100 / 3, 200 / 3])
    return np.digitize(g, [lo, hi])


def score(a, b, aspect=None):
    a, b = load(a), load(b)
    if aspect is None:
        aspect = min(aspect_of(a), aspect_of(b))
    a, b = centre_crop(a, aspect), centre_crop(b, aspect)
    coarse = [grid_luma(x, ROWS[0], aspect) for x in (a, b)]
    fine = [grid_luma(x, ROWS[1], aspect) for x in (a, b)]
    s32, s64 = ssim(*coarse), ssim(*fine)
    corr = rank_corr(*coarse)
    return {
        "ssim_32x18": round(s32, 4),
        "ssim_64x36": round(s64, 4),
        "value_corr": round(corr, 4),
        "notan_agree": round(float((notan(coarse[0]) == notan(coarse[1])).mean()), 4),
        "squint": round((s32 + s64 + corr) / 3, 4),
        "aspect": round(aspect, 4),
        "grid": [[coarse[0].shape[1], coarse[0].shape[0]], [fine[0].shape[1], fine[0].shape[0]]],
    }


def _scene(w, h, seed=0):
    """A synthetic 'interior': dark sides, a bright diagonal shaft, a few blobs, fine noise."""
    rng = np.random.RandomState(seed)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w, y / h
    lum = 0.08 + 0.25 * np.exp(-((u - 0.5) ** 2) / 0.05)
    lum += 0.5 * np.exp(-((u - (0.7 - 0.15 * v)) ** 2) / 0.002) * (v > 0.05)
    for cx, cy, r, k in ((0.3, 0.55, 0.08, 0.3), (0.66, 0.6, 0.05, -0.15), (0.1, 0.8, 0.1, -0.05)):
        lum += k * np.exp(-((u - cx) ** 2 + (v - cy) ** 2) / (r * r))
    lum += rng.normal(0, 0.03, lum.shape)
    lum = np.clip(lum, 0, 1)
    tint = np.array([1.0, 0.92, 0.6], dtype=np.float32)
    return np.clip(lum[:, :, None] * tint / (tint @ metrics.LUMA_WEIGHTS), 0, 1).astype(np.float32)


def selftest():
    big = _scene(1600, 900)
    same = score(big, big)
    assert same["ssim_32x18"] > 0.999 and same["ssim_64x36"] > 0.999 and same["value_corr"] > 0.999, same
    assert same["notan_agree"] == 1.0 and same["grid"] == [[32, 18], [64, 36]], same

    # resolution and pixel art do not matter: a 640x360 nearest-upscaled copy squints the same
    small = np.asarray(Image.fromarray((big * 255).astype(np.uint8)).resize((640, 360), Image.LANCZOS))
    chunky = np.asarray(Image.fromarray(small).resize((1280, 720), Image.NEAREST))
    for other in (small, chunky):
        s = score(big, other)
        assert s["ssim_32x18"] > 0.98 and s["value_corr"] > 0.97, s

    # a tone curve keeps the value order (value_corr stays 1) but SSIM sees the exposure change
    curved = score(big, big ** 2.2)
    assert curved["value_corr"] > 0.999 and curved["ssim_32x18"] < 0.9, curved

    # the same composition seen at 4:3 (the game keeps the rows and loses the sides)
    narrow = big[:, 200:1400]
    s = score(big, narrow)
    assert s["aspect"] == round(4 / 3, 4) and s["grid"] == [[24, 18], [48, 36]] and s["squint"] > 0.99, s

    # a mirrored layout, noise and an inverted value plan score lower, in that order
    mirrored = score(big, big[:, ::-1])
    noise = score(big, np.random.RandomState(1).rand(900, 1600, 3).astype(np.float32))
    inverted = score(big, 1.0 - big)
    assert same["squint"] > mirrored["squint"] > noise["squint"] > inverted["squint"], (mirrored, noise, inverted)
    assert abs(noise["value_corr"]) < 0.2 and inverted["value_corr"] < -0.95, (noise, inverted)

    # loading from disk and from PIL gives the same numbers
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "x.png")
        Image.fromarray((big * 255).astype(np.uint8)).save(p)
        assert score(p, Image.open(p)) == score(Image.open(p).convert("RGBA"), p)
    print("squint selftest OK", json.dumps({"same": same["squint"], "mirrored": mirrored["squint"], "noise": noise["squint"]}))


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("images", nargs="*")
    ap.add_argument("--aspect", help="common aspect, e.g. 16:9 or 1.7778 (default: the narrower image's)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return
    if len(args.images) != 2:
        ap.error("give two images")
    aspect = None
    if args.aspect:
        num, _, den = args.aspect.partition(":")
        aspect = float(num) / float(den) if den else float(num)
    result = score(args.images[0], args.images[1], aspect)
    result["a"], result["b"] = args.images
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
