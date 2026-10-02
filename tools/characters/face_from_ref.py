#!/usr/bin/env python3
"""Cuts the witch's face out of the user's camera-facing close-up and measures its relief, for witch_ref.py:

    python tools/characters/face_from_ref.py <close-up image> [--out tools/characters/ref] [--debug DIR]

  witch_face.png         the face, eyes levelled, hair/hood/flowers painted over with the nearest skin
  witch_face_depth.png   how near each texel is (Depth Anything V2 on the close-up: relative inverse depth, which over
                         a face this far from the camera is as good as depth), 0..255 from the face's farthest texel
                         to its nearest
  witch_face.json        the outline (u, v of the tile), the eye line, the face's size in metres

The reference is the user's own artwork and is never committed: only these derived files are. The iris centres are
read off the close-up (pass --iris for another image).
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'painted'))
from build_painted import run_depth  # noqa: E402  (the same depth model the painted room is built with)

IRIS = ((414.0, 432.0), (623.0, 441.0))  # the viewer's left and right iris in the camera-facing close-up (1024x918)
EYE_CHIN_M = 0.134            # eye line to chin on the model (the face's scale; the forehead's cut does not change it)
TILE = 112                    # the tile's longer side, in texels (the atlas is 256 wide)
FOREHEAD = 0.68               # the skin shows this far above the eye line, in eye-to-chin distances, before the flowers
NECK = 0.15                   # below the mouth, a row narrower than this share of the eye row is the neck


def skin_mask(rgb, seed):
    hsv = np.asarray(Image.fromarray(rgb).convert('HSV')).astype(float)
    h, s, v = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255, hsv[..., 2] / 255
    m = ((h < 32) | (h > 340)) & (s < 0.52) & (v > 0.46)
    m = ndimage.binary_closing(m, iterations=3)
    lab, _ = ndimage.label(m)
    keep = ndimage.binary_fill_holes(lab == lab[seed[1], seed[0]])
    keep = ndimage.binary_opening(keep, iterations=7)
    return ndimage.binary_fill_holes(keep)


def trim(m, eye_y):
    """The forehead ends in an arch under the flowers; the neck is cut where the face narrows below the mouth."""
    ys = np.nonzero(m.any(1))[0]
    widths = m.sum(1)
    eye_w = widths[int(round(eye_y))]
    chin = ys.max() + 1
    for y in range(int(eye_y + 0.6 * (chin - eye_y)), chin):
        if widths[y] < NECK * eye_w:
            chin = y
            break
    m = m.copy()
    m[chin:] = False
    row = np.nonzero(m[int(round(eye_y))])[0]
    cx, rx = (row.min() + row.max()) / 2.0, (row.max() - row.min()) / 2.0 * 1.04
    ry = FOREHEAD * (chin - eye_y)
    yy, xx = np.mgrid[0:m.shape[0], 0:m.shape[1]]
    m &= (yy >= eye_y) | (((xx - cx) / rx) ** 2 + ((yy - eye_y) / ry) ** 2 <= 1.0)
    return ndimage.binary_opening(m, iterations=2)


def convex(mask):
    """The mask's convex hull: a face is convex, so a notch where a petal or a lock of hair crossed it is filled."""
    from PIL import ImageDraw
    from scipy.spatial import ConvexHull
    ys, xs = np.nonzero(mask)
    pts = np.stack([xs, ys], 1)
    img = Image.new('L', (mask.shape[1], mask.shape[0]), 0)
    ImageDraw.Draw(img).polygon([tuple(map(int, p)) for p in pts[ConvexHull(pts).vertices]], fill=255)
    return np.asarray(img) > 127


def outline(mask, n=40):
    """Where the mask ends along `n` rays from its centre, as (u, v) of the tile, counter-clockwise on screen."""
    h, w = mask.shape
    cy, cx = ndimage.center_of_mass(mask)
    pts = []
    for t in np.linspace(0, 2 * math.pi, n, endpoint=False):
        r = 0.0
        while True:
            x, y = cx + (r + 1) * math.cos(t), cy + (r + 1) * math.sin(t)
            if not (0 <= int(x) < w and 0 <= int(y) < h) or not mask[int(y), int(x)]:
                break
            r += 1
        pts.append(((cx + r * math.cos(t)) / w, (cy + r * math.sin(t)) / h))
    return pts[::-1]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('image')
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), 'ref'))
    ap.add_argument('--iris', nargs=4, type=float, metavar=('LX', 'LY', 'RX', 'RY'))
    ap.add_argument('--debug', help='write a contact sheet of the steps here')
    a = ap.parse_args(argv)
    iris = ((a.iris[0], a.iris[1]), (a.iris[2], a.iris[3])) if a.iris else IRIS
    src = Image.open(a.image).convert('RGB')
    roll = math.degrees(math.atan2(iris[1][1] - iris[0][1], iris[1][0] - iris[0][0]))
    mid = ((iris[0][0] + iris[1][0]) / 2, (iris[0][1] + iris[1][1]) / 2)
    # PIL rotates counter-clockwise about `center`: the eye line slopes down to the right by `roll`, so +roll levels it
    img = src.rotate(roll, resample=Image.BICUBIC, center=mid, fillcolor=(0, 0, 0))
    rgb = np.asarray(img)
    eye_dist = math.hypot(iris[1][0] - iris[0][0], iris[1][1] - iris[0][1])
    mask = trim(skin_mask(rgb, (int(mid[0]), int(mid[1] + 0.3 * eye_dist))), mid[1])
    ys, xs = np.nonzero(mask)
    pad = 3
    x0, y0, x1, y1 = xs.min() - pad, ys.min() - pad, xs.max() + 1 + pad, ys.max() + 1 + pad
    # depth of a generous crop around the face (the model sees the head, not only the skin)
    m = int(0.6 * eye_dist)
    box = (max(0, x0 - m), max(0, y0 - m), min(rgb.shape[1], x1 + m), min(rgb.shape[0], y1 + m))
    disp = np.zeros(rgb.shape[:2], np.float32)
    disp[box[1]:box[3], box[0]:box[2]] = run_depth(img.crop(box), (box[2] - box[0], box[3] - box[1]))
    crop, cm, cd = rgb[y0:y1, x0:x1].copy(), mask[y0:y1, x0:x1], disp[y0:y1, x0:x1].astype(float)
    # paint everything outside the skin with skin, so no hair or flower bleeds in: where the outline's hull reaches past
    # the skin (a lock of hair crossed the forehead), the skin around it averaged; farther out, the nearest skin pixel.
    # Both from a few pixels inside the edge: the edge itself carries the petals' shadows and the hair's fringe.
    # the flowers cast soft grey-violet shadows on her forehead; the model's flowers are elsewhere, so those go too
    yy = np.arange(y0, y1)[:, None]
    cast = (crop[..., 0].astype(int) - crop[..., 2] < 40) & (yy < mid[1] - 0.38 * eye_dist)
    src = ndimage.binary_erosion(cm & ~ndimage.binary_dilation(cast, iterations=3), iterations=3)
    near = ndimage.distance_transform_edt(~src, return_distances=False, return_indices=True)
    filled = crop[near[0], near[1]].astype(float)
    weight = ndimage.gaussian_filter(src.astype(float), 0.04 * eye_dist)
    blurred = np.stack([ndimage.gaussian_filter(crop[..., c] * src, 0.04 * eye_dist) for c in range(3)], -1)
    hole = convex(cm) & ~src & (weight > 0.05)
    filled[hole] = blurred[hole] / weight[hole, None]
    filled = np.clip(filled, 0, 255).astype(np.uint8)
    h, w = cm.shape
    s = TILE / max(w, h)
    tw, th = max(8, round(w * s)), max(8, round(h * s))
    tile = Image.fromarray(filled).resize((tw, th), Image.LANCZOS)
    # depth: unitless (witch_ref.py fits it to the head); outside the face, the nearest texel inside
    small_m = np.asarray(Image.fromarray((cm * 255).astype(np.uint8)).resize((tw, th), Image.BILINEAR)) > 127
    small_d = np.asarray(Image.fromarray(cd.astype(np.float32)).resize((tw, th), Image.BILINEAR)).astype(float)
    small_d = ndimage.gaussian_filter(small_d, 0.6)
    small_d = small_d[tuple(ndimage.distance_transform_edt(~small_m, return_distances=False, return_indices=True))]
    lo, hi = float(small_d[small_m].min()), float(small_d[small_m].max())
    level = np.clip((small_d - lo) / (hi - lo), 0, 1)
    pts = outline(convex(cm))
    h_m = EYE_CHIN_M * h / (ys.max() + 1 - mid[1])
    out = {'tile': [tw, th], 'size_m': [round(h_m * w / h, 4), round(h_m, 4)],
           'eye_line_v': round((mid[1] - y0) / h, 4), 'mid_u': round((mid[0] - x0) / w, 4),
           'outline': [[round(u, 4), round(v, 4)] for u, v in pts],
           'roll_deg': round(roll, 2), 'source': 'camera-facing close-up reference (not committed); depth: Depth Anything V2 Small'}
    os.makedirs(a.out, exist_ok=True)
    tile.save(os.path.join(a.out, 'witch_face.png'))
    Image.fromarray((level * 255).round().astype(np.uint8)).save(os.path.join(a.out, 'witch_face_depth.png'))
    with open(os.path.join(a.out, 'witch_face.json'), 'w') as f:
        json.dump(out, f, indent=1)
    print('face tile %dx%d, %.3f x %.3f m, eye line at v=%.2f, roll %.1f deg'
          % (tw, th, out['size_m'][0], out['size_m'][1], out['eye_line_v'], roll))
    if a.debug:
        os.makedirs(a.debug, exist_ok=True)
        ov = rgb.copy()
        ov[mask] = (ov[mask] * .5 + np.array([0, 255, 0]) * .5).astype(np.uint8)
        Image.fromarray(ov).save(os.path.join(a.debug, 'face_mask.png'))
        k = 4
        sheet = Image.new('RGB', (tw * k * 2, th * k))
        sheet.paste(tile.resize((tw * k, th * k), Image.NEAREST), (0, 0))
        sheet.paste(Image.fromarray((level * 255).astype(np.uint8)).convert('RGB').resize((tw * k, th * k), Image.NEAREST), (tw * k, 0))
        sheet.save(os.path.join(a.debug, 'face_tile_depth.png'))


if __name__ == '__main__':
    sys.exit(main())
