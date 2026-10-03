#!/usr/bin/env python3
"""Lay candidate captures (tools/characters/capture_candidate.gd) side by side with the painting: python tools/characters/eval_sheet.py OUT_DIR LABEL=CAPTURE_DIR ... [--ref REFERENCE.png]

Writes OUT_DIR/eval_game.png (the room frame at game resolution, PSX on and off: where she is seen, about 100 px tall, from behind) and
OUT_DIR/eval_studio.png (front, back, three-quarter and the raised-arm cast pose of each model alone), one column a candidate, the reference first.
A label may carry facts after a pipe: "cpu int8|9000 tris, 21 bones".
"""
import os
import sys

from PIL import Image, ImageDraw

ROOM_BOX = (655, 448, 805, 648)                   # the witch in the 1280 x 720 room frame (compare_painted.py)
STUDIO_BOX = (380, 40, 900, 720)
CELL_H = 520


def fit(img, h, resample=Image.LANCZOS):
    return img.resize((max(1, round(img.width * h / img.height)), h), resample)


def room_cut(path, psx):
    im = Image.open(path).convert("RGB")
    k = im.width / 1280.0
    box = tuple(round(v * k) for v in ROOM_BOX)
    return fit(im.crop(box), CELL_H, Image.NEAREST if psx else Image.LANCZOS)


def studio_cut(path):
    return fit(Image.open(path).convert("RGB").crop(STUDIO_BOX), CELL_H)


def sheet(columns, rows, title_font_h=44):
    """columns: [(label, facts)], rows: [(row label, [cell image or None per column])]."""
    widths = [max((c.width for c in cells if c is not None), default=10) for cells in zip(*[r[1] for r in rows])]
    pad = 10
    row_h = [max((c.height for c in cells if c is not None), default=10) for _, cells in rows]
    W = sum(widths) + pad * (len(widths) + 1) + 120
    H = title_font_h + sum(row_h) + pad * (len(rows) + 1) + 18 * len(rows)
    out = Image.new("RGB", (W, H), (22, 22, 26))
    d = ImageDraw.Draw(out)
    x = 120 + pad
    for (label, facts), w in zip(columns, widths):
        d.text((x, 6), label, fill=(240, 240, 240))
        d.text((x, 22), facts, fill=(150, 150, 160))
        x += w + pad
    y = title_font_h + pad
    for (rlabel, cells), h in zip(rows, row_h):
        d.text((6, y + h // 2), rlabel, fill=(200, 200, 210))
        x = 120 + pad
        for c, w in zip(cells, widths):
            if c is not None:
                out.paste(c, (x, y))
            x += w + pad
        y += h + pad + 18
    return out


def main(argv):
    out_dir = argv[0]
    ref = None
    items = []
    rest = argv[1:]
    while rest:
        a = rest.pop(0)
        if a == "--ref":
            ref = rest.pop(0)
        else:
            label, _, cap = a.partition("=")
            items.append((label, cap))
    os.makedirs(out_dir, exist_ok=True)
    columns = [tuple((label.split("|") + [""])[:2]) for label, _ in items]
    caps = [c for _, c in items]
    if ref:
        columns.insert(0, ("the painting", "the target look (front)"))
    ref_img = fit(Image.open(ref).convert("RGB"), CELL_H) if ref else None

    def row(name, fn):
        cells = [fn(c) for c in caps]
        return (name, ([ref_img] if ref else []) + cells) if name == "reference" else (name, ([None] if ref else []) + cells)

    game_rows = [("PSX on\n(the game)", ([None] if ref else []) + [room_cut(os.path.join(c, "room_psx.png"), True) for c in caps]),
                 ("PSX off", ([ref_img] if ref else []) + [room_cut(os.path.join(c, "room_raw.png"), False) for c in caps])]
    sheet(columns, game_rows).save(os.path.join(out_dir, "eval_game.png"))
    studio_rows = []
    for view in ("front", "back", "three_quarter", "cast_front"):
        cells = [studio_cut(os.path.join(c, "studio_%s.png" % view)) for c in caps]
        studio_rows.append((view.replace("_", " "), ([ref_img if view == "front" else None] if ref else []) + cells))
    sheet(columns, studio_rows).save(os.path.join(out_dir, "eval_studio.png"))
    print(os.path.join(out_dir, "eval_game.png"), os.path.join(out_dir, "eval_studio.png"))


if __name__ == "__main__":
    main(sys.argv[1:])
