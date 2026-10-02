#!/usr/bin/env python3
"""Joins capture_clips.gd's frames into one sheet: a row per clip, its poses left to right.

    python tools/characters/clip_sheet.py FRAMES_DIR OUT.png [--crop X0,Y0,X1,Y1]
"""
import argparse
import glob
import os
import re

from PIL import Image, ImageDraw


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('frames')
    ap.add_argument('out')
    ap.add_argument('--crop', help='crop every frame to X0,Y0,X1,Y1 first')
    a = ap.parse_args(argv)
    clips = {}
    for path in glob.glob(os.path.join(a.frames, 'clip_*_*.png')):
        m = re.match(r'clip_(.+)_(\d+)\.png$', os.path.basename(path))
        clips.setdefault(m.group(1), {})[int(m.group(2))] = path
    order = [c for c in ('idle', 'walk', 'talk', 'cast', 'watch') if c in clips] + sorted(set(clips) - {'idle', 'walk', 'talk', 'cast', 'watch'})
    crop = tuple(int(v) for v in a.crop.split(',')) if a.crop else None
    first = Image.open(next(iter(clips[order[0]].values())))
    w, h = (crop[2] - crop[0], crop[3] - crop[1]) if crop else first.size
    cols = max(len(v) for v in clips.values())
    sheet = Image.new('RGB', (w * cols + 70, h * len(order)), (24, 22, 26))
    d = ImageDraw.Draw(sheet)
    for r, clip in enumerate(order):
        d.text((6, r * h + 6), clip, fill=(230, 230, 230))
        for c, i in enumerate(sorted(clips[clip])):
            im = Image.open(clips[clip][i]).convert('RGB')
            if crop:
                im = im.crop(crop)
            sheet.paste(im, (70 + c * w, r * h))
    sheet.save(a.out)
    print('wrote %s: %d clips x %d frames' % (a.out, len(order), cols))


if __name__ == '__main__':
    main()
