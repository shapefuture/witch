#!/usr/bin/env python3
"""The antler witch (v2): branch antlers with hanging charms, a maroon felt hood with a peak,
a cape with the tree of life, a green felt mantle and vest with root embroidery, a moon
pendant, two satchels (a mouse in a hat, a spoon, a feather and lavender; a little house, a
map, a mushroom), a garland of bones at the belt, a purple skirt with gold appliqué, laced
boots, a pink star wand, a bird on her shoulder, and the photo face plate from the T-pose
concept (front).

    python tools/characters/witch_antler.py --out assets/characters --refs <concept dir>

Reuses v1's geometry kit (`witch_kit`, `witch.py`'s hair, bird, hands, clips) with the
source's own proportions (this variant's concept matches them: the head is not enlarged),
and textures from the source's v2 painters (`witch_tex.py`) packed into one 512 px atlas.
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
import witch as w1              # noqa: E402
import witch_glb as glb         # noqa: E402
import witch_tex                # noqa: E402
from witch_kit import (A, N_, Grid, Model, blob, catmull, cres2d, disc2d, frame_n, loft,   # noqa: E402
                       poly2d, ringp, rotm, spiral_e, tube, xf)

REF_FRONT = 'witch2_antler_front.webp'

COL = dict(w1.COL)
COL.update({'maroon': (.45, .13, .26), 'maroon_d': (.24, .07, .14), 'green_d': (.20, .23, .09),
            'wood': (.40, .30, .21), 'wood_d': (.27, .19, .13), 'bone': (.93, .89, .80), 'cord': (.46, .33, .20),
            'pink': (.84, .55, .64), 'pink_d': (.70, .44, .58), 'leaf': (.40, .42, .24), 'gold': (.90, .70, .36),
            'wand': (.90, .78, .82), 'wandstar': (.90, .66, .78), 'light': (1.0, .86, .50), 'hat': (.52, .52, .24),
            'roof': (.36, .22, .14), 'bird': (.66, .64, .62), 'purple': (.42, .22, .52), 'purple_d': (.24, .10, .30)})

BONES = {'root': (None, (0, 0, 0)), 'hips': ('root', (0, .98, 0)), 'spine': ('hips', (0, 1.3, 0)),
         'neck': ('spine', (0, 2.3, 0)), 'head': ('neck', (0, 2.4, 0)), 'cape': ('spine', (0, 2.2, -.2)),
         'bird': ('spine', (.50, 2.27, 0))}
for _s, _d in ((1, '.L'), (-1, '.R')):
    BONES['arm_upper' + _d] = ('spine', (_s * .26, 2.13, 0))
    BONES['arm_lower' + _d] = ('arm_upper' + _d, (_s * .62, 2.13, 0))
    BONES['hand' + _d] = ('arm_lower' + _d, (_s * .95, 2.13, 0))
    BONES['leg' + _d] = ('hips', (_s * .19, .95, 0))
    BONES['foot' + _d] = ('leg' + _d, (_s * .19, .1, 0))
    BONES['hairB' + _d] = ('spine', (_s * .30, 2.25, -.12))
    BONES['hairT' + _d] = ('hairB' + _d, (_s * .62, 1.60, -.16))
HEAD_S = 1.08
PIV = A((0, 2.30, 0))
# antler hang points (head space) -> charm bones (model space, after the head scale)
HANG = {'.L': (.47, 2.955, -.05), '.R': (-.47, 2.955, -.05)}
for _d, _p in HANG.items():
    BONES['charm' + _d] = ('head', tuple(PIV + (A(_p) - PIV) * HEAD_S))

# head fitted to this concept's narrower, heart-shaped face window
HR = [(2.345, .04, .04, .055), (2.37, .085, .08, .05), (2.40, .135, .125, .045), (2.44, .170, .16, .038),
      (2.50, .200, .19, .03), (2.56, .218, .205, .022), (2.64, .222, .21, .016), (2.72, .215, .205, .01),
      (2.80, .185, .185, 0.), (2.86, .12, .125, -.01), (2.90, .04, .05, -.02)]


def head_rx(y):
    return w1.ring_at(y, HR)[0]


def head_front_z(x, y):
    rx, rz, cz = w1.ring_at(y, HR)
    u = min(1., abs(x) / max(rx, 1e-6))
    return cz + rz * max(0., 1 - u ** w1.HEAD_E) ** (1 / w1.HEAD_E)


def face_spec(refs):
    """Landmarks on the T-pose front concept (1034x772)."""
    return fp.FaceSpec(os.path.join(refs, REF_FRONT) if refs else None,
                       dict(eyeR=(495.6, 125.6), eyeL=(543.75, 126.9), nose=(520.0, 147.5),
                            mouth=(521.25, 158.1), chin=(522.5, 175.0)),
                       w1.LM, (-.26, .26, 2.33, 2.87), (176, 184), 'her_left', COL['skin'], COL['hair'],
                       hairline=2.78, eye_contrast=.4, eye_dark=.35)


# ---- texturing helpers --------------------------------------------------------------------------------
def loft_fuv(part, u0=0., u1=1., v0=0., v1=1., flip_v=False):
    """Per-face UVs from a loft's cylindrical coords, seam-safe, into a sub-rectangle of a tile."""
    uv = part['uvc']
    F = part['F']
    out = np.zeros((len(F), 3, 2))
    for i, f in enumerate(F):
        q = uv[f].copy()
        if q[:, 0].max() - q[:, 0].min() > .5:
            q[q[:, 0] < .5, 0] += 1.
        q[:, 0] = np.minimum(q[:, 0], 1.)
        if flip_v:
            q[:, 1] = 1 - q[:, 1]
        out[i, :, 0] = u0 + (u1 - u0) * q[:, 0]
        out[i, :, 1] = v0 + (v1 - v0) * q[:, 1]
    part['fuv'] = out
    return part


def card(M, c, right, up, w, h, tex, bone, shape='diamond', uvr=(0, 0, 1, 1)):
    """Double-sided sprite card (charms, satchel contents)."""
    c, right, up = A(c, float), N_(right), N_(up)
    if shape == 'diamond':
        q = [(0, 1), (-1, .15), (0, -1), (1, .15)]
    elif shape == 'leaf':
        q = [(0, 1), (-.8, .35), (-.55, -.5), (0, -1), (.55, -.5), (.8, .35)]
    else:
        q = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    V = A([c + right * x * w + up * y * h for x, y in q])
    F = [(0, k, k + 1) for k in range(1, len(q) - 1)]
    u0, v0, u1, v1 = uvr
    uv = A([(u0 + (x + 1) / 2 * (u1 - u0), v0 + (1 - y) / 2 * (v1 - v0)) for x, y in q])
    return M.add(dict(V=V, F=A(F, int), ax=A([c - np.cross(right, up) * .05]), fb=None, both=True, uv=uv), 'pink', bone=bone, tex=tex)


def vest_rows():
    return [(.98, .455, .335), (1.25, .36, .29), (1.55, .30, .255), (1.85, .275, .235), (2.12, .30, .22), (2.24, .22, .17)]


def vest_z(x, y):
    rows = vest_rows()
    ys = [r[0] for r in rows]
    rx = np.interp(y, ys, [r[1] for r in rows])
    rz = np.interp(y, ys, [r[2] for r in rows])
    return rz * max(0, 1 - (abs(x) / rx) ** 2.6) ** (1 / 2.6)


# ======================================================================================================
def build_parts(M, spec):
    rnd = random.Random(7)
    add, patch, place, stamp = M.add, M.patch, M.place, M.stamp
    P = M.P

    # ===== laced boots (visible under this skirt) and legs
    for s, d in ((1, '.L'), (-1, '.R')):
        bx = s * .19
        shaft = loft([((bx, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in ((.06, .12, .135, .01), (.19, .113, .125, -.01), (.36, .12, .12, -.01))],
                     10, 2.4, cap=(0, 0), j=.004, o=-5)
        add(loft_fuv(shaft, 0, 1, .02, .66, flip_v=True), 'boot', bone='foot' + d, tex='boots')
        foot = loft([((bx, cy, z), (rx, 0, 0), (0, ry, 0)) for z, rx, ry, cy in ((-.15, .10, .065, .075), (0, .125, .11, .10), (.16, .13, .09, .08), (.34, .095, .055, .055))],
                    10, 2.4, cap=(.03, .06), j=.005)
        add(loft_fuv(foot, 0, 1, .70, .92), 'boot', bone='foot' + d, tex='boots')
        sole = loft([((bx, .02, z), (rx, 0, 0), (0, .022, 0)) for z, rx in ((-.15, .092), (0, .117), (.15, .122), (.32, .088))], 8, 2.4, cap=(.02, .03))
        add(sole, 'sole', bone='foot' + d)
        cuff = loft([((bx, y, -.01), (rx, 0, 0), (0, 0, rz)) for y, rx, rz in ((.33, .128, .13), (.37, .13, .13))], 10, 2.4, cap=(0, 0))
        add(cuff, 'boot', bone='foot' + d)
        leg = loft([((bx, .3, 0), (.075, 0, 0), (0, 0, .075)), ((bx, 1.0, 0), (.09, 0, 0), (0, 0, .09))], 6, 2., cap=(0, 0))
        add(leg, 'leg', bone='leg' + d)

    # ===== skirt: 10 facets with the appliqué strip (one tile band per facet)
    sk = Grid([ringp(.98, .49, .345, 0, 10, 2., 4.5), ringp(.34, .62, .45, 0, 10, 2., 4.5)], True, [(0, .98, 0), (0, .34, 0)])
    add(sk.part(), 'purple', bone='hips', tex='skirt')
    add(sk.part(True, .014), 'purple_d', bone='hips')
    add(M.grid_rim(sk, .014), 'purple_d', bone='hips')

    # ===== vest: green felt, roots embroidered up from the hem (front at u=.5)
    vr = vest_rows() + [(2.30, .0, .0)]
    vg = Grid([ringp(y, rx, rz, 0, 12, 2.6, 5.5) for y, rx, rz in vr[::-1]], True, [(0, 2.3, 0), (0, .98, 0)])
    vg.ax = A([(0, y, 0) for y in np.linspace(.98, 2.10, 10)])
    vp = vg.part()
    add(vp, 'green', bone='spine', tex='vest')

    # ===== belt: cord and a garland of bones over the skirt top
    bel = [(math.sin(a) * .47, 1.0 - .03 * math.cos(3 * a) ** 2, math.cos(a) * .355 + .01) for a in np.linspace(-1.9, 1.9, 13)]
    add(tube(bel, [.014], 4, 1., (0, 1, 0), cap=(.01, .01)), 'cord', bone='hips')
    for k, a in enumerate(np.linspace(-1.75, 1.75, 11)):
        x, z = math.sin(a) * .49, math.cos(a) * .37 + .02
        y0 = .97 - .02 * (k % 2)
        ln = .085 if k % 2 else .07
        top_, bot_ = A((x, y0, z)), A((x * 1.01, y0 - ln, z + .005))
        add(tube([top_, bot_], [.011, .011], 4, 1., (0, 0, 1), cap=(.004, .004)), 'bone', bone='hips')
        for e_ in (top_, bot_):
            for sg in (-1, 1):
                add(blob(e_ + A((math.cos(a), 0, -math.sin(a))) * sg * .012, (.011, .011, .011), (0, 1, 0), 4, 2), 'bone', bone='hips')

    # ===== satchels: leather bodies and stitched flaps
    PX = .27
    for cx, cy in ((-PX, 1.32), (PX, 1.31)):
        pz = vest_z(cx, cy) - .02
        pch = loft([((cx, cy, pz + z), (.19 * q, 0, 0), (0, .19 * q, 0)) for z, q in ((-.02, 1.0), (.08, 1.0), (.14, .94), (.17, .78))], 8, 2.5, cap=(0, .03), j=.02)
        add(loft_fuv(pch), 'pouch', bone='spine', tex='pouch')
        if cx > 0:
            fl = loft([((cx, cy + .08, pz + z), (.20 * q, 0, 0), (0, .12 * q, 0)) for z, q in ((.0, 1.0), (.10, 1.0), (.165, .95), (.195, .80))], 8, 2.5, cap=(0, .014), j=.012)
            add(loft_fuv(fl), 'pouch', bone='spine', tex='flap')
    # her right satchel (-X): a mouse in a little hat, a spoon, a feather and lavender
    mz = vest_z(-PX, 1.5) + .06
    mx = -PX + .02
    add(blob((mx, 1.50, mz), (.052, .07, .05), (0, 1, .15), 6, 3), 'mouse', bone='spine')
    add(blob((mx, 1.60, mz + .035), (.043, .048, .045), (0, .5, 1), 6, 3), 'mouse', bone='spine')
    add(blob((mx, 1.588, mz + .088), (.02, .02, .02), (0, 0, 1), 5, 2), 'mousepink', bone='spine')
    for sg in (1, -1):
        add(blob((mx + sg * .042, 1.655, mz + .028), (.036, .008, .036), (0, 0, 1), 6, 2), 'mousepink', bone='spine')
        add(blob((mx + sg * .02, 1.612, mz + .082), (.007, .007, .007), (0, 1, 0), 4, 2), 'pupil', bone='spine')
    add(loft([((mx, 1.66, mz + .03), (.05, 0, 0), (0, 0, .05)), ((mx, 1.75, mz + .02), (.008, 0, 0), (0, 0, .008))], 6, 2., cap=(0, .02)), 'hat', bone='spine')
    add(loft([((mx, 1.655, mz + .03), (.075, 0, 0), (0, 0, .07)), ((mx, 1.665, mz + .03), (.075, 0, 0), (0, 0, .07))], 6, 2., cap=(0, 0)), 'hat', bone='spine')
    sp = tube([(-PX - .07, 1.47, mz - .01), (-PX - .085, 1.56, mz - .005), (-PX - .095, 1.66, mz)], [.013, .008], 4, 1., (0, 0, 1))
    bowl = blob((-PX - .105, 1.74, mz), (.05, .013, .075), (0, 0, 1), 6, 2)
    for q in (sp, bowl):
        xf(q, rotm((0, 0, 1), -14), (-PX - .07, 1.5, mz))
        add(q, 'silver', bone='spine')
    card(M, (-PX + .13, 1.62, mz - .02), (math.cos(.5), math.sin(.5), 0), (-math.sin(.5), math.cos(.5), 0), .045, .12, 'feather', 'spine', 'leaf')
    card(M, (-PX - .15, 1.58, mz - .03), (math.cos(-.4), math.sin(-.4), 0), (-math.sin(-.4), math.cos(-.4), 0), .05, .10, 'lav', 'spine', 'quad')
    # her left satchel (+X): a little house, a map, a mushroom, a small light
    hz = vest_z(PX, 1.5) + .05
    hx, hy = PX - .02, 1.50
    house = loft([((hx, hy, hz), (.055, 0, 0), (0, 0, .045)), ((hx, hy + .09, hz), (.055, 0, 0), (0, 0, .045))], 4, 2., cap=(0, 0), o=.5)
    add(loft_fuv(house), 'wood', bone='spine', tex='house')
    rv = [(hx - .07, hy + .09, hz + .06), (hx + .07, hy + .09, hz + .06), (hx + .07, hy + .09, hz - .06), (hx - .07, hy + .09, hz - .06), (hx, hy + .16, hz + .06), (hx, hy + .16, hz - .06)]
    patch([rv[0], rv[1], rv[4]], [(0, 1, 2)], (0, 0, 1), 'roof', 'spine')
    patch([rv[1], rv[2], rv[5], rv[4]], [(0, 1, 2), (0, 2, 3)], (1, 1, 0), 'roof', 'spine')
    patch([rv[3], rv[0], rv[4], rv[5]], [(0, 1, 2), (0, 2, 3)], (-1, 1, 0), 'roof', 'spine')
    card(M, (PX + .12, 1.49, hz + .03), (math.cos(.3), math.sin(.3), .2), (-math.sin(.3), math.cos(.3), .1), .08, .06, 'map', 'spine', 'quad')
    card(M, (PX - .13, 1.50, hz - .02), (1, 0, 0), (0, 1, 0), .045, .05, 'shroom', 'spine', 'quad')
    add(blob((PX + .06, 1.47, hz + .02), (.016, .016, .016), (0, 1, 0), 5, 2), 'light', bone='spine')
    # strap: from her left satchel up across the chest to her right shoulder
    pts = [(PX - .04, 1.42), (.12, 1.72), (-.05, 1.98), (-.20, 2.17)]
    band = []
    for k, (x, y) in enumerate(pts):
        nxt = pts[min(k + 1, 3)]
        prv = pts[max(k - 1, 0)]
        t = N_((nxt[0] - prv[0], nxt[1] - prv[1], 0))
        nrm = A((-t[1], t[0], 0)) * .026
        band.append([(x - nrm[0], y - nrm[1], vest_z(x - nrm[0], y - nrm[1]) + .012), (x + nrm[0], y + nrm[1], vest_z(x + nrm[0], y + nrm[1]) + .012)])
    sg_ = Grid(band, False, [(0, 1.7, -.3), (0, 1.8, -.3)])
    stp = sg_.part()
    stp['fuv'] = stp['fuv'][:, :, ::-1]          # the strap tile runs along v
    add(stp, 'cord', bone='spine', tex='strap')

    # ===== mantle (green felt, scalloped points) and the maroon bib with pink roots
    mrows = [(2.20, .47, .33), (2.06, .60, .41), (1.95, .63, .43)]
    angs = np.radians(np.linspace(-118, 118, 12))
    mg = Grid([[(rx * math.sin(t), y, rz * math.cos(t)) for t in angs] for y, rx, rz in mrows], False, [(0, y, 0) for y, _, _ in mrows])
    add(mg.part(), 'green', bone='spine', tex='mantle')
    add(mg.part(True, .012), 'green_d', bone='spine')
    bot = mg.P[-1]
    for k in range(len(bot) - 1):
        a_, b_ = bot[k], bot[k + 1]
        tip = (a_ + b_) / 2 + A((0, -.09, 0)) + N_((a_ + b_) / 2 * (1, 0, 1)) * .02
        add(dict(V=A([a_, b_, tip]), F=A([(0, 1, 2)]), ax=A([(0, 2.0, 0)]), fb=None, both=True, uv=A([(.2, .1), (.8, .1), (.5, .9)])),
            'green', bone='spine', tex='mantle')
    cg = Grid([ringp(2.37, .17, .15, 0, 12, 2.2, 5.5), ringp(2.29, .35, .26, 0, 12, 2.2, 5.5), ringp(2.11, .51, .35, 0, 12, 2.2, 5.5)],
              True, [(0, 2.45, 0), (0, 2.08, 0)])
    add(cg.part(), 'maroon', bone='spine', tex='bib')
    # chain + crescent moon pendant
    for (hw, cy0, cy1) in ((.20, 2.31, 2.02),):
        pts = [(x, cy1 + (cy0 - cy1) * (x / hw) ** 2, max(vest_z(x, cy1 + (cy0 - cy1) * (x / hw) ** 2), .0) + .04) for x in np.linspace(-hw, hw, 7)]
        add(tube(pts, [.012], 4, 1., (0, 0, 1), cap=(.005, .005)), 'chain', bone='spine')
    cv, cf = cres2d(.16)
    zc = vest_z(0, 1.86) + .035
    n = len(cv) // 2
    ang = math.radians(35)
    lp = [(x * math.cos(ang) - y * math.sin(ang), y * math.cos(ang) + x * math.sin(ang)) for x, y in cv]
    FV = [(x, y + 1.86, zc + .016) for x, y in lp] + [(x, y + 1.86, zc - .016) for x, y in lp]
    m2 = len(lp)
    F = []
    for k in range(n - 1):
        F += [(k, k + 1, n + k + 1), (k, n + k + 1, n + k)]
    Fb = [(a + m2, c + m2, b + m2) for a, b, c in F]
    lpi = list(range(n)) + list(range(2 * n - 1, n - 1, -1))
    Fs = []
    for i in range(len(lpi)):
        a, b = lpi[i], lpi[(i + 1) % len(lpi)]
        Fs += [(a, b, b + m2), (a, b + m2, a + m2)]
    axs = [A(((FV[k][0] + FV[n + k][0]) / 2, (FV[k][1] + FV[n + k][1]) / 2, zc)) for k in range(n)]
    add(dict(V=A(FV), F=A(F + Fb + Fs, int), ax=A(axs), fb=None), 'silver', bone='spine')

    # ===== cape: boxy maroon boucle with the tree of life down the back
    cy = [2.31, 1.62, .90]
    crx = [.47, .66, .78]
    ccz = [-.05, -.10, -.14]
    cap = Grid([[(rx * math.sin(math.radians(p)), y, cz + rx * .70 * math.cos(math.radians(p))) for p in np.linspace(102, 258, 7)]
                for y, rx, cz in zip(cy, crx, ccz)], False, [(0, y, cz) for y, cz in zip(cy, ccz)])
    add(cap.part(), 'maroon', bone='cape', tex='cape')
    add(cap.part(True, .014), 'maroon_d', bone='cape')
    add(M.grid_rim(cap, .014), 'maroon_d', bone='cape')

    # ===== sleeves with gold moons and stars, cuffs, hands, wand
    for s, d in ((1, '.L'), (-1, '.R')):
        xs = [.22, .50, .75, .95]
        ry = [.085, .12, .16, .19]
        rz = [.105, .115, .13, .14]
        rows = [[(s * x, 2.13 + a * math.sin(2 * math.pi * (k - .5) / 8), b * math.cos(2 * math.pi * (k - .5) / 8)) for k in range(8)] for x, a, b in zip(xs, ry, rz)]
        sg = Grid(rows, True, [(s * x, 2.13, 0) for x in xs])
        for inv, mat, tex in ((False, 'purple', 'sleeve'), (True, 'purple_d', None)):
            pp = sg.part(inv, .012 if inv else 0.)
            J, W = M.chainw(np.abs(pp['V'][:, 0]), [.62, .95], ['arm_upper' + d, 'arm_lower' + d, 'hand' + d], [.12, .06])
            if tex:
                add(pp, mat, J, W, tex=tex)
            else:
                add(pp, mat, J, W)
    w1.build_hands_wand(M)

    # ===== bird on her left shoulder, looking forward
    w1.build_bird(M, A((.50, 2.255, .0)), face=(.3, 0, 1), sc=1.05)

    # ===== neck & head (head space; scaled about PIV at the end)
    add(loft([((0, 2.22, 0), (.07, 0, 0), (0, 0, .07)), ((0, 2.38, .01), (.062, 0, 0), (0, 0, .062))], 7, 2., cap=(0, 0)), 'skin', bone='head')
    add(loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in HR], 14, w1.HEAD_E, cap=(.02, .04)), 'skin', bone='head')
    ys = [2.36, 2.375, 2.39, 2.41, 2.43, 2.45, 2.47, 2.49, 2.51, 2.535, 2.56, 2.585, 2.61, 2.64, 2.67, 2.70, 2.74, 2.78]
    fs = [-.95, -.78, -.6, -.42, -.26, -.12, 0, .12, .26, .42, .6, .78, .95]
    add(fp.plate(spec, head_rx, head_front_z, ys, fs, edge_off=.004, lift=.007), 'skin', bone='head', tex='face')

    # ===== hood: maroon felt, peak flopping back
    Hm = []
    for y, rx, cz, ph in zip(w1.HY, w1.HRX, w1.HCZ, w1.HPHI):
        amp = .022 * min(1, max(0, (y - 2.78) / .3))
        row = []
        for c in range(13):
            p = math.radians(ph + (360 - 2 * ph) * c / 12)
            row.append((rx * math.sin(p), y + amp * math.cos(2 * p), cz + rx * .93 * math.cos(p)))
        Hm.append(row)
    hg = Grid(Hm, False, [(0, y, cz) for y, cz in zip(w1.HY, w1.HCZ)])
    hg.ax = A([(0, y, z) for y, z in zip(np.linspace(2.30, 2.95, 12), np.linspace(-.03, -.14, 12))])
    add(hg.part(), 'maroon', bone='head', tex='boucle')
    add(hg.part(True, .012), 'maroon_d', bone='head')
    add(M.grid_rim(hg, .012), 'maroon', bone='head')
    top = hg.P[-1]
    tip = A((0, 3.06, -.56))          # longer, drooping peak
    pk = dict(V=A([tip] + [tuple(p) for p in top]), F=A([(0, 1 + k, 2 + k) for k in range(len(top) - 1)] + [(0, len(top), 1)], int),
              ax=A([(0, 2.95, -.2)]), fb=None, uv=A([(.5, 1.)] + [(k / (len(top) - 1), 0.) for k in range(len(top))]))
    add(pk, 'maroon', bone='head', tex='hoodtip')

    # ===== flower crown: denser dusty-pink flowers
    for i, ph in enumerate(np.linspace(-82, 82, 11)):
        p = math.radians(ph)
        yr = float(np.interp(abs(ph), w1.HPHI[:7][::-1], w1.HY[:7][::-1])) + .03
        pos, nn = w1.hood_pt(yr, p)
        nn = N_(nn)
        rr = .085 if i % 2 else .072
        t1, t2, n_ = frame_n(nn)
        for k in range(5):
            a = math.radians(90 + 72 * k + (20 if i % 2 else 0))
            tp = (rr * math.cos(a), rr * math.sin(a))
            l_ = (rr * .6 * math.cos(a - .55), rr * .6 * math.sin(a - .55))
            r_ = (rr * .6 * math.cos(a + .55), rr * .6 * math.sin(a + .55))
            V = [pos + n_ * .03, pos + t1 * l_[0] + t2 * l_[1] + n_ * .02, pos + t1 * tp[0] + t2 * tp[1] + n_ * .015, pos + t1 * r_[0] + t2 * r_[1] + n_ * .02]
            patch(V, [(0, 1, 2), (0, 2, 3)], n_, 'pink' if (k + i) % 2 == 0 else 'pink_d', 'head')
        V2, F = disc2d(rr * .26, 5)
        place(V2, F, pos, t1, t2, n_, 1., 0, .036, 'gold', 'head')

    # ===== branch antlers with tines (head space), charms hang from them on their own bones
    k_ant = len(P)
    for s, d in ((1, '.L'), (-1, '.R')):
        beam = catmull([(s * .27, 2.86, -.04), (s * .38, 2.93, -.05), (s * .52, 2.975, -.06), (s * .66, 3.01, -.07), (s * .80, 3.08, -.08)], 2)
        add(tube(beam, [.028, .022, .018, .013, .008], 5, 1., (0, 1, 0), cap=(.0, .01)), 'wood', bone='head')
        for b0, b1, r0 in (((s * .40, 2.94, -.05), (s * .37, 3.10, -.06), .014), ((s * .58, 2.99, -.065), (s * .62, 3.15, -.07), .012),
                           ((s * .66, 3.01, -.07), (s * .80, 2.98, -.09), .010), ((s * .48, 2.96, -.055), (s * .55, 3.06, -.02), .009)):
            mid = (A(b0) + A(b1)) / 2 + A((s * .015, .01, 0))
            add(tube([b0, mid, b1], [r0, r0 * .8, r0 * .4], 4, 1., (0, 0, 1), cap=(0, .006)), 'wood_d', bone='head')
    for p_ in P[k_ant:]:
        p_['V'] = (p_['V'] - PIV) * HEAD_S + PIV
        p_['ax'] = (p_['ax'] - PIV) * HEAD_S + PIV
        p_['J'][:, 0] = M.ix['head']
    # charms (model space, below the hang points)
    for d, hp in HANG.items():
        s = 1 if d == '.L' else -1
        h = PIV + (A(hp) - PIV) * HEAD_S
        b = 'charm' + d
        for dx, ln, tex, wv, hv, shape in ((0., .16, 'oak' if s < 0 else 'lav', .07, .09, 'leaf' if s < 0 else 'quad'),
                                           (s * .15, .12, 'carrot' if s < 0 else 'feather', .035, .08, 'diamond' if s < 0 else 'leaf')):
            top_ = h + A((dx, .04 * (dx != 0), -.01))
            add(tube([top_, top_ + A((0, -ln, 0))], [.004], 3, 1., (0, 0, 1), cap=(0, 0)), 'cord', bone=b)
            card(M, top_ + A((0, -ln - hv, 0)), (1, 0, .25 * s), (0, 1, 0), wv, hv, tex, b, shape)
        for dx in (-.08, .09):
            add(blob(h + A((s * dx, -.06 - .03 * (dx > 0), .01)), (.018, .018, .018), (0, 1, 0), 4, 2), 'light', bone=b)

    # ===== hair: face framing (head space), temple curls by the antlers, big side spirals
    def lock(pts, rad, s, bone, chain=False, ratio=.5):
        w1.hair_lock(M, pts, rad, s, bone, chain, ratio)
    for s in (1, -1):
        w1.hair_face(M, s, lock)
        # side ribbons come from under the hood, run inside the cape and spiral out at the hips
        d_ = [(.30, 2.26, -.10), (.42, 2.02, -.14), (.53, 1.80, -.16), (.60, 1.62, -.13)]
        pts = list(catmull(d_, 2))
        pts += spiral_e(pts[-1], (.80, 1.52), .19, .24, 1.4, 1, 10, -.06)
        lock(pts, w1.rcurve(len(pts), .17, .045), s, None, True, .45)
        d_ = [(.27, 2.24, -.06), (.36, 2.00, -.08), (.45, 1.76, -.08), (.50, 1.48, -.05)]
        pts = list(catmull(d_, 2))
        pts += spiral_e(pts[-1], (.66, 1.32), .14, .15, 1.3, 1, 9, .0)
        lock(pts, w1.rcurve(len(pts), .12, .04), s, None, True, .5)

    for p in M.parts_on('head'):
        if p.get('_scaled'):
            continue
        if any(p is q for q in P[k_ant:]):
            continue
        p['V'] = (p['V'] - PIV) * HEAD_S + PIV
        p['ax'] = (p['ax'] - PIV) * HEAD_S + PIV
    return M


def base_pose():
    """Wand up in her right hand at the chest; left arm relaxed by the satchel."""
    R = w1.arm_pose(-1, (-.50, -.84, .20), (-.42, .22, .88))
    L = w1.arm_pose(1, (.30, -.95, .08), (.18, -.88, .44))
    return w1.combine(R, L)


def extra(name, t, r):
    """Charms swing on their threads; the bird turns its head about."""
    S = math.sin
    amp = {'idle': 6, 'walk': 14, 'talk': 7, 'cast': 18}[name]
    fr = {'idle': 2 * math.pi / 2., 'walk': 2 * math.pi * 2, 'talk': 2 * math.pi / 1.5, 'cast': 2 * math.pi * 1.2}[name]
    if name == 'cast':
        amp *= min(1., t / .35)
    for d, ph in (('.L', 0.), ('.R', 1.3)):
        r['charm' + d] = w1.rz_(amp * S(fr * t + ph)) @ w1.rx_(amp * .5 * S(fr * t * .5 + ph))
    r['bird'] = w1.ry_(15 * S(2 * math.pi * t / 2.0) if name != 'walk' else 6 * S(4 * math.pi * t))


def build(refs, out_dir, preview=None):
    print('witch_antler (v2)')
    M = Model(BONES, COL)
    spec = face_spec(refs)
    at = atl.Atlas(512)
    at.alloc('face', *spec.size)
    witch_tex.build_atlas(at)
    at.paste('face', w1.face_texture(spec, os.path.join(out_dir, 'witch_antler.glb'), spec.size))
    build_parts(M, spec)
    clips = w1.clip_set(M, base=base_pose, extra=extra)
    return w1.export_character('witch_antler', M, at, clips, out_dir, preview, {'variant': 'antler'}, 'WitchAntler')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--refs', default=os.environ.get('WITCH_REFS'))
    ap.add_argument('--preview', default=None)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    build(a.refs, a.out, a.preview)


if __name__ == '__main__':
    main()
