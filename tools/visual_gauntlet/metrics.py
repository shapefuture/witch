#!/usr/bin/env python3
"""Numbers that go with the judgement: value structure, colour balance, facet energy, vignette.

    python tools/visual_gauntlet/metrics.py frame.png [more.png ...] > metrics.json

Taste decides who wins; these catch regressions and say WHY a frame feels flat (no dark frame, no
bright pool, no purple, no facet energy). Needs numpy and Pillow.

The per-pixel helpers (`rgb`, `luma`, `sat_hue`, `gradient_map`) are shared with `regions.py` and
`squint.py`, so a "median luma" or a "facet gradient" means the same thing in every tool.
"""
import json
import sys

import numpy as np
from PIL import Image

LUMA_WEIGHTS = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)  # Rec.709, on display-referred values


def rgb(src):
    """A path, a PIL image or an array -> float32 HxWx3 in [0, 1]. Alpha is dropped (frames are opaque)."""
    if isinstance(src, np.ndarray):
        a = src.astype(np.float32)
        if src.dtype == np.uint8:
            a /= 255.0
        if a.ndim == 2:
            a = np.repeat(a[:, :, None], 3, axis=2)
        return np.clip(a[:, :, :3], 0.0, 1.0)
    img = src if isinstance(src, Image.Image) else Image.open(src)
    return np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0


def luma(a):
    return a @ LUMA_WEIGHTS


def sat_hue(a):
    """HSV saturation and hue (degrees) per pixel, plus the max channel (the HSV value)."""
    mx, mn = a.max(axis=-1), a.min(axis=-1)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    d = np.maximum(mx - mn, 1e-4)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    return sat, hue, mx


def gradient_map(lum):
    """Per-pixel facet energy, (|dx| + |dy|) / 2 * 100; its mean over a whole frame is `facet_gradient`."""
    gx = np.abs(np.diff(lum, axis=1))
    gy = np.abs(np.diff(lum, axis=0))
    gx = np.concatenate([gx, gx[:, -1:]], axis=1)
    gy = np.concatenate([gy, gy[-1:, :]], axis=0)
    return (gx + gy) * 50.0


def analyse(path):
    a = rgb(path)
    lum = luma(a)
    h, w = lum.shape
    p = np.percentile(lum, [1, 5, 25, 50, 75, 95, 99])
    # hue/saturation share
    sat, hue, mx = sat_hue(a.reshape(-1, 3))
    lit = (mx > 0.18) & (sat > 0.12)
    olive_gold = (lit & (hue >= 30) & (hue <= 70)).mean()
    purple = (lit & (hue >= 255) & (hue <= 310)).mean()
    warm_orange = (lit & (hue >= 12) & (hue < 30)).mean()
    # facet energy: mean absolute gradient (high = crisp crystalline facets; very high = noise)
    gx = np.abs(np.diff(lum, axis=1)).mean()
    gy = np.abs(np.diff(lum, axis=0)).mean()
    # vignette: corners vs centre
    cy, cx = h // 2, w // 2
    centre = lum[cy - h // 6: cy + h // 6, cx - w // 6: cx + w // 6].mean()
    corners = np.mean([lum[:h // 6, :w // 6].mean(), lum[:h // 6, -w // 6:].mean(), lum[-h // 6:, :w // 6].mean(), lum[-h // 6:, -w // 6:].mean()])
    return {
        "file": path, "size": [w, h],
        "luma_pct_1_5_25_50_75_95_99": [round(float(x), 3) for x in p],
        "dark_frame_share_lt_0.12": round(float((lum < 0.12).mean()), 3),
        "bright_pool_share_gt_0.75": round(float((lum > 0.75).mean()), 3),
        "contrast_p95_over_p5": round(float(p[5] / max(p[1], 0.01)), 2),
        "olive_gold_share": round(float(olive_gold), 3), "purple_share": round(float(purple), 3), "orange_share": round(float(warm_orange), 3),
        "mean_saturation": round(float(sat[mx > 0.1].mean()), 3),
        "facet_gradient": round(float((gx + gy) / 2 * 100), 2),
        "vignette_corner_over_centre": round(float(corners / max(centre, 1e-3)), 3),
        "distinct_colours": int(len(np.unique((a * 31).astype(np.uint8).reshape(-1, 3), axis=0))),
    }


if __name__ == "__main__":
    print(json.dumps([analyse(p) for p in sys.argv[1:]], indent=1))
