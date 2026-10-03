#!/usr/bin/env python3
"""The live witch next to the user's reference sheet: front / side / back, and the room as the game draws it.

    python tools/characters/witch_strip.py CAPTURE_DIR OUT_DIR [--ref REF1.png]

CAPTURE_DIR holds what `capture_witch.gd` wrote. Writes in OUT_DIR:
  turnaround_live.png   rows: the reference (if --ref), the studio render, the room with PSX off; columns front, side, back
  room_psx.png          the room at game resolution with PSX on: front / side / back crops, enlarged 4x (nearest), and the
                        reference's back view at the same height for scale
  turnaround_sizes.png  the same three views at 100 %, 50 % and 25 % of the row height (the game sees her at ~100 px)
The reference sheet (1128 x 322, the witch's three views first) is the user's artwork and is not in the repository.
"""
import argparse
import os

from PIL import Image

H = 460
REF_BOXES = {'front': (0, 0, 222, 322), 'side': (222, 0, 412, 322), 'back': (410, 0, 640, 322)}
VIEWS = (('front', 'front'), ('side', 'left'), ('back', 'back'))        # (column, capture name)
ROOM_BOX_1280 = (645, 448, 825, 656)
BG = (24, 22, 26)


def fit_h(im, h):
    return im.resize((max(1, int(round(im.width * h / im.height))), h), Image.LANCZOS)


def studio_crop(path):
    im = Image.open(path).convert('RGB')
    w = 620
    return im.crop(((im.width - w) // 2, 0, (im.width + w) // 2, im.height))


def room_crop(path, nearest=False):
    im = Image.open(path).convert('RGB')
    s = im.width / 1280.
    box = tuple(int(round(v * s)) for v in ROOM_BOX_1280)
    return im.crop(box)


def join(ims, gap=6):
    W = sum(i.width for i in ims) + gap * (len(ims) - 1)
    c = Image.new('RGB', (W, ims[0].height), BG)
    x = 0
    for i in ims:
        c.paste(i, (x, 0))
        x += i.width + gap
    return c


def stack(rows, gap=6):
    W = max(r.width for r in rows)
    Ht = sum(r.height for r in rows) + gap * (len(rows) - 1)
    c = Image.new('RGB', (W, Ht), BG)
    y = 0
    for r in rows:
        c.paste(r, (0, y))
        y += r.height + gap
    return c


def main(cap, out, ref_path=None):
    os.makedirs(out, exist_ok=True)
    ref = Image.open(ref_path).convert('RGB') if ref_path and os.path.exists(ref_path) else None
    rows = {}
    if ref is not None:
        rows['ref'] = [fit_h(ref.crop(REF_BOXES[c]), H) for c, _ in VIEWS]
    rows['studio'] = [fit_h(studio_crop(os.path.join(cap, 'studio_%s.png' % n)), H) for _, n in VIEWS]
    rows['room'] = [fit_h(room_crop(os.path.join(cap, 'room_%s_raw.png' % n)), H) for _, n in VIEWS]
    stack([join(rows[k]) for k in ('ref', 'studio', 'room') if k in rows]).save(os.path.join(out, 'turnaround_live.png'))

    k = 4
    psx = []
    for _, n in VIEWS:
        c = room_crop(os.path.join(cap, 'room_%s_psx.png' % n))
        psx.append(c.resize((c.width * k, c.height * k), Image.NEAREST))
    hh = psx[0].height
    if ref is not None:
        psx.append(fit_h(ref.crop(REF_BOXES['back']), hh))
    join(psx).save(os.path.join(out, 'room_psx.png'))

    sizes = []
    for scale in (1., .5, .25):
        r = []
        for key in ('ref', 'studio'):
            if key in rows:
                r.append(join([i.resize((max(1, int(i.width * scale)), max(1, int(i.height * scale))), Image.LANCZOS) for i in rows[key]], gap=max(2, int(6 * scale))))
        sizes.append(stack(r, gap=2))
    stack(sizes, gap=4).save(os.path.join(out, 'turnaround_sizes.png'))
    print('wrote turnaround_live.png, room_psx.png, turnaround_sizes.png in %s' % out)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('capture_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--ref', default=None)
    a = ap.parse_args()
    main(a.capture_dir, a.out_dir, a.ref)
