"""The raccoon wizard (concept sheet, top right): grumpy, arms crossed, purple hat.

    python tools/characters/raccoon.py --out assets/characters [--preview DIR]

Writes raccoon.glb: one skinned mesh (one surface per palette colour), 0.70 m tall with
the hat, feet on y = 0, facing +Z; animations idle, walk, talk, watch.

Ported from the user's procedural model (numpy -> glTF). What changed against the sheet is
written up in docs/art/characters_raccoon_shadow.md; the short version: narrower head and
body (the source was ~30% too wide), arms modelled crossed in the bind pose, a two-lobed
bandit mask that sweeps down to pointed cheeks, half-lidded grumpy eyes, a crooked hat, and
a banded tail lying behind on the floor instead of out to one side.

Authoring units: the source's, about 3.1 units tall; finish() scales to metres.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb  # noqa: E402
from glb import A, Clip, catmull, hring, jitter, loft, nz, q5, smooth, tube, wave  # noqa: E402

HEIGHT = 0.70

PALETTE = {k: q5(v) for k, v in {
    'fur': (.66, .58, .55),       # warm grey-taupe, sits in an olive/ochre room
    'fur_d': (.52, .44, .41),     # paws, feet, the back of the ears
    'belly': (.76, .69, .65),
    'cream': (.86, .80, .74),     # muzzle, brows, lids, light tail bands
    'mask': (.31, .25, .23),      # bandit mask, dark tail bands
    'ear_in': (.46, .36, .35),
    'nose': (.11, .09, .09),
    'eye': (.90, .86, .74),
    'pupil': (.06, .05, .06),
    'hat': (.42, .24, .53),
    'hat_d': (.30, .16, .40),     # brim underside and band
    'star': (.93, .78, .76),
}.items()}


# ---------------------------------------------------------------------------- skeleton

def skeleton(m):
    m.bone('root', None, (0, 0, 0))
    m.bone('hips', 'root', (0, .62, 0))
    m.bone('spine', 'hips', (0, 1.05, 0))
    m.bone('chest', 'spine', (0, 1.38, 0))
    m.bone('head', 'chest', (0, 1.68, .04))
    m.bone('hat', 'head', (0, 2.47, -.04))
    m.bone('hat_tip', 'hat', (0, 2.82, -.19))
    for s, d in ((1, '.L'), (-1, '.R')):
        m.bone('ear' + d, 'head', (s * .44, 2.31, -.03))
        top = s > 0  # the left forearm lies over the right one
        m.bone('upper_arm' + d, 'chest', (s * .40, 1.56, -.02))
        m.bone('forearm' + d, 'upper_arm' + d, (s * .46, 1.30 - (0 if top else .02), .12 - (0 if top else .01)))
        m.bone('hand' + d, 'forearm' + d, (-s * .40, 1.44 - (0 if top else .04), .30 - (0 if top else .05)))
        m.bone('leg' + d, 'hips', (s * .27, .55, .03))
        m.bone('foot' + d, 'leg' + d, (s * .28, .12, .06))
    m.bone('tail1', 'hips', (0, .78, -.40))
    m.bone('tail2', 'tail1', (0, .48, -.95))
    m.bone('tail3', 'tail2', (0, .33, -1.40))


# ---------------------------------------------------------------------------- body

def body(m):
    R = [(0.30, .44, .40, -.05), (0.42, .57, .52, -.05), (0.60, .635, .59, -.06), (0.84, .645, .62, -.06),
         (1.10, .62, .59, -.09), (1.35, .58, .52, -.12), (1.55, .50, .48, -.12), (1.70, .38, .40, -.08),
         (1.80, .20, .24, -.04)]
    g = loft([hring(y, rx, rz, cz, N=12, e=2.2) for y, rx, rz, cz in R], cap=(.08, .04))
    g['V'] = jitter(g['V'], .018)
    V = g['V']
    W = m.blend(V[:, 1], [(.55, 'hips'), (.95, 'spine'), (1.30, 'spine'), (1.55, 'chest')])
    # the lower body follows the legs (stubby legs live inside the pear)
    a = smooth((.62 - V[:, 1]) / .42) * np.clip(np.abs(V[:, 0]) / .22, 0, 1) * .85
    leg = np.where(V[:, 0] >= 0, m.ix['leg.L'], m.ix['leg.R'])
    W *= (1 - a)[:, None]
    W[np.arange(len(V)), leg] += a

    def mat(c, n):
        if n[2] > .35 and abs(c[0]) < .40 and .22 < c[1] < 1.22:
            return 'belly'
        return 'fur'
    m.add(g, mat, W)


def legs(m):
    for s, d in ((1, '.L'), (-1, '.R')):
        shin = tube([(s * .25, .52, .0), (s * .27, .30, .03), (s * .28, .10, .05)], [.16, .15, .125], N=8,
                    cap=(.0, .02))
        shin['V'] = jitter(shin['V'], .008, 1)
        m.add(shin, 'fur', m.blend(shin['V'][:, 1], [(.14, 'foot' + d), (.26, 'leg' + d)]))
        rows = [(-.10, .12, .075, .08), (.04, .16, .095, .09), (.20, .15, .085, .08), (.33, .11, .055, .055)]
        ft = loft([glb.ring((s * .28, cy, .06 + z), (rx, 0, 0), (0, ry, 0), 8, 2.4) for z, rx, ry, cy in rows],
                  cap=(.03, .05))
        ft['V'] = jitter(ft['V'], .008, 2)
        glb.transform(ft, glb.rot_axis((0, 1, 0), s * 12), piv=(s * .28, 0, .06))
        m.add(ft, 'fur_d', 'foot' + d)


def arms(m):
    """Crossed in the bind pose, left forearm over the right, paws tucked at the far arm."""
    for s, d in ((1, '.L'), (-1, '.R')):
        sh, el = m.head('upper_arm' + d), m.head('forearm' + d)
        up = tube([sh + (s * -.04, .04, 0), sh, (sh + el) / 2 + (s * .03, 0, 0), el],
                  [.13, .155, .145, .13], N=8, cap=(.02, .02))
        up['V'] = jitter(up['V'], .008, 3)
        t = np.clip(((up['V'] - sh) @ nz(el - sh)) / np.linalg.norm(el - sh), 0, 1)
        m.add(up, 'fur', m.blend(t, [(0.0, 'chest'), (.25, 'upper_arm' + d), (.85, 'upper_arm' + d), (1.1, 'forearm' + d)]))
        top = s > 0  # the left forearm lies on top (further forward)
        dz = 0 if top else -.05
        dy = 0 if top else -.04
        ctrl = [el, (s * .36, 1.34 + dy, .36 + dz), (s * .10, 1.38 + dy, .46 + dz), (-s * .20, 1.42 + dy, .44 + dz),
                m.head('hand' + d)]
        path = catmull(ctrl, 2)
        fa = tube(path, [.13, .125, .12, .115, .11], N=8, cap=(.02, .03))
        fa['V'] = jitter(fa['V'], .008, 4)
        L = np.cumsum([0] + [np.linalg.norm(path[i + 1] - path[i]) for i in range(len(path) - 1)])
        # arc-length parameter for each vertex: nearest path sample
        idx = np.argmin(((fa['V'][:, None, :] - path[None]) ** 2).sum(2), 1)
        tt = L[idx] / L[-1]
        m.add(fa, 'fur', m.blend(tt, [(0.0, 'upper_arm' + d), (.12, 'forearm' + d), (.80, 'forearm' + d), (.98, 'hand' + d)]))
        wr = m.head('hand' + d)
        paw_c = wr + A((-s * .09, .0, -.10))
        paw = glb.blob(paw_c, (.095, .085, .11), nz(paw_c - wr) * A((1, .2, 1)), N=7, k=2)
        paw['V'] = jitter(paw['V'], .006, 5)
        m.add(paw, 'fur_d', 'hand' + d)
        # three blunt fingers curling over the far upper arm (only the top paw shows them)
        if top:
            for k in (-1, 0, 1):
                a0 = paw_c + A((-s * .03, .05 * k, -.02))
                a1 = a0 + A((-s * .06, .01 * k, -.07))
                m.add(tube([a0, a1], [.035, .028], N=5, cap=(.005, .015)), 'fur_d', 'hand' + d)


def tail(m):
    ctrl = [(0, .80, -.44), (0, .52, -.74), (0, .35, -1.02), (0, .30, -1.30), (0, .29, -1.56), (0, .31, -1.78)]
    path = catmull(ctrl, 2)
    r = [.17, .24, .28, .295, .29, .27, .24, .20, .155, .105, .065]
    g = tube(path, r, N=8, cap=(.03, .08), up=(1, 0, 0))
    g['V'] = jitter(g['V'], .012, 6)
    nring = len(path)
    # bands: light at the root, dark tip; one band per ring segment
    bands = ['fur', 'mask', 'cream', 'mask', 'cream', 'mask', 'cream', 'mask', 'cream', 'mask', 'mask']
    mats = [bands[min(k, len(bands) - 1)] for k in range(nring)]
    rid = np.arange(nring)
    W = m.blend(np.concatenate([np.repeat(rid, 8), [0, nring - 1]]).astype(float),
                [(0, 'hips'), (1.2, 'tail1'), (3.8, 'tail2'), (6.5, 'tail3')])
    m.add(g, mats, W)


# ---------------------------------------------------------------------------- head

HEAD_R = [(1.66, .30, .32, .05), (1.76, .47, .43, .06), (1.90, .55, .48, .04), (2.04, .56, .48, .02),
          (2.18, .53, .47, .0), (2.31, .47, .43, -.02), (2.42, .35, .34, -.04)]
HEAD_ZC = .04      # head axis for cylindrical decal projection
HEAD_R0 = .52      # nominal radius: decal u is arc length at this radius


def head_map(u, v):
    a = u / HEAD_R0
    return (0, v, HEAD_ZC), (math.sin(a), 0, math.cos(a))


def mask_lobe(s, k, side):
    """Left lobe in (u, v): s 0..1 from the nose bridge out to the cheek point, k 0..1 up.
    The band sweeps down and out to a point at the cheek (the sheet's grumpy bandit)."""
    u = .12 + .64 * s
    yb = 1.985 - .115 * s ** 1.15
    yt = 2.235 - .07 * s - .10 * s ** 3
    # round the inner end
    inset = .035 * (1 - smooth(s / .18))
    yb += inset
    yt -= inset * .6
    return (side * u, yb + (yt - yb) * k)


EYE_U, EYE_V = .33, 2.125


def head(m):
    g = loft([hring(y, rx, rz, cz, N=12, e=2.5) for y, rx, rz, cz in HEAD_R], cap=(.05, .05))
    # cheek tufts: the sides of the jaw rings flare to points (the sheet's hexagonal face)
    for ring_i, f, dy in ((1, 1.06, -.02), (2, 1.17, -.03), (3, 1.05, .0)):
        for k in (3, 9):
            g['V'][ring_i * 12 + k, 0] *= f
            g['V'][ring_i * 12 + k, 1] += dy
    g['V'] = jitter(g['V'], .014, 7)

    def hm(c, n):
        x, y, z = abs(c[0]), c[1], c[2]
        if z > .25 and n[2] > .25 and y < 1.96 and x < .42:
            return 'cream'          # lower face / chin
        return 'fur'
    m.add(g, hm, 'head')
    surf = glb.Surface([g])

    # muzzle: short and broad, light, the nose a dark wedge on its tip
    def rz_(z, rx, ry, y):
        return glb.ring((0, y, z), (rx, 0, 0), (0, ry, 0), 10, 2.3)
    sn = loft([rz_(.34, .26, .165, 1.88), rz_(.50, .22, .14, 1.875), rz_(.61, .155, .10, 1.88)], cap=(.04, .05))
    sn['V'] = jitter(sn['V'], .006, 8)
    m.add(sn, 'cream', 'head')
    snout = glb.Surface([sn])
    nose = glb.blob((0, 1.945, .655), (.088, .054, .06), (0, 1, .35), N=6, k=2)
    nose['V'][:, 1] = np.where(nose['V'][:, 1] < 1.94, nose['V'][:, 1] - .012 * (1 - np.abs(nose['V'][:, 0]) / .085), nose['V'][:, 1])
    m.add(nose, 'nose', 'head')

    def front(u, v):
        return (u, v, .30), (0, 0, 1)
    # frown + philtrum, on the muzzle front
    P, F = glb.stroke2d([(-.10, 1.805), (-.05, 1.835), (0, 1.845), (.05, 1.835), (.10, 1.805)], .022)
    m.add(dict(V=snout.project(P, front, .006), F=A(F), ax=A([(0, 1.86, .4)])), 'nose', 'head')
    P, F = glb.stroke2d([(0, 1.90), (0, 1.845)], .02)
    m.add(dict(V=snout.project(P, front, .006), F=A(F), ax=A([(0, 1.86, .4)])), 'nose', 'head')

    ax = A([(0, 2.0, HEAD_ZC)])
    for side in (1, -1):
        # mask lobe
        P, F = glb.grid2d(lambda s, k: mask_lobe(s, k, side), 9, 4)
        m.add(dict(V=surf.project(P, head_map, .014), F=A(F), ax=ax), 'mask', 'head')
        # light brow above it
        P, F = glb.grid2d(lambda s, k: (side * (.13 + .52 * s),
                                        mask_lobe(min(s * .52 / .64, 1), 1, side)[1] - .005 + (.075 - .03 * s) * k), 6, 2)
        m.add(dict(V=surf.project(P, head_map, .012), F=A(F), ax=ax), 'cream', 'head')
        # half-lidded eye: cream almond under a heavy flat lid, big pupil, dark lid line
        def lid_v(a):  # lid line: flat, lower toward the nose (grumpy)
            return .006 + .07 * a
        cu = side * EYE_U

        def E(a, b):  # a: outward from the nose, b: up
            return (cu + side * a, EYE_V + b)
        alm = [(-.09, lid_v(-.09)), (-.05, -.022), (0, -.040), (.05, -.034), (.088, -.010), (.09, lid_v(.09))]
        alm += [(a, lid_v(a)) for a in (.05, 0, -.05)]
        P, F = glb.fan2d([E(a, b) for a, b in alm])
        m.add(dict(V=surf.project(P, head_map, .022), F=A(F), ax=ax), 'eye', 'head')
        pup = [(-.04, lid_v(-.04)), (-.042, -.012), (-.02, -.036), (.012, -.036), (.032, -.014), (.032, lid_v(.032))]
        P, F = glb.fan2d([E(a - .004, b) for a, b in pup])
        m.add(dict(V=surf.project(P, head_map, .028), F=A(F), ax=ax), 'pupil', 'head')
        P, F = glb.stroke2d([E(a, lid_v(a)) for a in (-.10, -.05, 0, .05, .10)], .024)
        m.add(dict(V=surf.project(P, head_map, .032), F=A(F), ax=ax), 'pupil', 'head')
        lid = [(a, lid_v(a) + .012) for a in (-.095, -.05, 0, .05, .095)]
        lid += [(.085, lid_v(.085) + .045), (0, .060), (-.08, lid_v(-.08) + .05)]
        P, F = glb.fan2d([E(a, b) for a, b in lid])
        m.add(dict(V=surf.project(P, head_map, .030), F=A(F), ax=ax), 'cream', 'head')

        # ears: upright triangles at the top corners, darker inside
        d = '.L' if side > 0 else '.R'
        e0 = m.head('ear' + d)
        tip = e0 + A((side * .10, .32, -.02))
        for inner in (False, True):
            r0, r1 = (.145, .085) if not inner else (.095, .055)
            zoff = 0 if not inner else .055
            rows = [glb.ring(e0 + A((0, -.02, zoff)), (r0, 0, 0), (0, 0, r0 * .45), 6, 2),
                    glb.ring(e0 * .5 + tip * .5 + A((0, 0, zoff * .8)), (r1, 0, 0), (0, 0, r1 * .45), 6, 2)]
            eg = loft(rows, cap=(.0, float(np.linalg.norm(tip - e0)) * .5 - (.03 if inner else 0)))
            eg['V'] = jitter(eg['V'], .005, 9)
            m.add(eg, 'ear_in' if inner else (lambda c, n: 'fur_d' if n[2] < -.3 else 'fur'), 'ear' + d)


def hat(m):
    """Small cone, narrow brim, the top third bent backwards (crooked), pale stars."""
    path = catmull([(0, 2.47, -.04), (0, 2.63, -.08), (0, 2.77, -.15), (0, 2.85, -.25), (0, 2.90, -.36),
                    (0, 2.99, -.44)], 1)
    cone = tube(path, [.205, .16, .12, .085, .06, .042], N=10, cap=(.0, .07), up=(1, 0, 0))
    cone['V'] = jitter(cone['V'], .006, 10)
    W = m.blend(cone['V'][:, 1] - cone['V'][:, 2], [(2.80, 'hat'), (3.0, 'hat_tip')])
    m.add(cone, lambda c, n: 'hat_d' if c[1] < 2.50 else 'hat', W)
    brim = loft([glb.ring((0, y, -.04), (r, 0, 0), (0, 0, r), 12) for y, r in
                 ((2.485, .21), (2.47, .31), (2.445, .32), (2.43, .20))], cap=(.02, .02))
    m.add(brim, lambda c, n: 'hat' if n[1] > 0 else 'hat_d', 'hat')
    # pale stars and dots on a spiral
    surf = glb.Surface([cone])
    for i in range(7):
        y = 2.55 + .055 * i
        th = 1.0 + i * 2.35
        if y > 2.80:
            continue

        def mp(u, v, th=th):
            return (0, v, float(np.interp(v, path[:, 1], path[:, 2]))), (math.sin(th + u / .12), 0, math.cos(th + u / .12))
        r = .028 - .002 * i
        if i % 3 == 1:  # crescent
            pts = [(r * math.cos(a), y + r * math.sin(a)) for a in np.linspace(.5, 2 * math.pi - .5, 6)]
            pts += [(.45 * r + .6 * r * math.cos(a), y + .6 * r * math.sin(a)) for a in np.linspace(2 * math.pi - .9, .9, 5)]
            F = [(k, k + 1, 11 - k - 1) for k in range(5)] + [(k + 1, 11 - k - 2, 11 - k - 1) for k in range(4)]
            P = pts
        else:          # four-point star
            P = [(0, y)] + [((r if j % 2 == 0 else r * .4) * math.cos(j * math.pi / 4),
                             y + (r if j % 2 == 0 else r * .4) * math.sin(j * math.pi / 4)) for j in range(8)]
            F = [(0, 1 + j, 1 + (j + 1) % 8) for j in range(8)]
        V = surf.project(P, mp, .010)
        m.add(dict(V=V, F=A(F), ax=A([(0, y, -.03)])), 'star', m.blend(V[:, 1] - V[:, 2], [(2.80, 'hat'), (3.0, 'hat_tip')]))


def build():
    m = glb.Model('Raccoon')
    skeleton(m)
    body(m)
    legs(m)
    arms(m)
    tail(m)
    head(m)
    hat(m)
    m.finish(HEIGHT)
    return m


# ---------------------------------------------------------------------------- animation

def idle(t):
    br = wave(t, 4.0)            # one slow breath per loop
    br2 = wave(t, 2.0, .2)
    twitch = math.exp(-((t - 2.7) / .07) ** 2)
    return {
        'spine': (1.2 * br, 0, 0),
        'chest': (.8 * br2, 0, .6 * wave(t, 4.0, .3)),
        'head': (-1.0 * br + 1.2 * wave(t, 4.0, .5), 4 * wave(t, 4.0, .1), 1.5 * wave(t, 4.0, .35)),
        'ear.L': (0, 0, -14 * twitch),
        'ear.R': (0, 0, 2 * br2),
        'upper_arm.L': (-.8 * br, 0, 0),
        'upper_arm.R': (-.8 * br, 0, 0),
        'tail1': (0, 5 * wave(t, 4.0), 0),
        'tail2': (2 * wave(t, 2.0), 7 * wave(t, 4.0, .12), 0),
        'tail3': (3 * wave(t, 2.0, .1), 10 * wave(t, 4.0, .24), 0),
        'hat_tip': (2 * wave(t, 4.0, .25), 0, 2.5 * wave(t, 4.0, .4)),
    }


def walk(t, T=0.9):
    """In place: a stiff-armed waddle (arms stay crossed), two steps per loop."""
    s = wave(t, T)
    c2 = math.cos(4 * math.pi * t / T)
    lift = lambda ph: max(0.0, wave(t, T, ph)) ** 1.5  # noqa: E731
    return {
        'hips': dict(r=(0, 4 * s, 5 * s), t=(0, .045 * c2, 0)),
        'leg.L': (-26 * s, 0, 0),
        'leg.R': (26 * s, 0, 0),
        'foot.L': (18 * s - 22 * lift(.0), 0, 0),
        'foot.R': (-18 * s - 22 * lift(.5), 0, 0),
        'spine': (3 + 1.5 * c2, -3 * s, -3.5 * s),
        'chest': (0, -2 * s, -1.5 * s),
        'head': (-2 - 2 * c2, 2 * s, 1.5 * s),
        'tail1': (4 * c2, -12 * s, 0),
        'tail2': (0, -8 * wave(t, T, .1), 0),
        'tail3': (0, -10 * wave(t, T, .2), 0),
        'hat_tip': (-4 * c2, 0, 6 * wave(t, T, .15)),
        'ear.L': (0, 0, -3 * c2),
        'ear.R': (0, 0, 3 * c2),
    }


def talk(t, T=2.4):
    """Head beats and the top (left) forearm opening forward in a 'look here' gesture."""
    env = smooth((t - .15) / .35) * (1 - smooth((t - 1.75) / .45))
    beat = wave(t, .6)
    beat2 = wave(t, .4, .1)
    return {
        'head': (4 * beat * (.4 + .6 * env) - 2 * env, 5 * wave(t, 2.4, .1), 4 * wave(t, 1.2) * env),
        'chest': (2 * env, 3 * env, 0),
        'spine': (1.5 * beat2 * env, 0, 0),
        'upper_arm.L': (-14 * env, 0, -6 * env),
        'forearm.L': (8 * env * beat2, 72 * env, 0),
        'hand.L': (-20 * env, 0, 25 * env + 8 * beat * env),
        'hat_tip': (3 * beat, 0, 3 * beat2),
        'ear.L': (0, 0, -4 * env),
        'ear.R': (0, 0, 4 * env),
    }


def watch(t, T=4.0):
    """Turns its head to its left (+X) to keep an eye on something, holds, turns back."""
    k = smooth(t / .55) * (1 - smooth((t - 3.2) / .7))
    sus = math.exp(-((t - 1.9) / .12) ** 2)
    return {
        'head': (-4 * k + 3 * sus, 52 * k, 7 * k),
        'chest': (0, 12 * k, 0),
        'spine': (0, 5 * k, 0),
        'ear.L': (0, 0, -10 * k),
        'ear.R': (0, 0, 6 * k),
        'tail2': (0, -8 * k, 0),
        'tail3': (0, -6 * k, 0),
        'hat_tip': (0, 0, -6 * k),
    }


def clips():
    return [Clip('idle', 4.0, idle), Clip('walk', 0.9, walk), Clip('talk', 2.4, talk),
            Clip('watch', 4.0, watch)]


# ---------------------------------------------------------------------------- main

def export(out_dir):
    m = build()
    flat = m.flatten()
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, 'raccoon.glb')
    info = glb.write_glb(path, m, flat, PALETTE, clips(), generator='tools/characters/raccoon.py')
    glb.write_import(path, [c.name for c in clips() if c.loop])
    lo, hi = m.bbox()
    info.update(path=path, height=float(hi[1] - lo[1]), size=(hi - lo).round(3).tolist())
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--preview', help='write six-view and animation strips here')
    a = ap.parse_args(argv)
    info = export(a.out)
    print('raccoon: %(triangles)d tris, %(bones)d bones, %(materials)d materials, %(height).3f m -> %(path)s' % info)
    assert info['triangles'] <= 6000, 'over the 6k triangle budget'
    if a.preview:
        import glb_preview as gp
        os.makedirs(a.preview, exist_ok=True)
        gp.sheet(info['path'], os.path.join(a.preview, 'raccoon_6view.png'), title='raccoon.glb (rest)')
        for c in clips():
            gp.frames(info['path'], os.path.join(a.preview, 'raccoon_%s.png' % c.name), c.name)


if __name__ == '__main__':
    main()
