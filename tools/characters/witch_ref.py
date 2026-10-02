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
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas as atl            # noqa: E402
import witch_glb as glb         # noqa: E402
from witch_kit import A, N_, Model, bake_uvs, blob, cres3d, loft, rotm, star3d, tube   # noqa: E402

HEIGHT = 1.33
S = math.sin
C = math.cos
RAD = math.radians


# ---- palette: display-referred albedo (the room multiplies it by a warm, dim light) -------------------
COL = {
    'skin': (.94, .73, .62), 'skin_d': (.82, .60, .52), 'blush': (.95, .55, .52),
    'gold': (.95, .76, .38), 'silver': (.88, .88, .95), 'chain': (.66, .50, .30),
    'pink': (.93, .45, .68), 'pink_l': (.98, .64, .80), 'flower_c': (.98, .80, .45),
    'hood_in': (.30, .16, .46), 'hood_rim': (.55, .34, .72),
    'wand': (.62, .30, .42), 'wand_star': (.98, .48, .72),
    'bird': (.72, .74, .85), 'bird_d': (.52, .54, .66), 'bird_l': (.88, .90, .96), 'beak': (.95, .66, .30),
    'item_a': (.95, .62, .25), 'item_b': (.70, .62, .86), 'item_c': (.62, .72, .52), 'item_d': (.85, .80, .72),
    'boot': (.26, .16, .12),
}
FAMILIES = {          # name: (base colour, relative spread): four tones per flat-coloured material, like paper folds
    'hair': ((1., .70, .26), .17), 'purple': ((.50, .28, .70), .12), 'sleeve': ((.46, .26, .66), .12),
    'cuff': ((.56, .34, .72), .08), 'vest': ((.48, .33, .28), .12), 'pocket': ((.31, .21, .18), .12),
    'cloak': ((.44, .24, .62), .12),
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
ARM = {'.L': ((.20, .80, 0.), (.275, .655, .05), (.285, .715, .20)),       # shoulder, elbow, wrist
       '.R': ((-.20, .80, 0.), (-.28, .67, .04), (-.30, .785, .155))}
for _s, _d in ((1, '.L'), (-1, '.R')):
    BONES['arm_upper' + _d] = ('spine', ARM[_d][0])
    BONES['arm_lower' + _d] = ('arm_upper' + _d, ARM[_d][1])
    BONES['hand' + _d] = ('arm_lower' + _d, ARM[_d][2])
    BONES['leg' + _d] = ('hips', (_s * .07, .30, 0))
    BONES['foot' + _d] = ('leg' + _d, (_s * .07, .07, .03))
    BONES['hairB' + _d] = ('head', (_s * .19, .90, -.07))
    BONES['hairT' + _d] = ('hairB' + _d, (_s * .31, .62, -.12))
BONES['bird'] = ('hand.L', (.285, .77, .235))


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


def skirt_pts():
    rows = []
    for y, r in zip(SK_Y, SK_R):
        fade = 1 - y / SK_Y[-1]
        rows.append([(r * (1 - (.045 if k % 2 else 0.) * fade) * S(RAD(SK_PHI0 + 360. * k / SK_N)), y,
                      r * (1 - (.045 if k % 2 else 0.) * fade) * C(RAD(SK_PHI0 + 360. * k / SK_N))) for k in range(SK_N)])
    return A(rows, float)


# ---- the head -----------------------------------------------------------------------------------------------
HEAD_R = [(.905, .050, .060, .030), (.935, .095, .100, .030), (.990, .130, .125, .015), (1.060, .135, .130, .005),
          (1.130, .125, .125, 0.), (1.190, .100, .100, -.010), (1.235, .050, .060, -.010)]
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
HOOD_ROWS = [(.89, .245, .238, -.072), (.98, .248, .232, -.062), (1.07, .242, .225, -.045), (1.165, .215, .185, -.030),
             (1.25, .145, .130, -.005), (1.325, .055, .055, .010)]
HOOD_FRONT_BANDS = (0, 1, 2)                 # bands below the brow ring are open at the front...
HOOD_OPEN_COLS = (10, 11, 0, 1)              # ...in these columns (phi -60 .. +60)
HOOD_TIP = (0., 1.07, -.400)                # the folded peak, back and below the top


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
    return {(b, (c) % HOOD_N) for b in HOOD_FRONT_BANDS for c in HOOD_OPEN_COLS}


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


def mirror_x(P):
    Q = P.copy()
    Q[:, 0] *= -1
    return Q


# Side curls, one per row, for her left (+x); the right side is the mirror image with a small change.
# name, start xyz, heading deg (0 = +X, counter-clockwise), stalk [(length, turn)], r0, r1, turns, dirn (+1 = counter-clockwise),
# strand half-width, z drift over the spiral
CURLS = [
    ('lock_big', (.215, .90, -.045), -45, [(.07, 0), (.07, -8)], .080, .026, 1.25, +1, .050, -.03),
    ('side_mid', (.255, .70, -.150), -55, [(.07, 0), (.07, -12), (.05, 10)], .082, .026, 1.30, +1, .056, -.02),
    ('frame', (.150, 1.14, .075), -72, [(.10, 0), (.10, -5), (.10, 8)], .052, .020, 1.2, +1, .036, .01, .07),
    ('hood_hi', (.215, 1.10, -.150), 40, [(.06, 0), (.05, 15)], .062, .022, 1.20, +1, .036, -.02),
    ('hood_mid', (.235, .99, -.150), 15, [(.06, 0), (.05, -10)], .064, .022, 1.20, +1, .038, -.02),
]
# the curls on her right: a different spiral radius and turn count so the two sides do not match
CURLS_R_TWEAK = {'frame': dict(r0=.058, turns=1.1), 'lock_big': dict(r0=.082, turns=1.2), 'side_mid': dict(r0=.074, turns=1.4),
                 'hood_hi': dict(r0=.054, turns=1.3), 'hood_mid': dict(turns=1.1)}

# The long back hair is one lobed mass (a bulb that is widest at the shoulder blades, every lobe a flute) whose
# scalloped lower edge hangs lower under every second lobe; a thin tail leaves each of those tips and ends in a spiral.
MASS_PHIS = [75 + 15 * k for k in range(15)]                 # 75 .. 285 degrees: the sides and the back
MASS_ROWS = [(.57, .335, .225, -.100), (.66, .345, .225, -.104), (.75, .325, .215, -.108), (.84, .290, .200, -.112), (.93, .215, .160, -.115)]
TAIL_COLS = (3, 5, 7, 9, 11)                              # which columns drop a tail (the lobes that hang lower)
TAIL_IN = (False, True, False, True, False)           # curls toward the centre instead of outward


def mass_pts():
    """Rows (bottom first) of the hair mass; lobes alternate in radius, the odd-numbered bottoms hang lower."""
    rows = []
    for ri, (y, rx, rz, cz) in enumerate(MASS_ROWS):
        row = []
        for k, p in enumerate(MASS_PHIS):
            lob = 1.0 if k % 2 == 0 else .88
            yy = y - (.045 if (ri == 0 and k in TAIL_COLS) else 0.)
            row.append((rx * lob * S(RAD(p)), yy, cz + rz * lob * C(RAD(p))))
        rows.append(row)
    return A(rows, float)


TILT = .30        # the curls' planes lean back at the bottom, so their faces tilt up toward the room's key light


def curl_paths():
    out = []
    for row in CURLS:
        name, p0, th0, stalk, r0, r1, turns, dirn, width, dz = row[:10]
        dzs = row[10] if len(row) > 10 else 0.
        for side in (1, -1):
            kw = dict(r0=r0, r1=r1, turns=turns)
            if side < 0:
                kw.update(CURLS_R_TWEAK.get(name, {}))
            seg = 45. if r0 > .08 else 60.
            pts, z0 = turtle(p0, th0, stalk, kw['r0'], kw['r1'], kw['turns'], dirn, seg, dz, dzs)
            if side < 0:
                pts = mirror_x(pts)
            if name != 'frame':
                pts[:, 2] += TILT * (pts[:, 1] - pts[0, 1])
            out.append((name, side, pts, width, 5 if width > .045 else 4, len(stalk)))
    mp = mass_pts()
    for i, c in enumerate(TAIL_COLS):
        p0 = mp[0, c] + A((0., .012, 0.))
        s_ = 1 if p0[0] >= 0 else -1
        a_ = abs(p0[0]) / .26
        w = 12. * (1 if i % 2 == 0 else -1)
        L = .045 + .02 * (i % 2)
        stalk = [(L, -6. * s_ * a_ + w), (L, 12. * s_ * a_ - 2 * w), (L * .7, -8. * s_ * a_ + w)]
        dirn = -s_ if TAIL_IN[i] else s_
        pts, _ = turtle(p0, -90. + 20. * s_ * a_, stalk, .052 + .008 * (i % 2), .020, 1.2, dirn, 60., dz=.01)
        pts[:, 2] += TILT * (pts[:, 1] - pts[0, 1])
        out.append(('tail', s_, pts, .046, 4, 3))
    # a small spiral lying on the hollow at the centre of the back, as on the sheet
    pts, _ = turtle((0., .76, -.318), 165, [(.03, 0)], .046, .014, 1.6, +1, 60., dz=0.)
    out.append(('relief', 1, pts, .020, 4, 1))
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


def paint_skirt_tile(size=(240, 40)):
    """Cylindrical tile: u around (panel k = columns k*20..k*20+20, panel 0 centred on the front), v from the waist
    (top) to the hem (bottom). Violet paper, one tone per panel and triangle, gold stars and moons sized in metres."""
    W, H = size
    k = 4
    rng = np.random.default_rng(3)
    img = Image.new('RGB', (W * k, H * k), c8((.56, .30, .68)))
    d = ImageDraw.Draw(img)
    base = np.array((.56, .30, .68))
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
            fu, fv = rng.uniform(.26, .74), rng.uniform(.14, .90)          # fv: 0 top, 1 hem
            if all(abs(fu - a) * 1. > .30 or abs(fv - b) > .30 for a, b in placed):
                placed.append((fu, fv))
            if len(placed) >= 3:
                break
        for i, (fu, fv) in enumerate(placed):
            y = (1 - fv) * SK_Y[-1]
            rad = float(np.interp(y, SK_Y, SK_R))
            chord = 2 * rad * S(RAD(15.))
            px = pw / chord
            kind = syms[(m * 3 + i * 5 + int(rng.integers(0, 3))) % len(syms)]
            sym = {'moon': .046, 'star8': .036, 'star5': .040, 'dot': .02}[kind]
            col = c8(COL['silver']) if (m * 7 + i * 3) % 11 == 0 else c8(GOLD)
            draw_symbol(d, kind, (m * pw + fu * pw), fv * H, sym, px, py, k, col)
    return img.resize(size, Image.LANCZOS)


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
    base = np.array((.52, .29, .72))
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
    tr = [(.40, .215, .165, .050), (.55, .205, .160, .050), (.70, .200, .155, .050), (.80, .185, .140, .045), (.855, .085, .080, .035)]
    torso = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in tr], 12, 2.5, cap=(0, 0), j=.003, o=.5)
    add(torso, lit_toned('vest'), bone='spine')

    # two big pockets (flap boxes) with something sticking out of each
    for s in (1, -1):
        px = s * .108
        pk = loft([((px, y, z), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, z in
                   ((.445, .080, .046, .205), (.50, .088, .056, .222), (.585, .082, .046, .215))], 6, 2.6, cap=(0, .004), j=.003)
        add(pk, lit_toned('pocket'), bone='spine')
    add(blob((-.108, .615, .215), (.034, .05, .02), (0, 1, 0), N=6, k=2), 'item_a', bone='spine')
    add(blob((.100, .625, .215), (.026, .05, .016), (0.2, 1, 0), N=6, k=2), 'item_b', bone='spine')
    add(blob((.136, .600, .214), (.026, .036, .016), (0, 1, 0), N=5, k=2), 'item_c', bone='spine')

    # pendant: a crescent on the chest, and its chain
    pv, pf = cres3d(.052, 7, h=.010)
    pv = A([(x, y + .715, z + .187) for x, y, z in pv])
    add(dict(V=pv, F=A(pf, int), ax=A([(0, .715, .05)]), fb=None), 'silver', bone='spine')
    chain = [[(-.075, .83, .125), (0., .86, .12), (.075, .83, .125)], [(-.052, .775, .185), (0., .75, .19), (.052, .775, .185)]]
    cv = A([q for r in chain for q in r], float)
    add(dict(V=cv, F=A([(0, 3, 1), (1, 3, 4), (1, 4, 2), (2, 4, 5)], int), ax=A([(0, .6, -.2)]), fb=None, both=True), 'chain', bone='spine')

    # ===== cloak: shoulders down to a hem just below the hair, open at the front
    cr = [(.865, .150, .125, .020), (.78, .245, .185, -.010), (.62, .270, .215, -.030), (.48, .275, .230, -.050), (.355, .285, .235, -.060)]
    cp_ = [ring(y, rx, rz, cz, n=12, phi0=0.) for y, rx, rz, cz in cr[::-1]]
    cloak = gp(cp_, True, skip={(b, c) for b in range(len(cr) - 1) for c in (11, 0)})

    def cloak_w(p):
        lo = smooth((.70 - p[1]) / .25)
        return {'spine': 1 - lo, 'cape': lo}
    J, W = weights(M, cloak['V'], cloak_w)
    add(cloak, lit_toned('cloak'), J=J, W=W)

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
        add(sl, lit_toned('sleeve'), J=J, W=W)
        cuff = tube([mid2 + (wr - el) * .22, wr + (wr - el) * .30], [.080, .092], N=6, ratio=.9, flat=(0, 0, 1.), cap=(0, .0))
        add(cuff, 'cuff0', bone='hand' + d)
        add(blob(wr + (wr - el) * .60 + A((0, .01, .01)), (.040, .040, .046), (0, 0, 1), N=6, k=2), 'skin', bone='hand' + d)

    # ===== wand (right hand): a stick rising from the fist and a pink star
    wb = A(ARM['.R'][2]) + A((.0, .0, .02))
    wt = wb + A((-.065, .205, .015))
    add(tube([wb - (wt - wb) * .22, wt], [.010, .008], N=4, cap=(.004, .004)), 'wand', bone='hand.R')
    sc = wt + (wt - wb) / np.linalg.norm(wt - wb) * .030
    sv = [sc + A((0, 0, .014)), sc + A((0, 0, -.014))]
    for kk in range(10):
        a = math.pi / 2 + kk * math.pi / 5 + .22
        r = .052 if kk % 2 == 0 else .024
        sv.append(sc + A((r * math.cos(a), r * math.sin(a), 0.)))
    sf = []
    for kk in range(10):
        a, b = 2 + kk, 2 + (kk + 1) % 10
        sf += [(0, a, b), (1, b, a)]
    add(dict(V=A(sv), F=A(sf, int), ax=A([sc]), fb=None), 'wand_star', bone='hand.R')

    # ===== bird on the left hand: body, head, beak, tail, wings
    bc = A(BONES['bird'][1]) + A((0, .035, 0))
    add(blob(bc, (.040, .042, .070), (0, .35, 1), N=6, k=2), 'bird', bone='bird')
    add(blob(bc + A((.0, .050, .058)), (.030, .030, .032), (0, 1, 0), N=6, k=2), 'bird_l', bone='bird')
    add(tube([bc + A((0, .052, .088)), bc + A((0, .048, .125))], [.013, .001], N=4, cap=(0, 0)), 'beak', bone='bird')
    add(tube([bc + A((0, 0, -.05)), bc + A((.0, .0, -.12)), bc + A((.0, -.01, -.19))], [.030, .026, .004], N=4, ratio=.3, flat=(0, 1, 0), cap=(0, 0)), 'bird_d', bone='bird')
    for sgn in (1, -1):
        add(tube([bc + A((sgn * .03, .025, .01)), bc + A((sgn * .085, .06, -.04)), bc + A((sgn * .13, .095, -.10))], [.034, .030, .004], N=4, ratio=.22, flat=(0, 1, 0), cap=(0, 0)), 'bird_d', bone='bird')

    # ===== neck, head, face plate
    add(loft([((0, y, 0.01), (r, 0, 0), (0, 0, r)) for y, r in ((.84, .050), (.93, .045))], 8, 2., cap=(0, 0)), 'skin_d', bone='neck')
    head = loft([((0, y, cz), (rx, 0, 0), (0, 0, rz)) for y, rx, rz, cz in HEAD_R], 10, HEAD_E, cap=(.004, .004), j=.0015)
    add(head, lambda c, n: 'skin_d' if c[1] < .985 else 'hair1', bone='head')
    # the face plate is a rounded square: a square grid pulled in at the corners so the face has a jaw and a brow, not a box
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
    # flowers on the rim: ring vertices round the opening (side edges and the brow row)
    wreath = [(1, 10), (2, 10), (3, 10), (3, 11), (3, 0), (3, 1), (3, 2), (2, 2), (1, 2)]
    flip = [-1, 1]
    for i, (r, c) in enumerate(wreath):
        p = P[r, c] + A((0, 0, 0))
        cen = A([0., p[1], HOOD_ROWS[min(r, len(HOOD_ROWS) - 1)][3]])
        nrm = N_((p - cen) * A((1., .35, 1.)) + A((0, .25, 0)))
        add_flower(M, p + nrm * .012, nrm, .060 + .014 * ((i * 7) % 3), i, hood_w)

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
        rad = np.interp(np.arange(m), [0, n_st, m - 1], [width, width * .78, width * .30])
        cu = tube(pts, rad, N=nsides, ratio=.85, flat=(0, 0, 1.), cap=(0, .012), o=.5 if nsides == 4 else 0.)
        d = '.L' if side > 0 else '.R'
        t_ = (np.arange(m) / (m - 1))
        nv = nsides

        def curl_w(p, d=d):
            a = smooth((.92 - p[1]) / .25)
            b = smooth((.78 - p[1]) / .25)
            return {'head': 1 - a, 'hairB' + d: a * (1 - b), 'hairT' + d: a * b}
        J, W = weights(M, cu['V'], hair_w if name == 'relief' else curl_w)
        add(cu, lit_toned('hair'), J=J, W=W)


def add_flower(M, p, nrm, size, i, hood_w):
    """A five-petal flower lying on the surface at p: a star fan with a raised gold centre."""
    t1 = np.cross(nrm, (0., 1., 0.))
    if np.linalg.norm(t1) < 1e-3:
        t1 = np.cross(nrm, (1., 0., 0.))
    t1 = N_(t1)
    t2 = np.cross(nrm, t1)
    rot = (i * 37) % 72
    V = [p + nrm * .016]
    for k in range(10):
        a = RAD(rot) + k * math.pi / 5
        r = size if k % 2 == 0 else size * .50
        V.append(p + r * (math.cos(a) * t1 + math.sin(a) * t2) - nrm * (.004 if k % 2 else 0))
    F = [(0, 1 + k, 1 + (k + 1) % 10) for k in range(10)]
    part = dict(V=A(V), F=A(F, int), ax=A([p - nrm * .05]), fb=None)
    J, W = weights(M, part['V'], hood_w)
    M.add(part, lambda c, n, i=i: 'pink_l' if hsh1(c) > .6 else 'pink', J=J, W=W)


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
    tiles = {'skirt': paint_skirt_tile(), 'hood': paint_hood_tile(P), 'face': paint_face_tile()}
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
    arr = bake_uvs(tris, at, M.COL)
    top = float(arr['P'][:, 1].max())
    scale = HEIGHT / top
    ex = dict(variant='reference', tris=len(tris), hood_top_m=HEIGHT, units_per_m=1 / scale)
    path = os.path.join(out_dir, name + '.glb')
    n = glb.export(path, M, arr, at.img, clips, scale, mesh_name='Witch', generator='tools/characters/witch_ref.py', extras=ex)
    print('  %s: %d triangles, %d bones, %d clips, atlas %dx%d (%.0f%% used), top %.3f m (scale %.3f)'
          % (path, n, len(M.names), len(clips), at.W, at.H, 100 * at.usage(), top * scale, scale))
    assert n <= 4000, 'triangle budget'
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
