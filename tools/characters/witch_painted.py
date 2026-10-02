#!/usr/bin/env python3
"""The witch as the painted room has her: a very large, floppy, star-strewn violet hat on a small
body in a short dark-navy robe, dark sleeves, short boots, a pale face half hidden by the brim.

    python tools/characters/witch_painted.py --out assets/characters [--preview DIR]

writes `witch.glb` (the file the game loads) with the same skeleton names as the concept-sheet
witch (`witch.py`, kept as `--only v1` -> `witch_concept.glb`) plus one extra bone, `hat_tip`.
The design comes from the painting (the figure seen from behind in the reference still) and a
front/side/back turnaround generated from it (`tools/characters/ref/witch_turnaround.png`, see
docs/art/characters_painted.md). Authored in metres: y up, she faces +Z, +X is her left, feet at
y = 0, the hat tip at 1.30 m. One atlas (nearest, 5 bit): the hat's star tile, the face, and flat
colour swatches; one surface.

The rest pose is relaxed (arms hang), not a T-pose: bones are still translation-only, and every
clip keys every bone in rest-pose world axes.
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas as atl            # noqa: E402
import witch_glb as glb         # noqa: E402
from witch_kit import A, N_, Model, bake_uvs, loft, rotm, tube   # noqa: E402

HEIGHT = 1.30

# Display-referred colours (what the unshaded PSX actor shader multiplies by the room's light).
COL = {
    'robe': (.21, .22, .64), 'robe_d': (.06, .06, .12), 'robe_hem': (.16, .17, .46),
    'sleeve': (.22, .16, .20), 'cuff': (.12, .09, .12),
    'hand': (.40, .30, .26), 'boot': (.13, .09, .07), 'sole': (.08, .06, .05), 'leg': (.10, .08, .09),
    'skin': (.80, .66, .57), 'skin_d': (.62, .49, .44),
    'hair': (.22, .15, .13), 'hair_l': (.30, .21, .17),
    'hat': (.36, .25, .52), 'hat_u': (.19, .12, .27), 'hat_r': (.33, .22, .48),
    'wand': (.30, .20, .14), 'wand_star': (.93, .76, .36),
}
for _k in ('robe', 'robe_d', 'robe_hem', 'sleeve'):        # three tones per facet-coloured material (paper folds)
    for _v, _m in zip('abc', (.72, 1., 1.35)):
        COL[_k + _v] = tuple(min(1., c * _m) for c in COL[_k])
HAT_BASE = (.36, .31, .74)
# facet washes (multipliers): the painted hat is lit on some planes and nearly black on others
HAT_FACET = ((.50, .46, .58), (.68, .64, .74), (.85, .82, .90), (1., 1., 1.), (1.2, 1.1, 1.05), (1.45, 1.25, 1.1), (1.75, 1.4, 1.2))
STAR = (.90, .72, .34)

BONES = {'root': (None, (0, 0, 0)), 'hips': ('root', (0, .34, 0)), 'spine': ('hips', (0, .42, 0)),
         'neck': ('spine', (0, .63, 0)), 'head': ('neck', (0, .69, 0)), 'cape': ('spine', (0, .60, -.07)),
         'hat_tip': ('head', (0., 0., 0.))}      # moved onto the hat's axis below
for _s, _d in ((1, '.L'), (-1, '.R')):
    BONES['arm_upper' + _d] = ('spine', (_s * .136, .60, 0))
    BONES['arm_lower' + _d] = ('arm_upper' + _d, (_s * .166, .45, 0))
    BONES['hand' + _d] = ('arm_lower' + _d, (_s * .174, .30, .015))
    BONES['leg' + _d] = ('hips', (_s * .066, .34, 0))
    BONES['foot' + _d] = ('leg' + _d, (_s * .066, .07, 0))
    BONES['hairB' + _d] = ('head', (_s * .09, .76, -.04))
    BONES['hairT' + _d] = ('hairB' + _d, (_s * .10, .64, -.06))
BONES['bird'] = ('hand.L', (.18, .27, .04))      # carried over from the concept witch; nothing hangs on it


# ---- helpers -------------------------------------------------------------------------------------
def smooth(t):
    t = np.clip(t, 0., 1.)
    return t * t * (3 - 2 * t)


def weights(M, V, fn):
    """J, W (n, 4) from fn(point) -> {bone: weight}; the four strongest, normalised."""
    J = np.zeros((len(V), 4), int)
    W = np.zeros((len(V), 4))
    for i, p in enumerate(V):
        d = fn(p)
        items = sorted(((w, b) for b, w in d.items() if w > 1e-4), reverse=True)[:4]
        s = sum(w for w, _ in items)
        for k, (w, b) in enumerate(items):
            J[i, k] = M.ix[b]
            W[i, k] = w / s
    return J, W


def grid_part(P, wrap, u=None, v=None, th=.012):
    """A quad-facet surface from points P[row, column] (rows go up, columns turn counter-clockwise seen
    from above, or toward +X on a front plate): the winding then faces outward. Inward points stand in
    for the axis, so the kit's outward test agrees with the winding. u, v: tile coordinates per column
    / row boundary (len cols+1, rows)."""
    P = A(P, float)
    R, C = P.shape[:2]
    cols = C if wrap else C - 1
    F, FUV = [], []
    for r in range(R - 1):
        for m in range(cols):
            a, b = r * C + m, r * C + (m + 1) % C
            F += [(a, b, a + C), (b, b + C, a + C)]
            if u is not None:
                ua, ub, va, vb = u[m], u[m + 1], v[r], v[r + 1]
                FUV += [((ua, va), (ub, va), (ua, vb)), ((ub, va), (ub, vb), (ua, vb))]
    V = P.reshape(-1, 3)
    F = A(F, int)
    Q = V[F]
    fn = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
    vn = np.zeros_like(V)
    for k in range(3):
        np.add.at(vn, F[:, k], fn)
    vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-9)
    part = dict(V=V, F=F, ax=V - th * vn, fb=None)
    if u is not None:
        part['fuv'] = A(FUV, float)
    return part


def ring_pts(y, rx, rz, cx=0., cz=0., n=10, e=2., phi0=0.):
    out = []
    for k in range(n):
        t = math.radians(phi0 + 360. * k / n)
        s, c = math.sin(t), math.cos(t)
        if e != 2:
            s = math.copysign(abs(s) ** (2 / e), s)
            c = math.copysign(abs(c) ** (2 / e), c)
        out.append((cx + rx * s, y, cz + rz * c))
    return out


def hsh(p, a):
    x, y, z = abs(p[0]), p[1], p[2]
    d = A([math.sin(x * 127.1 + y * 311.7 + z * 74.7 + k * 19.19) * 43758.5453 for k in range(3)])
    d = (d - np.floor(d)) * 2 - 1
    d[0] *= math.copysign(1, p[0]) if abs(p[0]) > 1e-6 else 0
    return d * a


# ---- the head: a boxy, slightly forward-leaning head under the hat, a face plate on the front ------
HEAD_R = [(.686, .046, .050, .018), (.706, .068, .074, .012), (.740, .086, .086, .004), (.790, .090, .090, -.004),
          (.832, .080, .080, -.009), (.866, .042, .045, -.014)]
HEAD_E = 2.4
FACE_X = .074
FACE_Y0, FACE_Y1 = .672, .800


def head_z(x, y):
    ys = [r[0] for r in HEAD_R]
    y = min(max(y, ys[0]), ys[-1])
    rx = np.interp(y, ys, [r[1] for r in HEAD_R])
    rz = np.interp(y, ys, [r[2] for r in HEAD_R])
    cz = np.interp(y, ys, [r[3] for r in HEAD_R])
    u = min(1., abs(x) / max(rx, 1e-6))
    return cz + rz * max(0., 1 - u ** HEAD_E) ** (1 / HEAD_E)


# ---- the hat: modelled upright about its own pivot, then tipped back and to her left as one piece ------
# (the painted hat is a rigid, over-large cone resting on the shoulders: the brim is lowest behind and to
# her left, high in front and to her right, and the tip hooks further over)
HAT_PIVOT = A((0., .745, -.004))
HAT_LEAN = (21., 12.)
HAT_R = rotm((1, 0, 0), -HAT_LEAN[1]) @ rotm((0, 0, 1), -HAT_LEAN[0])
BRIM = ((.325, 0.), (.245, .045), (.190, .092))          # radius, lift above the edge
BRIM_ROLL = (.085, .060, .025)
CONE = [(.165, .178), (.255, .146), (.350, .115), (.440, .088), (.520, .062), (.585, .039), (.630, .019), (.652, .004)]
HAT_N = 12


def hat_bend(h):
    s = max(0., (h - .2) / .45)
    return .105 * s * s + .035 * s ** 4, -.040 * s * s


def to_world(q):
    return HAT_PIVOT + HAT_R @ A(q, float)


def hat_local(n=HAT_N):
    """Rows of the hat's outer surface in its own frame (edge .. tip): array (rows, n, 3)."""
    rows = []
    phis = [360. * k / n for k in range(n)]
    for (r, lift), roll in zip(BRIM, BRIM_ROLL):
        row = []
        for p in phis:
            k = max(0., -math.sin(math.radians(p))) ** 1.3          # her right: the brim curls up and out
            rr = r + .03 * k * (r / BRIM[0][0])
            row.append((rr * math.sin(math.radians(p)), lift + roll * k, rr * math.cos(math.radians(p))))
        rows.append(row)
    for h, r in CONE:
        cx, cz = hat_bend(h)
        rows.append([(cx + r * math.sin(math.radians(p)), h, cz + r * math.cos(math.radians(p))) for p in phis])
    P = A(rows, float)
    # hand-made irregularity (mirror-symmetric): the painted hat is crumpled paper
    for r in range(P.shape[0]):
        for c in range(P.shape[1]):
            P[r, c] += hsh(P[r, c], .007 if r < 3 else .005)
    return P


def hat_rows(n=HAT_N):
    P = hat_local(n)
    return A([[to_world(q) for q in row] for row in P])


_tip_x, _tip_z = hat_bend(.34)
BONES['hat_tip'] = ('head', tuple(to_world((_tip_x, .34, _tip_z))))


def row_v(P):
    """Tile v per row: arc length along a profile through the back of the hat (u = 180 degrees)."""
    n = P.shape[1]
    prof = P[:, n // 2]
    d = np.r_[0., np.cumsum(np.linalg.norm(np.diff(prof, axis=0), axis=1))]
    return d / d[-1]


# ---- textures --------------------------------------------------------------------------------------
def c8(c):
    return tuple(int(round(max(0., min(1., x)) * 255)) for x in c)


def paint_hat_tile(P, size=(160, 112)):   # P: hat_local() rows
    """Cylindrical tile: u around (0 = front, running counter-clockwise from above), v from the brim edge to
    the tip. Violet paper, a few darker/lighter facet washes, and soft gold stars sized in metres."""
    W, H = size
    rng = np.random.default_rng(5)
    img = Image.new('RGB', size, c8(HAT_BASE))
    # facet washes: 14 columns x the rows, a small tone offset each, so the tile reads as folded paper
    n = P.shape[1]
    v = row_v(P)
    d = ImageDraw.Draw(img)
    for r in range(len(v) - 1):
        for m in range(n):
            ua, ub = m / n * W, (m + 1) / n * W
            va, vb = v[r] * H, v[r + 1] * H
            for tri in (((ua, va), (ub, va), (ua, vb)), ((ub, va), (ub, vb), (ua, vb))):
                f = HAT_FACET[int(rng.integers(0, len(HAT_FACET)))]
                d.polygon(tri, fill=c8(tuple(HAT_BASE[k] * f[k] for k in range(3))))
    heights = [h for h, _ in CONE]
    radii = [r for _, r in CONE]
    vs = v[3:]
    total = float(np.sum(np.linalg.norm(np.diff(P[:, n // 2], axis=0), axis=1)))
    stars = []
    for i in range(9):
        phi = (137.5 * i + 150) % 360
        h = .17 + .36 * (i / 8.) ** .85
        stars.append((phi, h, .070 - .028 * i / 8.))
    for phi, h, s in stars:
        vv = float(np.interp(h, heights, vs))
        rad = float(np.interp(h, heights, radii))
        cx = phi / 360. * W
        cy = vv * H
        ru = s / (2 * math.pi * max(rad, .02)) * W
        rv = s / total * H
        pts = []
        for k in range(10):
            a = math.pi / 2 + k * math.pi / 5
            f = 1. if k % 2 == 0 else .46
            pts.append((cx + ru * f * math.cos(a), cy - rv * f * math.sin(a)))
        for dx in (-W, 0, W):
            d.polygon([(x + dx, y) for x, y in pts], fill=c8(STAR))
    return img


def paint_face_tile(size=(60, 48)):
    """The visible face: tan, in the brim's shadow above, two big dark eyes, a nose shadow and a small mouth."""
    W, H = size
    img = Image.new('RGB', size)
    d = ImageDraw.Draw(img)
    lit, mid, shade = (.80, .66, .57), (.66, .53, .47), (.45, .36, .34)
    for y in range(H):
        t = y / (H - 1)
        c = tuple(shade[k] + (lit[k] - shade[k]) * smooth(t * 1.9 - .15) for k in range(3))
        d.line([(0, y), (W, y)], fill=c8(c))
    # a faceted plane across the cheeks, like the painted faces
    d.polygon([(0, int(H * .62)), (int(W * .35), int(H * .50)), (W, int(H * .56)), (W, H), (0, H)], fill=c8((.78, .64, .55)))
    d.polygon([(0, int(H * .74)), (int(W * .30), int(H * .66)), (int(W * .22), H), (0, H)], fill=c8(mid))
    d.polygon([(W, int(H * .74)), (int(W * .70), int(H * .66)), (int(W * .78), H), (W, H)], fill=c8(mid))
    # eyes: tall dark ovals with a catch-light, high up under the brim
    for cx in (.30, .70):
        x, y = cx * W, .27 * H
        d.ellipse([x - 5.5, y - 7.5, x + 5.5, y + 7.5], fill=c8((.07, .06, .09)))
        d.rectangle([x - 2.5 + (1 if cx > .5 else 0), y - 5, x - .5 + (1 if cx > .5 else 0), y - 3], fill=c8((.78, .74, .80)))
    d.polygon([(W * .5 - 3, H * .56), (W * .5 + 3, H * .56), (W * .5, H * .50)], fill=c8((.60, .47, .42)))   # nose
    d.polygon([(W * .5 - 4, H * .76), (W * .5 + 4, H * .76), (W * .5, H * .82)], fill=c8((.46, .30, .30)))   # mouth
    return img


# ---- the model --------------------------------------------------------------------------------------
def build_parts(M):
    add = M.add
    # ===== boots and legs
    for s, d in ((1, '.L'), (-1, '.R')):
        bx = s * .066
        shaft = loft([((bx, y, -.003), (rx, 0, 0), (0, 0, rz)) for y, rx, rz in ((.005, .038, .046), (.085, .035, .042), (.150, .033, .037))],
                     8, 2.4, cap=(0, 0), j=.002)
        J, W = weights(M, shaft['V'], lambda p: {'foot' + d: 1. - smooth((p[1] - .10) / .06), 'leg' + d: smooth((p[1] - .10) / .06)})
        add(shaft, 'boot', J=J, W=W)
        foot = loft([((bx, cy, z), (rx, 0, 0), (0, ry, 0)) for z, rx, ry, cy in
                     ((-.055, .040, .026, .034), (.01, .052, .040, .042), (.075, .052, .034, .034), (.135, .036, .022, .024))],
                    8, 2.4, cap=(.012, .02), j=.002)
        add(foot, 'boot', bone='foot' + d)
        sole = loft([((bx, .006, z), (rx, 0, 0), (0, .008, 0)) for z, rx in ((-.055, .036), (.01, .048), (.075, .048), (.135, .030))], 8, 2.4, cap=(.008, .012))
        add(sole, 'sole', bone='foot' + d)
        leg = loft([((bx, .08, 0), (.034, 0, 0), (0, 0, .034)), ((bx, .36, 0), (.040, 0, 0), (0, 0, .040))], 6, 2., cap=(0, 0))
        add(leg, 'leg', bone='leg' + d)

    # ===== robe: a blocky bell, dark yoke above the seam, lighter skirt below; the hem swings with the legs
    rr = [(.150, .205, .152, 0.), (.255, .182, .136, 0.), (.375, .152, .118, 0.), (.385, .150, .116, 0.), (.470, .130, .104, 0.),
          (.545, .126, .097, 0.), (.598, .100, .078, 0.), (.628, .054, .052, 0.)]
    robe = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in rr], 10, 2.6, cap=(0, .004), j=.0035, o=.5)

    def robe_w(p):
        y = p[1]
        w_leg = smooth((.30 - y) / .15) * min(1., abs(p[0]) / .09) * .55
        up = smooth((y - .36) / .14)
        d = {'hips': (1 - up) * (1 - w_leg), 'spine': up}
        if w_leg > 1e-3:
            d['leg.L' if p[0] > 0 else 'leg.R'] = (1 - up) * w_leg
        return d
    J, W = weights(M, robe['V'], robe_w)
    def robe_mat(c, n):
        v = 'abc'[int(abs(math.sin(c[0] * 91.7 + c[1] * 53.3 + c[2] * 37.9) * 43758.5453) % 3)]
        return ('robe_d' if c[1] > .38 else ('robe_hem' if c[1] < .21 else 'robe')) + v
    add(robe, robe_mat, J=J, W=W)

    # ===== a short dark back panel on the cape bone (the painted back is a dark yoke)
    cape = []
    for y, hx, zb in ((.585, .115, -.088), (.50, .130, -.108), (.43, .138, -.114)):
        cape.append([(hx * x, y, zb * (1 - .55 * (x * x))) for x in np.linspace(-1, 1, 5)])
    cp = grid_part(cape, False)      # rows go down, columns toward +X: the winding faces the back
    J, W = weights(M, cp['V'], lambda p: {'cape': smooth((.60 - p[1]) / .08), 'spine': 1. - smooth((.60 - p[1]) / .08)})
    add(cp, 'robe_d', J=J, W=W)

    # ===== arms: dark sleeves with a flared cuff, small dark hands
    for s, d in ((1, '.L'), (-1, '.R')):
        pts = [(s * .136, .585, 0.), (s * .152, .52, 0.), (s * .166, .45, .004), (s * .171, .38, .01), (s * .174, .31, .014)]
        sl = tube(pts, [.040, .038, .036, .037, .048], N=6, ratio=.92, flat=(0, 0, 1.), cap=(.01, 0.))

        def arm_w(p, d=d, s=s):
            lo = smooth((.50 - p[1]) / .10)
            top = smooth((p[1] - .565) / .035)
            return {'arm_upper' + d: (1 - lo) * (1 - top * .5), 'arm_lower' + d: lo, 'spine': (1 - lo) * top * .5}
        J, W = weights(M, sl['V'], arm_w)
        add(sl, lambda c, n: 'cuff' if c[1] < .335 else 'sleeve' + 'abc'[int(abs(math.sin(c[0] * 91.7 + c[1] * 53.3 + c[2] * 37.9) * 43758.5453) % 3)], J=J, W=W)
        hand = loft([((s * .174, y, .016 + z), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, z in
                     ((.322, .034, .030, 0.), (.290, .036, .034, .004), (.262, .028, .028, .008), (.246, .012, .012, .01))], 6, 2.2, cap=(0, .004), j=.002)
        add(hand, 'hand', bone='hand' + d)

    # ===== wand in the right hand, pointing forward and a little down; a gold star on its tip
    base = A((-.174, .275, .030))
    tip = base + N_((0, -.10, 1.)) * .27
    add(tube([base - N_((0, -.10, 1.)) * .03, tip], [.011, .008], N=5, cap=(.004, .004)), 'wand', bone='hand.R')
    sv = []
    for k in range(5):
        a1, a2 = math.pi / 2 + k * 2 * math.pi / 5, math.pi / 2 + (k + .5) * 2 * math.pi / 5
        sv += [(0.022 * math.cos(a1), 0.022 * math.sin(a1)), (0.009 * math.cos(a2), 0.009 * math.sin(a2))]
    V = [tip + A((0, 0, .004))] + [tip + A((x, y, 0.)) + A((0, 0, .002)) for x, y in sv]
    F = [(0, 1 + k, 1 + (k + 1) % 10) for k in range(10)]
    add(dict(V=A(V), F=A(F), ax=A([tip - A((0, 0, .03))]), fb=None), 'wand_star', bone='hand.R')

    # ===== neck, head, face plate, hair
    add(loft([((0, y, 0), (r, 0, 0), (0, 0, r)) for y, r in ((.600, .040), (.690, .036))], 8, 2., cap=(0, 0)), 'skin_d', bone='neck')
    head = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in HEAD_R], 10, HEAD_E, cap=(.004, .004), j=.0015)
    add(head, 'skin_d', bone='head')
    xs = np.linspace(-FACE_X, FACE_X, 9)
    ys = np.linspace(FACE_Y0, FACE_Y1, 6)
    plate = [[(x, y, head_z(x, y) + .004) for x in xs] for y in ys]
    fp_ = grid_part(plate, False, u=[(x + FACE_X) / (2 * FACE_X) for x in xs], v=[(FACE_Y1 - y) / (FACE_Y1 - FACE_Y0) for y in ys])
    add(fp_, 'skin', bone='head', tex='face')

    # the bob: sides and back only (the face stays open), the lower rows follow hairB / hairT
    hair = []
    for y, rx, rz, cz in ((.612, .098, .092, -.026), (.655, .112, .104, -.020), (.730, .116, .108, -.012), (.810, .098, .094, -.006), (.862, .056, .054, -.010)):
        hair.append([(rx * math.sin(math.radians(p)), y, cz + rz * math.cos(math.radians(p)) * (1 if abs(p) > 50 else 1))
                     for p in range(60, 301, 30)])
    hp = grid_part(hair, False)

    def hair_w(p):
        a = smooth((.74 - p[1]) / .08)
        b = smooth((.66 - p[1]) / .06)
        d = '.L' if p[0] > 0 else '.R'
        return {'head': 1 - a, 'hairB' + d: a * (1 - b), 'hairT' + d: a * b}
    J, W = weights(M, hp['V'], hair_w)
    add(hp, lambda c, n: 'hair_l' if n[1] > .5 else 'hair', J=J, W=W)

    # ===== the hat
    P = hat_rows()
    v = row_v(hat_local())
    n = HAT_N
    top = grid_part(P, True, u=[m / n for m in range(n + 1)], v=v)

    def hat_w(p):
        h = float((HAT_R.T @ (p - HAT_PIVOT))[1])
        t = smooth((h - .30) / .20)
        return {'head': 1 - t, 'hat_tip': t}
    J, W = weights(M, top['V'], hat_w)
    add(top, 'hat', J=J, W=W, tex='hat')
    # underside: the same brim a hair lower, facing down (columns run the other way), closing onto the axis
    # above the head; and a rim joining the two along the edge
    def lower(row):
        return [(x, y - .011, z) for x, y, z in row]
    cen = A(P[2]).mean(0) - HAT_R @ A((0, .02, 0))
    lid = [tuple(cen)] * n
    rows_u = [list(reversed(lower(P[r]))) for r in (0, 1, 2)] + [lid]
    add(grid_part(rows_u, True), 'hat_u', bone='head')
    add(grid_part([lower(P[0]), [tuple(q) for q in P[0]]], True), 'hat_r', bone='head')


def base_pose():
    return {}


# ---- clips --------------------------------------------------------------------------------------------
def aim(a, b):
    a, b = N_(a), N_(b)
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else rotm((0, 1, 0), 180)
    K = A([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def rx_(d):
    return glb.rot((1, 0, 0), d)


def ry_(d):
    return glb.rot((0, 1, 0), d)


def rz_(d):
    return glb.rot((0, 0, 1), d)


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


def rest_dirs(side):
    d = '.L' if side > 0 else '.R'
    sh, el, wr = (A(BONES[b + d][1], float) for b in ('arm_upper', 'arm_lower', 'hand'))
    return N_(el - sh), N_(wr - el)


def arm_pose(side, upper, lower, hand_world=None):
    """World directions of the upper arm and forearm -> local rotations (the rest pose hangs, so rotations are
    relative to the hanging directions). `hand_world` is the hand's world rotation (default: follows the forearm)."""
    d = '.L' if side > 0 else '.R'
    ru, rl = rest_dirs(side)
    Ru = aim(ru, upper)
    Rl = aim(rl, lower)
    Rh = Rl if hand_world is None else hand_world
    return {'arm_upper' + d: Ru, 'arm_lower' + d: Ru.T @ Rl, 'hand' + d: Rl.T @ Rh}


WAND_REST = N_((0, -.10, 1.))


def clip_set(M):
    names = M.names
    S = math.sin
    tau = 2 * math.pi

    def full(r):
        for n in names:
            r.setdefault(n, np.eye(3))
        return r

    def idle(t):
        p = t / 4.0
        r = {}
        r['spine'] = rx_(1.0 * S(tau * p)) @ rz_(.5 * S(tau * p * 2 + .4))
        r['neck'] = ry_(3 * S(tau * p - .3))
        r['head'] = rz_(2.5 * S(tau * p + .8)) @ rx_(1.5 * S(tau * p * 2))
        r['hat_tip'] = rz_(7 * S(tau * p * 2 + .3)) @ rx_(4 * S(tau * p + 1.2))
        r['cape'] = rx_(2.0 * S(tau * p - .5))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['arm_upper' + d] = rx_(1.2 * S(tau * p + .3 * sg)) @ rz_(sg * 1.0 * S(tau * p))
            r['hairB' + d] = rz_(sg * 2.5 * S(tau * p + .2))
            r['hairT' + d] = rz_(sg * 4 * S(tau * p - .4)) @ rx_(2 * S(tau * p))
        return full(r), {'hips': (0, .0025 * S(tau * p * 2), 0)}

    def walk(t):
        p = t / 1.0
        ph = tau * p
        r = {}
        sw = 19 * S(ph)
        r['leg.L'] = rx_(-sw)
        r['leg.R'] = rx_(sw)
        r['foot.L'] = rx_(max(0., 12 * S(ph + 1.2)))
        r['foot.R'] = rx_(max(0., 12 * S(ph + 1.2 + math.pi)))
        r['hips'] = ry_(4 * S(ph)) @ rz_(2.5 * S(ph))
        r['spine'] = ry_(-5 * S(ph)) @ rx_(3)
        r['neck'] = ry_(2 * S(ph))
        r['head'] = rz_(-2 * S(ph)) @ rx_(-2)
        r['hat_tip'] = rx_(7 + 4 * S(2 * ph)) @ rz_(5 * S(ph - .6))
        r['cape'] = rx_(6 + 3 * S(2 * ph))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['arm_upper' + d] = rx_(sg * 12 * S(ph))
            r['arm_lower' + d] = rx_(-6 - sg * 4 * S(ph))
            r['hairB' + d] = rz_(sg * 3 * S(2 * ph)) @ rx_(4)
            r['hairT' + d] = rz_(sg * 5 * S(2 * ph - .8)) @ rx_(6 + 3 * S(2 * ph))
        bob = .012 * (1 - math.cos(2 * ph)) / 2
        return full(r), {'hips': (0, bob - .006, 0)}

    def talk(t):
        p = t / 3.0
        ph = tau * p
        r = {}
        r['head'] = rx_(4 * S(ph * 3) * (.6 + .4 * S(ph))) @ rz_(5 * S(ph + .5))
        r['neck'] = ry_(6 * S(ph))
        r['spine'] = rx_(1.5 * S(ph * 2)) @ ry_(3 * S(ph))
        r['hat_tip'] = rz_(8 * S(ph * 2 + .5)) @ rx_(4 * S(ph * 3))
        r['cape'] = rx_(2 * S(ph - .5))
        g = .5 + .5 * S(ph * 2 - 1.0)
        r.update(arm_pose(-1, (-.45, -.60, .60), (-.25 - .15 * g, .45 + .35 * g, .85)))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 2 * S(ph + .2))
            r['hairT' + d] = rz_(sg * 3 * S(ph - .4))
        return full(r), {'hips': (0, .002 * S(ph * 2), 0)}

    def cast(t):
        # 0-.35 s the wand arm goes out and up (the star clear of the hat), then a small flourish; it ends raised
        k = min(1., t / .35)
        k = k * k * (3 - 2 * k)
        r = {}
        lo = arm_pose(-1, rest_dirs(-1)[0], rest_dirs(-1)[1])
        up = arm_pose(-1, (-.80, .55, .15), (-.62, .75, .30), hand_world=aim(WAND_REST, N_((-.40, .85, .35))))
        for n_ in up:
            r[n_] = slerp(lo[n_], up[n_], k)
        fl = max(0., t - .35)
        r['hand.R'] = r['hand.R'] @ rz_(10 * S(fl * 9) * min(1, fl * 3)) @ rx_(8 * S(fl * 7))
        r['spine'] = rx_(-5 * k) @ ry_(-7 * k)
        r['head'] = rx_(-8 * k)
        r['neck'] = ry_(-5 * k)
        r['cape'] = rx_(8 * k)
        r['hat_tip'] = rx_(10 * k) @ rz_(6 * S(fl * 6) * min(1, fl * 2))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 5 * k) @ rx_(4 * k)
            r['hairT' + d] = rz_(sg * (8 * k + 2 * S(fl * 8))) @ rx_(7 * k)
        return full(r), {'hips': (0, .006 * k, 0)}

    return [glb.Clip('idle', 4.0, idle), glb.Clip('walk', 1.0, walk), glb.Clip('talk', 3.0, talk),
            glb.Clip('cast', 1.6, cast, loop=False)]


# ---- export ----------------------------------------------------------------------------------------------
def build(out_dir, preview=None, name='witch'):
    print('witch (painted)')
    M = Model(BONES, COL)
    at = atl.Atlas(256)
    hat_tile = paint_hat_tile(hat_local())
    face_tile = paint_face_tile()
    at.alloc('hat', *hat_tile.size)
    at.alloc('face', *face_tile.size)
    at.paste('hat', hat_tile)
    at.paste('face', face_tile)
    build_parts(M)
    clips = clip_set(M)
    tris = M.flatten()
    arr = bake_uvs(tris, at, M.COL)
    top = float(arr['P'][:, 1].max())
    scale = HEIGHT / top
    ex = dict(variant='painted', tris=len(tris), hood_top_m=HEIGHT, units_per_m=1 / scale)
    path = os.path.join(out_dir, name + '.glb')
    n = glb.export(path, M, arr, at.img, clips, scale, mesh_name='Witch', generator='tools/characters/witch_painted.py', extras=ex)
    print('  %s: %d triangles, %d bones, %d clips, atlas %dx%d (%.0f%% used), top %.3f m'
          % (path, n, len(M.names), len(clips), at.W, at.H, 100 * at.usage(), top * scale))
    print('  authored top %.3f m (scale %.3f)' % (top, scale))
    assert n <= 9000
    if preview:
        import witch_preview as wp
        os.makedirs(preview, exist_ok=True)
        clipd = {c.name: c for c in clips}
        r0, t0 = clipd['idle'].fn(0.)
        posed = glb.pose_arrays(M, arr, r0, t0)
        wp.sixview(posed, at.img, os.path.join(preview, name + '_sixview.png'), '%s idle pose  %d tris' % (name, n))
        for cn in ('walk', 'talk', 'cast'):
            c = clipd[cn]
            frames = []
            for t in np.linspace(0, c.duration, 4, endpoint=c.name == 'cast'):
                rr, tt = c.fn(float(t))
                frames.append(wp.render(glb.pose_arrays(M, arr, rr, tt), at.img, (-.5, -.1, -.85), (0, 1, 0), 240, 300,
                                        crop=(-.8, .8, -.05, 1.4)))
            strip_ = Image.new('RGB', (240 * len(frames), 300))
            for i, f in enumerate(frames):
                strip_.paste(f, (240 * i, 0))
            strip_.save(os.path.join(preview, name + '_' + cn + '.png'))
        at.img.resize((at.W * 2, at.H * 2), Image.NEAREST).save(os.path.join(preview, name + '_atlas.png'))
    return n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--preview', default=None, help='write preview PNGs here')
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    build(a.out, a.preview)


if __name__ == '__main__':
    main()
