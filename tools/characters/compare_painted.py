#!/usr/bin/env python3
"""Side by side: the painted witch / raccoon in the reference still, and the live models in the painted room.

    python tools/characters/compare_painted.py REFERENCE.png CAPTURE_DIR OUT_DIR

CAPTURE_DIR holds room_raw.png (1280x720, PSX off) and room_psx.png (game resolution, PSX on), written by
tools/characters/capture_actors.gd. Writes OUT_DIR/compare_<id>.png: reference | live, PSX off | live, PSX on,
all cut from the same box of the painting (the PSX frame scaled to match) and enlarged to the same size.
The reference is not in the repository.
"""
import os
import sys

from PIL import Image, ImageDraw

BOXES = {'witch': (655, 448, 805, 648), 'raccoon': (770, 545, 850, 675)}
SCALE = {'witch': 4, 'raccoon': 6}


def cut(img, box, k):
    sx = img.width / 1280.0
    b = tuple(int(round(v * sx)) for v in box)
    return img.crop(b)


def main(ref_path, cap, out):
    ref = Image.open(ref_path).convert('RGB')
    raw = Image.open(os.path.join(cap, 'room_raw.png')).convert('RGB')
    psx = Image.open(os.path.join(cap, 'room_psx.png')).convert('RGB')
    lit_path = os.path.join(cap, 'room_psx_lit.png')
    lit = Image.open(lit_path).convert('RGB') if os.path.exists(lit_path) else None
    os.makedirs(out, exist_ok=True)
    for name, box in BOXES.items():
        k = SCALE[name]
        w, h = (box[2] - box[0]) * k, (box[3] - box[1]) * k
        cells = [cut(ref, box, k).resize((w, h), Image.LANCZOS), cut(raw, box, k).resize((w, h), Image.LANCZOS),
                 cut(psx, box, k).resize((w, h), Image.NEAREST)]
        labels = ['painted', 'live (PSX off)', 'live (game, PSX on)']
        if lit is not None:
            cells.append(cut(lit, box, k).resize((w, h), Image.NEAREST))
            labels.append('live, actor light x1.7')
        sheet = Image.new('RGB', (w * len(cells) + 10 * (len(cells) - 1), h + 22), (24, 24, 24))
        d = ImageDraw.Draw(sheet)
        for i, (label, c) in enumerate(zip(labels, cells)):
            sheet.paste(c, (i * (w + 10), 22))
            d.text((i * (w + 10) + 4, 6), label, fill=(230, 230, 230))
        path = os.path.join(out, 'compare_%s.png' % name)
        sheet.save(path)
        print(path)


if __name__ == '__main__':
    main(*sys.argv[1:4])
