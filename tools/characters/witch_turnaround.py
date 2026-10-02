#!/usr/bin/env python3
"""Turnaround strip: the new witch (front / side / back) next to the user's reference sheet, at three sizes.

    python tools/characters/witch_turnaround.py OUT.png [--ref REF1.png] [--glb witch.glb]

Without --glb the model is built in memory from `witch_ref.py` (the idle pose at t = 0), and drawn by the
numpy previewer (flat key light, nearest-sampled atlas; NOT the game's shader: use capture_actors.gd for that).
`--ref` is the 1128 x 322 sheet (six views, the witch's three first); it is the user's artwork and is not in the
repository, so without it only the model's row is written. The rows are the reference then the model; the
columns are front, side, back; the sizes are 100 %, 50 % and 25 % of the row height (the game sees her at
about 100 px).
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import witch_glb as glb         # noqa: E402
import witch_preview as wp       # noqa: E402
import witch_ref as wr           # noqa: E402
from witch_kit import bake_uvs   # noqa: E402

BG = (.075, .075, .08)
REF_BOXES = {'front': (0, 0, 222, 322), 'side': (222, 0, 412, 322), 'back': (410, 0, 640, 322)}
VIEWS = (('front', (0, 0, -1)), ('side', (-1, 0, 0)), ('back', (0, 0, 1)))
CELL_W, CELL_H = 330, 440


def model_views(h=CELL_H, ss=2, pose='idle', t=0.):
    M, at = wr.make_model()
    clips = {c.name: c for c in wr.clip_set(M)}
    tris = M.flatten()
    arr = bake_uvs(tris, at, M.COL)
    r0, t0 = clips[pose].fn(t)
    posed = glb.pose_arrays(M, arr, r0, t0)
    span = wr.HEIGHT / (274. / 322.)                   # the sheet's figure fills 274 of its 322 rows
    y0 = -26. / 322. * span
    out = {}
    for name, fwd in VIEWS:
        b = REF_BOXES[name]
        w = int(h * (b[2] - b[0]) / (b[3] - b[1]))
        hw = span * w / h / 2
        cx = .05 if name == 'side' else 0.
        out[name] = wp.render(posed, at.img, fwd, (0, 1, 0), w, h, SS=ss, bg=BG, crop=(cx - hw, cx + hw, y0, y0 + span))
    return out, len(tris)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('out')
    ap.add_argument('--ref', default=None)
    a = ap.parse_args(argv)
    ours, n = model_views()
    rows = []
    if a.ref and os.path.exists(a.ref):
        ref = Image.open(a.ref).convert('RGB')
        refs = {k: ref.crop(b).resize((int(CELL_H * (b[2] - b[0]) / (b[3] - b[1])), CELL_H), Image.LANCZOS) for k, b in REF_BOXES.items()}
        rows.append(refs)
    rows.append(ours)
    sheets = []
    for scale in (1., .5, .25):
        parts = []
        for row in rows:
            ims = [row[k] for k, _ in VIEWS]
            ims = [im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS) for im in ims]
            W = sum(im.width for im in ims)
            H = max(im.height for im in ims)
            strip = Image.new('RGB', (W, H), tuple(int(c * 255) for c in BG))
            x = 0
            for im in ims:
                strip.paste(im, (x, 0))
                x += im.width
            parts.append(strip)
        sheets.append(parts)
    W = max(p.width for parts in sheets for p in parts)
    H = sum(parts[0].height * len(parts) for parts in sheets)
    canvas = Image.new('RGB', (W * 1, H), tuple(int(c * 255) for c in BG))
    y = 0
    for parts in sheets:
        for p in parts:
            canvas.paste(p, (0, y))
            y += p.height
    canvas.save(a.out)
    print('%s  (%d triangles)' % (a.out, n))


if __name__ == '__main__':
    main()
