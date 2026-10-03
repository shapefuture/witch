#!/usr/bin/env python3
"""Turnaround strip: the exported raccoon.glb next to the raccoon views of the user's reference sheet.

    python tools/characters/raccoon_compare.py SHEET.png OUT.png [--glb assets/characters/raccoon.glb] [--sizes 300 160 100]

SHEET.png is the 1128 x 322 turnaround (witch front/side/back, raccoon front/side/back); it is not in the
repository. Each row shows front, side and back, reference tile then ours, at one figure height (pixels), so
proportions and silhouettes compare directly; the small rows are about the size the character has in the game.
Ours is the GLB itself (tools/characters/glb_preview.py rasterises it flat-shaded), so this checks the export.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_preview as gp  # noqa: E402

# per view: x of the model origin in the sheet, figure top and bottom rows
REF = {'front': (696, 62, 298), 'left side': (847, 62, 298), 'back': (1050, 62, 298)}
WIDTH = {'front': 0.62, 'left side': 1.25, 'back': 0.62}


def row(ref, groups, top, Hc, views):
    m = int(0.06 * Hc)
    H = Hc + 2 * m
    tiles = []
    for v in views:
        W = int(WIDTH[v] * Hc)
        xc, yt, yb = REF[v]
        k = Hc / (yb - yt)
        bw, bh = W / k, H / k
        crop = ref.crop((int(round(xc - bw / 2)), int(round(yt - m / k)), int(round(xc + bw / 2)), int(round(yt - m / k + bh))))
        a = crop.resize((W, H), Image.LANCZOS)
        u = top / Hc
        box = (-W / 2 * u, W / 2 * u, -m * u, (Hc + m) * u)
        b = gp.to_pil(gp.render(groups, gp.VIEWS[v], W, H, box=box, fill=1.0))
        tiles += [(v + ' (sheet)', a), (v + ' (ours)', b)]
    return tiles, H


def silhouettes(ref, groups, top, Hc, views, out):
    """Overlay of the sheet's silhouette (red where only the sheet has it) and ours (green where only ours has it),
    yellow where they agree; prints the intersection over union per view. Origin-aligned, no fitting."""
    import numpy as np
    m = int(0.06 * Hc)
    H = Hc + 2 * m
    bg = np.asarray(ref.convert('RGB')).astype(float)[8:20, 600:640].reshape(-1, 3).mean(0)
    tiles = []
    for v in views:
        W = int(WIDTH[v] * Hc)
        xc, yt, yb = REF[v]
        k = Hc / (yb - yt)
        bw, bh = W / k, H / k
        x0, y0 = int(round(xc - bw / 2)), int(round(yt - m / k))
        crop = ref.crop((x0, y0, x0 + int(round(bw)), y0 + int(round(bh)))).resize((W, H), Image.LANCZOS)
        rm = np.abs(np.asarray(crop).astype(float) - bg).max(2) > 26
        if v == 'left side':
            rm[:, :max(0, int((797 - x0) * k))] = False      # the witch's edge
        u = top / Hc
        box = (-W / 2 * u, W / 2 * u, -m * u, (Hc + m) * u)
        im = gp.render(groups, gp.VIEWS[v], W, H, box=box, fill=1.0, bg=(1, 0, 1))
        om = np.abs(im - np.array([1, 0, 1.0])).max(2) > .05
        both, a, b = rm & om, rm & ~om, om & ~rm
        print('%-10s IoU %.3f   sheet-only %.1f%%  ours-only %.1f%%' % (v, both.sum() / max(1, (rm | om).sum()),
                                                                         100 * a.sum() / max(1, rm.sum()), 100 * b.sum() / max(1, om.sum())))
        img = np.zeros((H, W, 3), np.uint8)
        img[both] = (200, 200, 90)
        img[a] = (230, 60, 60)
        img[b] = (60, 200, 90)
        tiles.append(Image.fromarray(img))
    sheet = Image.new('RGB', (sum(t.width for t in tiles) + 6 * (len(tiles) - 1), H), (24, 24, 26))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width + 6
    sheet.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sheet')
    ap.add_argument('out')
    ap.add_argument('--glb', default='assets/characters/raccoon.glb')
    ap.add_argument('--sizes', type=int, nargs='+', default=[300, 160, 100])
    ap.add_argument('--anim')
    ap.add_argument('--t', type=float, default=0.0)
    ap.add_argument('--overlay_size', type=int, default=300)
    ap.add_argument('--overlay', help='also write the silhouette overlay (and print IoU) to this path')
    a = ap.parse_args()
    ref = Image.open(a.sheet).convert('RGB')
    g = gp.GLB(a.glb)
    groups = gp.groups_from_glb(g, a.anim, a.t)
    import numpy as np
    top = float(np.concatenate([gr['P'].reshape(-1, 3) for gr in groups])[:, 1].max())
    views = ['front', 'left side', 'back']
    if a.overlay:
        silhouettes(ref, groups, top, a.overlay_size, views, a.overlay)
    rows = [row(ref, groups, top, Hc, views) for Hc in a.sizes]
    gap = 6
    width = max(sum(t.width for _, t in tiles) + gap * (len(tiles) - 1) for tiles, _ in rows)
    height = sum(h + 14 for _, h in rows)
    out = Image.new('RGB', (width, height), (30, 30, 32))
    y = 0
    d = ImageDraw.Draw(out)
    for tiles, h in rows:
        x = 0
        for lab, t in tiles:
            out.paste(t, (x, y + 14))
            d.text((x + 2, y + 1), lab, fill=(200, 200, 200))
            x += t.width + gap
        y += h + 14
    out.save(a.out)
    print(a.out, out.size)


if __name__ == '__main__':
    main()
