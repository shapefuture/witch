"""The Shadow (concept sheet, bottom left) and the Lady under its cloak.

    python tools/characters/shadow.py --out assets/characters --face-tex FACE.png [--preview DIR]

Writes shadow.glb (hooded, ragged layered cloak, scroll bundle, satchel; 1.70 m with the hood)
and shadow_lady.glb (the same woman unhooded: brown jacket, gold collar, purple skirt). Both
face +Z with the feet on y = 0 and carry idle, walk and talk.

Ported from the user's LadyPSX model (numpy -> glTF). The face is a photo-projected relief
plate whose UVs come from reference pixels; --face-tex is the 160x228 texture its extractor
wrote (face_tex.png). The reference photo is not in the repo; without --face-tex the build
reuses the processed textures already embedded in the GLBs in --out.

Units are the source's metres; the head group is enlarged (HEAD_SCALE) toward the sheet's
proportions and finish() normalises the height.
"""

import argparse
import io
import math
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb  # noqa: E402
from glb import A, Clip, catmull, hring, loft, minrot, nz, q5, smooth, wave  # noqa: E402

HEIGHT = {True: 1.70, False: 1.65}       # the Shadow with its hood; the Lady
# The sheet's Shadow is stocky: hood and head are 27% of its height, shoulders 0.42 H wide.
# Measured against it, the source body is fine and the head is what has to grow (1.6x),
# with the arms set wider under a big mantle. The Lady keeps near-source proportions.
HEAD_SCALE = {True: 1.60, False: 1.20}
ARM_DX = {True: .045, False: 0.0}
HEAD_PIVOT = (0, 1.455, .012)

BASE = {
    'face': (1, 1, 1), 'skin': (.84, .72, .67), 'neck': (.70, .58, .54), 'silver': (.86, .87, .91),
    'hair': (.24, .19, .18), 'hair_d': (.13, .10, .10), 'hair_l': (.32, .26, .25),
    'boot': (.21, .16, .10), 'sole': (.11, .085, .065),
}
LADY = dict(BASE, **{
    'tights': (.17, .12, .14), 'jacket': (.28, .21, .14), 'gold': (.80, .63, .25), 'gold_d': (.58, .40, .09),
    'purple': (.40, .27, .48), 'purple_d': (.33, .22, .42), 'purple_in': (.14, .09, .20),
})
SHADOW = dict(BASE, **{
    'hair': (.15, .13, .14), 'hair_d': (.08, .07, .08), 'hair_l': (.22, .19, .20),
    'tights': (.13, .12, .16), 'wrap': (.40, .40, .46), 'nail': (.10, .08, .10),
    'cloak': (.22, .23, .31), 'cloak_d': (.17, .18, .25), 'cloak_l': (.27, .28, .37), 'lining': (.07, .07, .10),
    'robe': (.15, .17, .25), 'robe_l': (.22, .24, .33), 'scarf': (.18, .19, .26), 'sash': (.33, .33, .40),
    'leather': (.50, .33, .21), 'leather_d': (.35, .23, .15), 'brass': (.74, .62, .37),
    'parch': (.85, .73, .52), 'parch_d': (.65, .51, .33), 'ink': (.12, .10, .12),
})
LADY = {k: q5(v) for k, v in LADY.items()}
SHADOW = {k: q5(v) for k, v in SHADOW.items()}


# ---------------------------------------------------------------------------- face texture

EYE = dict(cy=102.0, cx=46.5, r=5.8, x0=33.5, x1=63.5, up=(101.0, 95.6, 100.0), lo=(102.0, 108.0, 103.0))


def _parab(p, x, x0, x1):
    """Quadratic through (x0, p0), (mid, p1), (x1, p2)."""
    xm = (x0 + x1) / 2
    return float(np.polyval(np.polyfit([x0, xm, x1], p, 2), x))


def face_texture(src, lidded):
    """The extractor's face texture with crisp, palette-painted eyes, mirrored and 5-bit.
    lidded: heavy upper lids and a lowered gaze (the sheet's downcast Shadow)."""
    from PIL import Image
    a = np.asarray(Image.open(src).convert('RGB')).astype(float) / 255
    a = a.copy()
    H, W, _ = a.shape
    e = EYE
    skin_above = np.median(a[86:92, 36:60].reshape(-1, 3), 0)
    lid = np.clip(skin_above * (.92, .86, .86), 0, 1)
    sclera = A((.86, .83, .79))
    iris_o, iris_i = A((.20, .17, .13)), A((.36, .31, .22))
    pupil, lash = A((.04, .03, .03)), A((.09, .06, .06))
    drop = 4.6 if lidded else 0.0
    gaze = 1.0 if lidded else 0.0
    for y in range(88, 114):
        for x in range(30, 68):
            xc = x + .5
            yc = y + .5
            if not e['x0'] <= xc <= e['x1']:
                continue
            yu = _parab(e['up'], xc, e['x0'], e['x1'])
            yl = _parab(e['lo'], xc, e['x0'], e['x1'])
            if yu - 1.7 <= yc < yu + .3 and not lidded:
                a[y, x] = lash
            elif yu <= yc < yl:
                if yc < yu + drop:
                    a[y, x] = lid
                    continue
                if lidded and yc < yu + drop + 1.4:
                    a[y, x] = lash
                    continue
                d = math.hypot(xc - e['cx'], yc - (e['cy'] + gaze))
                if d < 2.3:
                    a[y, x] = pupil
                elif d < 4.2:
                    a[y, x] = iris_i
                elif d < e['r']:
                    a[y, x] = iris_o
                else:
                    a[y, x] = sclera
            elif yl <= yc < yl + 1.0 and e['x0'] + 3 < xc < e['x1'] - 3:
                a[y, x] = a[y, x] * .78
    # catch-light, and the outer flick of the lash line
    hy = int(e['cy'] + gaze - 2)
    if not lidded or hy >= _parab(e['up'], 45, e['x0'], e['x1']) + drop + 1.5:
        a[hy, 45] = (.95, .93, .90)
    for x, y in ((32, 100), (31, 99), (33, 100)):
        a[y + (2 if lidded else 0), x] = lash
    half = W // 2
    a[:, half:] = a[:, :half][:, ::-1]
    a = np.round(np.clip(a, 0, 1) * 31) / 31
    im = Image.fromarray((a * 255 + .5).astype(np.uint8))
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    cheek = a[118:146, 26:52].reshape(-1, 3).mean(0)
    return buf.getvalue(), tuple(float(c) for c in cheek)


# ---------------------------------------------------------------------------- skeleton

def AY(x):
    return 1.341 - .037 * (x - .14)


def skeleton(m, shadow):
    b = m.bone
    b('root', None, (0, 0, 0))
    b('hips', 'root', (0, 1.0, 0))
    b('spine', 'hips', (0, 1.10, 0))
    b('chest', 'spine', (0, 1.24, 0))
    b('neck', 'chest', (0, 1.40, 0))
    b('head', 'neck', (0, 1.46, 0))
    if not shadow:
        b('hair1', 'head', (0, 1.58, -.09))
        b('hair2', 'hair1', (0, 1.42, -.15))
        b('hair3', 'hair2', (0, 1.27, -.15))
    for s, d in ((1, '.L'), (-1, '.R')):
        b('clav' + d, 'chest', (s * .03, 1.37, 0))
        b('uarm' + d, 'clav' + d, (s * .14, AY(.14), 0))
        b('farm' + d, 'uarm' + d, (s * .36, AY(.36), 0))
        b('hand' + d, 'farm' + d, (s * .55, AY(.55), 0))
        b('thigh' + d, 'hips', (s * .08, 1.0, 0))
        b('shin' + d, 'thigh' + d, (s * .084, .52, -.02))
        b('foot' + d, 'shin' + d, (s * .090, .08, -.04))
    if shadow:
        b('cloak1', 'hips', (0, 1.02, -.13))
        b('cloak2', 'cloak1', (0, .55, -.19))


# ---------------------------------------------------------------------------- shared helpers

def hairmat(c, n):
    h = .5 + .5 * math.sin(c[0] * 29 + c[1] * 37 + math.sin(c[2] * 31 + c[1] * 19) * 2.0)
    if n[1] > .55:
        return 'hair_l' if h > .35 else 'hair'
    return 'hair_l' if h > .80 else ('hair_d' if h < .22 else 'hair')


def blob(c, r, d=(0, 1, 0), N=8, k=3):
    return glb.blob(c, r, d, N, k)


def tube(path, radii, N=5, ratio=1., flat=(0, 0, 1.), cap=(.004, .01)):
    return glb.tube(path, radii, N, ratio, up=flat, cap=cap)


def leg_skin(m, V, s, d, front_only=False, amount=.75):
    """Weights for a skirt/robe vertex: hips, pulled toward the thigh on its side (more
    toward the hem and the outside), so a stride swings the hem instead of piercing it."""
    W = m.rigid(len(V), 'hips')
    t = smooth((1.0 - V[:, 1]) / .55) * np.clip(np.abs(V[:, 0]) / .09, 0, 1) * amount
    side = np.where(V[:, 0] >= 0, m.ix['thigh.L'], m.ix['thigh.R'])
    W *= (1 - t)[:, None]
    W[np.arange(len(V)), side] += t
    return W


# ---------------------------------------------------------------------------- head and face

HR = [(1.470, .014, .0285, .0585), (1.484, .036, .0515, .0465), (1.500, .050, .0655, .0405), (1.522, .064, .0825, .0275),
      (1.552, .069, .096, .018), (1.590, .069, .100, .015), (1.630, .066, .096, .011), (1.662, .054, .0845, .0065),
      (1.684, .028, .056, -.004)]
HYs = [h[0] for h in HR]


def hr(y):
    y = min(max(y, HYs[0]), HYs[-1])
    for i in range(len(HR) - 1):
        if HYs[i] <= y <= HYs[i + 1]:
            f = (y - HYs[i]) / (HYs[i + 1] - HYs[i])
            return [HR[i][k] * (1 - f) + HR[i + 1][k] * f for k in (1, 2, 3)]


def head_z(x, y):
    rx, rz, cz = hr(y)
    return cz + rz * math.sqrt(max(1 - (x / rx) ** 2, 0))


CXP, PPM, Y0W, TX0, TX1, TY0, TY1 = 397., 516.47, 1150., 357, 437, 284, 398


def relief(x, y):
    """Height of the face plate above the head shell (metres, source scale)."""
    ax = abs(x)
    h = 0.
    if 1.518 <= y <= 1.600:     # nose: bridge ridge -> tip -> under-nose
        if y >= 1.538:
            tt = min(1, max(0, (1.588 - y) / .050))
            hn = .0025 + (.0135 - .0025) * tt ** 1.25
            sg = .0045 + .0042 * tt
        else:
            hn = .0135 * max(0, (y - 1.518) / .020)
            sg = .0087
        h += hn * math.exp(-(ax / sg) ** 2)
    h += .0055 * math.exp(-(((ax - .0105) / .0055) ** 2 + ((y - 1.5345) / .0050) ** 2))      # alae
    h += .0042 * math.exp(-((ax / .026) ** 4 + ((y - 1.508) / .0085) ** 2))                   # lips
    h -= .0012 * math.exp(-((ax / .0045) ** 2 + ((y - 1.522) / .004) ** 2))                   # philtrum
    h += .0030 * math.exp(-((y - 1.603) / .0075) ** 2) * (1 if ax < .048 else math.exp(-((ax - .048) / .012) ** 2))
    h -= .0028 * math.exp(-(((ax - .030) / .014) ** 2 + ((y - 1.580) / .010) ** 2))           # sockets
    h += .0016 * math.exp(-(((ax - .031) / .012) ** 2 + ((y - 1.5885) / .0035) ** 2))         # upper lids
    h += .0030 * math.exp(-(((ax - .042) / .020) ** 2 + ((y - 1.545) / .020) ** 2))           # cheekbones
    h += .0032 * math.exp(-((ax / .020) ** 2 + ((y - 1.477) / .010) ** 2))                    # chin
    return h


def face_plate(m):
    ys = [1.470, 1.482, 1.494, 1.504, 1.512, 1.522, 1.532, 1.540, 1.552, 1.566, 1.574, 1.582, 1.590, 1.598,
          1.608, 1.626, 1.646, 1.664]
    fs = [-.93, -.70, -.50, -.36, -.24, -.12, 0, .12, .24, .36, .50, .70, .93]
    V, UV, F = [], [], []
    C = len(fs)
    for j, y in enumerate(ys):
        rx = hr(y)[0]
        for i, f in enumerate(fs):
            x = f * rx
            edge = i in (0, C - 1) or j in (0, len(ys) - 1)
            V.append((x, y, head_z(x, y) + (.0008 if edge else .0028 + relief(x, y))))
            UV.append(((CXP + PPM * x - TX0) / (TX1 - TX0), (Y0W - PPM * y - TY0) / (TY1 - TY0)))
    for j in range(len(ys) - 1):
        for i in range(C - 1):
            a = j * C + i
            F += [(a, a + 1, a + C + 1), (a, a + C + 1, a + C)]
    V = A(V)
    Nv = np.zeros_like(V)
    for f_ in F:
        q = V[list(f_)]
        n = np.cross(q[1] - q[0], q[2] - q[0])
        if n[2] < 0:
            n = -n
        for k in f_:
            Nv[k] += n
    Nv = Nv / np.linalg.norm(Nv, axis=1, keepdims=True)
    m.add(dict(V=V, F=A(F, int), ax=A([(0, y, hr(y)[2] - .05) for y in ys]), uv=A(UV), vn=Nv), 'face', 'head')


def build_head(m, shadow):
    m.add(loft([hring(y, rx, rz, cz, N=20) for y, rx, rz, cz in HR], (.008, .004)), 'skin', 'head')
    nk = loft([hring(1.34, .040, .042, .004, N=10), hring(1.40, .036, .038, .006, N=10), hring(1.475, .034, .036, .012, N=10)],
              (.003, .0))
    m.add(nk, 'neck', m.blend(nk['V'][:, 1], [(1.34, 'chest'), (1.40, 'neck'), (1.475, 'head')]))
    face_plate(m)
    if not shadow:
        for s in (1, -1):
            m.add(blob((s * .0660, 1.549, -.014), (.0055, .024, .016), (0, 1, 0), 6, 3), 'skin', 'head')
            m.add(blob((s * .0760, 1.526, -.004), (.0048, .0048, .0048), (0, 1, 0), 5, 2), 'silver', 'head')
            m.add(blob((s * .0765, 1.499, -.004), (.0058, .0205, .0045), (0, 1, 0), 6, 3), 'silver', 'head')


def hair_cap(m):
    """The source's hair 'hood': a shell round the skull with a window for the face."""
    rnd = random.Random(5)
    R = [(1.470, -.022, .112, .097, -.148, .045, -.040), (1.515, -.015, .108, .119, -.131, .084, -.043),
         (1.552, -.0125, .1055, .125, -.126, .084, -.046), (1.590, -.0105, .0975, .127, -.116, .058, -.030),
         (1.628, -.011, .088, .119, -.107, .044, -.014), (1.650, -.006, .076, .118, -.098, .030, .000),
         (1.668, -.008, .068, .104, -.084, None, None), (1.684, -.012, .054, .080, -.072, None, None),
         (1.696, -.018, .032, .048, -.050, None, None), (1.704, -.022, .008, .012, -.024, None, None)]
    M = 11
    rg = []
    for (y, cx, rx, fr, bk, xr, xl) in R:
        cz, rz = (fr + bk) / 2, (fr - bk) / 2
        pl = math.degrees(math.asin(max(-1, min(1, (xr - cx) / rx)))) if xr is not None else 0.
        pr = math.degrees(math.asin(max(-1, min(1, (cx - xl) / rx)))) if xl is not None else 0.
        r = []
        for k in range(M):
            t = math.radians(pl + (360 - pl - pr) * k / (M - 1))
            j = 1 + (rnd.uniform(-.006, .006) if 0 < k < M - 1 else 0)
            r.append((cx + rx * j * math.sin(t), y, cz + rz * j * math.cos(t)))
        rg.append(r)
    m.add(loft(rg, None, False, ax=[(0, y, -.02) for y, *_ in R]), hairmat, 'head')
    return rnd


def fringe_and_curtains(m, shadow):
    # curtains draping over the shoulders to points on the chest (both sides for the Shadow)
    for s in (() if shadow else (1,)):  # inside the hood the hair cap is enough
        x = -s
        p = [(x * .098, 1.500, .060), (x * .104, 1.462, .080), (x * .104, 1.415, .088), (x * .100, 1.360, .092),
             (x * .095, 1.315, .094), (x * .090, 1.272, .095)]
        m.add(tube(p, [.018, .028, .032, .030, .020, .003], 4, .42, (0, 0, 1), cap=(.004, .02)), hairmat, 'head')

    def hp(x, y, off):
        rx, rz, cz = hr(y)
        return (x, y, head_z(max(-.98 * rx, min(.98 * rx, x)), y) + off)
    fp = [(.005, 1.662, .012, .010), (-.030, 1.640, .020, .010), (-.043, 1.616, .024, .011), (-.049, 1.598, .026, .012),
          (-.041, 1.580, .026, .012), (-.035, 1.567, .020, .011), (-.030, 1.556, .006, .008)]
    p = [hp(x, y, o) for x, y, r_, o in fp]
    m.add(tube(catmull(p, 2), [r_ for _, _, r_, _ in fp], 5, .5, (0, 0, 1), cap=(.004, .01)), hairmat, 'head')


def back_hair(m, rnd):
    m.add(blob((-.021, 1.690, -.010), (.022, .018, .026), (0, 1, 0), 6, 2), hairmat, 'head')
    BM = [(1.60, -.010, .070, .072, -.030), (1.545, -.011, .088, .088, -.040), (1.50, -.012, .108, .094, -.052),
          (1.46, -.012, .126, .098, -.075), (1.42, -.012, .132, .095, -.082), (1.38, -.010, .158, .090, -.086),
          (1.34, -.008, .164, .088, -.088), (1.30, -.005, .156, .085, -.086), (1.26, -.003, .124, .082, -.086),
          (1.23, 0, .106, .074, -.090), (1.205, 0, .080, .055, -.094)]
    N = 20
    rings = []
    for i, (y, cx, rx, rz, cz) in enumerate(BM):
        r = hring(y, rx, rz, cz, N=N, e=2.3)
        r[:, 0] += cx
        for k in range(N):
            f = 1 + (rnd.uniform(-.012, .012) + .040 * math.sin(k * 2 * math.pi * 3 / N + y * 34)) * (0 if i == 0 else 1)
            r[k, 0] = cx + (r[k, 0] - cx) * f
            r[k, 2] = cz + (r[k, 2] - cz) * f
            if y < 1.44 and r[k, 2] < cz:
                r[k, 1] += rnd.uniform(-.014, .014)
        rings.append(r)
    g = loft(rings, (.012, .012))
    m.add(g, hairmat, m.blend(-g['V'][:, 1], [(-1.62, 'head'), (-1.5, 'hair1'), (-1.35, 'hair2'), (-1.2, 'hair3')]))
    tab = A(BM)

    def hb(x, y):
        cx = np.interp(-y, -tab[:, 0], tab[:, 1])
        rx = np.interp(-y, -tab[:, 0], tab[:, 2])
        rz = np.interp(-y, -tab[:, 0], tab[:, 3])
        cz = np.interp(-y, -tab[:, 0], tab[:, 4])
        return cz - rz * max(0, 1 - (abs(x - cx) / rx) ** 2.3) ** (1 / 2.3)
    for y0, xs, lim in ((1.44, (-.08, -.04, 0, .04, .08), .09), (1.35, (-.10, -.06, -.02, .02, .06, .10), .11),
                        (1.27, (-.075, -.035, .005, .045, .085), .09)):
        for x in xs:
            x = max(-lim, min(lim, x + rnd.uniform(-.006, .006)))
            ln = .10 + rnd.uniform(0, .03)
            p = [(x, y0, hb(x, y0) - .008), (x + rnd.uniform(-.008, .008), y0 - ln * .5, hb(x, y0 - ln * .5) - .010),
                 (x * .96 + rnd.uniform(-.006, .006), y0 - ln, hb(x, y0 - ln) - .006)]
            tb = tube(p, [.030, .026, .010], 4, .5, (0, 0, 1), cap=(.003, .014))
            m.add(tb, hairmat, m.blend(-tb['V'][:, 1], [(-1.5, 'hair1'), (-1.3, 'hair2'), (-1.2, 'hair3')]))
    for x, ye in ((-.05, 1.150), (-.02, 1.125), (0.01, 1.118), (.04, 1.135), (.065, 1.16)):
        p = [(x, 1.225, -.092), (x * .9, (1.225 + ye) / 2, -.090), (x * .8, ye, -.088)]
        m.add(tube(p, [.024, .017, .003], 4, .35, (0, 0, 1), cap=(.003, .01)), hairmat, 'hair3')


def hood(m):
    """Cloth hood (built at head scale; the head group is enlarged afterwards). Few, large
    facets: 11 columns with fold creases (darker valleys, a ridge down the back), the top
    rings walking backward into a soft peak that falls behind the head, and the bottom
    rings flaring into a ragged drape that lies over the shoulders into the mantle.
    Outer shell, near-black lining, and a rim round the face window (pointed arch on top)."""
    #      y     cz     rx    rz   window half-angle (deg)
    R = [(1.398, -.026, .200, .180, 38), (1.432, -.020, .158, .156, 42), (1.472, -.017, .150, .152, 50),
         (1.532, -.016, .160, .162, 60), (1.600, -.022, .150, .158, 60), (1.660, -.048, .116, .136, 46),
         (1.705, -.086, .076, .100, 28), (1.736, -.138, .042, .060, 0), (1.750, -.198, .020, .030, 0)]
    tip = A((0, 1.742, -.270))
    M = 11
    crease = [0, .06, -.03, .07, -.02, .09, -.02, .07, -.03, .06, 0]
    rnd = random.Random(61)
    outer, inner = [], []
    for y, cz, rx, rz, op in R:
        o, i_ = [], []
        for k in range(M):
            t = math.radians(op + (360 - 2 * op) * k / (M - 1))
            f = 1 + crease[k] * (0 if op and k in (0, M - 1) else 1)
            o.append((rx * f * math.sin(t), y, cz + rz * f * math.cos(t)))
            i_.append((rx * .86 * math.sin(t), y, cz + rz * .86 * math.cos(t) + .004))
        outer.append(o)
        inner.append(i_)
    axis = [(0, y, cz) for y, cz, rx, rz, op in R]
    go = loft(outer, None, False, ax=axis)
    V = list(go['V'])
    F = [tuple(f) for f in go['F']]
    fb = [1 if crease[(i // 2) % (M - 1)] < 0 or crease[(i // 2) % (M - 1) + 1] < 0 else 0 for i in range(len(F))]
    last = (len(R) - 1) * M
    V.append(tip)
    for k in range(M - 1):
        F.append((last + k, last + k + 1, len(V) - 1))
        fb.append(0)
    # torn drape edge over the shoulders
    for k in range(M - 1):
        a_, b_ = A(outer[0][k]), A(outer[0][k + 1])
        mid = (a_ + b_) / 2
        out = nz(mid - A((0, mid[1], -.03))) * A((1, 0, 1))
        V.append(mid + A((0, -.030 - rnd.uniform(0, .025), 0)) + out * .020)
        F.append((k, k + 1, len(V) - 1))
        fb.append(0)
    go = dict(V=A(V), F=A(F), ax=A(axis + [(0, 1.70, -.12)]), fb=A(fb))

    def hw(V):  # the drape follows the chest, the cowl the neck, the rest the head
        return m.blend(V[:, 1], [(1.38, 'chest'), (1.44, 'neck'), (1.51, 'head')])
    m.add(go, ['cloak', 'cloak_d'], hw(go['V']))
    gi = loft(inner, None, False, ax=axis)
    m.add(gi, 'lining', hw(gi['V']), inv=True)
    V, F = [], []
    for k in (0, M - 1):
        base = len(V)
        for r in range(len(R)):
            V += [outer[r][k], inner[r][k]]
        for r in range(len(R) - 1):
            a_ = base + 2 * r
            F += [(a_, a_ + 2, a_ + 3), (a_, a_ + 3, a_ + 1)]
    V = A(V)
    m.add(dict(V=V, F=A(F), ax=A([(0, 1.56, -.06)])), 'cloak_l', hw(V))


def scale_head_group(m, start, bones, k):
    for p in m.parts[start:]:
        glb.scale_about(p, k, HEAD_PIVOT)
    piv = A(HEAD_PIVOT)
    for b in bones:
        par, h = m.bones[b]
        m.bones[b] = (par, (h - piv) * k + piv)


def widen_arms(m, start, dx):
    """Set the arms further out (sleeves included): the sheet's shoulders are broad."""
    for p in m.parts[start:]:
        sgn = np.sign(p['V'][:, 0].mean())
        p['V'] = p['V'] + A((sgn * dx, 0, 0))
        p['ax'] = A(p['ax'], float) + A((sgn * dx, 0, 0))
    for d, sgn in (('.L', 1), ('.R', -1)):
        for b in ('uarm', 'farm', 'hand'):
            par, h = m.bones[b + d]
            m.bones[b + d] = (par, h + A((sgn * dx, 0, 0)))


# ---------------------------------------------------------------------------- body

def build_legs(m, shadow):
    for s, d in ((1, '.L'), (-1, '.R')):
        bx, zA = s * .092, -.038
        g = loft([hring(y, r, r, z, cx=cx, N=8) for y, r, cx, z in ((.28, .030, bx, zA), (.55, .040, s * .084, -.02),
                                                                     (.95, .052, s * .07, 0))], (.004, .004))
        m.add(g, 'tights', m.blend(g['V'][:, 1], [(.45, 'shin' + d), (.62, 'thigh' + d)]))
        ang, piv, bone = s * 28, (bx, 0, zA), 'foot' + d
        sh = loft([hring(y, .038, .040, zA, cx=bx, N=10) for y in (.07, .15, .24, .31)], (.0, .004))
        m.add(sh, 'boot', m.blend(sh['V'][:, 1], [(.12, bone), (.22, 'shin' + d)]))
        FR = ((-.050, .030, .040, .048), (-.020, .036, .055, .062), (.030, .037, .048, .055), (.090, .038, .036, .040),
              (.140, .033, .028, .031), (.175, .020, .020, .022))
        ft = loft([A([(bx + rx_ * math.cos(2 * math.pi * k / 8), cy + ry * math.sin(2 * math.pi * k / 8), zA + z)
                      for k in range(8)]) for z, rx_, ry, cy in FR], (.012, .02))
        m.add(glb.transform(ft, glb.rot_axis((0, 1, 0), ang), piv=piv), 'boot', bone)
        SR = ((-.055, .031), (-.02, .038), (.03, .039), (.09, .040), (.14, .035), (.185, .022))
        so = loft([A([(bx + rx_ * math.cos(2 * math.pi * k / 8), .010 + .010 * math.sin(2 * math.pi * k / 8), zA + z)
                      for k in range(8)]) for z, rx_ in SR], (.006, .012))
        m.add(glb.transform(so, glb.rot_axis((0, 1, 0), ang), piv=piv), 'sole', bone)


def hem_skirt(T, N, sc, zc, rg, ragged=1.0):
    """The source's skirt shell: rings T=(y, rx, rz), then a hem of pointed tatters."""
    dpk = [rg.uniform(.095, .112, 2) * ragged for _ in range(N)]
    dvl = [rg.uniform(.060, .076, 3) * ragged for _ in range(N)]

    def make(k_):
        rings = [A([(k_ * a * sc * math.sin(2 * math.pi * k / N), y, zc + k_ * b * sc * math.cos(2 * math.pi * k / N))
                    for k in range(N)]) for y, a, b in T]
        R = len(rings)
        V = [p for r in rings for p in r]
        F = []
        for k in range(R - 1):
            for mm in range(N):
                a_, b_ = k * N + mm, k * N + (mm + 1) % N
                F += [(a_, b_, a_ + N), (b_, b_ + N, a_ + N)]
        last, prev = rings[-1], rings[-2]
        base, cb = (R - 1) * N, len(V)
        for mm in range(N):
            V.append(last[mm] + nz(last[mm] - prev[mm]) * dvl[mm][0])
        for mm in range(N):
            m1 = (mm + 1) % N
            e = last[m1] - last[mm]
            d = nz((last[mm] + last[m1]) / 2 - (prev[mm] + prev[m1]) / 2)
            h0 = len(V)
            V.append(last[mm] + .25 * e + d * dpk[mm][0])
            V.append(last[mm] + .5 * e + d * dvl[mm][1])
            V.append(last[mm] + .75 * e + d * dpk[mm][1])
            F += [(base + mm, cb + mm, h0), (base + mm, h0, h0 + 1), (base + mm, h0 + 1, base + m1),
                  (base + m1, h0 + 1, h0 + 2), (base + m1, h0 + 2, cb + m1)]
        return dict(V=A(V), F=A(F, int), ax=A([(0, y, zc) for y in np.linspace(T[0][0], T[-1][0] + .05, 14)]))
    return make


def build_skirt(m):
    N, zc = 16, -.010
    T = [(1.10, .108, .078), (1.05, .124, .089), (1.03, .130, .093), (.93, .153, .111), (.885, .167, .120),
         (.68, .190, .137), (.48, .203, .146), (.27, .216, .156)]
    rg = np.random.RandomState(3)
    make = hem_skirt(T, N, 1.016, zc, rg)
    g = make(1.)
    fm = [(rg.rand() < .4) for _ in range(N)]

    def mat(c, n):
        k = int(round(math.atan2(c[0], c[2] - zc) / (2 * math.pi / N) - .5)) % N
        return 'purple_d' if fm[k] else 'purple'
    m.add(g, mat, leg_skin(m, g['V'], 1, '', amount=.6))
    gi = make(.985)
    m.add(gi, 'purple_in', leg_skin(m, gi['V'], 1, '', amount=.6), inv=True)


JR = [(1.035, .132, .092, .010), (1.105, .108, .074, .014), (1.14, .102, .069, .017), (1.18, .110, .076, .018),
      (1.225, .118, .086, .010), (1.265, .128, .098, .012), (1.30, .132, .104, .012), (1.34, .136, .094, .010),
      (1.375, .138, .080, .006), (1.402, .110, .064, .002), (1.42, .052, .048, .004)]
JY = [j[0] for j in JR]


def jr(y):
    return [np.interp(y, JY, [j[k] for j in JR]) for k in (1, 2, 3)]


def bust(x, y):
    return float(np.interp(y, [1.20, 1.245, 1.285, 1.325, 1.36], [0, .006, .011, .006, 0]) * math.exp(-((abs(x) - .05) / .036) ** 2))


def jz(x, y, back=False):
    rx, rz, cz = jr(y)
    v = max(0, 1 - (abs(x) / rx) ** 2.2) ** (1 / 2.2)
    return cz - rz * v if back else cz + rz * v + bust(x, y)


SLX = [.10, .14, .18, .22, .30, .40, .48, .55, .565]
SLR = [.062, .056, .046, .038, .032, .029, .0245, .022, .0215]


def slz(x, y):
    x = abs(x)
    if x < .10:
        return 0.
    r = np.interp(x, SLX, SLR)
    dy = y - AY(x)
    return math.sqrt(max(0, r * r - dy * dy))


def sz(x, y):
    return max(jz(x, y), slz(x, y))


def build_jacket(m, shadow):
    N = 20
    rings = []
    for i, (y, rx, rz, cz) in enumerate(JR):
        r = hring(y, rx, rz, cz, N=N, e=2.2)
        for k in range(N):
            if r[k, 2] > cz:
                r[k, 2] += bust(r[k, 0], y)
            if i == 0:
                r[k, 1] = (1.028 + .40 * min(abs(r[k, 0]), .130)) if r[k, 2] > cz else 1.080
        rings.append(r)
    g = loft(rings, (.004, .004))
    if shadow:  # the dark under-tunic: same torso, no collar
        m.add(g, 'robe', m.blend(g['V'][:, 1], [(1.05, 'hips'), (1.14, 'spine'), (1.22, 'spine'), (1.30, 'chest')]))
        return
    mat = lambda c, n: 'skin' if (c[2] > .03 and c[1] > 1.352 and abs(c[0]) < (c[1] - 1.352) * .45 + .004) else 'jacket'  # noqa: E731
    m.add(g, mat, m.blend(g['V'][:, 1], [(1.05, 'hips'), (1.14, 'spine'), (1.22, 'spine'), (1.30, 'chest')]))
    rx, rz, cz = .054, .052, .010
    M, bot, ph0 = 13, 1.394, 43
    top = lambda t: 1.470 - .040 * (abs(t) / math.pi) ** 1.2  # noqa: E731
    rg, rg2 = [], []
    for f in (0, .5, 1):
        r, r2 = [], []
        for k in range(M):
            tt = math.radians(ph0 + (360 - 2 * ph0) * k / (M - 1))
            ts = tt if tt <= math.pi else tt - 2 * math.pi
            y = bot + (top(ts) - bot) * f
            rad = 1 + .16 * f
            r.append((rx * rad * math.sin(tt), y, cz + rz * rad * math.cos(tt)))
            r2.append((.90 * rx * rad * math.sin(tt), y, cz + .90 * rz * rad * math.cos(tt)))
        rg.append(r)
        rg2.append(r2)
    ax = [(0, 1.395, cz), (0, 1.43, cz), (0, 1.47, cz)]
    m.add(loft(rg, None, False, ax=ax), 'gold', 'neck')
    m.add(loft(rg2, None, False, ax=ax), 'gold_d', 'neck', inv=True)
    O = [(0, 1.313), (.033, 1.326), (.058, 1.336), (.077, 1.346), (.093, 1.365), (.110, 1.384), (.116, 1.394), (.104, 1.412)]
    I = [(0, 1.352), (.004, 1.366), (.012, 1.380), (.015, 1.394), (.020, 1.405), (.030, 1.418), (.045, 1.426), (.057, 1.427)]
    n_ = len(O)
    for s_ in (1, -1):
        V = [(s_ * x, y, sz(x, y) + .010) for x, y in O] + [(s_ * x, y, sz(x, y) + .010) for x, y in I]
        F = []
        for k in range(n_ - 1):
            F += [(k, k + 1, n_ + k + 1), (k, n_ + k + 1, n_ + k)]
        m.add(dict(V=A(V), F=A(F), ax=A([(0, 1.32, 0), (0, 1.38, 0), (0, 1.44, 0)])), 'gold', 'chest')
    V = [(-x, y, sz(x, y) + .006) for x, y in I] + [(x, y, sz(x, y) + .006) for x, y in I]
    F = []
    for k in range(n_ - 1):
        F += [(k, k + 1, n_ + k + 1), (k, n_ + k + 1, n_ + k)]
    m.add(dict(V=A(V), F=A(F), ax=A([(0, 1.32, 0), (0, 1.38, 0), (0, 1.44, 0)])), 'skin', 'chest')


def arm_weights(m, X, d):
    return m.blend(np.abs(X), [(.12, 'clav' + d), (.19, 'uarm' + d), (.30, 'uarm' + d), (.36, 'farm' + d),
                               (.50, 'farm' + d), (.56, 'hand' + d)])


def build_arms(m, shadow):
    """T-pose arms exactly as the source builds them; pose_bind() lowers them later."""
    for s, d in ((1, '.L'), (-1, '.R')):
        rings = [[(s * x, AY(x) + r * math.sin(2 * math.pi * (k + .5) / 8), r * math.cos(2 * math.pi * (k + .5) / 8))
                  for k in range(8)] for x, r in zip(SLX, SLR)]
        g = loft(rings, (.004, .004), ax=[(s * x, AY(x), 0) for x in SLX])
        m.add(g, 'wrap' if shadow else 'jacket', arm_weights(m, g['V'][:, 0], d))
        hb = 'hand' + d
        yc = lambda x: AY(x) - .002  # noqa: E731
        pr = [(.548, .0135, .020), (.585, .0120, .028), (.625, .0105, .031), (.650, .0090, .030)]
        palm = loft([[(s * x, yc(x) + ry * math.sin(2 * math.pi * (k + .5) / 6), rz * math.cos(2 * math.pi * (k + .5) / 6))
                      for k in range(6)] for x, ry, rz in pr], (.004, .006), ax=[(s * x, yc(x), 0) for x, _, _ in pr])
        m.add(palm, 'skin', hb)
        tip = ['skin', 'skin', 'nail'] if shadow else 'skin'
        for zf, L, sp, dr in ((.0215, .078, .008, .007), (.0070, .088, .003, .008), (-.0075, .082, -.002, .008),
                              (-.0215, .066, -.008, .006)):
            x0 = .648
            pts = [(s * x0, yc(x0), zf), (s * (x0 + .5 * L), yc(x0) - dr * .3, zf + sp * .5), (s * (x0 + L), yc(x0) - dr, zf + sp)]
            m.add(tube(pts, [.0088, .0072, .0048], 5, 1., (0, 1, 0), cap=(.002, .006)), tip, hb)
        pts = [(s * .585, yc(.585) - .004, .022), (s * .610, yc(.61) - .006, .048), (s * .632, yc(.63) - .008, .070)]
        m.add(tube(pts, [.0125, .0098, .0072], 5, 1., (0, 1, 0), cap=(.002, .007)), tip, hb)
        if shadow:
            sleeve(m, s, d)


def sleeve(m, s, d):
    """Bell sleeve flaring past the elbow, torn at the cuff; two-sided."""
    rg = random.Random(11 + s)
    xs = [(.25, .068), (.36, .094), (.46, .140)]
    N = 9
    rings = [[(s * x, AY(x) + r * math.sin(2 * math.pi * k / N), r * math.cos(2 * math.pi * k / N)) for k in range(N)]
             for x, r in xs]
    last = A(rings[-1])
    tips = []
    for k in range(N):
        k1 = (k + 1) % N
        mid = (last[k] + last[k1]) / 2 + A((s * rg.uniform(.04, .09), -.012, 0))
        tips.append(mid)
    for inner in (False, True):
        sc = .92 if inner else 1.0
        rr = [[(p[0], AY(abs(p[0])) + (p[1] - AY(abs(p[0]))) * sc, p[2] * sc) for p in r] for r in rings]
        g = loft(rr, None, ax=[(s * x, AY(x), 0) for x, _ in xs] + [(s * .5, AY(.5), 0)])
        V = list(g['V'])
        F = [tuple(f) for f in g['F']]
        R = len(rr)
        for k in range(N):
            k1 = (k + 1) % N
            V.append(tips[k])
            F.append(((R - 1) * N + k, (R - 1) * N + k1, len(V) - 1))
        V = A(V)
        m.add(dict(V=V, F=A(F), ax=g['ax']), 'lining' if inner else 'cloak', arm_weights(m, V[:, 0], d), inv=inner)


# ---------------------------------------------------------------------------- poses

def arm_pose(m, shadow):
    """Global orientations for the arm chains -> local rotations for pose_bind()."""
    rots = {}

    def chain(d, rest, du, df, dh, roll_f=0.0, roll_h=0.0):
        Gu = minrot(rest, du)
        Gf = glb.rot_axis(df, roll_f) @ minrot(rest, df)
        Gh = glb.rot_axis(dh, roll_h) @ minrot(rest, dh)
        rots['uarm' + d] = Gu
        rots['farm' + d] = Gu.T @ Gf
        rots['hand' + d] = Gf.T @ Gh
    if shadow:  # the free right arm hangs a little forward of the cloak; the left cradles the scrolls
        chain('.R', (-1, 0, 0), (-.36, -.93, .06), (-.16, -.93, .33), (-.10, -.96, .25))
        chain('.L', (1, 0, 0), (.25, -.90, .35), (-.40, -.08, .91), (-.95, .20, .05), roll_f=-80, roll_h=-95)
    else:
        chain('.R', (-1, 0, 0), (-.20, -.975, -.03), (-.13, -.97, .19), (-.10, -.98, .14))
        chain('.L', (1, 0, 0), (.20, -.975, -.03), (.13, -.97, .19), (.10, -.98, .14))
    return rots


# ---------------------------------------------------------------------------- the Shadow's clothes

def robe(m):
    N, zc = 14, -.012
    T = [(1.08, .130, .096), (.98, .170, .122), (.80, .215, .152), (.58, .262, .182), (.36, .305, .208), (.15, .340, .232)]
    rg = np.random.RandomState(7)
    make = hem_skirt(T, N, 1.0, zc, rg, ragged=.8)
    g = make(1.)
    worn = [(rg.rand() < .35) for _ in range(N)]

    def mat(c, n):
        k = int(round(math.atan2(c[0], c[2] - zc) / (2 * math.pi / N) - .5)) % N
        return 'robe_l' if worn[k] and c[1] < .55 else 'robe'
    m.add(g, mat, leg_skin(m, g['V'], 1, '', amount=.7))
    gi = make(.97)
    m.add(gi, 'lining', leg_skin(m, gi['V'], 1, '', amount=.7), inv=True)


def open_shell(rings, th0s, M):
    """Rings (y, rx, rz, cz) as arcs from th0 to 2pi - th0 (an opening at the front)."""
    out = []
    for (y, rx, rz, cz), th0 in zip(rings, th0s):
        out.append([(rx * math.sin(t), y, cz + rz * math.cos(t)) for t in np.linspace(th0, 2 * math.pi - th0, M)])
    return out


def tatter(rings, rnd, depth, jag=.4):
    """Pointed teeth hanging from the last ring of an open shell: (V, F) to append."""
    last = A(rings[-1])
    prev = A(rings[-2])
    V, F = [], []
    for k in range(len(last) - 1):
        d = nz((last[k] + last[k + 1]) / 2 - (prev[k] + prev[k + 1]) / 2)
        tip = (last[k] + last[k + 1]) / 2 + d * depth * (1 + rnd.uniform(-jag, jag))
        V.append(tip)
        F.append((k, k + 1, len(last) + len(V) - 1))
    return V, F


def two_sided(m, rings, tat, mat_out, mat_in, W_of, axis, inset=.012):
    """An open shell with tattered hem, plus a lining shell pushed inward."""
    for inner in (False, True):
        rr = []
        for r in rings:
            r = A(r, float)
            if inner:
                ax_c = A(axis[min(range(len(axis)), key=lambda i: abs(axis[i][1] - r[0][1]))])
                v = r - ax_c
                v[:, 1] = 0
                r = r - nz_rows(v) * inset
            rr.append(r)
        g = loft(rr, None, False, ax=axis)
        V = list(g['V'])
        F = [tuple(f) for f in g['F']]
        base = (len(rr) - 1) * len(rr[0])
        for k, tip in enumerate(tat[0]):
            V.append(tip if not inner else tip + (A(axis[-1]) - tip) * A((1, 0, 1)) * .03)
            a, b, _ = tat[1][k]
            F.append((base + a, base + b, len(V) - 1))
        V = A(V)
        m.add(dict(V=V, F=A(F), ax=A(axis)), mat_in if inner else mat_out, W_of(V), inv=inner)


def nz_rows(v):
    n = np.linalg.norm(v, axis=1, keepdims=True)
    return v / np.where(n > 1e-9, n, 1)


def cloak_weights(m):
    def W(V):
        Wt = m.blend(V[:, 1], [(.50, 'cloak2'), (.95, 'cloak1'), (1.15, 'spine'), (1.28, 'chest')])
        # the front panels also follow the legs a little so a stride swings them
        front = np.clip(V[:, 2] / .12, 0, 1) * smooth((1.0 - V[:, 1]) / .6) * .55
        side = np.where(V[:, 0] >= 0, m.ix['thigh.L'], m.ix['thigh.R'])
        Wt *= (1 - front)[:, None]
        Wt[np.arange(len(V)), side] += front
        return Wt
    return W


def cloak(m):
    rnd = random.Random(21)
    M = 17
    R = [(1.30, .230, .170, -.020), (1.12, .262, .190, -.030), (.92, .290, .212, -.040), (.66, .335, .240, -.050),
         (.40, .385, .272, -.060), (.15, .425, .300, -.070)]
    th = [.70, .82, .92, .98, 1.02, 1.05]
    rings = open_shell(R, th, M)
    # a longer, uneven back hem
    for k in range(M):
        t = th[-1] + (2 * math.pi - 2 * th[-1]) * k / (M - 1)
        back = .5 - .5 * math.cos(t)
        rings[-1][k] = (rings[-1][k][0], rings[-1][k][1] - .07 * back + rnd.uniform(-.02, .02), rings[-1][k][2])
    axis = [(0, y, cz) for y, rx, rz, cz in R]
    two_sided(m, rings, tatter(rings, rnd, .10), lambda c, n: 'cloak_d' if (c[0] * 7.3 + c[1] * 3.1) % 1 < .3 else 'cloak',
              'lining', cloak_weights(m), axis)
    # wide ragged panels hanging down the back from under the mantle, three teeth each
    def surf(xx, y, off):
        rx, rz, cz = (np.interp(-y, [-q[0] for q in R], [q[i] for q in R]) for i in (1, 2, 3))
        return cz - rz * math.sqrt(max(0, 1 - (xx / rx) ** 2)) - off
    for x, y0, ln, w in ((-.14, 1.00, .62, .105), (.0, .98, .80, .115), (.14, 1.00, .54, .10)):
        V, F = [], []
        rows, cols = 3, 4
        for r in range(rows + 1):
            y = y0 - ln * r / rows
            for c in range(cols):
                xx = x + w * (2 * c / (cols - 1) - 1) * (1 - .12 * r / rows)
                V.append((xx, y, surf(xx, y, .012 + .004 * r)))
        for r in range(rows):
            for c in range(cols - 1):
                a_ = r * cols + c
                F += [(a_, a_ + 1, a_ + cols + 1), (a_, a_ + cols + 1, a_ + cols)]
        base = rows * cols
        for c in range(cols - 1):
            xa, xb = V[base + c][0], V[base + c + 1][0]
            yt = y0 - ln - rnd.uniform(.05, .12)
            V.append(((xa + xb) / 2 + rnd.uniform(-.01, .01), yt, surf((xa + xb) / 2, yt, .028)))
            F.append((base + c, base + c + 1, len(V) - 1))
        V = A(V)
        m.add(dict(V=V, F=A(F), ax=A([(x, y0 - ln / 2, 0)])), 'cloak_d', cloak_weights(m)(V))
    # a belt cinching the cloak at the waist (over the panels), ends at the front edges
    th_b = .90
    band = [[(rx * math.sin(t), y, cz + rz * math.cos(t)) for t in np.linspace(th_b, 2 * math.pi - th_b, 13)]
            for y, rx, rz, cz in ((.880, .312, .234, -.044), (.945, .304, .228, -.041))]
    g = loft(band, None, False, ax=[(0, .88, -.044), (0, .945, -.041)])
    m.add(g, 'leather_d', 'hips')


def mantle(m):
    """Broad shoulder cape in two layered tiers (the hood's drape lies over both), open at the
    throat, big ragged points, the lower tier longer at the back and over the arms."""
    def W(V):
        return m.blend(V[:, 1], [(1.20, 'spine'), (1.32, 'chest')])
    for seed, R, th, drop_b, drop_s, depth in (
            (31, [(1.37, .170, .150, .000), (1.25, .335, .245, -.015), (1.13, .425, .305, -.025), (1.02, .462, .330, -.035)],
             [.40, .42, .44, .46], .03, .05, .14),
            (33, [(1.39, .205, .175, .000), (1.30, .318, .235, -.010), (1.19, .405, .292, -.020)],
             [.38, .40, .42], .04, .03, .11)):
        rnd = random.Random(seed)
        M = 11
        rings = open_shell(R, th, M)
        for k in range(M):
            t = th[-1] + (2 * math.pi - 2 * th[-1]) * k / (M - 1)
            drop = drop_b * (.5 - .5 * math.cos(t)) + drop_s * abs(math.sin(t))
            rings[-1][k] = (rings[-1][k][0], rings[-1][k][1] - drop, rings[-1][k][2])
        axis = [(0, y, cz) for y, rx, rz, cz in R]
        two_sided(m, rings, tatter(rings, rnd, depth, .45), 'cloak_l' if seed == 33 else 'cloak', 'lining', W, axis,
                  inset=.012)


def scarf(m):
    """Bulky cowl under the chin that frames the pale face from below."""
    rg = random.Random(41)
    rings = []
    for y, rx, rz, cz in ((1.355, .118, .108, .006), (1.400, .126, .116, .012), (1.445, .112, .108, .016),
                          (1.478, .088, .088, .014), (1.492, .070, .072, .006)):
        r = hring(y, rx, rz, cz, N=14)
        r = r + A([(rg.uniform(-.004, .004), rg.uniform(-.004, .004), rg.uniform(-.004, .004)) for _ in r])
        rings.append(r)
    g = loft(rings, (.0, .0))
    m.add(g, lambda c, n: 'scarf' if n[1] < .4 else 'cloak_l', m.blend(g['V'][:, 1], [(1.36, 'chest'), (1.46, 'neck')]))
    # a fold hanging on the chest
    p = [(.03, 1.40, .115), (.02, 1.33, .125), (.0, 1.25, .118)]
    m.add(tube(p, [.035, .03, .012], 5, .45, (0, 0, 1), cap=(.004, .02)), 'scarf', 'chest')


def sash(m):
    """Bulky grey cloth sash at the waist, knotted at the front, two short ends."""
    g = loft([hring(y, rx, rz, -.004, N=12) for y, rx, rz in ((.965, .180, .135), (1.015, .186, .140), (1.065, .172, .130))],
             (.0, .0))
    g['V'] = glb.jitter(g['V'], .004, 3)
    m.add(g, 'sash', 'hips')
    m.add(blob((-.07, 1.015, .140), (.040, .034, .024), (0, 1, 0), 6, 2), 'sash', 'hips')
    for dx, ln in ((-.09, .16), (-.055, .12)):
        p = [(dx, 1.00, .146), (dx - .012, 1.00 - ln / 2, .158), (dx - .008, 1.00 - ln, .164)]
        m.add(tube(p, [.020, .018, .005], 4, .3, (0, 0, 1), cap=(.002, .012)), 'sash', 'hips')


def satchel(m):
    """Leather satchel low on the left hip (flap, buckle), strap over the right shoulder;
    a small drawstring pouch on the right hip."""
    c = A((.300, .74, .045))
    R = glb.rot_axis((0, 1, 0), 72) @ glb.rot_axis((0, 0, 1), -4)
    m.add(glb.box(c, (.115, .095, .040), R), 'leather', 'hips')
    m.add(glb.box(c + R @ A((0, .045, .012)), (.120, .055, .036), R @ glb.rot_axis((1, 0, 0), -5)), 'leather_d', 'hips')
    m.add(glb.box(c + R @ A((0, .010, .052)), (.018, .016, .006), R), 'brass', 'hips')
    path = [c + R @ A((-.09, .09, 0)), (.28, 1.00, -.12), (.12, 1.16, -.21), (-.10, 1.27, -.20), (-.22, 1.33, -.08),
            (-.20, 1.33, .09), (-.06, 1.20, .17), (.13, 1.00, .19), c + R @ A((.09, .09, 0))]
    st = tube(catmull(path, 2), [.020], 4, .3, (0, 0, 1), cap=(0.001, 0.001))
    m.add(st, 'leather_d', m.blend(st['V'][:, 1], [(1.05, 'hips'), (1.20, 'spine'), (1.30, 'chest')]))
    m.add(blob((-.255, .86, .10), (.060, .072, .045), (0, 1, 0), 6, 2), 'leather_d', 'hips')
    m.add(blob((-.255, .935, .104), (.032, .014, .030), (0, 1, 0), 5, 2), 'sash', 'hips')


SCROLL_BASE = A((.045, .92, .185))
SCROLL_AXIS = nz((.25, 1.0, -.12))


def scrolls(m):
    """A big bundle of rolled parchment cradled at the waist in the left arm, tops fanning
    toward the left shoulder; a dark quill among them and a leather tie."""
    rg = random.Random(51)
    specs = [(0, 0, .56, .040), (.050, .018, .50, .036), (-.045, .022, .47, .037), (.015, -.045, .44, .033),
             (.070, -.030, .40, .031), (-.020, .060, .36, .030)]
    for dx, dz, ln, r in specs:
        a = nz(SCROLL_AXIS + A((rg.uniform(-.08, .08) + dx * 2.0, 0, rg.uniform(-.06, .06) + dz * 2.0)))
        p0 = SCROLL_BASE + A((dx, rg.uniform(-.03, .03), dz))
        p1 = p0 + a * ln
        g = tube([p0, (p0 + p1) / 2, p1], [r, r * 1.03, r], 6, 1., (1, 0, 0), cap=(.002, .002))
        m.add(g, ['parch', 'parch', 'parch_d'], 'hand.L')
    q0 = SCROLL_BASE + A((-.07, .05, .03))
    m.add(tube([q0, q0 + nz((-.05, 1, .12)) * .42], [.007, .003], 4, 1., (1, 0, 0), cap=(.001, .03)), 'ink', 'hand.L')
    tie = loft([hring(0, .095, .080, 0, N=8) + A((0, h, 0)) for h in (-.016, .016)], (.0, .0))
    glb.transform(tie, minrot((0, 1, 0), SCROLL_AXIS), t=SCROLL_BASE + SCROLL_AXIS * .10 + A((.01, 0, .0)))
    m.add(tie, 'leather_d', 'hand.L')


# ---------------------------------------------------------------------------- build

def build(shadow):
    m = glb.Model('Shadow' if shadow else 'ShadowLady')
    skeleton(m, shadow)
    build_legs(m, shadow)
    if shadow:
        robe(m)
    else:
        build_skirt(m)
    build_jacket(m, shadow)
    start = len(m.parts)
    build_arms(m, shadow)
    widen_arms(m, start, ARM_DX[shadow])
    start = len(m.parts)
    build_head(m, shadow)
    rnd = hair_cap(m)
    fringe_and_curtains(m, shadow)
    if shadow:
        hood(m)
        scarf(m)
    else:
        back_hair(m, rnd)
    hb = ['head'] + ([] if shadow else ['hair1', 'hair2', 'hair3'])
    scale_head_group(m, start, hb, HEAD_SCALE[shadow])
    m.pose_bind(arm_pose(m, shadow))
    if shadow:
        mantle(m)
        cloak(m)
        sash(m)
        satchel(m)
        scrolls(m)
    return m


# ---------------------------------------------------------------------------- animation

def idle(shadow):
    def f(t):
        br = wave(t, 4.0)
        k = {
            'spine': (.8 * br, 0, 0),
            'chest': (1.2 * wave(t, 4.0, .1), 0, .6 * wave(t, 4.0, .3)),
            'neck': (-.6 * br, 0, 0),
            'head': (1.5 * wave(t, 4.0, .45), 3 * wave(t, 4.0, .2), 2.2 * wave(t, 4.0, .6)),
            'uarm.R': (2 * wave(t, 4.0, .15), 0, -1.5 * br),
            'farm.R': (-3 * wave(t, 4.0, .25), 0, 0),
        }
        if shadow:
            k.update({'cloak1': (1.5 * wave(t, 4.0, .2), 0, 1.0 * wave(t, 4.0, .4)), 'cloak2': (2 * wave(t, 4.0, .35), 0, 0),
                      'uarm.L': (.8 * br, 0, 0)})
        else:
            k.update({'uarm.L': (2 * wave(t, 4.0, .65), 0, 1.5 * br), 'farm.L': (-3 * wave(t, 4.0, .75), 0, 0),
                      'hair1': (1.5 * wave(t, 4.0, .3), 0, 0), 'hair2': (2 * wave(t, 4.0, .4), 0, 0)})
        return k
    return Clip('idle', 4.0, f)


def walk(shadow, T=1.1):
    def f(t):
        s = wave(t, T)
        c2 = math.cos(4 * math.pi * t / T)
        swing = lambda ph: max(0.0, wave(t, T, ph))  # noqa: E731
        k = {
            'hips': dict(r=(0, 5 * s, 2 * s), t=(0, .012 * c2, 0)),
            'thigh.L': (-20 * s - 4, 0, 0),
            'thigh.R': (20 * s - 4, 0, 0),
            'shin.L': (28 * swing(.25) + 4, 0, 0),
            'shin.R': (28 * swing(.75) + 4, 0, 0),
            'foot.L': (8 * s, 0, 0),
            'foot.R': (-8 * s, 0, 0),
            'spine': (2, -3 * s, -1.5 * s),
            'chest': (0, -3 * s, 0),
            'head': (-1 - c2, 3 * s, 1 * s),
            'uarm.R': (-14 * s, 0, 0),
            'farm.R': (-10 - 8 * swing(.0), 0, 0),
        }
        if shadow:
            k.update({'cloak1': (-4 - 3 * c2, -2 * s, 0), 'cloak2': (-5 * c2 - 3, 0, 2 * s), 'uarm.L': (1.5 * c2, 0, 0)})
        else:
            k.update({'uarm.L': (14 * s, 0, 0), 'farm.L': (-10 - 8 * swing(.5), 0, 0),
                      'hair1': (2 + 3 * c2, 0, 0), 'hair2': (3 * c2, 0, 0), 'hair3': (4 * c2, 0, 0)})
        return k
    return Clip('walk', T, f)


def talk(shadow, T=2.4):
    def f(t):
        env = smooth((t - .1) / .35) * (1 - smooth((t - 1.8) / .45))
        beat = wave(t, .6)
        k = {
            'head': (3.5 * beat * (.4 + .6 * env) - 2, 6 * wave(t, 2.4, .1), 3 * wave(t, 1.2) * env),
            'neck': (1.5 * env, 0, 0),
            'chest': (1.5 * env, 2 * env, 0),
            'uarm.R': (-32 * env, 0, -8 * env),
            'farm.R': (-55 * env - 8 * beat * env, 15 * env, 0),
            'hand.R': (0, 0, 20 * env + 10 * beat * env),
        }
        if shadow:
            k['uarm.L'] = (1.5 * beat * env, 0, 0)
        else:
            k.update({'uarm.L': (-6 * env, 0, 3 * env), 'farm.L': (-14 * env, 0, 0)})
        return k
    return Clip('talk', T, f)


def clips(shadow):
    return [idle(shadow), walk(shadow), talk(shadow)]


# ---------------------------------------------------------------------------- main

def embedded_texture(path):
    g = glb.GLB(path)
    buf = io.BytesIO()
    g.image(0).save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def export(out_dir, face_tex=None):
    os.makedirs(out_dir, exist_ok=True)
    res = []
    for shadow, name in ((True, 'shadow'), (False, 'shadow_lady')):
        path = os.path.join(out_dir, name + '.glb')
        if face_tex:
            png, cheek = face_texture(face_tex, lidded=shadow)
        else:
            if not os.path.exists(path):
                raise SystemExit('need --face-tex (the face extractor output) for a first build')
            png = embedded_texture(path)
            from PIL import Image
            a = np.asarray(Image.open(io.BytesIO(png)).convert('RGB')).astype(float) / 255
            cheek = tuple(a[118:146, 26:52].reshape(-1, 3).mean(0))
        pal = dict(SHADOW if shadow else LADY)
        pal['skin'] = q5(cheek)
        pal['neck'] = q5(A(cheek) * .86)
        m = build(shadow)
        m.finish(HEIGHT[shadow])
        flat = m.flatten()
        info = glb.write_glb(path, m, flat, pal, clips(shadow), textures={'face': png},
                             generator='tools/characters/shadow.py')
        glb.write_import(path, [c.name for c in clips(shadow) if c.loop], embed_textures=True)
        lo, hi = m.bbox()
        info.update(path=path, height=float(hi[1] - lo[1]))
        res.append(info)
    return res


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--face-tex', help='face_tex.png from the face extractor (160x228)')
    ap.add_argument('--preview', help='write six-view and animation strips here')
    a = ap.parse_args(argv)
    for info in export(a.out, a.face_tex):
        print('%(path)s: %(triangles)d tris, %(bones)d bones, %(materials)d materials, %(height).3f m' % info)
        assert info['triangles'] <= 6000, 'over the 6k triangle budget'
        if a.preview:
            import glb_preview as gp
            os.makedirs(a.preview, exist_ok=True)
            base = os.path.splitext(os.path.basename(info['path']))[0]
            gp.sheet(info['path'], os.path.join(a.preview, base + '_6view.png'), title=base + '.glb (rest)')
            for c in info['animations']:
                gp.frames(info['path'], os.path.join(a.preview, '%s_%s.png' % (base, c)), c)


if __name__ == '__main__':
    main()
