#!/usr/bin/env python3
"""Joins the crops capture_painted.gd writes (toy_<id>_<n>_<reaction>_<frame>.png) into one sheet per prop:
a row per reaction, a column per frame (about 2 ticks apart).

    python tools/painted/toy_sheet.py CAPTURE_DIR [OUT_DIR] [--scale 2]
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw

NAME = re.compile(r"toy_(.+)_(\d+)_([a-z_]+)_(\d+)\.png$")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("capture_dir")
    parser.add_argument("out_dir", nargs="?")
    parser.add_argument("--scale", type=int, default=2)
    args = parser.parse_args(argv)
    src = Path(args.capture_dir)
    out = Path(args.out_dir) if args.out_dir else src
    out.mkdir(parents=True, exist_ok=True)
    rows = defaultdict(lambda: defaultdict(dict))
    for path in sorted(src.glob("toy_*.png")):
        m = NAME.search(path.name)
        if m:
            prop, turn, reaction, frame = m.group(1), int(m.group(2)), m.group(3), int(m.group(4))
            rows[prop][(turn, reaction)][frame] = path
    for prop, table in rows.items():
        sample = Image.open(next(iter(next(iter(table.values())).values())))
        scale = args.scale if sample.width * args.scale <= 260 else 1
        w, h = sample.width * scale, sample.height * scale
        frames = max(len(r) for r in table.values())
        sheet = Image.new("RGB", (frames * (w + 2) + 90, len(table) * (h + 2)), (24, 24, 24))
        draw = ImageDraw.Draw(sheet)
        for r, ((turn, reaction), cells) in enumerate(sorted(table.items())):
            draw.text((4, r * (h + 2) + 4), reaction, fill=(255, 255, 0))
            for frame, path in sorted(cells.items()):
                im = Image.open(path).convert("RGB").resize((w, h), Image.NEAREST)
                sheet.paste(im, (90 + frame * (w + 2), r * (h + 2)))
        sheet.save(out / ("sheet_%s.png" % prop))
        print("sheet_%s.png %dx%d" % (prop, *sheet.size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
