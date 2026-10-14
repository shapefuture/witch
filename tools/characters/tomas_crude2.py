#!/usr/bin/env python3
"""Tomas, second crude trial (not shipped, not loaded by the game). Follows docs/art/crude_trial/COMPARISON.md.

The polygons go where the identity is: the head, the hair, the hands and the wrench keep the model's density; the
torso, the arms and the legs get fewer sides. The face texture is the sheet's own 64 px crop, contrast raised so the
brows, eyes and mouth stay readable. The garments are saturated colour blocks within SC7 (jewel and earthy anchors).
The silhouette and the proportions are the shipped model's. The shipped tomas.glb is not touched.

    python tools/characters/tomas_crude2.py --out assets/characters/trial --preview docs/art/crude_trial/tomas_crude2.png

writes DIR/tomas_crude2.glb. With --preview, four rows: the concept sheet, the current model, trial 1 and trial 2.
"""
import argparse
import contextlib
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import tomas  # noqa: E402
import tomas_crude as tc  # noqa: E402
import tomas_preview as tp  # noqa: E402

# density per part, as a fraction of the shipped model's ring and side counts (tomas.sides)
PART_DETAIL = {'legs': .5, 'torso': .6, 'belt': .6, 'arms': .7, 'head': 1.0, 'hair': 1.0, 'wrench': 1.0}
# the hands keep full density inside the arms (build_hand is called from build_arms)
HAND_DETAIL = 1.0
# the face's features: the darkest FEATURE_PERCENTILE of the central face, in one colour (a bold read at 64 px)
FEATURE_PERCENTILE = 6
FEATURE_COLOUR = (.34, .19, .13)
# saturated colour blocks, all within SC7 (jewel tones and the earthy anchors); the shipped values are in tomas.PALETTE
TRIAL2_PALETTE = {
    'skin': (.86, .56, .42), 'skin_d': (.70, .42, .32), 'neck': (.78, .48, .36),
    'hair': (.60, .34, .14), 'hair_l': (.72, .44, .20), 'hair_d': (.42, .22, .10),
    'shirt': (.95, .84, .52), 'shirt_d': (.80, .64, .36),
    'vest': (.45, .14, .50), 'vest_d': (.34, .10, .40), 'vest_in': (.22, .06, .26),
    'belt': (.42, .22, .10), 'belt_d': (.30, .15, .07),
    'pouch': (.80, .50, .14), 'pouch_d': (.60, .36, .10),
    'trousers': (.34, .52, .18), 'trousers_d': (.25, .40, .13), 'cuff': (.30, .46, .16),
    'boot': (.55, .25, .10), 'boot_d': (.42, .18, .07), 'sole': (.16, .10, .06),
}


@contextlib.contextmanager
def at_detail(d):
    saved = tomas.DETAIL
    tomas.DETAIL = d
    try:
        yield
    finally:
        tomas.DETAIL = saved


@contextlib.contextmanager
def trial2_build():
    """The trial's palette and hand density, active only while its parts are built and flattened."""
    saved_palette = dict(tomas.PALETTE)
    saved_hand = tomas.build_hand
    tomas.PALETTE.update(TRIAL2_PALETTE)

    def hand_full(b, s, d, wr):
        with at_detail(HAND_DETAIL):
            saved_hand(b, s, d, wr)
    tomas.build_hand = hand_full
    try:
        yield
    finally:
        tomas.build_hand = saved_hand
        tomas.PALETTE.clear()
        tomas.PALETTE.update(saved_palette)


def build_trial2(cx):
    b = tomas.Builder()
    with at_detail(PART_DETAIL['legs']):
        tomas.build_legs(b)
    with at_detail(PART_DETAIL['torso']):
        tomas.build_torso(b)
        tomas.build_vest(b)
    with at_detail(PART_DETAIL['belt']):
        tomas.build_belt(b)
    with at_detail(PART_DETAIL['arms']):
        tomas.build_arms(b)
    with at_detail(PART_DETAIL['head']):
        tomas.build_head(b, cx)
    with at_detail(PART_DETAIL['hair']):
        tomas.build_hair(b)
    with at_detail(PART_DETAIL['wrench']):
        tomas.build_wrench(b)
    return b.parts


def face_texture(src_png, px=64):
    """The sheet's face at px texels, read like the references' faces: the darkest 6% of the central face (brows,
    eyes, mouth line) becomes one feature colour, not thickened; the skin is posterised to 8 levels per channel.
    Quantised to 5 bits per channel. Returns the PNG bytes (embedded as is) and the image (for the preview)."""
    img = Image.open(src_png).convert('RGB').resize((px, px), Image.BOX)
    arr = np.asarray(img).astype(float) / 255
    luma = arr @ np.array([.2126, .7152, .0722])
    centre = np.zeros((px, px), bool)
    lo, hi = px // 5, px - px // 5
    centre[lo:hi, lo:hi] = True
    cut = np.percentile(luma[centre], FEATURE_PERCENTILE)
    feature = (luma <= cut) & centre
    out = np.round(arr * 7) / 7
    out[feature] = FEATURE_COLOUR
    out = np.round(np.round(out * 31) / 31 * 255).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(out).save(buf, 'PNG')
    return buf.getvalue(), Image.fromarray(out)


def preview(path, cx, rows):
    """Concept sheet, then one row per (surfaces, texture, label): four views and a face close-up."""
    cols = len(tc.VIEWS) + 1
    w, h = tc.CELL
    lab = 22
    sheet = Image.new('RGB', (w * cols, (h + lab) * (len(rows) + 1)), tuple(int(v * 255) for v in tp.BG))
    scale = 230.0 / tomas.SHEET_PPM
    sv = tp.sheet_views(os.path.join(REPO, 'docs', 'art', 'references', '03_concept_sheet_witch_raccoon_shadow_tomas.png'), scale)
    for k, name in enumerate(('front', 'side', 'back')):
        im = sv[name]
        im = im.crop((0, 0, im.width, min(im.height, h)))
        sheet.paste(im, (k * w + (w - im.width) // 2, lab))
    tp.label(sheet, 'concept sheet 03 (front, side, back, same scale)', (6, 4))
    for r, (surf, tex, name) in enumerate(rows, start=1):
        y0 = r * (h + lab)
        tp.label(sheet, name, (6, y0 + 4))
        for k, (vname, yaw, pitch) in enumerate(tc.VIEWS):
            im = tp.to_img(tp.render(surf, tex, yaw, pitch, tc.CELL, ppm=230., centre=(0, .78, 0)))
            sheet.paste(im, (k * w, y0 + lab))
            tp.label(sheet, vname, (k * w + 6, y0 + lab + h - 18))
        face = tp.to_img(tp.render(surf, tex, 0, 0, tc.CELL, ppm=640., centre=(0, 1.26, 0)))
        sheet.paste(face, (len(tc.VIEWS) * w, y0 + lab))
        tp.label(sheet, 'face', (len(tc.VIEWS) * w + 6, y0 + lab + h - 18))
    sheet.save(path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='assets/characters/trial', help='folder for the trial GLB')
    ap.add_argument('--name', default='tomas_crude2')
    ap.add_argument('--face-px', type=int, default=64, help='face texture size (texels square, nearest)')
    ap.add_argument('--preview', help='write the four-row comparison sheet (PNG) here')
    a = ap.parse_args(argv)

    cx = json.load(open(os.path.join(HERE, 'tomas_face.json')))['sheet_cx']
    face_src = os.path.join(REPO, 'assets', 'characters', 'tomas_face.png')
    png, tex2 = face_texture(face_src, a.face_px)
    with trial2_build():
        trial2 = tomas.flatten(build_trial2(cx))
    tris, lo, hi = tomas.stats(trial2)
    assert len(trial2) <= 2 and tris <= 9000, 'trial 2 is over the budget'
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, a.name + '.glb')
    tomas.export_glb(trial2, png, path)
    print('%s: %d triangles, %d surfaces, %d bones, %d animations, face %d px, bounds %s .. %s' % (
        path, tris, len(trial2), len(tomas.BONE_NAMES), len(tomas.ANIMATIONS), a.face_px,
        np.round(lo, 3), np.round(hi, 3)))

    if a.preview:
        os.makedirs(os.path.dirname(os.path.abspath(a.preview)), exist_ok=True)
        current = tc.tomas_surfaces(1.0, tomas.FACE_ROWS, tomas.FACE_COLS, cx)
        current_tex = np.asarray(Image.open(face_src).convert('RGB')).astype(float) / 255
        trial1 = tc.tomas_surfaces(0.4, tc.FACE_ROWS_CRUDE, tc.FACE_COLS_CRUDE, cx)
        trial1_tex = np.asarray(tc.face_texture(face_src, 32)[1].convert('RGB')).astype(float) / 255
        trial2_tex = np.asarray(tex2.convert('RGB')).astype(float) / 255
        preview(a.preview, cx, [
            (current, current_tex, 'current tomas.glb (%d tris)' % tomas.stats(current)[0]),
            (trial1, trial1_tex, 'trial 1 (%d tris, face 32 px)' % tomas.stats(trial1)[0]),
            (trial2, trial2_tex, 'trial 2 (%d tris, face %d px, saturated)' % (tris, a.face_px)),
        ])
        print('preview: %s' % a.preview)
    return trial2


if __name__ == '__main__':
    main()
