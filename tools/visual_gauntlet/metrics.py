#!/usr/bin/env python3
"""Numbers that go with the judgement: value structure, colour balance, facet energy, vignette.

    python tools/visual_gauntlet/metrics.py frame.png [more.png ...] > metrics.json

Taste decides who wins; these catch regressions and say WHY a frame feels flat (no dark frame, no
bright pool, no purple, no facet energy). Needs numpy and Pillow.
"""
import colorsys
import json
import sys

import numpy as np
from PIL import Image


def analyse(path):
    img = Image.open(path).convert("RGB")
    a = np.asarray(img, dtype=np.float32) / 255.0
    luma = a @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    h, w = luma.shape
    p = np.percentile(luma, [1, 5, 25, 50, 75, 95, 99])
    # hue/saturation share
    flat = a.reshape(-1, 3)
    mx, mn = flat.max(axis=1), flat.min(axis=1)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
    hue = np.zeros(len(flat), dtype=np.float32)
    r, g, b = flat[:, 0], flat[:, 1], flat[:, 2]
    d = np.maximum(mx - mn, 1e-4)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60.0
    lit = (mx > 0.18) & (sat > 0.12)
    olive_gold = (lit & (hue >= 30) & (hue <= 70)).mean()
    purple = (lit & (hue >= 255) & (hue <= 310)).mean()
    warm_orange = (lit & (hue >= 12) & (hue < 30)).mean()
    # facet energy: mean absolute gradient (high = crisp crystalline facets; very high = noise)
    gx = np.abs(np.diff(luma, axis=1)).mean()
    gy = np.abs(np.diff(luma, axis=0)).mean()
    # vignette: corners vs centre
    cy, cx = h // 2, w // 2
    centre = luma[cy - h // 6: cy + h // 6, cx - w // 6: cx + w // 6].mean()
    corners = np.mean([luma[:h // 6, :w // 6].mean(), luma[:h // 6, -w // 6:].mean(), luma[-h // 6:, :w // 6].mean(), luma[-h // 6:, -w // 6:].mean()])
    return {
        "file": path, "size": [w, h],
        "luma_pct_1_5_25_50_75_95_99": [round(float(x), 3) for x in p],
        "dark_frame_share_lt_0.12": round(float((luma < 0.12).mean()), 3),
        "bright_pool_share_gt_0.75": round(float((luma > 0.75).mean()), 3),
        "contrast_p95_over_p5": round(float(p[5] / max(p[1], 0.01)), 2),
        "olive_gold_share": round(float(olive_gold), 3), "purple_share": round(float(purple), 3), "orange_share": round(float(warm_orange), 3),
        "mean_saturation": round(float(sat[mx > 0.1].mean()), 3),
        "facet_gradient": round(float((gx + gy) / 2 * 100), 2),
        "vignette_corner_over_centre": round(float(corners / max(centre, 1e-3)), 3),
        "distinct_colours": int(len(np.unique((a * 31).astype(np.uint8).reshape(-1, 3), axis=0))),
    }


if __name__ == "__main__":
    print(json.dumps([analyse(p) for p in sys.argv[1:]], indent=1))
