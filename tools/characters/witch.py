#!/usr/bin/env python3
"""The witch (v1): orange paper-strip curls, purple star-studded hood, flower crown, wand,
bird on her hand, pouches with a mouse and other things, embossed stars and moons, and a
photo-projected face plate taken from the concept sheet.

    python tools/characters/witch.py --out assets/characters --refs <dir with the concept art>

builds `witch.glb` and (unless `--only v1`) `witch_antler.glb` via `witch_antler.py`. The concept
art is not in the repository: without `--refs` the face texture is read back out of the GLB
already in `--out`, so the model can be rebuilt anywhere. `--preview DIR` writes six-view and
face close-up PNGs (the idle pose, and the rest pose).

Authoring space: y up, she faces +Z, +X is her left, feet at y=0, about 3.3 units tall. The
export scales so the top of the hood is 1.30 m.
"""
import argparse
import math
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas as atl            # noqa: E402
import face_plate as fp         # noqa: E402
import witch_glb as glb         # noqa: E402
from witch_kit import (A, N_, Grid, Model, blob, bake_uvs, catmull, cres2d, cres3d, disc2d, frame_n,   # noqa: E402
                       loft, poly2d, ringp, rotm, spiral_e, star3d, tube, xf)

HOOD_TOP_M = 1.30
REF_SHEET = 'sheet_witch_raccoon_shadow_tomas.webp'

# Palette, display-referred. Pulled toward the concept sheet: a warmer mauve-violet, peach gold,
# a less saturated orange, a lighter brown vest, pinker flowers.
COL = {'skin': (.87, .68, .60), 'skin_d': (.78, .58, .52),
       'hair': (.88, .53, .23), 'hair_d': (.70, .37, .15), 'hair_l': (.95, .66, .36),
       'purple': (.45, .26, .55), 'purple_d': (.24, .12, .30), 'purple_l': (.54, .34, .62),
       'gold': (.88, .66, .38), 'vest': (.45, .31, .22), 'vest_d': (.26, .19, .15),
       'boot': (.36, .22, .15), 'sole': (.13, .085, .065), 'leg': (.20, .13, .10),
       'silver': (.84, .84, .88), 'chain': (.52, .40, .26),
       'pink': (.90, .56, .64), 'pink_d': (.74, .42, .54), 'leaf': (.42, .32, .50),
       'bird': (.70, .66, .63), 'bird_l': (.86, .84, .80), 'bird_d': (.46, .43, .42), 'bird_h': (.78, .77, .76),
       'bird_w': (.62, .60, .60), 'beak': (.90, .63, .30), 'foot': (.92, .66, .66), 'pupil': (.09, .08, .08),
       'pouch': (.33, .24, .18), 'mouse': (.68, .61, .65), 'mousepink': (.88, .62, .68),
       'parch': (.92, .82, .58), 'parch_d': (.72, .56, .35), 'acorn': (.62, .38, .18), 'gem': (.68, .58, .82),
       'wand': (.82, .60, .66), 'wandstar': (.92, .52, .66), 'feather': (.66, .62, .70), 'orb': (.82, .88, .93)}

# ---- skeleton: she faces +Z, +X is her left. The bird rides on her left hand.
BONES = {'root': (None, (0, 0, 0)), 'hips': ('root', (0, .98, 0)), 'spine': ('hips', (0, 1.3, 0)),
         'neck': ('spine', (0, 2.3, 0)), 'head': ('neck', (0, 2.4, 0)), 'cape': ('spine', (0, 2.2, -.2))}
for _s, _d in ((1, '.L'), (-1, '.R')):
    BONES['arm_upper' + _d] = ('spine', (_s * .26, 2.13, 0))
    BONES['arm_lower' + _d] = ('arm_upper' + _d, (_s * .62, 2.13, 0))
    BONES['hand' + _d] = ('arm_lower' + _d, (_s * .95, 2.13, 0))
    BONES['leg' + _d] = ('hips', (_s * .19, .95, 0))
    BONES['foot' + _d] = ('leg' + _d, (_s * .19, .1, 0))
    BONES['hairB' + _d] = ('head', (_s * .25, 2.30, -.30))
    BONES['hairT' + _d] = ('hairB' + _d, (_s * .55, 1.55, -.36))
BONES['bird'] = ('hand.L', (1.12, 2.17, 0))

# Head space: the head and everything rigid on it is authored at the source's size, then
# scaled about the neck (HEAD_S) for the sheet's big-headed proportions; the torso is then
# shortened (`remap_y`) so the chin sits where the sheet puts it.
HEAD_S = 1.45
PIV = A((0, 2.30, 0))
TORSO = (.98, 2.30, .91)          # y0, y1, factor: [y0, y1] compressed, above shifted down

# head rings (y, rx, rz, cz), fitted to the face window measured off the sheet
HR = [(2.345, .05, .05, .05), (2.37, .105, .09, .05), (2.40, .150, .13, .045), (2.44, .188, .165, .038),
      (2.50, .232, .195, .03), (2.56, .238, .207, .022), (2.64, .235, .212, .016), (2.72, .225, .207, .01),
      (2.80, .19, .19, 0.), (2.86, .12, .13, -.01), (2.90, .04, .05, -.02)]
HEAD_E = 2.2
EYE_D = .231                       # eye spacing; every face measure is a fraction of it
EYE_Y = 2.60
LM = dict(eyeR=(-EYE_D / 2, EYE_Y), eyeL=(EYE_D / 2, EYE_Y), nose=(0, EYE_Y - .45 * EYE_D),
          mouth=(0, EYE_Y - .66 * EYE_D), chin=(0, EYE_Y - 1.04 * EYE_D))

# hood: gabled cowl, now with a peak that leans back (side view of the sheet)
HY = [2.30, 2.42, 2.54, 2.64, 2.72, 2.79, 2.85, 2.91, 2.97, 3.02, 3.06, 3.09]
HRX = [.33, .365, .385, .392, .392, .385, .372, .35, .31, .24, .16, .075]
HCZ = [-.03, -.03, -.035, -.04, -.05, -.06, -.075, -.095, -.13, -.18, -.25, -.33]
HPHI = [96, 74, 60, 52, 42, 28, 0, 0, 0, 0, 0, 0]
HOOD_TIP = (0, 3.10, -.44)


def ring_at(y, table=None):
    t = table or HR
    ys = [h[0] for h in t]
    y = min(max(y, ys[0]), ys[-1])
    for i in range(len(t) - 1):
        if ys[i] <= y <= ys[i + 1]:
            f = (y - ys[i]) / (ys[i + 1] - ys[i])
            return [t[i][k] * (1 - f) + t[i + 1][k] * f for k in (1, 2, 3)]


def head_rx(y):
    return ring_at(y)[0]


def head_front_z(x, y):
    rx, rz, cz = ring_at(y)
    u = min(1., abs(x) / max(rx, 1e-6))
    return cz + rz * max(0., 1 - u ** HEAD_E) ** (1 / HEAD_E)


def hood_pt(y, phi):
    rx = np.interp(y, HY, HRX)
    rz = rx * .93
    cz = np.interp(y, HY, HCZ)
    return A((rx * math.sin(phi), y, cz + rz * math.cos(phi))), A((math.sin(phi) / rx, .35, math.cos(phi) / rz))


def vest_rows():
    return [(.98, .50, .40), (1.25, .43, .34), (1.55, .40, .31), (1.85, .38, .29), (2.12, .37, .26), (2.24, .26, .19)]


def vest_z(x, y):
    rows = vest_rows()
    ys = [r[0] for r in rows]
    rx = np.interp(y, ys, [r[1] for r in rows])
    rz = np.interp(y, ys, [r[2] for r in rows])
    return rz * max(0, 1 - (abs(x) / rx) ** 2.6) ** (1 / 2.6)


def cowl_z(x, y):
    ys = [2.16, 2.265, 2.345]
    rx = np.interp(y, ys, [.46, .32, .17])
    rz = np.interp(y, ys, [.31, .23, .15])
    return rz * max(0, 1 - (abs(x) / rx) ** 2.2) ** (1 / 2.2)


FACE_PAINT = dict(eye_w=.064, eye_h=.034, tilt=.011, iris_r=.038, white=(.92, .91, .87), white_shade=(.70, .68, .68),
                  lid=(.86, .62, .58), lid_shade=(.78, .55, .52), pupil=(.08, .06, .07), lash=(.20, .11, .10), lash_w=.0085,
                  lower_lid=(.66, .44, .42), brow=(.72, .44, .22), brow_d=(.52, .30, .16), brow_dy=.083,
                  lip_up=(.84, .46, .43), lip_lo=(.91, .57, .52), lip_line=(.58, .27, .27), lip_hi=(1., .80, .76),
                  # light grey-violet iris, as in the sheet: outer ring, body, inner
                  iris=((.42, .38, .54), (.60, .56, .72), (.75, .71, .85)))


def face_spec(refs):
    """Landmarks on the sheet's front view (top left), pixels at the original 1197x668 size."""
    return fp.FaceSpec(os.path.join(refs, REF_SHEET) if refs else None,
                       dict(eyeR=(150.4, 92.3), eyeL=(176.9, 100.4), nose=(161.9, 108.75),
                            mouth=(159.6, 113.6), chin=(162.5, 125.2)),
                       LM, (-.26, .26, 2.33, 2.87), (176, 184), 'her_right', COL['skin'], COL['hair'],
                       hairline=2.79, paint=FACE_PAINT)


# ======================================================================================================
def build_parts(M, face_tex_name='face', spec=None):
    rnd = random.Random(11)
    P = M.P
    add, patch, place, stamp = M.add, M.patch, M.place, M.stamp

    # ===== boots & legs: under the floor-length skirt; kept for the walk, kept cheap
    for s, d in ((1, '.L'), (-1, '.R')):
        bx = s * .19
        foot = loft([((bx, cy, z), (rx, 0, 0), (0, ry, 0)) for z, rx, ry, cy in
                     ((-.15, .10, .065, .075), (0, .125, .11, .10), (.16, .13, .09, .08), (.30, .095, .055, .055))], 8, 2.4, cap=(.03, .05), j=.005)
        add(foot, 'boot', bone='foot' + d)
        sole = loft([((bx, .02, z), (rx, 0, 0), (0, .022, 0)) for z, rx in ((-.15, .092), (0, .117), (.15, .122), (.29, .088))], 8, 2.4, cap=(.02, .03))
        add(sole, 'sole', bone='foot' + d)
        shaft = loft([((bx, y, -.01), (rx, 0, 0), (0, 0, rx)) for y, rx in ((.08, .115), (.30, .11))], 8, 2.2, cap=(0, 0))
        add(shaft, 'boot', bone='foot' + d)
        leg = loft([((bx, .28, 0), (.075, 0, 0), (0, 0, .075)), ((bx, 1.0, 0), (.09, 0, 0), (0, 0, .09))], 6, 2., cap=(0, 0))
        add(leg, 'leg', bone='leg' + d)

    # ===== skirt: wide floor-length cone (the sheet's hem is two thirds of her height), 12 facets
    NS = 12
    sk = Grid([ringp(.98, .47, .40, 0, NS, 2., .5), ringp(.52, .80, .67, 0, NS, 2., .5), ringp(.07, 1.08, .90, 0, NS, 2., .5)],
              True, [(0, .98, 0), (0, .52, 0), (0, .07, 0)])
    add(sk.part(), 'purple', bone='hips')
    add(sk.part(True, .016), 'purple_d', bone='hips')
    add(M.grid_rim(sk, .016), 'purple', bone='hips')
    kinds = ['m', 's6', 's5', 's6', 'm', 's4']
    for m in range(NS):
        for r in (0, 1):
            rows = ((.30, .55), (.75, .5)) if r == 0 else ((.22, .5), (.58, .45), (.88, .5))
            for k_, (fv, fu) in enumerate(rows):
                fu = fu + (.18 if (m + k_) % 2 else -.18) + rnd.uniform(-.06, .06)
                kd = kinds[(m * 3 + k_ + r) % len(kinds)]
                sz = (.055 if r == 0 else .068) * (1.1 if kd == 'm' else 1.)
                stamp(sk, r, m, fu, fv, kd, sz, rnd.uniform(-1, 1) * (.8 if kd == 'm' else .3), bone='hips', off=.009, lo=True)

    # ===== vest / tunic, wider than the source so the torso reads as the sheet's
    vr = vest_rows() + [(2.30, .0, .0)]
    vg = Grid([ringp(y, rx, rz, 0, 12, 2.6, -.5) for y, rx, rz in vr], True, [(0, .98, 0), (0, 2.3, 0)])
    vg.ax = A([(0, y, 0) for y in np.linspace(.98, 2.10, 10)])
    add(vg.part(), 'vest', bone='spine')
    # hem band where the vest overlaps the skirt
    hem = Grid([ringp(1.03, .505, .405, 0, 12, 2.6, -.5), ringp(.95, .52, .42, 0, 12, 2.6, -.5)], True, [(0, 1.05, 0), (0, .93, 0)])
    add(hem.part(), 'vest_d', bone='spine')

    # pouches, sitting on the wider vest
    PX = .31
    PZ = vest_z(PX, 1.32) - .02
    for (cx, rx, ry, cy) in ((-PX, .20, .19, 1.32), (PX, .20, .185, 1.31)):
        if cx > 0:
            fl = loft([((cx, cy + ry * .42, PZ + z), (rx * 1.05 * q, 0, 0), (0, ry * .62 * q, 0)) for z, q in ((.0, 1.0), (.10, 1.0), (.165, .95), (.195, .80))], 8, 2.5, cap=(0, .014), j=.012)
            add(fl, 'pouch', bone='spine')
        pch = loft([((cx, cy, PZ + z), (rx * q, 0, 0), (0, ry * q, 0)) for z, q in ((-.02, 1.0), (.08, 1.0), (.145, .94), (.175, .78))], 8, 2.5, cap=(0, .03), j=.02)
        add(pch, 'pouch', bone='spine')
    dz = PZ - .22                       # contents were authored for a pouch front at z=.22
    k0 = len(P)

    def feather(base, ang, ln, w, mat='feather'):
        base = A(base, float)
        prt = [(tube([base, base + A((0, ln, 0))], [.005, .003], 3, 1., (0, 0, 1), cap=(.0, .012)), 'chain')]
        for i in range(4):
            y = base[1] + ln * (.22 + .18 * i)
            sc = 1 - .16 * i
            for sg in (1, -1):
                b = blob((base[0] + sg * w * .5 * sc, y + .012, base[2]), (w * .55 * sc, .03, .004), (0, 1, 0), 4, 2)
                xf(b, rotm((0, 0, 1), -sg * 38), (base[0], y, base[2]))
                prt.append((b, mat))
        prt.append((blob(base + A((0, ln, 0)), (.011, .03, .004), (0, 1, 0), 4, 2), mat))
        for p_, m_ in prt:
            xf(p_, rotm((0, 0, 1), ang), base)
            add(p_, m_, bone='spine')
    # LEFT pouch (her right, -X): mouse with paws on the rim, spoon, two barbed feathers, cord
    mx = -PX + .035
    add(blob((mx, 1.50, .29), (.052, .07, .05), (0, 1, .15), 6, 3), 'mouse', bone='spine')
    add(blob((mx, 1.60, .325), (.043, .048, .045), (0, .5, 1), 6, 3), 'mouse', bone='spine')
    add(blob((mx, 1.588, .378), (.02, .02, .02), (0, 0, 1), 5, 2), 'mousepink', bone='spine')
    for sg in (1, -1):
        add(blob((mx + sg * .042, 1.655, .318), (.036, .008, .036), (0, 0, 1), 6, 2), 'mousepink', bone='spine')
        add(blob((mx + sg * .02, 1.612, .372), (.007, .007, .007), (0, 1, 0), 4, 2), 'pupil', bone='spine')
        add(blob((mx + sg * .03, 1.462, .375), (.014, .012, .02), (0, 0, 1), 4, 2), 'mousepink', bone='spine')
    sp = tube([(-PX - .07, 1.47, .28), (-PX - .085, 1.56, .285), (-PX - .095, 1.64, .29)], [.013, .008], 4, 1., (0, 0, 1))
    add(sp, 'silver', bone='spine')
    bowl = blob((-PX - .105, 1.72, .29), (.06, .015, .09), (0, 0, 1), 6, 2)
    add(bowl, 'silver', bone='spine')
    xf(bowl, rotm((0, 0, 1), -14), (-PX - .07, 1.5, .29))
    xf(sp, rotm((0, 0, 1), -14), (-PX - .07, 1.5, .29))
    feather((-PX - .14, 1.46, .27), 58, .2, .05)
    feather((-PX + .20, 1.47, .27), -16, .24, .055)
    # RIGHT pouch (her left): leather hat, map, glass orb, purple crystal, buckle strap
    add(blob((PX, 1.535, .31), (.08, .065, .08), (0, 1, 0), 7, 3, .004), 'acorn', bone='spine')
    add(blob((PX, 1.575, .31), (.055, .02, .055), (0, 1, 0), 7, 2), 'vest_d', bone='spine')
    mp = [(PX + .04, 1.36, .40), (PX + .17, 1.40, .38), (PX + .18, 1.55, .36), (PX + .05, 1.50, .385), (PX + .11, 1.455, .395)]
    patch([mp[0], mp[1], mp[4], mp[3]], [(0, 1, 2), (0, 2, 3)], (0, .2, 1), 'parch', bone='spine')
    patch([mp[1], mp[2], mp[4]], [(0, 1, 2)], (0, .2, 1), 'parch_d', bone='spine')
    add(blob((PX - .11, 1.555, .30), (.04, .04, .04), (0, 1, 0), 6, 3), 'orb', bone='spine')
    add(blob((PX - .065, 1.49, .335), (.022, .05, .022), (.3, 1, .2), 5, 2), 'gem', bone='spine')
    V2, F = poly2d([(-.014, .13), (.014, .13), (.014, -.13), (-.014, -.13)])
    place(V2, F, A((PX - .035, 1.36, .452)), (1, 0, 0), (0, 1, 0), (0, 0, 1), 1., 0., .004, 'vest_d', 'spine')
    V2, F = poly2d([(-.035, -.03), (.035, -.03), (.035, .03), (-.035, .03)])
    place(V2, F, A((PX - .035, 1.24, .452)), (1, 0, 0), (0, 1, 0), (0, 0, 1), 1., 0., .006, 'gold', 'spine')
    for p_ in P[k0:]:
        p_['V'] = p_['V'] + A((0, .03, dz))
        p_['ax'] = p_['ax'] + A((0, .03, dz))

    # vest trinkets
    for sx in (-1, 1):
        V2, F = cres3d(.045, 6, h=.006)
        place(V2, F, A((sx * .17, 2.07, vest_z(sx * .17, 2.07))), (1, 0, 0), (0, 1, 0), (0, .05, 1), 1., (.5 if sx > 0 else -.5) + (math.pi if sx < 0 else 0), .011, 'gold', 'spine')
    # chains + crescent pendant
    for (hw, cy0, cy1) in ((.21, 2.31, 2.08), (.27, 2.27, 2.0)):
        pts = [(x, cy1 + (cy0 - cy1) * (x / hw) ** 2,
                max(vest_z(x, cy1 + (cy0 - cy1) * (x / hw) ** 2), cowl_z(x, cy1 + (cy0 - cy1) * (x / hw) ** 2)) + .03) for x in np.linspace(-hw, hw, 7)]
        add(tube(pts, [.012], 4, 1., (0, 0, 1), cap=(.005, .005)), 'chain', bone='spine')
    cv, cf = cres2d(.15)
    zc = vest_z(0, 1.89) + .03
    n = len(cv) // 2

    def rot2(pts, ang):
        c_, s_ = math.cos(ang), math.sin(ang)
        return [(x * c_ - y * s_, y * c_ + x * s_) for x, y in pts]
    lp = rot2(cv, math.radians(35))
    FV = [(x, y + 1.89, zc + .016) for x, y in lp] + [(x, y + 1.89, zc - .016) for x, y in lp]
    m2 = len(lp)
    F = []
    for k in range(n - 1):
        F += [(k, k + 1, n + k + 1), (k, n + k + 1, n + k)]
    Ff = [(a, b, c) for a, b, c in F]
    Fb = [(a + m2, c + m2, b + m2) for a, b, c in F]
    lpi = list(range(n)) + list(range(2 * n - 1, n - 1, -1))
    Fs = []
    for i in range(len(lpi)):
        a, b = lpi[i], lpi[(i + 1) % len(lpi)]
        Fs += [(a, b, b + m2), (a, b + m2, a + m2)]
    axs = [A(((FV[k][0] + FV[n + k][0]) / 2, (FV[k][1] + FV[n + k][1]) / 2, zc)) for k in range(n)]
    add(dict(V=A(FV), F=A(Ff + Fb + Fs, int), ax=A(axs), fb=None), 'silver', bone='spine')

    # ===== cowl / lapels
    cg = Grid([ringp(2.345, .17, .15, 0, 12, 2.2, -.5), ringp(2.265, .32, .23, 0, 12, 2.2, -.5), ringp(2.16, .46, .31, 0, 12, 2.2, -.5)],
              True, [(0, 2.4, 0), (0, 2.15, 0)])
    add(cg.part(), 'purple', bone='spine')
    for sx in (1, -1):
        patch([(-sx * .17, 2.33, .19), (-sx * .09, 2.33, .192), (sx * .17, 2.17, .27), (sx * .09, 2.17, .272)], [(0, 1, 2), (0, 2, 3)], (0, .35, 1), 'purple_l', 'spine')

    # ===== cape: flat-faceted trapezoid down the back (mostly under the hair)
    cy = [2.24, 1.62, .95]
    crx = [.40, .60, .76]
    ccz = [-.05, -.08, -.10]
    cap = Grid([[(rx * math.sin(math.radians(p)), y, cz + rx * .74 * math.cos(math.radians(p))) for p in np.linspace(106, 254, 7)]
                for y, rx, cz in zip(cy, crx, ccz)], False, [(0, y, cz) for y, cz in zip(cy, ccz)])
    add(cap.part(), 'purple', bone='cape')
    add(cap.part(True, .014), 'purple_d', bone='cape')
    add(M.grid_rim(cap, .014), 'purple', bone='cape')
    for c in range(6):
        for fu, fv in ((rnd.uniform(.35, .62), rnd.uniform(.40, .55)), (rnd.uniform(.35, .65), rnd.uniform(.72, .86))):
            stamp(cap, 1, c, fu, fv, rnd.choice(['m', 's6', 's5']), rnd.uniform(.045, .06), rnd.uniform(-1.3, 1.3), bone='cape', off=.013, lo=True)

    # ===== sleeves (bell-shaped), cuffs and hands
    for s, d in ((1, '.L'), (-1, '.R')):
        xs = [.22, .50, .76, .97]
        ry = [.09, .125, .17, .21]
        rz = [.11, .12, .14, .16]
        rows = [[(s * x, 2.13 + a * math.sin(2 * math.pi * (k - .5) / 8), b * math.cos(2 * math.pi * (k - .5) / 8)) for k in range(8)] for x, a, b in zip(xs, ry, rz)]
        sg = Grid(rows, True, [(s * x, 2.13, 0) for x in xs])
        sp = sg.part()
        J, W = M.chainw(np.abs(sp['V'][:, 0]), [.62, .95], ['arm_upper' + d, 'arm_lower' + d, 'hand' + d], [.12, .06])
        add(sp, 'purple', J, W)
        inner = sg.part(True, .012)
        J, W = M.chainw(np.abs(inner['V'][:, 0]), [.62, .95], ['arm_upper' + d, 'arm_lower' + d, 'hand' + d], [.12, .06])
        add(inner, 'purple_d', J, W)
        cuff = [(s * .955, 2.13, 0)] + [tuple(A(p) * (1, 1, 1) - A((s * .02, 0, 0))) for p in rows[-1]]
        patch(cuff, [(0, 1 + k, 1 + (k + 1) % 8) for k in range(8)], (s, 0, 0), 'purple_d', 'arm_lower' + d)
        dec = [(1, 0, 'm', .075, .5, .62), (2, 1, 's6', .06, .5, .5), (1, 2, 's5', .05, .5, .5), (2, 3, 'm', .06, .5, .5),
               (1, 4, 'm', .07, .5, .6), (2, 5, 's6', .055, .5, .5), (2, 7, 's5', .05, .5, .5), (0, 2, 's4', .04, .5, .55)]
        for (r, c, k, sz, fu, fv) in dec:
            stamp(sg, r, c, fu, fv, k, sz, (.4 if k == 'm' else 0) + rnd.uniform(-.3, .3), up=(s * 1., 0, 0) if c in (2, 6) else (0, 1, 0),
                  bone=('arm_upper' + d if r < 2 else 'arm_lower' + d), off=.009, lo=True)
    build_hands_wand(M)

    # ===== bird: songbird standing on the back of her left hand, beak along +Z in rest
    build_bird(M, A((1.12, 2.155, 0)), face=(0, 0, 1))

    # ===== neck & head (head space; scaled about PIV at the end)
    add(loft([((0, 2.22, 0), (.07, 0, 0), (0, 0, .07)), ((0, 2.38, .01), (.062, 0, 0), (0, 0, .062))], 7, 2., cap=(0, 0)), 'skin', bone='head')
    head = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in HR], 14, HEAD_E, cap=(.02, .04))
    add(head, 'skin', bone='head')
    # ---- the face: photo-projected plate (replaces the painted-polygon decal face)
    if spec is not None:
        ys = [2.36, 2.375, 2.39, 2.41, 2.43, 2.45, 2.47, 2.49, 2.51, 2.535, 2.56, 2.585, 2.61, 2.64, 2.67, 2.70, 2.74, 2.78]
        fs = [-.95, -.78, -.6, -.42, -.26, -.12, 0, .12, .26, .42, .6, .78, .95]
        pl = fp.plate(spec, head_rx, head_front_z, ys, fs, edge_off=.004, lift=.007)
        add(pl, 'skin', bone='head', tex=face_tex_name)

    # ===== hood: gabled cowl leaning back to a peak; lined; star-studded
    Hm = []
    for y, rx, cz, ph in zip(HY, HRX, HCZ, HPHI):
        amp = .022 * min(1, max(0, (y - 2.78) / .3))
        row = []
        for c in range(13):
            p = math.radians(ph + (360 - 2 * ph) * c / 12)
            row.append((rx * math.sin(p), y + amp * math.cos(2 * p), cz + rx * .93 * math.cos(p)))
        Hm.append(row)
    hg = Grid(Hm, False, [(0, y, cz) for y, cz in zip(HY, HCZ)])
    hg.ax = A([(0, y, z) for y, z in zip(np.linspace(2.30, 2.95, 12), np.linspace(-.03, -.14, 12))])
    add(hg.part(), 'purple', bone='head')
    add(hg.part(True, .012), 'purple_d', bone='head')
    add(M.grid_rim(hg, .012), 'purple', bone='head')
    top = hg.P[-1]
    tip = A(HOOD_TIP)
    patch([tip] + [tuple(p) for p in top], [(0, 1 + k, 1 + (k + 1) % len(top)) for k in range(len(top))], (0, .6, -1), 'purple', 'head')
    for (r, c, k, sz) in ((3, 1, 's6', .045), (5, 2, 'm', .045), (2, 6, 'm', .045), (3, 5, 's6', .045), (3, 8, 's5', .04), (4, 6, 's6', .05),
                          (4, 9, 'm', .05), (4, 3, 's5', .045), (5, 6, 'm', .05), (6, 6, 's6', .05), (6, 3, 'm', .045), (6, 9, 's5', .04),
                          (7, 6, 'm', .045), (8, 6, 's5', .035), (5, 11, 's5', .035), (1, 6, 's6', .045), (8, 4, 's4', .04), (8, 8, 's4', .04)):
        stamp(hg, r, c, .5, .5, k, sz, rnd.uniform(-1, 1), bone='head', off=.016, lo=True)

    # ===== flower crown along the hood's face edge
    for i, ph in enumerate(np.linspace(-80, 80, 9)):
        p = math.radians(ph)
        yr = float(np.interp(abs(ph), HPHI[:7][::-1], HY[:7][::-1])) + .03
        pos, nn = hood_pt(yr, p)
        nn = N_(nn)
        rr = .10 if i == 4 else (.082 if i % 2 else .072)
        t1, t2, n = frame_n(nn)
        for ln in (-1, 1):
            V2, F = poly2d([(0, 0), (ln * .05, .03), (ln * .11, .0), (ln * .05, -.03)])
            place(V2, F, pos, t1, t2, n, rr / .07, 0, .014, 'leaf', 'head')
        for k in range(5):
            a = math.radians(90 + 72 * k + (15 if i % 2 else 0))
            tip_ = (rr * math.cos(a), rr * math.sin(a))
            l_ = (rr * .6 * math.cos(a - .55), rr * .6 * math.sin(a - .55))
            r_ = (rr * .6 * math.cos(a + .55), rr * .6 * math.sin(a + .55))
            V = [pos + n * .03, pos + t1 * l_[0] + t2 * l_[1] + n * .02, pos + t1 * tip_[0] + t2 * tip_[1] + n * .015, pos + t1 * r_[0] + t2 * r_[1] + n * .02]
            patch(V, [(0, 1, 2), (0, 2, 3)], n, ('pink' if (k + i) % 2 == 0 else 'pink_d'), 'head')
        V2, F = disc2d(rr * .26, 5)
        place(V2, F, pos, t1, t2, n, 1., 0, .036, 'gold', 'head')

    build_hair(M)

    # head scale about the neck, then the shorter torso
    for p in M.parts_on('head'):
        p['V'] = (p['V'] - PIV) * HEAD_S + PIV
        p['ax'] = (p['ax'] - PIV) * HEAD_S + PIV
    remap_y(M, *TORSO)
    return M


def build_hands_wand(M):
    add = M.add
    # right hand (-X): fist, finger bars, thumb, wand through the fingers
    add(blob((-1.0, 2.13, -.005), (.056, .074, .062), (0, 1, 0), 7, 3, .002, 3.0), 'skin', bone='hand.R')
    for yy in (2.175, 2.135, 2.095, 2.055):
        add(blob((-1.08, yy, .02), (.052, .0155, .042), (0, 1, 0), 5, 2, .0, 3.), 'skin', bone='hand.R')
    add(blob((-1.045, 2.222, .03), (.04, .03, .036), (.6, 1, .3), 5, 2), 'skin', bone='hand.R')
    wd = tube([(-.998, 1.98, .055), (-1.20, 2.49, .055)], [.016, .013], 5, 1., (0, 0, 1), cap=(.01, .012))
    add(wd, 'wand', bone='hand.R')
    sv = [(0, 0, .045)] + [((.13 if k % 2 == 0 else .058) * math.cos(math.pi / 2 + k * math.pi / 5), (.13 if k % 2 == 0 else .058) * math.sin(math.pi / 2 + k * math.pi / 5), 0) for k in range(10)] + [(0, 0, -.045)]
    sF = [(0, 1 + k, 1 + (k + 1) % 10) for k in range(10)] + [(11, 1 + (k + 1) % 10, 1 + k) for k in range(10)]
    sv = [(x - 1.215, y + 2.58, z + .055) for x, y, z in sv]
    add(dict(V=A(sv), F=A(sF, int), ax=A([(-1.215, 2.58, .055)]), fb=None), 'wandstar', bone='hand.R')
    # left hand (+X): flat slab of joined fingers, separate thumb; the bird stands on it
    add(loft([((.95, 2.128, 0), (0, .032, 0), (0, 0, .062)), ((1.06, 2.12, 0), (0, .030, 0), (0, 0, .07)), ((1.18, 2.105, 0), (0, .024, 0), (0, 0, .062)),
              ((1.30, 2.083, 0), (0, .012, 0), (0, 0, .03))], 7, 2.4, cap=(.03, .014), j=.002), 'skin', bone='hand.L')
    add(blob((1.09, 2.075, .075), (.017, .05, .018), (.7, -.6, .4), 5, 2), 'skin', bone='hand.L')


def build_bird(M, bs, face=(0, 0, 1), sc=1.1):
    """Upright songbird: pale head, folded wings, tail swept up and back, pink feet.
    Authored with the beak along -X (the source), then turned so it looks along `face`."""
    k0 = len(M.P)

    def bb(m, c, r, d=(0, 1, 0), N=7, k=3):
        M.add(blob(bs + A(c) * sc, tuple(x * sc for x in r), d, N, k), m, bone='bird')
    bb('bird', (.005, .10, 0), (.062, .088, .056), (-.05, 1, 0), 7, 4)
    bb('bird_l', (-.03, .085, .0), (.046, .066, .040), (-.04, 1, 0), 6, 3)
    bb('bird_h', (-.03, .205, .004), (.05, .05, .048), (0, 1, 0), 7, 3)
    bb('beak', (-.085, .196, .006), (.016, .03, .016), (-1, -.15, 0), 4, 2)
    for sg in (1, -1):
        bb('pupil', (-.057, .214, sg * .04), (.008, .008, .006), (0, 0, sg), 4, 2)
        bb('bird_w', (.02, .09, sg * .052), (.024, .088, .014), (.2, -1, 0), 5, 3)
        bb('bird_d', (.05, .03, sg * .058), (.008, .03, .006), (.5, -1, 0), 4, 2)
        M.add(tube([bs + A((-.005, .045, sg * .022)) * sc, bs + A((-.005, .0, sg * .022)) * sc], [.006, .006], 4, 1., (0, 0, 1), cap=(.003, .003)), 'foot', bone='bird')
    bb('bird_w', (.118, .15, 0), (.036, .095, .006), (.8, .6, 0), 5, 2)
    bb('bird_w', (.098, .135, 0), (.028, .078, .005), (.7, .7, 0), 4, 2)
    # beak was -X: turn about the bird's feet so it looks along `face`
    f = N_(face)
    ang = math.degrees(math.atan2(-f[2], f[0])) - 180.
    R = rotm((0, 1, 0), ang)
    for p in M.P[k0:]:
        xf(p, R, bs)


def hairmat(R, mats=('hair_d', 'hair')):
    return [mats[0]] * (R // 3) + [mats[1]] * (R - R // 3)


def wavy(pts, nd, amp, fr, axis=0):
    pts = [list(p) for p in pts]
    for i in range(min(nd, len(pts))):
        pts[i][axis] += math.sin(fr * i) * amp * min(1, i / 4.)
    return pts


def rcurve(Mn, r0, r1, swell=.10, fr=.6, pw=.85):
    return [(r0 + (r1 - r0) * (i / (Mn - 1)) ** pw) * (1 + swell * math.sin(fr * i)) for i in range(Mn)]


def hair_lock(M, pts, rad, s, bone, chain=False, ratio=.5):
    """A flat paper-strip ribbon along `pts` (x mirrored by s), root darker than the rest."""
    pts = A(pts, float)
    pts[:, 0] *= s
    R = len(pts)
    tb = tube(pts, rad, 4, ratio, (0, 0, 1), cap=(.05, rad[-1] * 2.6), e=2., o=.5)
    if chain:
        d = '.L' if s > 0 else '.R'
        J, W = M.chainw(tb['rid'] / (R - 1), [.45], ['hairB' + d, 'hairT' + d], [.25])
        M.add(tb, hairmat(R), J, W)
    else:
        M.add(tb, hairmat(R), bone=bone)


def hair_face(M, s, lock):
    """Head-space hair around the face: cheek ringlet, side curtain, fringe, temple curls."""
    d = [(.235, 2.80, .12), (.25, 2.70, .15), (.262, 2.60, .165), (.255, 2.50, .16), (.28, 2.40, .15), (.33, 2.32, .13)]
    pts = list(catmull(d, 3))
    pts = wavy(pts, len(pts), .008, .8)
    pts += spiral_e(pts[-1], (.42, 2.29), .08, .08, 1.3, 1, 9, (-.03 if s > 0 else .08))
    lock(pts, rcurve(len(pts), .10, .04, .10, .7, .7), s, 'head', False, .5)
    # side curtain: hair filling the gap between the face and the hood's edge
    d = [(.27, 2.80, .02), (.30, 2.66, .06), (.31, 2.52, .07), (.31, 2.40, .04), (.33, 2.31, -.01)]
    lock(catmull(d, 2), [.07, .09, .09, .08, .05], s, 'head', False, .45)
    # fringe band under the flower crown
    d = [(.0, 2.83, .195), (.09, 2.815, .205), (.17, 2.775, .205), (.225, 2.70, .195)]
    lock(catmull(d, 2), [.02, .05, .05, .03], s, 'head', False, .4)
    # temple curls growing from behind the hood
    d = [(.25, 2.58, -.02), (.29, 2.69, -.06), (.31, 2.78, -.08)]
    pts = list(catmull(d, 2))
    pts += spiral_e(pts[-1], (.415, 2.82), .10, .10, 1.2, -1, 9, -.03)
    lock(pts, rcurve(len(pts), .115, .035), s, 'head', False, .5)
    d = [(.30, 2.50, -.06), (.36, 2.55, -.07), (.42, 2.58, -.07)]
    pts = list(catmull(d, 2))
    pts += spiral_e(pts[-1], (.50, 2.49), .10, .10, 1.25, 1, 9, -.04)
    lock(pts, rcurve(len(pts), .105, .032), s, 'head', False, .5)


def build_hair(M):
    """Flat paper-strip ribbons: fringe, cheek ringlets and side curls (rigid on the head, head
    space), and the mass of back locks ending in spirals (chained hairB -> hairT, model space)."""
    def lock(pts, rad, s, bone, chain=False, ratio=.5):
        hair_lock(M, pts, rad, s, bone, chain, ratio)

    def cz(x, y, off):
        """z just behind the cape's back surface at (x, y), lifted `off`."""
        rx = float(np.interp(-y, [-2.24, -1.62, -.95], [.40, .60, .76]))
        c = float(np.interp(-y, [-2.24, -1.62, -.95], [-.05, -.08, -.10]))
        u = min(abs(x) / rx, .96)
        return c - .74 * rx * math.sqrt(1 - u * u) - off

    def onback(pts, off):
        return [(x, y, cz(x, y, off)) for x, y in pts]

    for s in (1, -1):
        # --- back locks (model space): from under the hood down the back, spiral ends
        # big outer ribbon, faceted elliptical spiral at the hip
        d = [(.40, 2.30, -.36), (.50, 2.14, -.40), (.60, 1.96, -.42), (.68, 1.78, -.42), (.72, 1.60, -.40), (.70, 1.46, -.38)]
        pts = list(catmull(d, 2))
        pts = wavy(pts, len(pts), .02, .9)
        pts += spiral_e(pts[-1], (.92, 1.56), .23, .30, 1.45, 1, 11, -.24)
        lock(pts, rcurve(len(pts), .20, .05), s, None, True, .42)
        # second ribbon, lower spiral
        d = [(.30, 2.28, -.40), (.40, 2.08, -.44), (.47, 1.84, -.46), (.51, 1.60, -.45), (.53, 1.40, -.43)]
        pts = list(catmull(d, 2))
        pts = wavy(pts, len(pts), -.018, 1.1)
        pts += spiral_e(pts[-1], (.70, 1.24), .16, .16, 1.3, 1, 10, -.38)
        lock(pts, rcurve(len(pts), .13, .04), s, None, True, .5)
        # inner locks covering the spine of the back
        d = onback([(.10, 2.26), (.12, 2.02), (.14, 1.76), (.16, 1.52), (.18, 1.30)], .05)
        pts = list(catmull(d, 2))
        pts += spiral_e(pts[-1], (.30, 1.20), .12, .12, 1.2, 1, 8, d[-1][2] - .02)
        lock(pts, rcurve(len(pts), .16, .04), s, None, True, .45)
        d = onback([(.24, 2.28), (.29, 2.08), (.34, 1.88), (.38, 1.70)], .06)
        pts = list(catmull(d, 2))
        pts += spiral_e(pts[-1], (.50, 1.60), .10, .11, 1.2, -1, 7, d[-1][2] - .02)
        lock(pts, rcurve(len(pts), .15, .04), s, None, True, .45)

        hair_face(M, s, lock)


def remap_y(M, y0, y1, k):
    """Compress [y0, y1] by k and shift everything above down; bones follow."""
    def f(y):
        y = np.asarray(y, float)
        return np.where(y <= y0, y, np.where(y <= y1, y0 + (y - y0) * k, y - (y1 - y0) * (1 - k)))
    for p in M.P:
        p['V'] = p['V'].copy()
        p['V'][:, 1] = f(p['V'][:, 1])
        p['ax'] = p['ax'].copy()
        p['ax'][:, 1] = f(p['ax'][:, 1])
    for n, (par, h) in list(M.B.items()):
        M.B[n] = (par, (h[0], float(f(h[1])), h[2]))


# ======================================================================================================
# Poses and clips. Rest is the T-pose; every clip keys every bone.
def aim(a, b):
    """Minimal rotation taking direction a to direction b."""
    a, b = N_(a), N_(b)
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else rotm((0, 1, 0), 180)
    K = A([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def arm_pose(side, upper, lower, hand_world=None, twist=0.):
    """World directions for the upper arm and forearm (+ optional hand world rotation)
    -> local rotations for arm_upper, arm_lower, hand. `twist` rolls the whole arm (deg)."""
    d = '.L' if side > 0 else '.R'
    rest = A((side, 0, 0.))
    Ru = aim(rest, upper) @ rotm(rest, twist)
    Rl = aim(rest, lower) @ rotm(rest, twist)
    Rh = Rl if hand_world is None else hand_world
    return {'arm_upper' + d: Ru, 'arm_lower' + d: Ru.T @ Rl, 'hand' + d: Rl.T @ Rh}


def combine(*dicts):
    out = {}
    for dct in dicts:
        for k, v in dct.items():
            out[k] = out[k] @ v if k in out else v
    return out


def rx_(d):
    return glb.rot((1, 0, 0), d)


def ry_(d):
    return glb.rot((0, 1, 0), d)


def rz_(d):
    return glb.rot((0, 0, 1), d)


def base_pose(t=0., breathe=0.):
    """The sheet's pose: wand up in her right hand, the bird held up on her left hand."""
    R = arm_pose(-1, (-.50, -.84, .20), (-.42, .22, .88), twist=0.)
    L = arm_pose(1, (.36, -.88, .30), (.30, .25, .92), hand_world=ry_(-80) @ rz_(6))
    return combine(R, L)


def clip_set(M, base=None, extra=None):
    """idle, walk, talk, cast. `base()` gives the arm pose; `extra(name, t, r)` adds bones."""
    base = base or base_pose
    names = M.names
    S = math.sin
    tau = 2 * math.pi

    def full(r, name=None, t=0.):
        if extra and name:
            extra(name, t, r)
        for n in names:
            r.setdefault(n, np.eye(3))
        return r

    def idle(t):
        p = t / 4.0
        r = dict(base())
        r['spine'] = rx_(1.2 * S(tau * p)) @ rz_(.6 * S(tau * p * 2 + .4))
        r['neck'] = ry_(4 * S(tau * p - .3))
        r['head'] = rz_(3 * S(tau * p + .8)) @ rx_(1.5 * S(tau * p * 2))
        r['cape'] = rx_(2.5 * S(tau * p - .5))
        r['bird'] = ry_(-25 + 18 * S(tau * p * 2 + 1.0))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 2.5 * S(tau * p + .2))
            r['hairT' + d] = rz_(sg * 4 * S(tau * p - .4)) @ rx_(2 * S(tau * p))
            r['arm_upper' + d] = r['arm_upper' + d] @ rx_(1.5 * S(tau * p + .3 * sg))
        return full(r, 'idle', t), {'hips': (0, .006 * S(tau * p * 2), 0)}

    def walk(t):
        p = t / 1.0                      # one full cycle (two steps) per second, in place
        ph = tau * p
        r = dict(base())
        sw = 24 * S(ph)
        r['leg.L'] = rx_(-sw)
        r['leg.R'] = rx_(sw)
        r['foot.L'] = rx_(max(0., 14 * S(ph + 1.2)))
        r['foot.R'] = rx_(max(0., 14 * S(ph + 1.2 + math.pi)))
        r['hips'] = ry_(4 * S(ph)) @ rz_(2.5 * S(ph))
        r['spine'] = ry_(-5 * S(ph)) @ rx_(3)
        r['neck'] = ry_(2 * S(ph))
        r['head'] = rz_(-2 * S(ph)) @ rx_(-2)
        r['cape'] = rx_(6 + 3 * S(2 * ph))
        r['bird'] = ry_(-25) @ rz_(4 * S(2 * ph + .5))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 3 * S(2 * ph)) @ rx_(4)
            r['hairT' + d] = rz_(sg * 5 * S(2 * ph - .8)) @ rx_(6 + 3 * S(2 * ph))
            r['arm_upper' + d] = r['arm_upper' + d] @ rx_(-sg * 6 * S(ph))
        bob = .035 * (1 - math.cos(2 * ph)) / 2
        return full(r, 'walk', t), {'hips': (0, bob - .02, 0)}

    def talk(t):
        p = t / 3.0
        ph = tau * p
        r = dict(base())
        r['head'] = rx_(4 * S(ph * 3) * (.6 + .4 * S(ph))) @ rz_(5 * S(ph + .5))
        r['neck'] = ry_(6 * S(ph))
        r['spine'] = rx_(1.5 * S(ph * 2)) @ ry_(3 * S(ph))
        r['cape'] = rx_(2 * S(ph - .5))
        r['bird'] = ry_(-25 + 25 * S(ph * 2 + 1.3))
        # the wand hand gestures while she speaks
        g = .5 + .5 * S(ph * 2 - 1.0)
        R = arm_pose(-1, (-.50, -.80, .35), (-.30 - .25 * g, .30 + .35 * g, .85), twist=0.)
        r.update(R)
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 2 * S(ph + .2))
            r['hairT' + d] = rz_(sg * 3 * S(ph - .4))
        return full(r, 'talk', t), {'hips': (0, .004 * S(ph * 2), 0)}

    def cast(t):
        # 0-.35 s raise the wand overhead, then hold it there with a small flourish (ends raised)
        k = min(1., t / .35)
        k = k * k * (3 - 2 * k)
        r = dict(base())
        up = arm_pose(-1, (-.80, .55, .22), (-.55, .80, .25))
        lo = arm_pose(-1, (-.50, -.84, .20), (-.42, .22, .88))
        for n_ in up:
            r[n_] = slerp(lo[n_], up[n_], k)
        fl = max(0., t - .35)
        r['hand.R'] = r['hand.R'] @ rz_(10 * S(fl * 9) * min(1, fl * 3)) @ rx_(8 * S(fl * 7))
        r['spine'] = rx_(-6 * k) @ ry_(-8 * k)
        r['head'] = rx_(-10 * k)
        r['neck'] = ry_(-6 * k)
        r['cape'] = rx_(8 * k)
        r['bird'] = ry_(-25 + 30 * k)
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 6 * k) @ rx_(5 * k)
            r['hairT' + d] = rz_(sg * (9 * k + 2 * S(fl * 8))) @ rx_(8 * k)
        return full(r, 'cast', t), {'hips': (0, .02 * k, 0)}

    return [glb.Clip('idle', 4.0, idle), glb.Clip('walk', 1.0, walk), glb.Clip('talk', 3.0, talk), glb.Clip('cast', 1.6, cast, loop=False)]


def slerp(Ra, Rb, t):
    qa, qb = glb.quat(Ra), glb.quat(Rb)
    if qa @ qb < 0:
        qb = -qb
    q = qa * (1 - t) + qb * t
    q /= np.linalg.norm(q)
    x, y, z, w = q
    return A([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
              [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
              [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


# ======================================================================================================
def face_texture(spec, glb_path, tile_size):
    """From the concept art if available, else read back out of the existing GLB."""
    if spec.ref and os.path.exists(spec.ref):
        tex, info = fp.face_texture(spec)
        print('  face: from %s (affine residual %.1f px)' % (os.path.basename(spec.ref), info['resid_px']))
        return tex
    g, im = glb.read_glb(glb_path)
    if im is None or 'face_rect' not in g['asset'].get('extras', {}):
        raise SystemExit('no concept art (--refs) and no previous %s to take the face from' % glb_path)
    x, y, w, h = g['asset']['extras']['face_rect']
    print('  face: reused from %s' % glb_path)
    return im.crop((x, y, x + w, y + h)).resize(tile_size)


def export_character(name, M, at, clips, out_dir, preview, extras, mesh_name):
    tris = M.flatten()
    arr = bake_uvs(tris, at, M.COL)
    top = arr['P'][:, 1].max()
    # the hood top (not antlers) sets the scale: measure only hood/hat materials
    hood_keys = {'purple', 'maroon'}
    keys = [t['key'] for t in tris for _ in range(3)]
    tex = [t['tex'] or '' for t in tris for _ in range(3)]
    hood_y = [p[1] for p, k, tx in zip(arr['P'], keys, tex) if k in hood_keys or tx.startswith('hood')]
    hood_top = max(hood_y) if hood_y else top
    scale = HOOD_TOP_M / hood_top
    ex = dict(extras)
    if at.has('face'):
        ex['face_rect'] = list(at.rect['face'])
    ex.update(tris=len(tris), hood_top_m=HOOD_TOP_M, units_per_m=1 / scale)
    path = os.path.join(out_dir, name + '.glb')
    n = glb.export(path, M, arr, at.img, clips, scale, mesh_name=mesh_name, generator='tools/characters/' + name, extras=ex)
    print('  %s: %d triangles, %d bones, %d clips, atlas %dx%d (%.0f%% used), hood top %.3f m, overall top %.3f m'
          % (path, n, len(M.names), len(clips), at.W, at.H, 100 * at.usage(), hood_top * scale, top * scale))
    if preview:
        import witch_preview as wp
        os.makedirs(preview, exist_ok=True)
        clipd = {c.name: c for c in clips}
        r0, t0 = clipd['idle'].fn(0.)
        posed = glb.pose_arrays(M, arr, r0, t0)
        wp.sixview(posed, at.img, os.path.join(preview, name + '_sixview.png'), '%s  idle pose  %d tris' % (name, n))
        wp.sixview(arr, at.img, os.path.join(preview, name + '_rest.png'), '%s  rest (T) pose' % name)
        hy = M.B['head'][1][1]
        wp.closeup(posed, at.img, os.path.join(preview, name + '_face.png'), (-.55, .55, hy - .35, hy + .75))
        for cn in ('walk', 'talk', 'cast'):
            c = clipd[cn]
            frames = []
            for t in np.linspace(0, c.duration, 4, endpoint=c.name == 'cast'):
                rr, tt = c.fn(float(t))
                frames.append(wp.render(glb.pose_arrays(M, arr, rr, tt), at.img, (-.5, -.1, -.85), (0, 1, 0), 240, 300,
                                        crop=(-2.0, 2.0, -.1, 4.0)))
            strip_ = wp.Image.new('RGB', (240 * len(frames), 300))
            for i, f in enumerate(frames):
                strip_.paste(f, (240 * i, 0))
            strip_.save(os.path.join(preview, name + '_' + cn + '.png'))
        at.img.resize((at.W * 2, at.H * 2), wp.Image.NEAREST).save(os.path.join(preview, name + '_atlas.png'))
    return n


def build_v1(refs, out_dir, preview=None):
    print('witch (v1)')
    M = Model(BONES, COL)
    spec = face_spec(refs)
    at = atl.Atlas(256)
    at.alloc('face', *spec.size)
    at.paste('face', face_texture(spec, os.path.join(out_dir, 'witch.glb'), spec.size))
    build_parts(M, 'face', spec)
    return export_character('witch', M, at, clip_set(M), out_dir, preview, {'variant': 'v1'}, 'Witch')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--refs', default=os.environ.get('WITCH_REFS'), help='directory with the concept art (not in the repo)')
    ap.add_argument('--preview', default=None, help='write preview PNGs here')
    ap.add_argument('--only', choices=('v1', 'antler'), default=None)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    if a.only in (None, 'v1'):
        build_v1(a.refs, a.out, a.preview)
    if a.only in (None, 'antler'):
        import witch_antler
        witch_antler.build(a.refs, a.out, a.preview)


if __name__ == '__main__':
    main()
