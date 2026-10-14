#!/usr/bin/env python3
"""Tomas as a PS1-era crude trial (not shipped, not loaded by the game): the same skeleton, clips, palette and
faceting as tomas.py, with fewer rings and sides (`--detail`), a thinner face plate and a face texture of
`--face-px` texels, nearest sampled. The shipped tomas.glb is not touched.

    python tools/characters/tomas_crude.py --out assets/characters/trial --preview docs/art/crude_trial/tomas_crude.png

writes DIR/tomas_crude.glb. With --preview, one sheet: the concept sheet's Tomas (row 0), the current model (row 1)
and the trial (row 2), at the same scale, each with a face close-up. tomas_preview.py's rasteriser draws them.
"""
import argparse
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import tomas  # noqa: E402
import tomas_preview as tp  # noqa: E402

# the trial's face grid: every other row and column of the shipped plate, kept where the relief lives
FACE_ROWS_CRUDE = [1.122, 1.148, 1.176, 1.204, 1.230, 1.256, 1.288, 1.322, 1.362, 1.410]
FACE_COLS_CRUDE = [-.92, -.56, -.26, -.05, .05, .26, .56, .92]
VIEWS = [('FRONT', 0, 0), ('SIDE', 90, 0), ('BACK', 180, 0), ('FRONT-LEFT', 40, 8)]
CELL = (230, 400)


def tomas_surfaces(detail, rows, cols, cx):
    """Tomas's flat surfaces at a density; tomas.py's module defaults are restored afterwards."""
    saved = (tomas.DETAIL, tomas.FACE_ROWS, tomas.FACE_COLS)
    tomas.DETAIL, tomas.FACE_ROWS, tomas.FACE_COLS = detail, rows, cols
    try:
        return tomas.flatten(tomas.build_parts(cx))
    finally:
        tomas.DETAIL, tomas.FACE_ROWS, tomas.FACE_COLS = saved


def face_texture(src_png, px):
    """The shipped face plate box-filtered to px x px and quantised to 5 bits per channel. Returns the PNG bytes
    (embedded as is) and the image (for the preview)."""
    img = Image.open(src_png).convert('RGB').resize((px, px), Image.BOX)
    a = np.asarray(img).astype(float) / 255
    a = np.round(np.round(a * 31) / 31 * 255).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(a).save(buf, 'PNG')
    return buf.getvalue(), Image.fromarray(a)


def preview(path, cx, current, current_tex, crude, crude_tex, title_crude):
    """Three rows (concept sheet, current, trial) by the four views and a face close-up."""
    cols = len(VIEWS) + 1
    w, h = CELL
    lab = 22
    sheet = Image.new('RGB', (w * cols, (h + lab) * 3), tuple(int(v * 255) for v in tp.BG))
    scale = 230.0 / tomas.SHEET_PPM
    sv = tp.sheet_views(os.path.join(REPO, 'docs', 'art', 'references', '03_concept_sheet_witch_raccoon_shadow_tomas.png'), scale)
    for k, name in enumerate(('front', 'side', 'back')):
        im = sv[name]
        im = im.crop((0, 0, im.width, min(im.height, h)))
        sheet.paste(im, (k * w + (w - im.width) // 2, lab))
    tp.label(sheet, 'concept sheet 03 (front, side, back, same scale)', (6, 4))
    rows = [(current, current_tex, 'current tomas.glb'), (crude, crude_tex, title_crude)]
    for r, (surf, tex, name) in enumerate(rows, start=1):
        y0 = r * (h + lab)
        tp.label(sheet, name, (6, y0 + 4))
        for k, (vname, yaw, pitch) in enumerate(VIEWS):
            im = tp.to_img(tp.render(surf, tex, yaw, pitch, CELL, ppm=230., centre=(0, .78, 0)))
            sheet.paste(im, (k * w, y0 + lab))
            tp.label(sheet, vname, (k * w + 6, y0 + lab + h - 18))
        face = tp.to_img(tp.render(surf, tex, 0, 0, CELL, ppm=640., centre=(0, 1.26, 0)))
        sheet.paste(face, (len(VIEWS) * w, y0 + lab))
        tp.label(sheet, 'face', (len(VIEWS) * w + 6, y0 + lab + h - 18))
    sheet.save(path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='assets/characters/trial', help='folder for the trial GLB')
    ap.add_argument('--name', default='tomas_crude')
    ap.add_argument('--detail', type=float, default=0.4, help='ring and side counts, times the shipped model\'s')
    ap.add_argument('--face-px', type=int, default=32, help='face texture size (texels square, nearest)')
    ap.add_argument('--preview', help='write the comparison sheet (PNG) here')
    a = ap.parse_args(argv)

    cx = json.load(open(os.path.join(HERE, 'tomas_face.json')))['sheet_cx']
    face_src = os.path.join(REPO, 'assets', 'characters', 'tomas_face.png')
    png, crude_tex = face_texture(face_src, a.face_px)
    crude = tomas_surfaces(a.detail, FACE_ROWS_CRUDE, FACE_COLS_CRUDE, cx)
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, a.name + '.glb')
    tomas.export_glb(crude, png, path)
    tris, lo, hi = tomas.stats(crude)
    print('%s: %d triangles, %d surfaces, %d bones, %d animations, face %d px, bounds %s .. %s' % (
        path, tris, len(crude), len(tomas.BONE_NAMES), len(tomas.ANIMATIONS), a.face_px,
        np.round(lo, 3), np.round(hi, 3)))

    if a.preview:
        os.makedirs(os.path.dirname(os.path.abspath(a.preview)), exist_ok=True)
        current = tomas_surfaces(1.0, tomas.FACE_ROWS, tomas.FACE_COLS, cx)
        current_tex = np.asarray(Image.open(face_src).convert('RGB')).astype(float) / 255
        crude_tex_a = np.asarray(crude_tex.convert('RGB')).astype(float) / 255
        cur_tris = tomas.stats(current)[0]
        preview(a.preview, cx, current, current_tex, crude, crude_tex_a,
                'crude trial %s (%d tris, face %d px)' % (a.name, tris, a.face_px))
        print('preview: %s (current model %d triangles)' % (a.preview, cur_tris))
    return crude


if __name__ == '__main__':
    main()
