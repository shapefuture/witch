#!/usr/bin/env python3
"""The witch of the new references: a purple star-and-moon hooded cloak whose peak is bent back, a ring of pink
flowers on the hood's edge, very long golden-orange hair that ends in big spiral curls sticking out sideways, a
brown vest with two big pockets and a crescent pendant, a flared pleated skirt covered in gold stars and
crescents, a pink star wand in one hand and a small grey bird on the other.

    python tools/characters/witch_ref.py --out assets/characters [--preview DIR]

writes `witch.glb` (the file the game loads) with the skeleton and clip names every witch has had
(`witch.py`, `witch_painted.py`) plus `hat_tip`, the hood's drooping peak. The design comes from the user's own
turnaround sheet and hero render (not in the repository; see docs/art/characters_painted.md). She is seen from
BEHIND in the painted room at about 100 px tall, so the back reads first: the hood and its peak, the lobed
orange hair with its spiral tips, the cloak's hem, the skirt; then the side; the front last.

Authored in metres: y up, she faces +Z, +X is her left, feet at y = 0, the hood's top at 1.33 m. One atlas
(nearest, 5 bit, 256 px): the skirt's and the hood's star tiles, the face, flat colour swatches; one surface.
No baked light: the room lights her (psx_lit_actor.gdshader), so every colour here is albedo.

The rest pose is the pose she holds in the sheet (the wand arm raised, the bird arm held out), not a T-pose:
bones are translation-only, and every clip keys every bone against that rest.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas as atl            # noqa: E402
import witch_glb as glb         # noqa: E402
from witch_kit import A, N_, Model, bake_uvs, blob, catmull, cres3d, loft, rotm, star3d, tube   # noqa: E402

HEIGHT = 1.33
S = math.sin
C = math.cos
RAD = math.radians


# ---- palette: display-referred albedo (the room multiplies it by a warm, dim light) -------------------
COL = {
    'skin': (.94, .73, .62), 'skin_d': (.82, .60, .52), 'blush': (.95, .55, .52),
    'gold': (.95, .76, .38), 'silver': (.88, .88, .95), 'chain': (.66, .50, .30),
    'pink': (.93, .45, .68), 'pink_l': (.98, .64, .80), 'flower_c': (.98, .80, .45),
    'petal': (.80, .44, .72), 'petal_l': (.93, .62, .86), 'petal_d': (.66, .32, .62), 'leaf': (.66, .58, .30),
    'spoon': (.80, .80, .86), 'mouse': (.62, .60, .64), 'mouse_n': (.95, .62, .70), 'feather': (.86, .80, .94),
    'herb': (.45, .62, .38), 'candy_p': (.96, .52, .70), 'candy_g': (.55, .80, .55), 'cookie': (.80, .55, .28),
    'paper': (.90, .84, .68), 'button': (.95, .76, .38),
    'hood_in': (.26, .14, .40), 'hood_rim': (.48, .29, .64),
    'wand': (.62, .30, .42), 'wand_star': (.98, .48, .72),
    'bird': (.62, .66, .74), 'bird_d': (.46, .50, .60), 'bird_l': (.92, .93, .95), 'beak': (.30, .26, .24),
    'item_a': (.95, .62, .25), 'item_b': (.70, .62, .86), 'item_c': (.62, .72, .52), 'item_d': (.85, .80, .72),
    'boot': (.26, .16, .12),
}
FAMILIES = {          # name: (base colour, relative spread): four tones per flat-coloured material, like paper folds
    'hair': ((.94, .60, .27), .17), 'purple': ((.44, .25, .62), .12), 'sleeve': ((.40, .23, .58), .12),
    'cuff': ((.47, .28, .63), .08), 'vest': ((.38, .27, .22), .12), 'pocket': ((.29, .20, .16), .12),
    'cloak': ((.39, .22, .55), .12),
}


def _family(name, base, spread, n=4):
    for k in range(n):
        m = 1 + spread * (k - (n - 1) / 2) / ((n - 1) / 2)
        COL['%s%d' % (name, k)] = tuple(min(1., c * m) for c in base)


for _n, (_b, _s) in FAMILIES.items():
    _family(_n, _b, _s)


def hsh1(c):
    """Deterministic 0..1 from a position (so the same facet always gets the same tone)."""
    return (math.sin(c[0] * 91.7 + c[1] * 53.3 + c[2] * 37.9) * 43758.5453) % 1.


def toned(name, n=4):
    return lambda c, nrm: '%s%d' % (name, int(hsh1(c) * n) % n)


def lit_toned(name, n=4):
    """Like `toned`, but faces that look up take the lighter tones (paper catches light on its tops)."""
    return lambda c, nrm: '%s%d' % (name, min(n - 1, max(0, int(hsh1(c) * 2 + (1 if nrm[1] > .35 else 0) + (1 if nrm[1] > .8 else 0) - (1 if nrm[1] < -.3 else 0)))))


# ---- skeleton (absolute rest positions; the parent only builds the hierarchy) ---------------------------
BONES = {'root': (None, (0, 0, 0)), 'hips': ('root', (0, .30, 0)), 'spine': ('hips', (0, .41, 0)),
         'neck': ('spine', (0, .86, 0)), 'head': ('neck', (0, .93, 0)), 'cape': ('spine', (0, .84, -.08)),
         'hat_tip': ('head', (0, 1.10, -.22))}
ARM = {'.L': ((.20, .80, -.01), (.275, .655, .025), (.285, .715, .165)),       # shoulder, elbow, wrist
       '.R': ((-.20, .80, -.01), (-.28, .67, .015), (-.30, .785, .125))}
for _s, _d in ((1, '.L'), (-1, '.R')):
    BONES['arm_upper' + _d] = ('spine', ARM[_d][0])
    BONES['arm_lower' + _d] = ('arm_upper' + _d, ARM[_d][1])
    BONES['hand' + _d] = ('arm_lower' + _d, ARM[_d][2])
    BONES['leg' + _d] = ('hips', (_s * .07, .30, 0))
    BONES['foot' + _d] = ('leg' + _d, (_s * .07, .07, .03))
    BONES['hairB' + _d] = ('head', (_s * .19, .90, -.07))
    BONES['hairT' + _d] = ('hairB' + _d, (_s * .31, .62, -.12))
BONES['bird'] = ('hand.L', (.285, .77, .200))


# ---- helpers ---------------------------------------------------------------------------------------------
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


def gp(P, wrap, skip=(), u=None, v=None, th=.012):
    """Quad-facet surface from points P[row, column]. Rows go up and columns turn counter-clockwise seen from above
    (or toward +X on a front plate), so the winding faces outward. `skip`: set of (band, column) quads left out."""
    P = A(P, float)
    R, Cc = P.shape[:2]
    cols = Cc if wrap else Cc - 1
    F, FUV = [], []
    for r in range(R - 1):
        for m in range(cols):
            if (r, m) in skip:
                continue
            a, b = r * Cc + m, r * Cc + (m + 1) % Cc
            F += [(a, b, a + Cc), (b, b + Cc, a + Cc)]
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
    # one anchor just behind each face, so the kit never flips a face whose winding is already right
    # (a sharp ridge like the peak disagrees with the averaged vertex normals)
    ln = np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    part = dict(V=V, F=F, ax=Q.mean(1) - th * fn / ln, fb=None)
    if u is not None:
        part['fuv'] = A(FUV, float)
    return part


def ring(y, rx, rz, cz=0., cx=0., n=12, phi0=0., e=2., phis=None):
    """Points of one ring, phi measured from +Z toward +X."""
    out = []
    for p in (phis if phis is not None else [phi0 + 360. * k / n for k in range(n)]):
        t = RAD(p)
        s_, c_ = S(t), C(t)
        if e != 2:
            s_ = math.copysign(abs(s_) ** (2 / e), s_)
            c_ = math.copysign(abs(c_) ** (2 / e), c_)
        out.append((cx + rx * s_, y, cz + rz * c_))
    return out


def c8(c):
    return tuple(int(round(max(0., min(1., x)) * 255)) for x in c)


# ---- the skirt: twelve flat panels, a cone that flares to a wide hem ---------------------------------------
SK_Y = (0., .14, .285, .43)
SK_R = (.460, .385, .300, .225)
SK_N = 12
SK_PHI0 = 15.        # panels centred on 0 (front) and 180 (back)
SK_DEPTH = (1., .94, .86, .80)
SKIRT_BASE = (.41, .23, .57)     # the hood's deep violet (the sheet's skirt and hood are one cloth)   # each row's depth over its width: the waist is oval under the slim vest
VEST_DZ = -.048                  # the vest's front things sit this far back of where they were first placed (slimmer vest)


def skirt_pts():
    rows = []
    for y, r, dp in zip(SK_Y, SK_R, SK_DEPTH):
        fade = 1 - y / SK_Y[-1]
        rows.append([(r * (1 - (.045 if k % 2 else 0.) * fade) * S(RAD(SK_PHI0 + 360. * k / SK_N)), y,
                      dp * r * (1 - (.045 if k % 2 else 0.) * fade) * C(RAD(SK_PHI0 + 360. * k / SK_N))) for k in range(SK_N)])
    return A(rows, float)


# ---- the head -----------------------------------------------------------------------------------------------
# the jaw rows hug the face's outline (tools/characters/ref/witch_face.json), so the head never shows around her chin
HEAD_R = [(.905, .036, .050, -.010), (.935, .050, .100, .000), (.960, .086, .115, -.005), (.990, .112, .125, -.015),
          (1.060, .135, .130, -.025),
          (1.130, .125, .125, -.030), (1.190, .100, .100, -.040), (1.235, .050, .060, -.040)]
HEAD_E = 2.2
FACE_X = .115
FACE_Y0, FACE_Y1 = .922, 1.172


def head_z(x, y):
    ys = [r[0] for r in HEAD_R]
    y = min(max(y, ys[0]), ys[-1])
    rx = np.interp(y, ys, [r[1] for r in HEAD_R])
    rz = np.interp(y, ys, [r[2] for r in HEAD_R])
    cz = np.interp(y, ys, [r[3] for r in HEAD_R])
    u = min(1., abs(x) / max(rx, 1e-6))
    return cz + rz * max(0., 1 - u ** HEAD_E) ** (1 / HEAD_E)


# ---- the hood: a dome with a front opening, the peak folded back into a tip below its top ------------------------
HOOD_N = 12
HOOD_ROWS = [(.89, .228, .204, -.072), (.98, .244, .206, -.066), (1.07, .244, .200, -.054), (1.165, .222, .176, -.040),
             (1.25, .172, .140, -.020), (1.312, .098, .084, -.008), (1.332, .036, .030, -.002)]
HOOD_HEM_DIP = .035                          # the bottom edge hangs this much lower at the centre back (draped, not a ring)
HOOD_FRONT_BANDS = (0, 1, 2)                 # bands below the brow ring are open at the front...
HOOD_OPEN_COLS = (10, 11, 0, 1)              # ...in these columns (phi -60 .. +60)
HOOD_TIP = (0., 1.07, -.355)                # the folded peak, back and below the top


def hood_pts():
    P = np.array([ring(y, rx, rz, cz, n=HOOD_N) for y, rx, rz, cz in HOOD_ROWS], float)
    # the peak: the back-centre column is pulled out to the tip and its neighbours half way (a ridge, then a point)
    k6 = HOOD_N // 2
    P[3, k6] = HOOD_TIP
    for dk in (-1, 1):
        P[3, k6 + dk] += (0., .008, -.060)
    P[4, k6] += (0., -.015, -.080)
    P[2, k6] += (0., .0, -.020)
    P[2, k6 - 1] += (0., 0., -.008)
    P[2, k6 + 1] += (0., 0., -.008)
    P[5, k6] += (0., 0., -.012)
    for c in range(HOOD_N):
        P[0, c, 1] -= HOOD_HEM_DIP * max(0., -C(RAD(360. * c / HOOD_N)))
    # hand-made crumple (mirror-symmetric): paper, not a lathe
    for r in range(P.shape[0]):
        for c in range(P.shape[1]):
            P[r, c] += hsh3(P[r, c], .010 if r < 5 else .004)
    return P


def hsh3(p, a):
    x, y, z = abs(p[0]), p[1], p[2]
    d = A([math.sin(x * 127.1 + y * 311.7 + z * 74.7 + k * 19.19) * 43758.5453 for k in range(3)])
    d = (d - np.floor(d)) * 2 - 1
    d[0] *= math.copysign(1, p[0]) if abs(p[0]) > 1e-6 else 0
    return d * a


def hood_skip():
    return {(b, (c) % HOOD_N) for b in HOOD_FRONT_BANDS for c in HOOD_OPEN_COLS if b > 0 or c in (11, 0)}


# ---- hair ---------------------------------------------------------------------------------------------------------
def turtle(p0, th0, stalk, r0, r1, turns, dirn, seg=45., dz=0., dzs=0.):
    """A polyline in the XY plane (the picture plane when she is seen from behind or in front): a stalk of
    (length, turn) steps, then a spiral of `turns` turns from radius r0 down to r1. Angles in degrees,
    0 = +X, counter-clockwise."""
    pts = [A(p0, float)]
    th = th0
    for length, dth in stalk:
        th += dth
        pts.append(pts[-1] + length * A((C(RAD(th)), S(RAD(th)), dzs / len(stalk) / max(length, 1e-6))))
    n = max(2, int(round(turns * 360. / seg)))
    z0 = pts[-1][2]
    for i in range(n):
        f = (i + .5) / n
        r = r0 + (r1 - r0) * f
        d = dirn * seg
        mid = RAD(th + d / 2)
        ds = 2 * r * S(RAD(seg) / 2)
        pts.append(pts[-1] + ds * A((C(mid), S(mid), 0.)) + A((0, 0, dz / n)))
        th += d
    return A(pts), z0


def spiral_on(stalk, r0, r1, turns, dirn, seg):
    """A stalk (any 3D polyline) continued by a flat spiral in the XY plane that starts along the stalk's last
    direction (projected), shrinking from radius r0 to r1."""
    pts = [A(q, float) for q in stalk]
    d = pts[-1] - pts[-2]
    th = math.degrees(math.atan2(d[1], d[0]))
    n = max(2, int(round(turns * 360. / seg)))
    for i in range(n):
        r = r0 + (r1 - r0) * (i + .5) / n
        mid = RAD(th + dirn * seg / 2)
        pts.append(pts[-1] + 2 * r * S(RAD(seg) / 2) * A((C(mid), S(mid), 0.)))
        th += dirn * seg
    return A(pts)


def mirror_x(P):
    Q = P.copy()
    Q[:, 0] *= -1
    return Q


# Side curls, one per row, for her left (+x); the right side is the mirror image with a small change.
# name, start xyz, heading deg (0 = +X, counter-clockwise), stalk [(length, turn)], r0, r1, turns, dirn (+1 = counter-clockwise),
# strand half-width, z drift over the spiral
CURLS = [
    ('lock_big', (.215, .90, -.045), -45, [(.07, 0), (.07, -8)], .080, .040, 1.1, +1, .038, -.03),
    # the hip curls, the widest point of her outline: from under the hood's back, down and out
    ('side_mid', (.200, .845, -.135), -66, [(.08, 0), (.08, -8), (.07, 10)], .086, .040, 1.15, +1, .040, -.02),
    # one small curl high on her left only, hugging the hood beside the flowers (the sheet is not symmetric there)
    ('hood_hi', (.165, 1.150, .040), 62, [(.050, 0), (.045, -22)], .042, .016, 1.20, -1, .030, -.02, -.02),
]
CURLS_ONE_SIDE = {'hood_hi': 1}
# the curls on her right: a different spiral radius and turn count so the two sides do not match
CURLS_R_TWEAK = {'lock_big': dict(r0=.082, turns=1.2), 'side_mid': dict(r0=.080, turns=1.4)}
# The hair that frames her face, one continuous lock a side: from under the flowers down the cheek, in front of the
# hood's lower edge, over the shoulder, then behind the arm down to the hip, where it ends in a big outward curl.
FRAME = [(.172, 1.160, .020), (.188, 1.070, .036), (.200, .975, .078), (.222, .900, .078), (.262, .830, -.020),
         (.290, .740, -.095), (.300, .650, -.105), (.300, .580, -.100)]
FRAME_CURL = dict(r0=.072, r1=.038, turns=1.1)

# The long back hair: a lobed mass under the hood's back edge (a bulb, every lobe a flute) from which eight thick locks
# hang side by side down to the waist, each ending in a curl, like the sheet's back view (an octopus of hair).
MASS_PHIS = [75 + 15 * k for k in range(15)]                 # 75 .. 285 degrees: the sides and the back
MASS_ROWS = [(.70, .180, .140, -.095), (.78, .232, .190, -.100), (.86, .240, .196, -.105), (.92, .200, .150, -.108), (.99, .160, .115, -.105)]
# (degrees from the back's centre, stalk length, curl turns: +1 counter-clockwise seen from behind... as drawn, radius)
# (degrees round from the back's centre, stalk step, curl: 'out' or 'in' toward her middle, curl radius, lock radius).
# The outer locks splay and end in big outward spirals (the hair is widest at the bottom); the inner ones curl in;
# the middle one is short, with a small spiral at mid-back.
LOCKS = [(-76, .066, 'out', .080, .034), (-57, .092, 'out', .064, .036), (-38, .118, 'in', .054, .038),
         (-19, .136, 'in', .048, .038), (0, .052, 'in', .038, .036), (19, .132, 'out', .050, .038),
         (38, .114, 'out', .056, .038), (57, .088, 'in', .060, .036), (76, .064, 'out', .078, .034)]


def mass_pts():
    """Rows (bottom first) of the hair mass; lobes alternate in radius, every second bottom hangs a little lower."""
    rows = []
    for ri, (y, rx, rz, cz) in enumerate(MASS_ROWS):
        row = []
        for k, p in enumerate(MASS_PHIS):
            lob = 1.0 if (k % 2 == 0 or ri > 1) else .94    # only the lower rows are lobed: the top is a smooth edge tucked under the hood
            yy = y - (.03 if (ri == 0 and k % 2 == 1) else 0.)
            row.append((rx * lob * S(RAD(p)), yy, cz + rz * lob * C(RAD(p))))
        rows.append(row)
    return A(rows, float)


TILT = .30        # the curls' planes lean back at the bottom, so their faces tilt up toward the room's key light
CURL_SEG = 36.    # degrees per spiral step: ten a turn, so a curl reads round, not as a paper clip
BACK_TILT = .08   # the back locks lean less: they hang close over the cloak, as on the sheet


def curl_paths():
    out = []
    for row in CURLS:
        name, p0, th0, stalk, r0, r1, turns, dirn, width, dz = row[:10]
        dzs = row[10] if len(row) > 10 else 0.
        for side in (1, -1):
            if side not in (CURLS_ONE_SIDE.get(name, side),):
                continue
            kw = dict(r0=r0, r1=r1, turns=turns)
            if side < 0:
                kw.update(CURLS_R_TWEAK.get(name, {}))
            seg = CURL_SEG
            pts, z0 = turtle(p0, th0, stalk, kw['r0'], kw['r1'], kw['turns'], dirn, seg, dz, dzs)
            if side < 0:
                pts = mirror_x(pts)
            pts[:, 2] += TILT * (pts[:, 1] - pts[0, 1])
            out.append((name, side, pts, width, 6 if width > .045 else 5, len(stalk)))
    for side in (1, -1):
        stalk = catmull(A(FRAME, float), 4)
        pts = spiral_on(stalk, FRAME_CURL['r0'], FRAME_CURL['r1'], FRAME_CURL['turns'] - (.1 if side < 0 else 0.), +1, CURL_SEG)
        if side < 0:
            pts = mirror_x(pts)
        out.append(('frame', side, pts, .040, 6, len(stalk) - 1))
    y0, rx, rz, cz = MASS_ROWS[2]
    for off, length, way, r0, width in LOCKS:
        phi = RAD(180 + off)
        p0 = A((rx * .97 * S(phi), y0 + .012, cz + rz * .97 * C(phi)))
        # built hanging in the back's plane as if at the centre, then turned half way round her toward its own place, so
        # the outer curls face back and out (they show from the side too) while their splay still widens her outline
        s_ = 1 if off < 0 else -1 if off > 0 else 1                # her left (+x) for the locks left of the centre
        dirn = s_ if way == 'out' else -s_
        splay = -off * .50          # rays: every lock leaves the hood's rim pointing away from the back's centre
        wave = 7. * dirn
        stalk = [(length, splay * .30 + wave), (length, splay * .15 - 2 * wave), (length * .85, -splay * .20 + wave)]
        local, _ = turtle(A((0., p0[1], 0.)), -90. + splay * .5, stalk, r0, .034, 1.15, dirn, CURL_SEG, dz=.012)
        local[:, 2] += BACK_TILT * (local[:, 1] - local[0, 1])
        local[:, 2] *= -1                                          # the back's plane faces -z
        rot = rotm((0, 1, 0), off * .5)
        pts = A([p0 + rot @ (q - A((0., p0[1], 0.))) for q in local])
        out.append(('tail', 1 if pts[0][0] >= 0 else -1, pts, width, 6, 3))
    return out


# ---- textures --------------------------------------------------------------------------------------------------------
GOLD = (.95, .76, .38)


def star_poly(cx, cy, ro, ri, n, rot=-math.pi / 2, sx=1., sy=1.):
    pts = []
    for k in range(2 * n):
        a = rot + k * math.pi / n
        r = ro if k % 2 == 0 else ri
        pts.append((cx + sx * r * math.cos(a), cy + sy * r * math.sin(a)))
    return pts


def crescent_poly(cx, cy, R, sx=1., sy=1., rot=0., n=10, d=.5, rb=.82):
    """A crescent as one polygon: the outer arc, then the inner arc back."""
    d *= R
    rb *= R
    xx = (d * d + R * R - rb * rb) / (2 * d)
    yy = math.sqrt(max(R * R - xx * xx, 1e-9))
    th0 = math.atan2(yy, xx)
    bt = math.atan2(yy, xx - d)
    o = [(R * math.cos(t), R * math.sin(t)) for t in np.linspace(th0, 2 * math.pi - th0, n)]
    i = [(d + rb * math.cos(t), rb * math.sin(t)) for t in np.linspace(2 * math.pi - bt, bt, n)]
    out = []
    cr, sr = math.cos(rot), math.sin(rot)
    for x, y in o + i:
        x -= .35 * R
        out.append((cx + sx * (x * cr - y * sr), cy + sy * (x * sr + y * cr)))
    return out


def draw_symbol(d, kind, cx, cy, size, sx, sy, k, col):
    """size in metres; sx, sy = pixels per metre along the tile's x and y; k = supersampling factor."""
    if kind == 'moon':
        pts = crescent_poly(cx * k, cy * k, size * sx * k, 1., sy / sx, rot=.6)
    elif kind == 'star8':
        pts = star_poly(cx * k, cy * k, size * sx * k, size * sx * k * .42, 8, sy=sy / sx)
    elif kind == 'star5':
        pts = star_poly(cx * k, cy * k, size * sx * k, size * sx * k * .46, 5, sy=sy / sx)
    else:
        pts = star_poly(cx * k, cy * k, size * sx * k * .6, size * sx * k * .6, 4, sy=sy / sx)
    d.polygon(pts, fill=col)


def paint_skirt_tile(size=(240, 56)):
    """Cylindrical tile: u around (panel k = columns k*20..k*20+20, panel 0 centred on the front), v from the waist
    (top) to the hem (bottom). Violet paper, one tone per panel and triangle, gold stars and moons sized in metres."""
    W, H = size
    k = 4
    rng = np.random.default_rng(3)
    img = Image.new('RGB', (W * k, H * k), c8(SKIRT_BASE))
    d = ImageDraw.Draw(img)
    base = np.array(SKIRT_BASE)
    pw = W / SK_N
    rows = len(SK_Y) - 1
    for r in range(rows):
        for m in range(SK_N):
            for tri in range(2):
                f = 1 + rng.uniform(-.13, .13)
                col = tuple(min(1., c * f) for c in base)
                ua, ub = m * pw * k, (m + 1) * pw * k
                va, vb = (rows - 1 - r) / rows * H * k, (rows - r) / rows * H * k
                # row r of the grid goes up from the hem, and the tile's v runs down, so rows are flipped
                pts = [(ua, vb), (ub, vb), (ua, va)] if tri == 0 else [(ub, vb), (ub, va), (ua, va)]
                d.polygon(pts, fill=c8(col))
    slant = math.hypot(SK_R[0] - SK_R[-1], SK_Y[-1])
    py = H / slant                                           # tile px per metre along the slant
    syms = ('moon', 'star8', 'star5', 'star8', 'dot', 'moon', 'star5')
    for m in range(SK_N):
        placed = []
        for _ in range(60):
            fu, fv = rng.uniform(.18, .82), rng.uniform(.10, .92)          # fv: 0 top, 1 hem
            if all(abs(fu - a) * 1. > .26 or abs(fv - b) > .22 for a, b in placed):
                placed.append((fu, fv))
            if len(placed) >= 4:
                break
        for i, (fu, fv) in enumerate(placed):
            y = (1 - fv) * SK_Y[-1]
            rad = float(np.interp(y, SK_Y, SK_R))
            chord = 2 * rad * S(RAD(15.))
            px = pw / chord
            kind = syms[(m * 3 + i * 5 + int(rng.integers(0, 3))) % len(syms)]
            sym = {'moon': .040, 'star8': .031, 'star5': .034, 'dot': .018}[kind]
            col = c8(GOLD)
            draw_symbol(d, kind, (m * pw + fu * pw), fv * H, sym, px, py, k, col)
    return img.resize(size, Image.LANCZOS)


def paint_sleeve_tile(size=(48, 40), n_around=6, n_along=4):
    """Tile for a sleeve tube: u around (n_around facets), v along (n_along bands). Violet, a tone per triangle, a few
    gold moons and stars (the sheet's sleeves are printed like the skirt)."""
    W, H = size
    k = 4
    rng = np.random.default_rng(21)
    base = np.array((.40, .23, .58))
    img = Image.new('RGB', (W * k, H * k), c8(base))
    d = ImageDraw.Draw(img)
    for r in range(n_along):
        for m in range(n_around):
            for tri in range(2):
                f = 1 + rng.uniform(-.12, .12)
                ua, ub = m * W / n_around * k, (m + 1) * W / n_around * k
                va, vb = r * H / n_along * k, (r + 1) * H / n_along * k
                pts = [(ua, va), (ub, va), (ua, vb)] if tri == 0 else [(ub, va), (ub, vb), (ua, vb)]
                d.polygon(pts, fill=c8(tuple(min(1., c * f) for c in base)))
    px = W / (2 * math.pi * .062)             # tile px per metre round the sleeve
    py = H / .36                              # and along it
    for i, (fu, fv, kind) in enumerate(((.10, .30, 'moon'), (.42, .62, 'star8'), (.75, .25, 'star5'), (.60, .86, 'moon'),
                                         (.25, .80, 'star8'), (.90, .62, 'dot'))):
        draw_symbol(d, kind, fu * W, fv * H, {'moon': .034, 'star8': .026, 'star5': .028, 'dot': .014}[kind], px, py, k,
                    c8(GOLD))
    return img.resize(size, Image.LANCZOS)


def cyl_fuv(part):
    """Per-face UVs from a loft's cylindrical per-vertex UVs, with the seam's wrapped faces fixed (u 0 -> 1 there)."""
    uv = part['uvc']
    out = []
    for f in part['F']:
        q = uv[f].copy()
        if q[:, 0].max() - q[:, 0].min() > .5:
            q[q[:, 0] < .5, 0] += 1.
        q[:, 0] = np.minimum(q[:, 0], 1.)
        out.append(q)
    return A(out, float)


def hood_v(P):
    """Tile v per hood ring: arc length from the bottom edge to the top along the back (column 6)."""
    prof = P[:, HOOD_N // 2]
    d = np.r_[0., np.cumsum(np.linalg.norm(np.diff(prof, axis=0), axis=1))]
    return d / d[-1], float(d[-1])


def paint_hood_tile(P, size=(144, 60)):
    """u around (column m = 12 px; column 0 is the front), v from the hood's bottom edge (top of the tile) to its top.
    Violet, a tone per triangle, gold stars and moons in metres."""
    W, H = size
    k = 4
    rng = np.random.default_rng(11)
    base = np.array((.43, .25, .62))
    img = Image.new('RGB', (W * k, H * k), c8(base))
    d = ImageDraw.Draw(img)
    v, total = hood_v(P)
    rows = P.shape[0] - 1
    pw = W / HOOD_N
    for r in range(rows):
        for m in range(HOOD_N):
            for tri in range(2):
                f = 1 + rng.uniform(-.16, .16)
                col = tuple(min(1., c * f) for c in base)
                ua, ub = m * pw * k, (m + 1) * pw * k
                va, vb = v[r] * H * k, v[r + 1] * H * k
                pts = [(ua, va), (ub, va), (ua, vb)] if tri == 0 else [(ub, va), (ub, vb), (ua, vb)]
                d.polygon(pts, fill=c8(col))
    py = H / total
    heights = [row[0] for row in HOOD_ROWS]
    vs = list(v)
    slots = []
    for _ in range(400):
        phi = rng.uniform(0, 360)
        h = rng.uniform(.95, 1.29)
        if h < 1.16 and (phi < 62 or phi > 298):
            continue                                     # the open front
        if h >= 1.16 and (phi < 25 or phi > 335):
            continue
        if all(min(abs(phi - a), 360 - abs(phi - a)) > 42 or abs(h - b) > .085 for a, b in slots):
            slots.append((phi, h))
        if len(slots) >= 15:
            break
    syms = ('star8', 'moon', 'star5', 'star8', 'dot', 'star8', 'moon')
    for i, (phi, h) in enumerate(slots):
        rad = float(np.interp(h, heights, [row[1] for row in HOOD_ROWS]))
        chord = 2 * math.pi * rad / HOOD_N
        px = pw / chord
        kind = syms[i % len(syms)]
        size_m = {'moon': .052, 'star8': .040, 'star5': .042, 'dot': .02}[kind] * (1.15 if h < 1.12 else .85)
        cy = float(np.interp(h, heights, vs)) * H
        draw_symbol(d, kind, phi / 360. * W, cy, size_m, px, py, k, c8(GOLD))
    return img.resize(size, Image.LANCZOS)


# ---- the face from the user's close-up (tools/characters/face_from_ref.py writes ref/witch_face.png + .json) --------------
FACE_REF = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ref', 'witch_face')
EYE_Y = 1.057                                    # where the eye line sits on the head (the painted plate's was the same)


def face_ref():
    """(meta, tile image, depth or None) of the face cut out of the reference, or None when the tile has not been made.
    The depth (0..1 per texel of the tile, 1 nearest) is the depth model's, unitless."""
    if not (os.path.exists(FACE_REF + '.json') and os.path.exists(FACE_REF + '.png')):
        return None
    with open(FACE_REF + '.json') as fh:
        meta = json.load(fh)
    depth = None
    if os.path.exists(FACE_REF + '_depth.png'):
        depth = np.asarray(Image.open(FACE_REF + '_depth.png').convert('L'), float) / 255.
    return meta, Image.open(FACE_REF + '.png').convert('RGB'), depth


def membrane(values, mask):
    """The smoothest surface (Laplace) through `values` on the mask's border, over the mask's inside."""
    from scipy import sparse
    from scipy.sparse.linalg import spsolve
    inner = mask.copy()
    inner[0, :] = inner[-1, :] = inner[:, 0] = inner[:, -1] = False
    inner[1:-1, 1:-1] &= mask[:-2, 1:-1] & mask[2:, 1:-1] & mask[1:-1, :-2] & mask[1:-1, 2:]
    idx = -np.ones(mask.shape, int)
    ys, xs = np.nonzero(inner)
    idx[ys, xs] = np.arange(len(ys))
    rows, cols, vals = [], [], []
    b = np.zeros(len(ys))
    for k, (y, x) in enumerate(zip(ys, xs)):
        rows.append(k), cols.append(k), vals.append(4.)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            j = idx[y + dy, x + dx]
            if j >= 0:
                rows.append(k), cols.append(j), vals.append(-1.)
            else:
                b[k] += values[y + dy, x + dx]
    out = values.astype(float).copy()
    out[ys, xs] = spsolve(sparse.csr_matrix((vals, (rows, cols)), shape=(len(ys), len(ys))), b)
    return out


def _inside(poly, pts):
    """Even-odd test of points against a polygon, both (n, 2)."""
    x, y = pts[:, 0], pts[:, 1]
    inside = np.zeros(len(pts), bool)
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        cross = ((y1 > y) != (y2 > y)) & (x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-12) + x1)
        inside ^= cross
    return inside


FACE_POINTS = 110          # vertices of the sculpted face (the outline's 40 included)
FACE_TOL = .0012           # ...or fewer, once no texel's relief is further than this from the facets (metres)
FACE_LIFT = .004           # the plate floats this far off the head, so the head never shows through it
FACE_RELIEF = .8           # the depth model's relief, scaled (1: as measured; the sheet's profile is flatter)


def face_height(meta, depth):
    """z of the face on every texel of its tile (NaN outside the outline). The depth model's face is much flatter than
    the head it sits on and has no unit, so only its relief is used: how far each texel stands out of the smooth surface
    its own outline spans (nose, brows, cheeks, lips, chin; the eye sockets lower), in the unit that best fits the
    depth to the head, raised off the head's own surface. On the outline the relief is nil, so the face meets the head."""
    w_m, h_m = meta['size_m']
    mid_u, eye_v = meta['mid_u'], meta['eye_line_v']
    th, tw = depth.shape
    u, v = np.meshgrid((np.arange(tw) + .5) / tw, (np.arange(th) + .5) / th)
    X, Y = (u - mid_u) * w_m, EYE_Y - (v - eye_v) * h_m
    H = np.vectorize(head_z)(X, Y)
    xy_out = A([((a - mid_u) * w_m, EYE_Y - (b - eye_v) * h_m) for a, b in meta['outline']])
    inside = _inside(xy_out, np.stack([X.ravel(), Y.ravel()], 1)).reshape(X.shape)
    ring = inside.copy()
    ring[1:-1, 1:-1] |= inside[:-2, 1:-1] | inside[2:, 1:-1] | inside[1:-1, :-2] | inside[1:-1, 2:]
    relief = depth - membrane(np.where(ring, depth, 0.), ring)
    unit = np.polyfit(depth[inside], H[inside], 1)[0]          # metres per unit of the model's depth
    Z = H + FACE_LIFT + np.maximum(relief, 0.) * unit * FACE_RELIEF
    Z[~inside] = np.nan
    return X, Y, Z, xy_out, unit


def face_plate_ref(meta, depth=None, spacing=.03):
    """The face's own outline as a mesh. With a relief: sculpted, vertices added one at a time where the facets so far
    miss the relief most (the low-poly look of the reference: big planes on the cheeks, many small ones at the nose,
    brows, lips). Without: a loose grid that follows the head. UVs are where each point sits in the tile."""
    from scipy.spatial import Delaunay
    w_m, h_m = meta['size_m']
    mid_u, eye_v = meta['mid_u'], meta['eye_line_v']
    if depth is not None:
        X, Y, Z, xy_out, _ = face_height(meta, depth)
        ok = ~np.isnan(Z)
        cand = np.stack([X[ok], Y[ok]], 1)
        cz = Z[ok]
        d = np.min(np.linalg.norm(cand[:, None, :] - xy_out[None, :, :], axis=2), axis=1)
        cand, cz = cand[d > .008], cz[d > .008]
        pts, zs = list(xy_out), [head_z(x, y) + FACE_LIFT for x, y in xy_out]
        while len(pts) < FACE_POINTS:
            P2 = A(pts)
            tri = Delaunay(P2)
            simp = tri.find_simplex(cand)
            T = tri.transform[simp]
            bc = np.einsum('nij,nj->ni', T[:, :2], cand - T[:, 2])
            bary = np.concatenate([bc, 1 - bc.sum(1, keepdims=True)], 1)
            zl = np.sum(A(zs)[tri.simplices[simp]] * bary, 1)
            err = np.abs(zl - cz)
            err[simp < 0] = 0.
            k = int(np.argmax(err))
            if err[k] < FACE_TOL:
                break
            pts.append(cand[k])
            zs.append(cz[k])
        pts, zs = A(pts), A(zs)
    else:
        xy_out = A([((u - mid_u) * w_m, EYE_Y - (v - eye_v) * h_m) for u, v in meta['outline']])
        lo, hi = xy_out.min(0), xy_out.max(0)
        gx, gy = np.meshgrid(np.arange(lo[0], hi[0], spacing), np.arange(lo[1], hi[1], spacing))
        grid = np.stack([gx.ravel(), gy.ravel()], 1)
        grid = grid[_inside(xy_out, grid)]
        if len(grid):
            d = np.min(np.linalg.norm(grid[:, None, :] - xy_out[None, :, :], axis=2), axis=1)
            grid = grid[d > spacing * .45]
        pts = np.concatenate([xy_out, grid], 0)
        zs = A([head_z(x, y) + FACE_LIFT for x, y in pts])
    tri = Delaunay(pts).simplices
    cen = pts[tri].mean(1)
    tri = tri[_inside(xy_out, cen)]
    V = np.concatenate([pts, zs[:, None]], 1)
    F = []
    for a, b, c in tri:
        cr = (pts[b, 0] - pts[a, 0]) * (pts[c, 1] - pts[a, 1]) - (pts[b, 1] - pts[a, 1]) * (pts[c, 0] - pts[a, 0])
        F.append((a, b, c) if cr > 0 else (a, c, b))
    F = A(F, int)
    uv = A([(mid_u + x / w_m, eye_v - (y - EYE_Y) / h_m) for x, y in pts], float)
    Q = V[F]
    fn = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
    ln = np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    return dict(V=V, F=F, ax=Q.mean(1) - .012 * fn / ln, fb=None, fuv=uv[F])


def paint_face_tile(size=(64, 56)):
    """The face plate: peach skin with planes, big blue eyes with a heavy upper lid, orange brows, a small nose,
    a closed smile, rosy cheeks. u across (x from -FACE_X to FACE_X), v from the brow ring down to the chin."""
    W, H = size
    k = 4
    img = Image.new('RGB', (W * k, H * k), c8(COL['skin']))
    d = ImageDraw.Draw(img)

    def P(x, y):
        return (x * W * k, y * H * k)

    # planes: the forehead a touch lighter, the jaw shaded, a cheek facet on each side
    d.polygon([P(0, 0), P(1, 0), P(1, .30), P(0, .30)], fill=c8((.96, .77, .66)))
    d.polygon([P(0, .62), P(.30, .50), P(.20, 1), P(0, 1)], fill=c8((.86, .64, .55)))
    d.polygon([P(1, .62), P(.70, .50), P(.80, 1), P(1, 1)], fill=c8((.86, .64, .55)))
    d.polygon([P(.30, .72), P(.70, .72), P(.50, 1.0)], fill=c8((.90, .68, .58)))
    for cx in (.25, .75):                                   # cheeks
        d.ellipse([P(cx - .10, .56), P(cx + .10, .70)], fill=c8((.96, .60, .56)))
    # hair-gold brows
    for cx, sgn in ((.29, 1), (.71, -1)):
        d.polygon([P(cx - .14, .335), P(cx + .13, .26 if sgn > 0 else .30), P(cx + .13, .30 if sgn > 0 else .34),
                   P(cx - .14, .385)] if sgn > 0 else
                  [P(cx - .13, .30), P(cx + .14, .335), P(cx + .14, .385), P(cx - .13, .34)], fill=c8((.78, .42, .14)))
    # eyes: white, a big blue iris, a dark pupil, a catch-light, a heavy upper lid
    for cx in (.29, .71):
        ex, ey = cx * W * k, .46 * H * k
        d.ellipse([ex - 7.2 * k, ey - 7.0 * k, ex + 7.2 * k, ey + 7.0 * k], fill=c8((.97, .96, .98)))
        d.ellipse([ex - 5.6 * k, ey - 6.9 * k, ex + 5.6 * k, ey + 6.9 * k], fill=c8((.30, .52, .90)))
        d.ellipse([ex - 3.2 * k, ey - 3.4 * k, ex + 3.2 * k, ey + 3.9 * k], fill=c8((.10, .14, .36)))
        d.ellipse([ex - 4.2 * k, ey - 5.4 * k, ex - 1.2 * k, ey - 2.4 * k], fill=c8((.98, .98, 1.)))
        d.line([(ex - 8 * k, ey - 3 * k), (ex - 4 * k, ey - 7.6 * k), (ex + 4 * k, ey - 7.6 * k), (ex + 8 * k, ey - 3 * k)],
               fill=c8((.42, .22, .20)), width=int(1.8 * k))
    d.polygon([P(.46, .66), P(.54, .66), P(.50, .74)], fill=c8((.80, .56, .48)))                           # nose
    d.polygon([P(.38, .85), P(.62, .85), P(.56, .90), P(.44, .90)], fill=c8((.78, .34, .38)))              # mouth
    d.line([P(.37, .84), P(.50, .86), P(.63, .84)], fill=c8((.55, .24, .28)), width=int(1.2 * k))
    return img.resize(size, Image.LANCZOS)


# ---- the model -----------------------------------------------------------------------------------------------------------
def seg_dist(p, a, b):
    ab = b - a
    t = float(np.clip((p - a) @ ab / max(ab @ ab, 1e-9), 0., 1.))
    return float(np.linalg.norm(p - (a + ab * t)))


def side_of(p):
    return '.L' if p[0] > 0 else '.R'


# ---- hands: a fist round the wand (her right), an open palm under the bird (her left) ---------------------------------------
def hand_axes(d):
    """Forearm direction, and the hand's own frame: `a` along the forearm, `up` its normal toward the sky, `side` across."""
    sh, el, wr = (A(ARM[d][i], float) for i in range(3))
    a = N_(wr - el)
    up = N_(A((0, 1., 0)) - a * a[1])
    return wr, a, up, N_(np.cross(up, a))


def fist_frame():
    wr, a, up, side = hand_axes('.R')
    return wr + a * .085, N_(A((-.30, 1., .06)))


def add_fist(M):
    """Her right hand closed round the wand: a palm, a roll of four knuckles across the front of the stick, a thumb
    over them; rigid on hand.R (the wand is too, so the grip holds in every clip)."""
    wr, a, up, side = hand_axes('.R')
    c, wdir = fist_frame()
    front = N_(np.cross(wdir, side))
    if front @ a < 0:
        front = -front
    M.add(blob(wr + a * .050, (.036, .030, .032), a, N=6, k=2), 'skin', bone='hand.R')            # the back of the hand
    M.add(blob(c - front * .006, (.034, .040, .034), wdir, N=6, k=2), 'skin', bone='hand.R')       # the closed palm
    M.add(tube([c + front * .022 - wdir * .026, c + front * .026, c + front * .022 + wdir * .026], [.017, .018, .016],
               N=5, ratio=.85, flat=wdir, cap=(.008, .008)), 'skin', bone='hand.R')                 # the curled fingers
    M.add(tube([c - side * .030 - front * .004 + wdir * .010, c - side * .022 + front * .022 + wdir * .028],
               [.013, .010], N=4, cap=(0, .006)), 'skin', bone='hand.R')                            # the thumb


def add_palm(M):
    """Her left hand open, palm up, the bird standing on it: a flat palm, the fingers together curving up at the tips,
    the thumb out to the side."""
    wr, a, up, side = hand_axes('.L')
    pc = wr + a * .070
    M.add(blob(pc, (.044, .046, .014), a, N=6, k=2), 'skin', bone='hand.L')
    fingers = [pc + a * .040, pc + a * .075 + up * .004, pc + a * .100 + up * .020]
    M.add(tube(fingers, [.038, .034, .022], N=4, ratio=.32, flat=up, cap=(0, .008)), 'skin', bone='hand.L')
    M.add(tube([pc + side * .040 + a * .005, pc + side * .062 + a * .035 + up * .012], [.012, .009], N=4, cap=(0, .005)),
          'skin', bone='hand.L')


def build_parts(M):
    add = M.add

    # ===== skirt: panels on hips, the hem following the legs a little
    sp = skirt_pts()
    n = SK_N
    v = [1 - r / (len(SK_Y) - 1) for r in range(len(SK_Y))]
    skirt = gp(sp, True, u=[k / n for k in range(n + 1)], v=v)

    def skirt_w(p):
        low = smooth((.26 - p[1]) / .26)
        w_leg = low * min(1., abs(p[0]) / .16) * .5
        d = {'hips': 1 - w_leg}
        if w_leg > 1e-3:
            d['leg' + side_of(p)] = w_leg
        return d
    J, W = weights(M, skirt['V'], skirt_w)
    add(skirt, 'skirt_tex', J=J, W=W, tex='skirt')

    # ===== torso: the brown vest (boxy, a bit wide in the shoulders)
    tr = [(.40, .190, .120, .032), (.55, .180, .116, .032), (.70, .172, .112, .032), (.80, .160, .104, .028), (.855, .080, .066, .020)]
    torso = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in tr], 12, 2.5, cap=(0, 0), j=.003, o=.5)
    add(torso, lit_toned('vest'), bone='spine')

    front0 = len(M.P)
    # two big pockets on the hips (wider at the bottom, a flap at the top), stuffed: a spoon, a toy mouse, a feather and
    # herbs on her right; sweets, a cookie and a folded note on her left
    for s in (1, -1):
        px = s * .112
        pk = loft([((px, y, z), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, z in
                   ((.430, .046, .030, .208), (.450, .074, .050, .216), (.52, .078, .058, .224), (.580, .068, .050, .220))],
                  8, 2.3, cap=(.006, .004), j=.003)
        add(pk, lit_toned('pocket'), bone='spine')
        add(tube([A((px - .068, .575, .262)), A((px, .569, .272)), A((px + .068, .575, .262))], [.015, .017, .015], N=4,
                 ratio=.45, flat=(0, 1, 0), cap=(.004, .004)), 'pocket3', bone='spine')
    sp0, sp1 = A((-.150, .560, .245)), A((-.168, .690, .262))
    add(tube([sp0, sp1], [.008, .007], N=4, cap=(.002, 0)), 'spoon', bone='spine')
    add(blob(sp1 + A((-.004, .026, .002)), (.022, .030, .010), (0, 1, 0), N=6, k=2), 'spoon', bone='spine')
    mx = -.112
    mc = A((mx, .600, .226))
    add(blob(mc, (.040, .038, .030), (0, 1, 0), N=6, k=2), 'mouse', bone='spine')
    hc = mc + A((0, .042, .020))
    add(blob(hc, (.030, .030, .028), (0, 1, 0), N=6, k=2), 'mouse', bone='spine')
    for ex in (-1, 1):
        add(blob(hc + A((ex * .030, .030, -.004)), (.022, .026, .006), N_((ex * .3, 0, 1)), N=6, k=2), 'mouse_n', bone='spine')
        add(blob(mc + A((ex * .024, .000, .036)), (.010, .008, .008), (0, 0, 1), N=4, k=2), 'mouse', bone='spine')
    add(blob(hc + A((0, -.006, .028)), (.007, .007, .007), (0, 0, 1), N=4, k=2), 'mouse_n', bone='spine')
    add(tube([mc + A((.020, -.010, .000)), mc + A((.050, .010, -.010)), mc + A((.064, -.030, .000)), mc + A((.060, -.070, .008))],
             [.006, .005, .004, .003], N=4, cap=(0, .002)), 'mouse_n', bone='spine')
    add(tube([A((-.062, .565, .245)), A((-.050, .640, .250)), A((-.030, .715, .240))], [.016, .020, .004], N=4, ratio=.25,
             flat=(0, 0, 1), cap=(0, 0)), 'feather', bone='spine')
    for hx, hy in ((-.185, .665), (-.200, .635)):
        add(tube([A((-.175, .575, .240)), A((hx, hy, .245))], [.010, .002], N=4, ratio=.3, flat=(0, 0, 1), cap=(0, 0)),
            'herb', bone='spine')
    for (cx, cy, cz), mat in (((.070, .600, .245), 'candy_p'), ((.098, .612, .250), 'candy_g'), ((.122, .598, .246), 'gold')):
        add(blob(A((cx, cy, cz)), (.016, .016, .014), (0, 1, 0), N=5, k=2), mat, bone='spine')
    add(blob(A((.150, .618, .245)), (.034, .034, .010), N_((.4, .2, 1)), N=7, k=2), 'cookie', bone='spine')
    pv_ = [A((.155, .585, .232)), A((.200, .590, .228)), A((.205, .650, .238)), A((.165, .660, .242))]
    add(dict(V=A(pv_), F=A([(0, 1, 2), (0, 2, 3)], int), ax=A([(.18, .62, .10)]), fb=None, both=True), 'paper', bone='spine')

    # pendant: a big silver crescent on a gold chain, a small crescent and a stud below it; gold buttons by the collar
    pv, pf = cres3d(.044, 8, h=.010)
    pv = A([(x, y + .775, z + .196) for x, y, z in pv])
    add(dict(V=pv, F=A(pf, int), ax=A([(0, .775, .05)]), fb=None), 'silver', bone='spine')
    chain = [[(-.062, .872, .160), (0., .884, .158), (.062, .872, .160)], [(-.018, .822, .192), (0., .816, .194), (.018, .822, .192)]]
    cv = A([q for r in chain for q in r], float)
    add(dict(V=cv, F=A([(0, 3, 1), (1, 3, 4), (1, 4, 2), (2, 4, 5)], int), ax=A([(0, .6, -.2)]), fb=None, both=True), 'chain', bone='spine')
    sv_, sf_ = cres3d(.022, 6, h=.008)
    add(dict(V=A([(x + .055, y + .640, z + .214) for x, y, z in sv_]), F=A(sf_, int), ax=A([(.055, .64, .05)]), fb=None),
        'silver', bone='spine')
    add(blob(A((.032, .600, .218)), (.010, .010, .007), (0, 0, 1), N=4, k=2), 'silver', bone='spine')
    for bx, by in ((-.070, .790), (.070, .790), (-.062, .742), (.062, .742)):
        add(blob(A((bx, by, .205)), (.011, .011, .007), (0, 0, 1), N=4, k=2), 'button', bone='spine')

    for part in M.P[front0:]:
        part['V'] = part['V'] + A((0, 0, VEST_DZ))
        part['ax'] = part['ax'] + A((0, 0, VEST_DZ))

    # ===== cloak: shoulders down to a hem just below the hair, open at the front
    cr = [(.865, .140, .104, .005), (.78, .212, .150, -.020), (.64, .232, .170, -.035), (.53, .240, .178, -.046), (.445, .246, .184, -.054)]
    # open at the front from -45 to +45 degrees (16 columns), so the vest shows from the collar down, as on the references
    cp_ = [ring(y, rx, rz, cz, n=16, phi0=0.) for y, rx, rz, cz in cr[::-1]]
    top_band = len(cr) - 2
    cloak = gp(cp_, True, skip={(b, c) for b in range(len(cr) - 1) for c in ((15, 0) if b == top_band else (14, 15, 0, 1))})

    def cloak_w(p):
        lo = smooth((.70 - p[1]) / .25)
        return {'spine': 1 - lo, 'cape': lo}
    J, W = weights(M, cloak['V'], cloak_w)
    add(cloak, lit_toned('cloak'), J=J, W=W)
    # the cowl: the cloak's collar round the base of her neck; a short shaded neck shows above it, as on the references
    cowl = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in
                 ((.810, .160, .118, -.015), (.852, .118, .094, -.010), (.893, .072, .064, -.012))],
                12, 2.0, cap=(0, 0), j=.003)
    J, W = weights(M, cowl['V'], lambda p: {'spine': 1 - smooth((p[1] - .86) / .07), 'neck': smooth((p[1] - .86) / .07)})
    add(cowl, lit_toned('cloak'), J=J, W=W)

    # ===== sleeves and hands
    for s, d in ((1, '.L'), (-1, '.R')):
        sh, el, wr = (A(ARM[d][i], float) for i in range(3))
        mid1 = sh + (el - sh) * .55 + A((s * .012, 0, .0))
        mid2 = el + (wr - el) * .45
        pts = [sh + A((s * -.03, .02, 0)), mid1, el, mid2, wr + (wr - el) * .25]
        sl = tube(pts, [.060, .058, .056, .062, .085], N=6, ratio=.9, flat=(0, 0, 1.), cap=(.01, 0.))

        def arm_w(p, d=d, el=el, sh=sh, wr=wr):
            lo = smooth((seg_dist(p, sh, el) - seg_dist(p, el, wr)) / .10 + .5)
            top = smooth((.05 - float((p - sh) @ N_(el - sh))) / .06)
            return {'arm_upper' + d: (1 - lo) * (1 - .5 * top), 'arm_lower' + d: lo, 'spine': (1 - lo) * .5 * top}
        J, W = weights(M, sl['V'], arm_w)
        sl['fuv'] = cyl_fuv(sl)
        sl['both'] = True      # solid from every side, whichever way the sweep wound
        add(sl, 'sleeve1', J=J, W=W, tex='sleeve')
        cuff = tube([mid2 + (wr - el) * .22, wr + (wr - el) * .30], [.080, .092], N=6, ratio=.9, flat=(0, 0, 1.), cap=(0, .0))
        cuff['both'] = True
        add(cuff, 'cuff0', bone='arm_lower' + d)
    add_fist(M)
    add_palm(M)

    # ===== wand (right hand): a stick rising from the fist and a pink star
    fc, wdir = fist_frame()
    wb = fc - wdir * .045
    wt = fc + wdir * .200
    add(tube([wb - wdir * .03, wt], [.010, .008], N=4, cap=(.004, .004)), 'wand', bone='hand.R')
    sc = wt + (wt - wb) / np.linalg.norm(wt - wb) * .040
    sv = [sc + A((0, 0, .024)), sc + A((0, 0, -.024))]
    for kk in range(10):
        a = math.pi / 2 + kk * math.pi / 5 + .22
        r = .068 if kk % 2 == 0 else .031
        sv.append(sc + A((r * math.cos(a), r * math.sin(a), 0.)))
    sf = []
    for kk in range(10):
        a, b = 2 + kk, 2 + (kk + 1) % 10
        sf += [(0, a, b), (1, b, a)]
    add(dict(V=A(sv), F=A(sf, int), ax=A([sc]), fb=None), 'wand_star', bone='hand.R')

    # ===== bird on the left hand: a plump grey-blue songbird, white belly, wings folded along its sides, tail up
    bc = A(BONES['bird'][1]) + A((0, .038, 0))
    add(blob(bc, (.040, .044, .062), (0, .30, 1), N=7, k=3), 'bird', bone='bird')
    add(blob(bc + A((0, -.012, .022)), (.030, .030, .040), (0, .30, 1), N=6, k=2), 'bird_l', bone='bird')
    add(blob(bc + A((.0, .052, .046)), (.030, .030, .032), (0, 1, 0), N=7, k=2), 'bird', bone='bird')
    add(tube([bc + A((0, .054, .074)), bc + A((0, .050, .100))], [.010, .001], N=4, cap=(0, 0)), 'beak', bone='bird')
    for sgn in (1, -1):
        add(blob(bc + A((sgn * .022, .062, .066)), (.006, .006, .006), (0, 0, 1), N=4, k=2), 'boot', bone='bird')
        add(tube([bc + A((sgn * .036, .020, .030)), bc + A((sgn * .044, .016, -.020)), bc + A((sgn * .030, .004, -.080))],
                 [.026, .024, .006], N=4, ratio=.30, flat=(sgn, 0, 0), cap=(0, 0)), 'bird_d', bone='bird')
    add(tube([bc + A((0, .004, -.050)), bc + A((0, .022, -.100)), bc + A((0, .050, -.150))], [.022, .020, .006], N=4,
             ratio=.3, flat=(0, 1, 0), cap=(0, 0)), 'bird_d', bone='bird')

    # ===== neck, head, face plate
    add(loft([((0, y, -.015), (r, 0, 0), (0, 0, r)) for y, r in ((.84, .036), (.93, .033))], 8, 2., cap=(0, 0)), 'skin_d', bone='neck')
    head = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in HEAD_R], 10, HEAD_E, cap=(.004, .004), j=.0015)
    add(head, lambda c, n: 'skin_d' if c[1] < .985 else 'hair1', bone='head')
    ref = face_ref()
    if ref is not None:
        fp_ = face_plate_ref(ref[0], ref[2])
    else:
        # the painted fallback: a rounded square, a square grid pulled in at the corners so the face has a jaw and a brow
        ab = np.linspace(-1, 1, 8)
        bb = np.linspace(-1, 1, 7)
        yc, hy = (FACE_Y0 + FACE_Y1) / 2, (FACE_Y1 - FACE_Y0) / 2
        plate = []
        for b in bb:
            row = []
            for a in ab:
                x = FACE_X * a * math.sqrt(1 - b * b / 2)
                y = yc + hy * b * math.sqrt(1 - a * a / 2)
                row.append((x, y, head_z(x, y) + .004))
            plate.append(row)
        fp_ = gp(plate, False, u=[(a + 1) / 2 for a in ab], v=[(1 - b) / 2 for b in bb])
    add(fp_, 'skin', bone='head', tex='face')

    # ===== the hood: dome with a front opening, its lining, the peak, the flower wreath on the rim
    P = hood_pts()
    v, _ = hood_v(P)
    n = HOOD_N
    skip = hood_skip()
    hood = gp(P, True, skip=skip, u=[m / n for m in range(n + 1)], v=v)

    def hood_w(p):
        t = smooth((p[1] - 1.02) / .12) * smooth((-p[2] - .06) / .14)
        return {'head': 1 - t, 'hat_tip': t}
    J, W = weights(M, hood['V'], hood_w)
    add(hood, 'hood_tex', J=J, W=W, tex='hood')
    shrink = P.copy()
    for r in range(P.shape[0]):
        cen = A([P[r][:, 0].mean(), P[r][:, 1].mean(), P[r][:, 2].mean()])
        shrink[r] = cen + (P[r] - cen) * .955 - A((0, .012, 0))
    # inside: the same dome, shrunk, the winding reversed (columns the other way)
    lin = gp(shrink[:, ::-1], True, skip={(b, (n - 2 - c) % n) for b, c in skip})
    J2, W2 = weights(M, lin['V'], lambda p: {'head': 1 - smooth((p[1] - 1.02) / .12) * smooth((-p[2] - .06) / .14),
                                              'hat_tip': smooth((p[1] - 1.02) / .12) * smooth((-p[2] - .06) / .14)})
    add(lin, 'hood_in', J=J2, W=W2)
    # the flower crown: along the opening's rim from temple to temple over the brow, clustered at the temples (as on the
    # references), round five-petal flowers, a few leaves between them
    rim = A([P[2, 10], P[3, 10], P[3, 11], P[3, 0], P[3, 1], P[3, 2], P[2, 2]], float)
    seg_l = np.r_[0., np.cumsum(np.linalg.norm(np.diff(rim, axis=0), axis=1))]
    for i, f in enumerate(CROWN):
        p = A([np.interp(f * seg_l[-1], seg_l, rim[:, k]) for k in range(3)])
        cen = A([0., p[1] - .04, HOOD_ROWS[3][3]])
        nrm = N_((p - cen) * A((1., .5, 1.)) + A((0, .15, .35)))
        add_flower(M, p + nrm * .010, nrm, CROWN_SIZE[i % len(CROWN_SIZE)], i, hood_w)
    for i, f in enumerate(LEAVES):
        p = A([np.interp(f * seg_l[-1], seg_l, rim[:, k]) for k in range(3)])
        cen = A([0., p[1] - .04, HOOD_ROWS[3][3]])
        nrm = N_((p - cen) * A((1., .5, 1.)) + A((0, .15, .35)))
        add_leaf(M, p + nrm * .006, nrm, i, hood_w)

    # ===== hair: the lobed mass behind her, then the curls
    hm = gp(mass_pts(), False)

    def hair_w(p):
        a = smooth((.80 - p[1]) / .14)
        b = smooth((.64 - p[1]) / .12)
        d = side_of(p)
        if abs(p[0]) < .06:
            return {'head': 1 - a, 'hairB.L': a * (1 - b) * .5, 'hairB.R': a * (1 - b) * .5, 'hairT.L': a * b * .5, 'hairT.R': a * b * .5}
        return {'head': 1 - a, 'hairB' + d: a * (1 - b), 'hairT' + d: a * b}
    J, W = weights(M, hm['V'], hair_w)
    add(hm, lit_toned('hair'), J=J, W=W)

    for name, side, pts, width, nsides, n_st in curl_paths():
        m = len(pts)
        taper = (.80, .32) if name == 'tail' else (.85, .40)     # thick down into the curl, as on the sheet
        rad = np.interp(np.arange(m), [0, n_st, m - 1], [width, width * taper[0], width * taper[1]])
        ratio = {'frame': .50, 'tail': .50}.get(name, .50)   # flat ribbons, as on the sheet
        flat = N_((side * .7, 0., 1.)) if name == 'frame' else (0, 0, 1.)
        cu = tube(pts, rad, N=nsides, ratio=ratio, flat=flat, cap=(0, .012), o=.5 if nsides == 4 else 0.)
        d = '.L' if side > 0 else '.R'
        t_ = (np.arange(m) / (m - 1))
        nv = nsides

        def curl_w(p, d=d):
            a = smooth((.92 - p[1]) / .25)
            b = smooth((.78 - p[1]) / .25)
            return {'head': 1 - a, 'hairB' + d: a * (1 - b), 'hairT' + d: a * b}
        J, W = weights(M, cu['V'], hair_w if name == 'relief' else curl_w)
        add(cu, lit_toned('hair'), J=J, W=W)

    # bangs: swept from the parting to each temple over the forehead's top corners, under the flowers
    for sx in (1, -1):
        pts = [A((sx * x, y, head_z(x, y) + dz)) for x, y, dz in BANGS]
        bg = tube(pts, [.020, .026, .022, .014], N=4, ratio=.45, flat=(0, 0, 1.), cap=(0, .006), o=.5)
        add(bg, lit_toned('hair'), bone='head')


BANGS = ((.015, 1.168, .045), (.060, 1.158, .042), (.110, 1.128, .036), (.150, 1.085, .030))   # x, y, out of the head
CROWN = (.02, .10, .18, .33, .50, .66, .80, .90, .98)   # where the flowers sit along the rim, 0..1 (temple to temple)
CROWN_SIZE = (.058, .050, .064, .052, .066, .050, .062, .052, .058)
LEAVES = (.06, .26, .58, .74, .94)


def add_flower(M, p, nrm, size, i, hood_w):
    """A five-petal flower lying on the surface at p: rounded petals (each a fan of four facets, lighter at the tip) round
    a raised gold centre."""
    t1 = np.cross(nrm, (0., 1., 0.))
    if np.linalg.norm(t1) < 1e-3:
        t1 = np.cross(nrm, (1., 0., 0.))
    t1 = N_(t1)
    t2 = np.cross(nrm, t1)
    rot = RAD((i * 37) % 72)

    def at(a, r, lift=0.):
        return p + r * (math.cos(a) * t1 + math.sin(a) * t2) + nrm * lift

    V, F, mats = [p + nrm * .012], [], []
    for k in range(5):
        a0 = rot + k * 2 * math.pi / 5
        base = len(V)
        V += [at(a0 - .56, size * .70, .004), at(a0 - .25, size * .98, .008), at(a0 + .25, size * .98, .008),
              at(a0 + .56, size * .70, .004)]
        tip = 'petal_l' if (i + k) % 3 == 0 else 'petal'
        F += [(0, base, base + 1), (0, base + 1, base + 2), (0, base + 2, base + 3)]
        mats += ['petal_d' if k % 2 else 'petal', tip, 'petal' if k % 2 else 'petal_d']
    cen = len(V)
    V.append(p + nrm * .020)
    ring_ = len(V)
    for k in range(5):
        V.append(at(rot + k * 2 * math.pi / 5 + .6, size * .26, .014))
    for k in range(5):
        F.append((cen, ring_ + k, ring_ + (k + 1) % 5))
        mats.append('flower_c')
    part = dict(V=A(V), F=A(F, int), ax=A([p - nrm * .05]), fb=list(range(len(F))))
    J, W = weights(M, part['V'], hood_w)
    M.add(part, mats, J=J, W=W)


def add_leaf(M, p, nrm, i, hood_w):
    """A small olive leaf tucked between the flowers: a flat diamond pointing outward along the rim."""
    t1 = N_(np.cross(nrm, (0., 0., 1.)) if abs(nrm[2]) < .95 else np.cross(nrm, (1., 0., 0.)))
    t2 = np.cross(nrm, t1)
    a = RAD(30 + (i * 53) % 120)
    d = math.cos(a) * t1 + math.sin(a) * t2
    w = np.cross(nrm, d)
    V = [p, p + d * .030 + w * .012, p + d * .058, p + d * .030 - w * .012]
    part = dict(V=A(V), F=A([(0, 1, 2), (0, 2, 3)], int), ax=A([p - nrm * .05]), fb=None, both=True)
    J, W = weights(M, part['V'], hood_w)
    M.add(part, 'leaf', J=J, W=W)


# ---- clips --------------------------------------------------------------------------------------------------------------------
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


def rest_dirs(d):
    sh, el, wr = (A(ARM[d][i], float) for i in range(3))
    return N_(el - sh), N_(wr - el)


def arm_pose(d, upper, lower, hand_world=None):
    """World directions of the upper arm and forearm -> local rotations relative to the rest pose."""
    ru, rl = rest_dirs(d)
    Ru = aim(ru, upper)
    Rl = aim(rl, lower)
    Rh = Rl if hand_world is None else hand_world
    return {'arm_upper' + d: Ru, 'arm_lower' + d: Ru.T @ Rl, 'hand' + d: Rl.T @ Rh}


def clip_set(M):
    names = M.names
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
        r['hat_tip'] = rz_(6 * S(tau * p * 2 + .3)) @ rx_(4 * S(tau * p + 1.2))
        r['cape'] = rx_(2.0 * S(tau * p - .5))
        r['hand.R'] = rz_(3 * S(tau * p * 2)) @ rx_(2 * S(tau * p + .5))
        r['hand.L'] = rx_(2 * S(tau * p - .5))
        r['bird'] = ry_(8 * S(tau * p * 2 + 1.0)) @ rx_(2 * S(tau * p * 3))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['arm_upper' + d] = rx_(1.2 * S(tau * p + .3 * sg))
            r['hairB' + d] = rz_(sg * 2.2 * S(tau * p + .2))
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
        r['bird'] = ry_(6 * S(2 * ph + .8))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['arm_upper' + d] = rx_(sg * 6 * S(ph))
            r['arm_lower' + d] = rx_(-3 - sg * 3 * S(ph))
            r['hairB' + d] = rz_(sg * 3 * S(2 * ph)) @ rx_(4)
            r['hairT' + d] = rz_(sg * 6 * S(2 * ph - .8)) @ rx_(6 + 3 * S(2 * ph))
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
        ru, rl = rest_dirs('.R')
        r.update(arm_pose('.R', N_(ru + A((-.15 * g, .10 * g, .20 * g))), N_(rl + A((-.20 * g, .25 * g, .35 * g)))))
        r['bird'] = ry_(10 * S(ph * 2 + 1.0)) @ rx_(3 * S(ph * 3))
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 2 * S(ph + .2))
            r['hairT' + d] = rz_(sg * 3 * S(ph - .4))
        return full(r), {'hips': (0, .002 * S(ph * 2), 0)}

    def cast(t):
        # 0-.35 s the wand arm swings forward and up, then a small flourish; it ends raised
        k = min(1., t / .35)
        k = k * k * (3 - 2 * k)
        r = {}
        ru, rl = rest_dirs('.R')
        lo = arm_pose('.R', ru, rl)
        up = arm_pose('.R', N_((-.55, .70, .45)), N_((-.20, .55, .80)))
        for n_ in up:
            r[n_] = slerp(lo[n_], up[n_], k)
        fl = max(0., t - .35)
        r['hand.R'] = r['hand.R'] @ rz_(10 * S(fl * 9) * min(1, fl * 3)) @ rx_(8 * S(fl * 7))
        r['spine'] = rx_(-4 * k) @ ry_(-6 * k)
        r['head'] = rx_(-6 * k)
        r['neck'] = ry_(-4 * k)
        r['cape'] = rx_(8 * k)
        r['hat_tip'] = rx_(10 * k) @ rz_(6 * S(fl * 6) * min(1, fl * 2))
        r['bird'] = ry_(25 * k) @ rx_(-6 * k)
        for d, sg in (('.L', 1), ('.R', -1)):
            r['hairB' + d] = rz_(sg * 5 * k) @ rx_(4 * k)
            r['hairT' + d] = rz_(sg * (8 * k + 2 * S(fl * 8))) @ rx_(7 * k)
        return full(r), {'hips': (0, .006 * k, 0)}

    return [glb.Clip('idle', 4.0, idle), glb.Clip('walk', 1.0, walk), glb.Clip('talk', 3.0, talk),
            glb.Clip('cast', 1.6, cast, loop=False)]


# ---- export ---------------------------------------------------------------------------------------------------------------------------
def make_model():
    M = Model(BONES, COL)
    at = atl.Atlas(256)
    P = hood_pts()
    ref = face_ref()
    tiles = {'skirt': paint_skirt_tile(), 'hood': paint_hood_tile(P), 'face': ref[1] if ref is not None else paint_face_tile(),
             'sleeve': paint_sleeve_tile()}
    for k, im in tiles.items():
        at.alloc(k, *im.size)
    for k, im in tiles.items():
        at.paste(k, im)
    build_parts(M)
    return M, at


def build(out_dir, preview=None, name='witch'):
    print('witch (new references)')
    M, at = make_model()
    clips = clip_set(M)
    tris = M.flatten()
    arr = bake_uvs(tris, at, M.COL, soft=('face',))
    top = float(arr['P'][:, 1].max())
    scale = HEIGHT / top
    ex = dict(variant='reference', tris=len(tris), hood_top_m=HEIGHT, units_per_m=1 / scale)
    path = os.path.join(out_dir, name + '.glb')
    n = glb.export(path, M, arr, at.img, clips, scale, mesh_name='Witch', generator='tools/characters/witch_ref.py', extras=ex)
    print('  %s: %d triangles, %d bones, %d clips, atlas %dx%d (%.0f%% used), top %.3f m (scale %.3f)'
          % (path, n, len(M.names), len(clips), at.W, at.H, 100 * at.usage(), top * scale, scale))
    assert n <= 6500, "triangle budget"
    if preview:
        os.makedirs(preview, exist_ok=True)
        import witch_preview as wp
        clipd = {c.name: c for c in clips}
        r0, t0 = clipd['idle'].fn(0.)
        posed = glb.pose_arrays(M, arr, r0, t0)
        wp.sixview(posed, at.img, os.path.join(preview, name + '_sixview.png'), '%s idle pose  %d tris' % (name, n))
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
