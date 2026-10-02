#!/usr/bin/env python3
"""How well does a live character's silhouette sit on the painted one?

    python tools/characters/silhouette_diff.py REFERENCE.png CAPTURE_DIR OUT_DIR

The same colour test (purple or dark, against the hall's golden-olive) cuts the figure out of the reference
and out of the live frame (CAPTURE_DIR/room_raw.png); the overlay shows painted-only in red, live-only in
green and both in yellow, with the numbers (intersection over union, height and width ratios, centroid shift).
The test is crude (dark floor shadows leak in), so the boxes are tight; it is for steering, not for proof.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

BOXES = {'witch': (660, 450, 800, 645), 'raccoon': (775, 548, 850, 672)}


def figure_mask(a, box):
    x0, y0, x1, y1 = box
    r = a[y0:y1, x0:x1]
    luma = r @ np.array([.3, .55, .15])
    purple = (r[..., 2] >= r[..., 1] * .85) & (r[..., 0] < 190) & (luma > 14)
    dark = luma < 34
    m = purple | dark
    m = ndimage.binary_opening(m, iterations=1)
    m = ndimage.binary_closing(m, iterations=2)
    lab, n = ndimage.label(m)
    if n == 0:
        return m
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    m = ndimage.binary_fill_holes(lab == (int(np.argmax(sizes)) + 1))
    return m


def stats(m):
    ys, xs = np.where(m)
    return dict(area=int(m.sum()), x0=int(xs.min()), x1=int(xs.max()), y0=int(ys.min()), y1=int(ys.max()),
                cx=float(xs.mean()), cy=float(ys.mean()))


def main(ref_path, cap, out):
    ref = np.asarray(Image.open(ref_path).convert('RGB')).astype(float)
    live = np.asarray(Image.open(os.path.join(cap, 'room_raw.png')).convert('RGB')).astype(float)
    os.makedirs(out, exist_ok=True)
    for name, box in BOXES.items():
        mp, ml = figure_mask(ref, box), figure_mask(live, box)
        sp, sl = stats(mp), stats(ml)
        iou = (mp & ml).sum() / max(1, (mp | ml).sum())
        print('%s: IoU %.2f | painted h %d w %d area %d | live h %d w %d area %d | centroid shift (%.1f, %.1f) px | '
              'top shift %d px, bottom shift %d px' % (
                  name, iou, sp['y1'] - sp['y0'], sp['x1'] - sp['x0'], sp['area'], sl['y1'] - sl['y0'], sl['x1'] - sl['x0'],
                  sl['area'], sl['cx'] - sp['cx'], sl['cy'] - sp['cy'], sl['y0'] - sp['y0'], sl['y1'] - sp['y1']))
        h, w = mp.shape
        img = np.zeros((h, w, 3), np.uint8)
        img[..., 0] = mp * 255
        img[..., 1] = ml * 255
        k = 5
        Image.fromarray(img).resize((w * k, h * k), Image.NEAREST).save(os.path.join(out, 'silhouette_%s.png' % name))


if __name__ == '__main__':
    main(*sys.argv[1:4])
