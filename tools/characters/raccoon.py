"""The raccoon of the new references: a chubby upright raccoon, arms crossed on its chest, grey-beige faceted
fur, a dark bandit mask and a grumpy face, a big tail with dark bands, and a small purple pointed hat with a moon
and stars perched between the ears.

    python tools/characters/raccoon.py --out assets/characters [--preview DIR]

Writes raccoon.glb: one skinned mesh (one surface per palette colour; the game folds the flat ones into one),
0.76 m tall with the hat, feet on y = 0, facing +Z, the origin under the middle of the body (the tail trails
behind it); animations idle, walk, talk, watch.

The proportions were measured on the turnaround sheet (front / side / back, the raccoon half of the user's
reference, which is not in the repository; docs/art/characters_painted.md). The model is authored in the sheet's
own pixels (the whole figure is 235 px tall, hat tip included) and scaled to metres by `Model.finish`.
`Y(r)` turns a fraction of the figure's height into pixels, `Zs(dx)` turns a side-view x offset (from the
sheet's centre line of the side view, the figure faces left) into z, so every number below can be checked
against the sheet.

The skeleton keeps the names of the earlier raccoons (the game's clips and tests address them): `upper_arm /
forearm / hand` are now the crossed arms, `leg / foot` the legs, `tail1..3`, `ear.L/R`, `hat`, `hat_tip`.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb  # noqa: E402
from glb import A, Clip, hring, jitter, loft, q5, smooth, tube, wave  # noqa: E402

HEIGHT = 0.76
H = 235.0          # the figure on the sheet, in sheet pixels (the authoring unit)


def Y(r):
    """Fraction of the figure's height -> y in sheet pixels."""
    return r * H


def Zs(dx):
    """Side-view x offset from the sheet's side centre line (front is -x) -> model z; the origin sits under the body."""
    return -dx - 33.0


_BASE = {
    'fur': (.77, .69, .65),        # grey-beige. The room's key light is gold and its fill purple, so the albedo is
    'fur_d': (.58, .51, .50),      # near-neutral and bright (a warm albedo goes orange); the arms' undersides, ear backs
    'belly': (.90, .83, .78),
    'cream': (.93, .88, .83),      # muzzle, the wedge between the eyes
    'mask': (.40, .30, .30),       # bandit mask
    'ear_in': (.80, .68, .68),
    'nose': (.16, .12, .13),
    'eye': (.96, .93, .88),
    'pupil': (.16, .12, .13),
    'paw': (.46, .35, .33),
    'foot': (.60, .47, .40),
    'tail_d': (.46, .36, .34),     # dark tail bands and the tip
    'tail_l': (.90, .86, .84),
    'hat': (.52, .26, .78),        # blue-heavy: under the gold key a violet albedo would go red
    'hat_d': (.36, .18, .55),      # brim underside
    'star': (.96, .88, .66),
    'moon': (.92, .92, .92),
}
PALETTE = {k: q5(v) for k, v in _BASE.items()}
# three tones of the big surfaces, picked per facet (crumpled paper, subtle: the room's key light does the form)
for _k in ('fur', 'belly', 'hat'):
    for _v, _m in zip('abc', (.90, 1.0, 1.08)):
        PALETTE[_k + _v] = q5(tuple(min(1., c * _m) for c in _BASE[_k]))


def vary(name, c):
    h = abs(math.sin(c[0] * 91.7 + c[1] * 53.3 + c[2] * 37.9) * 43758.5453)
    return name + 'abc'[int(h % 3)]


# ---------------------------------------------------------------------------- skeleton

HIPS_Y, SPINE_Y, CHEST_Y, HEAD_Y = 56.0, 84.0, 112.0, 137.0
HAT_BASE_Y = 196.0

# the crossed arms: shoulder, elbow, wrist (left arm; the right one mirrors x), sheet pixels
SHOULDER = (30.0, 128.0, 3.0)
ELBOW = (33.5, 100.0, 15.0)
WRIST_L = (-10.0, 113.0, 30.0)
WRIST_R = (10.0, 113.0, 33.0)       # the right arm lies over the left one


def skeleton(m):
    m.bone('root', None, (0, 0, 0))
    m.bone('hips', 'root', (0, HIPS_Y, -4))
    m.bone('spine', 'hips', (0, SPINE_Y, -2))
    m.bone('chest', 'spine', (0, CHEST_Y, 0))
    m.bone('head', 'chest', (0, HEAD_Y, -2))
    m.bone('hat', 'head', (0, 188, -6))
    m.bone('hat_tip', 'hat', (0, 222, -4))
    for s, d in ((1, '.L'), (-1, '.R')):
        m.bone('ear' + d, 'head', (s * 27.5, 183, -8))
        m.bone('upper_arm' + d, 'chest', (s * SHOULDER[0], SHOULDER[1], SHOULDER[2]))
        m.bone('forearm' + d, 'upper_arm' + d, (s * ELBOW[0], ELBOW[1], ELBOW[2]))
        w = WRIST_L if s > 0 else WRIST_R
        m.bone('hand' + d, 'forearm' + d, w)
        m.bone('leg' + d, 'hips', (s * 23, 48, -2))
        m.bone('foot' + d, 'leg' + d, (s * 27, 13, 3))
    m.bone('tail1', 'hips', (0, 49, -42))
    m.bone('tail2', 'tail1', (0, 32, -72))
    m.bone('tail3', 'tail2', (0, 25, -98))


# ---------------------------------------------------------------------------- body

# r (fraction of the height), half width, front z, back z: read off the front and side views
TORSO = [(.13, 40, 20, -37), (.20, 47, 33, -43), (.28, 49, 39, -46), (.36, 47, 36, -46),
         (.44, 39, 29, -43), (.51, 38, 23, -38), (.56, 35, 19, -35), (.61, 29, 13, -32)]


def torso(m):
    rings = [hring(Y(r), hw, (zf - zb) / 2, (zf + zb) / 2, N=12, e=2.3) for r, hw, zf, zb in TORSO]
    g = loft(rings, cap=(6, 5))
    g['V'] = jitter(g['V'], 1.0, 1)
    W = m.blend(g['V'][:, 1], [(Y(.14), 'hips'), (Y(.36), 'spine'), (Y(.52), 'chest')])

    def mat(c, n):
        if n[2] > .35 and abs(c[0]) < 36 and Y(.16) < c[1] < Y(.40):
            return vary('belly', c)
        return vary('fur', c)
    m.add(g, mat, W)


def legs(m):
    """Short, thick legs with big flat feet that point forward; the notch between them shows the tail behind."""
    for s, d in ((1, '.L'), (-1, '.R')):
        thigh = glb.blob((s * 23, 30, 2), (16, 27, 18), (0, 1, 0), N=8, k=3)
        thigh['V'] = jitter(thigh['V'], .5, 2)
        W = m.blend(-thigh['V'][:, 1], [(-60, 'hips'), (-40, 'leg' + d), (-8, 'leg' + d)])
        m.add(thigh, lambda c, n: vary('fur', c), W)
        foot = glb.blob((s * 30, 6.5, 3), (14.5, 6.5, 23), (0, 1, 0), N=8, k=2)
        foot['V'] = jitter(foot['V'], .5, 3)
        foot = glb.transform(foot, glb.rot_axis((0, 1, 0), s * 8), piv=(s * 30, 0, 3))
        m.add(foot, lambda c, n: 'foot', 'foot' + d)


def arms(m):
    """Crossed on the chest: upper arms hang from the shoulders to the elbows, the forearms cross in front of the
    chest, each paw tucked over the opposite arm."""
    for s, d in ((1, '.L'), (-1, '.R')):
        sh = A((s * SHOULDER[0], SHOULDER[1], SHOULDER[2]))
        el = A((s * ELBOW[0], ELBOW[1], ELBOW[2]))
        w = WRIST_L if s > 0 else WRIST_R
        wr = A(w)
        ua = tube([sh, (sh + el) / 2 + A((s * 1.5, 0, 2.5)), el], [12, 12, 11.5], N=7, cap=(6, 0), up=(0, 0, 1))
        ua['V'] = jitter(ua['V'], .8, 4)
        t = ((ua['V'] - sh) @ (el - sh)) / float((el - sh) @ (el - sh))
        W = m.blend(-t, [(0.0, 'forearm' + d), (-.75, 'upper_arm' + d), (-1.0, 'upper_arm' + d), (-1.2, 'chest')])
        m.add(ua, lambda c, n: 'fur_d' if n[1] < -.5 else vary('fur', c), W)
        elbow = glb.blob(el, (11.5, 11.5, 11.5), (0, 1, 0), N=7, k=2)
        elbow['V'] = jitter(elbow['V'], .7, 5)
        m.add(elbow, lambda c, n: vary('fur', c), 'forearm' + d)
        fa = tube([el, (el + wr) / 2 + A((0, 1.5, 3)), wr], [12, 11, 9.5], N=7, cap=(0, 4), up=(0, 0, 1))
        fa['V'] = jitter(fa['V'], .7, 6)
        m.add(fa, lambda c, n: 'fur_d' if n[1] < -.45 else vary('fur', c), 'forearm' + d)
        paw = glb.blob(wr + A((-s * 4, 3.5, 1)), (8.5, 4.5, 6.5), (0, 1, 0), N=7, k=2)
        paw['V'] = jitter(paw['V'], .6, 7)
        m.add(paw, lambda c, n: 'paw', 'hand' + d)


# The tail sweeps out to one side and rises at the end, fat and ringed like the sheet's. TAIL_SIDE +1 is the raccoon's
# left (screen-left from behind, which is how the painted room sees him); -1 puts it on his right.
TAIL_SIDE = -1
# x (out to the side), height as a fraction of the figure, z (back); the rings' radii thin toward the tip
TAIL_PATH = [(0, .205, -44), (11, .194, -52), (26, .186, -58), (42, .189, -61), (56, .200, -59), (69, .217, -54),
             (80, .238, -48), (89, .262, -42)]
TAIL_RAD = [19, 27, 29, 29, 28, 27, 24, 17]


def tail(m):
    """Fat, out to the side and curling up: dark root, then cream and dark bands, a dark tip. Its rings are low-poly
    (8 sides, a ridge on top), which from behind makes the stacked chevrons of the sheet."""
    path = A([(TAIL_SIDE * x, Y(r), z) for x, r, z in TAIL_PATH])
    g = tube(path, TAIL_RAD, N=8, ratio=.73, cap=(0, 7))
    g['V'] = jitter(g['V'], .5, 8)
    bands = ['tail_d', 'tail_l', 'tail_d', 'tail_l', 'tail_d', 'tail_l', 'tail_d', 'tail_d']
    # skin by how far out from the body's centre line it reaches (it used to trail straight back: the same number)
    reach = np.hypot(g['V'][:, 0], g['V'][:, 2])
    W = m.blend(reach, [(38, 'hips'), (50, 'tail1'), (76, 'tail2'), (102, 'tail3')])
    m.add(g, bands, W)


# ---------------------------------------------------------------------------- head

# r, half width, half depth, centre z: a hexagon in front view (wide cheeks, narrow chin and brow)
HEAD = [(.585, 30, 26, -1), (.62, 41, 32, -2.5), (.66, 48, 34, -4.5), (.70, 42, 34.5, -3.5), (.75, 35, 33, -2),
        (.795, 28, 23, -6)]
HEAD_ZC = -3.0     # the head's vertical axis, for polar decals
NOSE = (0.0, 155.0, 45.0)


def polar(a_deg, y):
    """Polar decal coordinates (degrees from the front, y) -> ray from the head axis."""
    a = math.radians(a_deg)
    return (0, y, HEAD_ZC), (math.sin(a), 0, math.cos(a))


def head(m):
    g = loft([hring(Y(r), hw, rz, cz, N=12, e=2.5) for r, hw, rz, cz in HEAD], cap=(3, 4))
    g['V'] = jitter(g['V'], .8, 9)

    def hm(c, n):
        x, y, z = abs(c[0]), c[1], c[2]
        return vary('fur', c)
    m.add(g, hm, 'head')
    skull = glb.Surface([g])

    def zr(z, rx, ry, y):
        return glb.ring((0, y, z), (rx, 0, 0), (0, ry, 0), 10, 2.3)
    sn = loft([zr(22, 19, 14, 148), zr(36, 14, 11, 149.5), zr(44, 9, 8.5, 150.5)], cap=(0, 2))
    sn['V'] = jitter(sn['V'], .6, 10)
    m.add(sn, 'cream', 'head')
    snout = glb.Surface([sn])
    nose = glb.blob(NOSE, (6.5, 4.5, 4.5), (0, 1, .3), N=6, k=2)
    m.add(nose, 'nose', 'head')

    def front(u, v):
        return (u, v, 0), (0, 0, 1)
    axp = A([(0, 165.0, HEAD_ZC)])
    # the pale wedge between the mask lobes, down to the muzzle
    P = [(-4, 176), (4, 176), (21, 146), (24, 138), (-24, 138), (-21, 146)]
    P, F = glb.fan2d(P)
    m.add(dict(V=skull.project(P, front, .5), F=A(F), ax=axp), 'cream', 'head')
    # frown under the nose
    P, F = glb.stroke2d([(-6, 141.5), (-3, 143.2), (3, 143.2), (6, 141.5)], 1.6)
    m.add(dict(V=snout.project(P, front, .5), F=A(F), ax=A([(0, 148, 36)])), 'nose', 'head')

    for side in (1, -1):
        # the mask lobe: inner top, outer top, cheek tip, inner bottom (degrees from the front, height)
        IT, OT, TIP, IB = (7, Y(.735)), (46, Y(.742)), (82, Y(.648)), (34, Y(.618))

        def lobe(s, k, side=side):
            lo = (IB[0] + (TIP[0] - IB[0]) * s, IB[1] + (TIP[1] - IB[1]) * s)
            hi = (IT[0] + (OT[0] - IT[0]) * s, IT[1] + (OT[1] - IT[1]) * s)
            return (side * (lo[0] + (hi[0] - lo[0]) * k), lo[1] + (hi[1] - lo[1]) * k)
        P, F = glb.grid2d(lobe, 24, 5)    # fine enough that no triangle bridges a ridge of the 12-sided skull
        V = []
        for a, y in P:
            o, d = polar(a, y)
            p, n = skull.cast(o, d)
            V.append(p + n * 1.3)
        m.add(dict(V=A(V), F=A(F), ax=axp), 'mask', 'head')
        # half-lidded eye: a pale lens under a flat dark lid, lower toward the nose (grumpy)
        cx, cy = side * 16.0, Y(.706)

        def lid(a):
            return .5 - .28 * a / 5.0
        lens = [(-5, lid(-5)), (-3, -1.9), (0, -2.5), (3, -1.9), (5, lid(5)), (3, lid(3)), (0, lid(0)), (-3, lid(-3))]
        P, F = glb.fan2d([(cx + side * a, cy + b) for a, b in lens])
        m.add(dict(V=skull.project(P, front, 1.4), F=A(F), ax=axp), 'eye', 'head')
        P, F = glb.stroke2d([(cx + side * a, cy + lid(a) + .2) for a in (-5.5, -2.5, 0, 2.5, 5.5)], 1.4)
        m.add(dict(V=skull.project(P, front, 1.9), F=A(F), ax=axp), 'pupil', 'head')

    # ears: small and upright at the top corners, pale pink inside
    for side in (1, -1):
        d = '.L' if side > 0 else '.R'
        e0 = m.head('ear' + d)
        tip = e0 + A((side * 2.5, 20.0, 0))
        mid = e0 * .5 + tip * .5 + A((side * .5, 0, 0))
        rows = [glb.ring(e0, (10.5, 0, 0), (0, 0, 6), 6, 2), glb.ring(mid, (8.0, 0, 0), (0, 0, 4.6), 6, 2)]
        eg = loft(rows, cap=(0, 10.5))
        eg['V'] = jitter(eg['V'], .5, 11)
        m.add(eg, lambda c, n: 'ear_in' if n[2] > .35 else vary('fur', c), 'ear' + d)


# ---------------------------------------------------------------------------- hat

# a straight pointed cone, upright (z, y, radius)
HAT_PATH = [(-4, HAT_BASE_Y, 15), (-4, 206, 12.5), (-4, 217, 9), (-4, 228, 5), (-4, 239, .7)]


def crescent(cx, cy, R, r_in, off, n=9, a0=40, a1=320):
    """A crescent (outer circle R, inner circle r_in shifted by off in x) as a strip of quads between two arcs."""
    O, I = [], []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        O.append((cx + R * math.cos(a), cy + R * math.sin(a)))
        # the inner arc: the point of the inner circle on the same ray, clamped so the horns meet
        ix, iy = off + r_in * math.cos(a), r_in * math.sin(a)
        I.append((cx + ix, cy + iy))
    P = O + I
    F = []
    for k in range(n):
        F += [(k, k + 1, n + 1 + k + 1), (k, n + 1 + k + 1, n + 1 + k)]
    return P, F


def hat(m):
    path = A([(0, y, z) for z, y, _ in HAT_PATH])
    rad = [r for _, _, r in HAT_PATH]
    cone = tube(path, rad, N=8, cap=(0, 1.5), up=(1, 0, 0))
    cone['V'] = jitter(cone['V'], .6, 12)
    W = m.blend(cone['V'][:, 1], [(214, 'hat'), (226, 'hat_tip')])
    m.add(cone, lambda c, n: vary('hat', c), W)
    # brim: thin, wide, level, drooping a little at the edge
    bz = -4.0
    brim = loft([glb.ring((0, 197.0, bz), (14, 0, 0), (0, 0, 14), 10), glb.ring((0, 193.5, bz), (19.5, 0, 0), (0, 0, 19.5), 10),
                 glb.ring((0, 191.0, bz), (22, 0, 0), (0, 0, 22), 10), glb.ring((0, 189.0, bz), (15, 0, 0), (0, 0, 15), 10)],
                cap=(1, 1))
    brim['V'] = jitter(brim['V'], .5, 13)
    brim = glb.transform(brim, glb.rot_axis((1, 0, 0), -1.5), piv=(0, 191.0, bz))
    m.add(brim, lambda c, n: 'hat_d' if n[1] < -.2 else vary('hat', c), 'hat')

    # a crescent moon and stars on the cone (the lower, straight part), front and back
    surf = glb.Surface([cone])

    def axis_z(y):
        return float(np.interp(y, path[:, 1], path[:, 2]))

    def cone_map(th):
        def mp(u, v):
            a = th + u / 11.0
            return (0, v, axis_z(v)), (math.sin(a), 0, math.cos(a))
        return mp
    P, F = crescent(-.5, 207.0, 5.8, 5.0, 2.2)
    V = surf.project(P, cone_map(0.0), .5)
    m.add(dict(V=V, F=A(F), ax=A([(0, 207, axis_z(207))])), 'moon', 'hat')
    for th, y, r in ((.95, 213.5, 2.6), (-.85, 201.5, 2.3), (.5, 201.0, 2.0), (3.3, 209.0, 2.8), (2.5, 203.5, 2.3),
                     (4.1, 212.5, 2.1), (-1.5, 212.0, 2.2)):
        P = [(0, y)] + [((r if j % 2 == 0 else r * .42) * math.cos(j * math.pi / 4),
                         y + (r if j % 2 == 0 else r * .42) * math.sin(j * math.pi / 4)) for j in range(8)]
        F = [(0, 1 + j, 1 + (j + 1) % 8) for j in range(8)]
        V = surf.project(P, cone_map(th), .5)
        m.add(dict(V=V, F=A(F), ax=A([(0, y, axis_z(y))])), 'star', 'hat')


def build():
    m = glb.Model('Raccoon')
    skeleton(m)
    torso(m)
    legs(m)
    arms(m)
    tail(m)
    head(m)
    hat(m)
    m.finish(HEIGHT)
    return m


# ---------------------------------------------------------------------------- animation
# Rotations are degrees about the rest-pose world axes (x: pitch, + swings a hanging limb backwards and puts a
# forward-pointing foot toe-down; y: yaw, + turns toward +X, the raccoon's left; z: roll). Translations are in
# sheet pixels. The crossed arms ride on the chest, so they move with the body for free.

def idle(t):
    br = wave(t, 4.0)
    br2 = wave(t, 2.0, .2)
    twitch = math.exp(-((t - 2.7) / .07) ** 2)
    return {
        'hips': dict(r=(.3 * br, 0, 0), t=(0, .5 * br2, 0)),
        'spine': (.8 * br, 0, 0),
        'chest': (1.0 * br2, 0, .5 * wave(t, 4.0, .3)),
        'upper_arm.L': (.8 * br, 0, 0),
        'upper_arm.R': (.8 * br, 0, 0),
        'head': (-1.0 * br + 1.2 * wave(t, 4.0, .5), 4 * wave(t, 4.0, .1), 1.2 * wave(t, 4.0, .35)),
        'ear.L': (0, 0, -14 * twitch),
        'ear.R': (0, 0, 2 * br2),
        'tail1': (0, 5 * wave(t, 4.0), 0),
        'tail2': (1.5 * wave(t, 2.0), 7 * wave(t, 4.0, .12), 0),
        'tail3': (2.5 * wave(t, 2.0, .1), 10 * wave(t, 4.0, .24), 0),
        'hat_tip': (2.5 * wave(t, 4.0, .25), 0, 3 * wave(t, 4.0, .4)),
    }


def walk(t, T=0.7):
    """In place: an upright waddle, hips rolling and yawing, the tail swinging against them, the hat tip lagging."""
    s = wave(t, T)
    c1 = math.cos(2 * math.pi * t / T)
    c2 = math.cos(4 * math.pi * t / T)
    lift_l = max(0.0, -c1) ** 1.5
    lift_r = max(0.0, c1) ** 1.5
    return {
        'hips': dict(r=(0, 6 * s, 4 * s), t=(0, 1.4 * c2, 0)),
        'spine': (1.5 + .8 * c2, -4 * s, -2.5 * s),
        'chest': (0, -4 * s, -2 * s),
        'head': (-1.5 - 1.5 * c2, 4 * s, 2 * s),
        'leg.L': (24 * s, 0, 0),
        'leg.R': (-24 * s, 0, 0),
        'foot.L': dict(r=(-10 * s + 14 * lift_l, 0, 0), t=(0, 4.5 * lift_l, 0)),
        'foot.R': dict(r=(10 * s + 14 * lift_r, 0, 0), t=(0, 4.5 * lift_r, 0)),
        'tail1': (2 * c2, -12 * s, 0),
        'tail2': (0, -10 * wave(t, T, .1), 0),
        'tail3': (0, -12 * wave(t, T, .2), 0),
        'hat_tip': (-5 * c2, 0, 7 * wave(t, T, .15)),
        'ear.L': (0, 0, -3 * c2),
        'ear.R': (0, 0, 3 * c2),
    }


def talk(t, T=2.4):
    """Head beats, and the left forearm lifts off the chest in a 'now listen' gesture while the right stays crossed."""
    env = smooth((t - .15) / .35) * (1 - smooth((t - 1.75) / .45))
    beat = wave(t, .6)
    beat2 = wave(t, .4, .1)
    return {
        'head': (4 * beat * (.4 + .6 * env) - 2 * env, 5 * wave(t, 2.4, .1), 4 * wave(t, 1.2) * env),
        'chest': (2 * env, 3 * env, 0),
        'spine': (1.5 * beat2 * env, 0, 0),
        'upper_arm.L': (-14 * env, 0, 4 * env),
        'forearm.L': (0, 28 * env, -62 * env + 6 * env * beat2),
        'hand.L': (-10 * env + 8 * beat * env, 0, -10 * env),
        'hat_tip': (3 * beat, 0, 3 * beat2),
        'ear.L': (0, 0, -4 * env),
        'ear.R': (0, 0, 4 * env),
        'tail2': (0, 5 * wave(t, 2.4), 0),
    }


def watch(t, T=4.0):
    """Turns its head to its left (+X) to keep an eye on something, holds, turns back."""
    k = smooth(t / .55) * (1 - smooth((t - 3.2) / .7))
    sus = math.exp(-((t - 1.9) / .12) ** 2)
    return {
        'head': (-4 * k + 3 * sus, 50 * k, 7 * k),
        'chest': (0, 12 * k, 0),
        'spine': (0, 5 * k, 0),
        'ear.L': (0, 0, -10 * k),
        'ear.R': (0, 0, 6 * k),
        'tail2': (0, -8 * k, 0),
        'tail3': (0, -6 * k, 0),
        'hat_tip': (0, 0, -6 * k),
    }


def clips():
    return [Clip('idle', 4.0, idle), Clip('walk', 0.7, walk), Clip('talk', 2.4, talk), Clip('watch', 4.0, watch)]


# ---------------------------------------------------------------------------- main

def export(out_dir):
    m = build()
    flat = m.flatten()
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, 'raccoon.glb')
    info = glb.write_glb(path, m, flat, PALETTE, clips(), generator='tools/characters/raccoon.py')
    glb.write_import(path, [c.name for c in clips() if c.loop])
    lo, hi = m.bbox()
    info.update(path=path, height=float(hi[1] - lo[1]), size=(hi - lo).round(3).tolist(), scale=m.scale)
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--preview', help='write six-view and animation strips here')
    a = ap.parse_args(argv)
    info = export(a.out)
    print('raccoon: %(triangles)d tris, %(bones)d bones, %(materials)d materials, %(height).3f m (scale %(scale).4f) -> %(path)s' % info)
    assert info['triangles'] <= 3000, 'over the 3k triangle budget'
    if a.preview:
        import glb_preview as gp
        os.makedirs(a.preview, exist_ok=True)
        gp.sheet(info['path'], os.path.join(a.preview, 'raccoon_6view.png'), title='raccoon.glb (rest)')
        for c in clips():
            gp.frames(info['path'], os.path.join(a.preview, 'raccoon_%s.png' % c.name), c.name)


if __name__ == '__main__':
    main()
