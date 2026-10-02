"""The raccoon wizard as the painted room has him: a dark, round, four-legged raccoon with a fat ringed
tail, a rounded face with the bandit mask, and a tall straight violet hat with a small brim and a few
yellow marks.

    python tools/characters/raccoon.py --out assets/characters [--preview DIR]

Writes raccoon.glb: one skinned mesh (one surface per palette colour; the game folds the flat ones into
one), 0.70 m tall with the hat, feet on y = 0, facing +Z; animations idle, walk, talk, watch.

The skeleton keeps the names of the concept sheet's upright raccoon (the arms are now the front legs,
`upper_arm / forearm / hand`; the legs are the hind legs); the body is modelled on all fours, as in the
painting (the figure at the lower right of the reference still) and in the turnaround generated from it
(tools/characters/ref/raccoon_turnaround.png, docs/art/characters_painted.md). The head is the concept
sheet's, scaled onto the neck. Authored in metres.
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

_BASE = {
    'fur': (.43, .39, .34),       # dark warm grey: the painted raccoon is nearly black in its own shade
    'fur_d': (.24, .21, .19),     # paws, feet, the back of the ears
    'belly': (.52, .47, .41),
    'cream': (.88, .82, .70),     # muzzle, brows, lids, the light tail rings
    'mask': (.10, .085, .09),     # bandit mask, the dark tail rings
    'ear_in': (.32, .25, .24),
    'nose': (.07, .06, .06),
    'eye': (.90, .86, .74),
    'pupil': (.06, .05, .06),
    'hat': (.40, .27, .64),
    'hat_d': (.24, .16, .38),     # brim underside and band
    'star': (.93, .76, .36),
}
PALETTE = {k: q5(v) for k, v in _BASE.items()}
# three tones of the big surfaces, picked per facet: crumpled paper, as in the painting
for _k in ('fur', 'belly', 'hat'):
    for _v, _m in zip('abc', (.78, 1.0, 1.30)):
        PALETTE[_k + _v] = q5(tuple(min(1., c * _m) for c in _BASE[_k]))


def vary(name, c):
    h = abs(math.sin(c[0] * 91.7 + c[1] * 53.3 + c[2] * 37.9) * 43758.5453)
    return name + 'abc'[int(h % 3)]


# ---------------------------------------------------------------------------- skeleton

# where the old head's pivot sits in the source's units, and where it goes (metres)
HEAD_OLD = A((0.0, 2.04, 0.04))
HEAD_NEW = A((0.0, 0.318, 0.200))
HEAD_K = 0.185


EAR_OLD = (.46, 2.16, -.02)         # the ears sit lower than the sheet's, so they show under the hat's brim


def carry(p):
    """A point of the source head -> its place on the quadruped."""
    return (A(p, float) - HEAD_OLD) * HEAD_K + HEAD_NEW


def skeleton(m):
    m.bone('root', None, (0, 0, 0))
    m.bone('hips', 'root', (0, .20, -.12))
    m.bone('spine', 'hips', (0, .23, -.02))
    m.bone('chest', 'spine', (0, .255, .09))
    m.bone('head', 'chest', (0, .285, .15))
    m.bone('hat', 'head', (0, .408, .20))
    m.bone('hat_tip', 'hat', (0, .56, .19))
    for s, d in ((1, '.L'), (-1, '.R')):
        m.bone('ear' + d, 'head', carry((s * EAR_OLD[0], EAR_OLD[1], EAR_OLD[2])))
        m.bone('upper_arm' + d, 'chest', (s * .09, .22, .09))
        m.bone('forearm' + d, 'upper_arm' + d, (s * .095, .135, .10))
        m.bone('hand' + d, 'forearm' + d, (s * .095, .055, .125))
        m.bone('leg' + d, 'hips', (s * .095, .185, -.14))
        m.bone('foot' + d, 'leg' + d, (s * .100, .07, -.12))
    m.bone('tail1', 'hips', (0, .195, -.20))
    m.bone('tail2', 'tail1', (0, .18, -.36))
    m.bone('tail3', 'tail2', (0, .14, -.48))


# ---------------------------------------------------------------------------- body

def body(m):
    path = [(0, .185, -.190), (0, .208, -.110), (0, .232, -.020), (0, .255, .070), (0, .270, .140)]
    g = tube(path, [.070, .112, .127, .118, .085], N=10, ratio=.93, cap=(.02, .03))
    g['V'] = jitter(g['V'], .006, 1)
    V = g['V']
    W = m.blend(V[:, 2], [(-.16, 'hips'), (-.03, 'spine'), (.10, 'chest')])
    m.add(g, lambda c, n: vary('belly' if n[1] < -.45 else 'fur', c), W)


def legs(m):
    """Front legs on the arm bones, hind legs on the leg bones; short, dark, planted."""
    for s, d in ((1, '.L'), (-1, '.R')):
        fl = tube([(s * .092, .24, .09), (s * .095, .135, .10), (s * .095, .065, .125)], [.056, .046, .038], N=7, cap=(.01, .02))
        fl['V'] = jitter(fl['V'], .004, 2)
        W = m.blend(-fl['V'][:, 1], [(-.23, 'upper_arm' + d), (-.16, 'upper_arm' + d), (-.11, 'forearm' + d), (-.075, 'hand' + d)])
        m.add(fl, 'fur_d', W)
        paw = glb.blob((s * .095, .028, .140), (.050, .064, .031), (0, 0, 1), N=7, k=2)
        paw['V'] = jitter(paw['V'], .003, 3)
        m.add(paw, 'fur_d', 'hand' + d)
        thigh = glb.blob((s * .105, .145, -.125), (.074, .090, .097), (0, 1, -.15), N=8, k=3)
        thigh['V'] = jitter(thigh['V'], .005, 4)
        m.add(thigh, lambda c, n: vary('fur', c), 'leg' + d)
        shin = tube([(s * .102, .11, -.12), (s * .100, .06, -.125)], [.050, .040], N=6, cap=(.0, .01))
        m.add(shin, 'fur_d', m.blend(-shin['V'][:, 1], [(-.11, 'leg' + d), (-.07, 'foot' + d)]))
        foot = glb.blob((s * .100, .030, -.095), (.048, .088, .030), (0, 0, 1), N=7, k=2)
        foot['V'] = jitter(foot['V'], .003, 5)
        m.add(foot, 'fur_d', 'foot' + d)


def tail(m):
    """Fat and ringed, out behind and curling down: dark at the root and the tip, cream between."""
    ctrl = [(0, .196, -.20), (.008, .192, -.29), (.028, .178, -.385), (.055, .155, -.47), (.080, .128, -.535), (.100, .106, -.575)]
    path = catmull(ctrl, 2)
    r = [.052, .078, .096, .100, .092, .072, .042]
    g = tube(path, r, N=8, cap=(.02, .035), up=(1, 0, 0))
    g['V'] = jitter(g['V'], .005, 6)
    nring = len(path)
    bands = ['mask', 'cream', 'mask', 'cream', 'mask', 'cream', 'mask', 'cream', 'mask', 'mask', 'mask']
    mats = [bands[min(k, len(bands) - 1)] for k in range(nring)]
    W = m.blend(-g['V'][:, 2], [(.20, 'hips'), (.28, 'tail1'), (.38, 'tail2'), (.48, 'tail3')])
    m.add(g, mats, W)


# ---------------------------------------------------------------------------- head
# The head is the concept sheet's (a two-lobed bandit mask, cream muzzle, pale half-lidded eyes), built in the
# source's own units on a throwaway model, then scaled and carried onto the quadruped's neck (`carry`).

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




def head_on_neck(m):
    """Build the source head in its own units, then scale it onto the quadruped's neck."""
    old = glb.Model('source_head')
    old.bone('root', None, (0, 0, 0))
    old.bone('head', 'root', (0, 1.68, .04))
    for s, d in ((1, '.L'), (-1, '.R')):
        old.bone('ear' + d, 'head', (s * EAR_OLD[0], EAR_OLD[1], EAR_OLD[2]))
    head(old)
    nb = len(m.bones)
    for p in old.parts:
        W = np.zeros((len(p['V']), nb))
        for name, oi in old.ix.items():
            if name in m.ix:
                W[:, m.ix[name]] += p['W'][:, oi]
        g = dict(V=(A(p['V'], float) - HEAD_OLD) * HEAD_K + HEAD_NEW, F=p['F'],
                 ax=(A(p['ax'], float) - HEAD_OLD) * HEAD_K + HEAD_NEW, fb=p.get('fb'))
        m.add(g, p['mat'], W, inv=p['inv'], orient=p['orient'])


# ---------------------------------------------------------------------------- hat

HAT_BASE_Y = .408


def hat(m):
    """Tall straight cone on a small brim, a floppy tip, a few small yellow marks (the painted hat)."""
    path = A([(0, HAT_BASE_Y + .004, .200), (0, .49, .200), (0, .565, .198), (0, .630, .193), (0, .683, .186)])
    cone = tube(path, [.090, .072, .052, .030, .009], N=12, cap=(.0, .02), up=(1, 0, 0))
    cone['V'] = jitter(cone['V'], .0025, 10)
    W = m.blend(cone['V'][:, 1], [(.52, 'hat'), (.65, 'hat_tip')])
    m.add(cone, lambda c, n: vary('hat', c), W)
    brim = loft([glb.ring((0, y, .200), (r, 0, 0), (0, 0, r), 12) for y, r in
                 ((HAT_BASE_Y + .020, .090), (HAT_BASE_Y + .006, .122), (HAT_BASE_Y - .004, .130), (HAT_BASE_Y - .010, .096))],
                cap=(.008, .008))
    brim['V'] = jitter(brim['V'], .003, 11)
    m.add(brim, lambda c, n: 'hat_d' if n[1] < 0 else vary('hat', c), 'hat')
    # marks on a spiral (small stars and diamonds in the same yellow as the painting)
    surf = glb.Surface([cone])
    for i in range(7):
        y = .45 + .031 * i
        th = 1.0 + i * 2.35

        def mp(u, v, th=th):
            return (0, v, float(np.interp(v, path[:, 1], path[:, 2]))), (math.sin(th + u / .05), 0, math.cos(th + u / .05))
        r = .0125 - .0008 * i
        P = [(0, y)] + [((r if j % 2 == 0 else r * .42) * math.cos(j * math.pi / 4),
                         y + (r if j % 2 == 0 else r * .42) * math.sin(j * math.pi / 4)) for j in range(8)]
        F = [(0, 1 + j, 1 + (j + 1) % 8) for j in range(8)]
        V = surf.project(P, mp, .004)
        m.add(dict(V=V, F=A(F), ax=A([(0, y, .2)])), 'star', m.blend(V[:, 1], [(.52, 'hat'), (.65, 'hat_tip')]))


def build():
    m = glb.Model('Raccoon')
    skeleton(m)
    body(m)
    legs(m)
    tail(m)
    head_on_neck(m)
    hat(m)
    m.finish(HEIGHT)
    return m


# ---------------------------------------------------------------------------- animation
# Rotations are degrees about the rest-pose world axes (x: pitch, + swings a hanging leg backwards;
# y: yaw, + turns toward +X, the raccoon's left; z: roll).

def idle(t):
    br = wave(t, 4.0)
    br2 = wave(t, 2.0, .2)
    twitch = math.exp(-((t - 2.7) / .07) ** 2)
    return {
        'hips': dict(r=(.4 * br, 0, 0), t=(0, .002 * br2, 0)),
        'spine': (1.0 * br, 0, 0),
        'chest': (.8 * br2, 0, .5 * wave(t, 4.0, .3)),
        'head': (-1.2 * br + 1.5 * wave(t, 4.0, .5), 5 * wave(t, 4.0, .1), 1.5 * wave(t, 4.0, .35)),
        'ear.L': (0, 0, -14 * twitch),
        'ear.R': (0, 0, 2 * br2),
        'tail1': (0, 6 * wave(t, 4.0), 0),
        'tail2': (2 * wave(t, 2.0), 8 * wave(t, 4.0, .12), 0),
        'tail3': (3 * wave(t, 2.0, .1), 11 * wave(t, 4.0, .24), 0),
        'hat_tip': (2.5 * wave(t, 4.0, .25), 0, 3 * wave(t, 4.0, .4)),
    }


def walk(t, T=0.9):
    """In place: a trot, diagonal pairs together, the body rocking, the tail swinging, the hat tip lagging."""
    s = wave(t, T)
    c2 = math.cos(4 * math.pi * t / T)
    lift = lambda ph: max(0.0, wave(t, T, ph)) ** 1.5  # noqa: E731
    return {
        'hips': dict(r=(0, 5 * s, 3.5 * s), t=(0, .012 * c2, 0)),
        'spine': (2 + 1.2 * c2, -4 * s, -2.5 * s),
        'chest': (0, -3 * s, -1.5 * s),
        'head': (-2 - 2 * c2, 3 * s, 1.5 * s),
        'upper_arm.L': (-24 * s, 0, 0),
        'upper_arm.R': (24 * s, 0, 0),
        'forearm.L': (-10 * lift(.0) - 4 * s, 0, 0),
        'forearm.R': (-10 * lift(.5) + 4 * s, 0, 0),
        'hand.L': (10 * lift(.0), 0, 0),
        'hand.R': (10 * lift(.5), 0, 0),
        'leg.L': (24 * s, 0, 0),
        'leg.R': (-24 * s, 0, 0),
        'foot.L': (-16 * s + 22 * lift(.5), 0, 0),
        'foot.R': (16 * s + 22 * lift(.0), 0, 0),
        'tail1': (3 * c2, -14 * s, 0),
        'tail2': (0, -10 * wave(t, T, .1), 0),
        'tail3': (0, -12 * wave(t, T, .2), 0),
        'hat_tip': (-5 * c2, 0, 7 * wave(t, T, .15)),
        'ear.L': (0, 0, -3 * c2),
        'ear.R': (0, 0, 3 * c2),
    }


def talk(t, T=2.4):
    """Head beats, and the left front paw lifted in a 'look here' gesture."""
    env = smooth((t - .15) / .35) * (1 - smooth((t - 1.75) / .45))
    beat = wave(t, .6)
    beat2 = wave(t, .4, .1)
    return {
        'head': (4 * beat * (.4 + .6 * env) - 2 * env, 5 * wave(t, 2.4, .1), 4 * wave(t, 1.2) * env),
        'chest': (2 * env, 3 * env, 0),
        'spine': (1.5 * beat2 * env, 0, 0),
        'upper_arm.L': (-52 * env, 0, -8 * env),
        'forearm.L': (-34 * env + 8 * env * beat2, 0, 0),
        'hand.L': (-15 * env + 8 * beat * env, 0, 0),
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
    info.update(path=path, height=float(hi[1] - lo[1]), size=(hi - lo).round(3).tolist(), scale=m.scale)
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--preview', help='write six-view and animation strips here')
    a = ap.parse_args(argv)
    info = export(a.out)
    print('raccoon: %(triangles)d tris, %(bones)d bones, %(materials)d materials, %(height).3f m (scale %(scale).3f) -> %(path)s' % info)
    assert info['triangles'] <= 6000, 'over the 6k triangle budget'
    if a.preview:
        import glb_preview as gp
        os.makedirs(a.preview, exist_ok=True)
        gp.sheet(info['path'], os.path.join(a.preview, 'raccoon_6view.png'), title='raccoon.glb (rest)')
        for c in clips():
            gp.frames(info['path'], os.path.join(a.preview, 'raccoon_%s.png' % c.name), c.name)


if __name__ == '__main__':
    main()
