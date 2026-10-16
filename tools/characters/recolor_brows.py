"""Recolour the witch's brows in ref/witch_face.png to the darker tone of her ash-blond hair.

The face tile is photo-derived, so its brows kept the original orange. Only the brow strokes change: they are the
two large connected runs of saturated orange inside the brow band (rows above the eyelid creases); each pixel's
hue is replaced and its saturation and value are scaled so the median brow pixel lands on the target, keeping the
stroke's own light/dark variation. A one-pixel antialiased rim is blended by how orange it is.

    python3 tools/characters/recolor_brows.py [--src PATH] [--out PATH] [--compare PNG]

It refuses to run on a tile whose brows already carry the target hue, so rerunning it in place changes nothing.
"""
import argparse
import colorsys
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
FACE = os.path.join(HERE, 'ref', 'witch_face.png')

TARGET = (0.60, 0.49, 0.32)           # the hair's darker tone (witch_ref.py FAMILIES['hair'])
BAND = (13, 30)                       # tile rows holding the brows; the eyelid creases start lower and elsewhere
CORE_HUE = (0.06, 0.16)
CORE_SAT = 0.45
RIM_HUE = (0.04, 0.16)
RIM_SAT = (0.30, 0.45)                # rim weight ramps from 0 to 1 across this saturation range
MIN_COMPONENT = 60                    # a brow is hundreds of pixels; stray specks are not brows


def hsv(px):
    return colorsys.rgb_to_hsv(*(c / 255.0 for c in px))


def brow_mask(img):
    w, h = img.size
    px = img.load()
    core = set()
    for y in range(BAND[0], BAND[1]):
        for x in range(w):
            hh, s, _ = hsv(px[x, y])
            if s > CORE_SAT and CORE_HUE[0] < hh < CORE_HUE[1]:
                core.add((x, y))
    keep = set()
    seen = set()
    for start in sorted(core):
        if start in seen:
            continue
        comp, stack = [], [start]
        seen.add(start)
        while stack:
            x, y = stack.pop()
            comp.append((x, y))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (x + dx, y + dy)
                    if n in core and n not in seen:
                        seen.add(n)
                        stack.append(n)
        if len(comp) >= MIN_COMPONENT:
            keep.update(comp)
    weight = {p: 1.0 for p in keep}
    for x, y in keep:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (x + dx, y + dy)
                if n in weight or not (0 <= n[0] < w and 0 <= n[1] < h):
                    continue
                hh, s, _ = hsv(px[n])
                if RIM_HUE[0] < hh < RIM_HUE[1] and s > RIM_SAT[0]:
                    weight[n] = min(1.0, (s - RIM_SAT[0]) / (RIM_SAT[1] - RIM_SAT[0]))
    return weight


def median(vals):
    vals = sorted(vals)
    return vals[len(vals) // 2]


def recolor(img):
    img = img.convert('RGB').copy()
    px = img.load()
    weight = brow_mask(img)
    core = [hsv(px[p]) for p, wt in weight.items() if wt >= 1.0]
    if not core:
        return img, weight
    th, ts, tv = colorsys.rgb_to_hsv(*TARGET)
    if abs(median(c[0] for c in core) - th) < 0.005:
        return img, {}
    ks = ts / median(c[1] for c in core)
    kv = tv / median(c[2] for c in core)
    for p, wt in weight.items():
        r0, g0, b0 = (c / 255.0 for c in px[p])
        _, s, v = colorsys.rgb_to_hsv(r0, g0, b0)
        r1, g1, b1 = colorsys.hsv_to_rgb(th, min(1.0, s * ks), min(1.0, v * kv))
        px[p] = tuple(int(round(255 * (a + (b - a) * wt))) for a, b in ((r0, r1), (g0, g1), (b0, b1)))
    return img, weight


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=FACE)
    ap.add_argument('--out', default=FACE)
    ap.add_argument('--compare', help='write a before/after PNG (enlarged) here')
    a = ap.parse_args()
    before = Image.open(a.src).convert('RGB')
    after, weight = recolor(before)
    after.save(a.out)
    print('%d brow pixels recoloured (%d rim)' % (len(weight), sum(1 for v in weight.values() if v < 1.0)))
    if a.compare:
        w, h = before.size
        k = 5
        sheet = Image.new('RGB', (w * k * 2 + k, h * k), (0, 0, 0))
        sheet.paste(before.resize((w * k, h * k), Image.NEAREST), (0, 0))
        sheet.paste(after.resize((w * k, h * k), Image.NEAREST), (w * k + k, 0))
        sheet.save(a.compare)


if __name__ == '__main__':
    main()
