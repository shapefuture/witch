#!/usr/bin/env python3
"""The crude town characters: Мирон (miron), Элиан (elian), Вера (vera), Илья (ilya), Дворник (janitor) and the hotel's
Портье (concierge, a bird). Written to the house pattern of tomas_crude2.py: low-poly, flat-tinted (one colour per part,
one swatch atlas, one surface), feet at the origin, facing +Z, metres at game scale, clips idle, walk and talk.

Skinning follows template_rig.py: the witch kit's bone names, parents and neutral arm pose, distance-to-segment weights
(template_rig.skin_weights) on the body, and the witch kit's clips (witch.clip_set). Legs, boots, hats and props are rigid
on one bone each, so a walk swings the legs without bending the skirts; the body parts blend at the joints.

    python tools/characters/npc_crude.py --out assets/characters [--only miron] [--preview DIR]

writes DIR/<id>.glb for each character and, with --preview, DIR/<id>_sixview.png. The budgets are 3,000 triangles and one
surface (tests/world/test_npc_models.gd). The choices the bible does not make are listed in docs/art/characters.md.
"""
import argparse
import math
import os
import sys
import types

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import template_rig as tr   # noqa: E402  (KIT_H, GAME_H, skin_weights, neutral_base: the witch kit's skeleton and rest pose)
import witch                # noqa: E402  (BONES: names and parents; clip_set: idle, walk, talk, cast)
import witch_glb as glb     # noqa: E402  (the glTF writer)
import witch_preview        # noqa: E402  (six-view previews of the exported arrays)

K = tr.KIT_H / tr.GAME_H    # kit units per metre; the export scales back by GAME_H / KIT_H
ATLAS = 128                 # one swatch atlas: 16 px cells, nearest-sampled
CELL = 16


# ---- primitives (metres; each returns (V, F) with an outward winding fixed by orient()) ----------------------------
def loft(rings, cap=True):
    """Quads between consecutive rings of equal length, with a centre fan at each end when `cap`."""
    rings = [np.asarray(r, float) for r in rings]
    n = len(rings[0])
    V = np.vstack(rings)
    F = []
    for i in range(len(rings) - 1):
        for k in range(n):
            a, a2 = i * n + k, i * n + (k + 1) % n
            b, b2 = (i + 1) * n + k, (i + 1) * n + (k + 1) % n
            F += [(a, a2, b2), (a, b2, b)]
    if cap:
        for i in (0, len(rings) - 1):
            c = len(V)
            V = np.vstack([V, rings[i].mean(0)])
            for k in range(n):
                a, a2 = i * n + k, i * n + (k + 1) % n
                F.append((a, a2, c))
    return V, np.asarray(F, int)


def ellipsoid(c, r, nlat=4, nlon=8):
    rings = []
    for i in range(1, nlat):
        th = math.pi * i / nlat
        s, y = math.sin(th), c[1] + r[1] * math.cos(th)
        rings.append([(c[0] + r[0] * s * math.cos(2 * math.pi * k / nlon), y, c[2] + r[2] * s * math.sin(2 * math.pi * k / nlon))
                      for k in range(nlon)])
    return loft(rings)


def tube(p0, p1, r0, r1, n=8):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = p1 - p0
    d /= np.linalg.norm(d)
    u = np.cross(d, (0., 0., 1.)) if abs(d[2]) < .9 else np.cross(d, (1., 0., 0.))
    u /= np.linalg.norm(u)
    v = np.cross(d, u)

    def ring(p, r):
        return [p + r * (math.cos(2 * math.pi * k / n) * u + math.sin(2 * math.pi * k / n) * v) for k in range(n)]
    return loft([ring(p0, r0), ring(p1, r1)])


def profile(rows, n=12):
    """A vertical loft: rows of (y, rx, rz) or (y, rx, rz, cx, cz) ellipses, bottom first."""
    rings = []
    for row in rows:
        y, rx, rz = row[0], row[1], row[2]
        cx, cz = (row[3], row[4]) if len(row) > 3 else (0., 0.)
        rings.append([(cx + rx * math.sin(2 * math.pi * k / n), y, cz + rz * math.cos(2 * math.pi * k / n)) for k in range(n)])
    return loft(rings)


def box(c, h):
    x, y, z = c
    hx, hy, hz = h
    ring = lambda yy: [(x - hx, yy, z - hz), (x + hx, yy, z - hz), (x + hx, yy, z + hz), (x - hx, yy, z + hz)]
    return loft([ring(y - hy), ring(y + hy)])


def orient(V, F):
    """Winding that faces away from the part's own centre (every part here is a convex-ish solid or a shell)."""
    F = F.copy()
    T = V[F]
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    flip = np.einsum('ij,ij->i', n, T.mean(1) - V.mean(0)) < 0
    F[flip] = F[flip][:, [0, 2, 1]]
    return F


def mirror(geom):
    V, F = geom
    V = V.copy()
    V[:, 0] *= -1
    return V, F


class Figure:
    def __init__(self, height, joints, segs):
        self.H = height
        self.joints = joints      # every witch.BONES name -> rest position (metres)
        self.segs = segs          # the SKINNED names -> (a, b) segment (metres) for the distance weights
        self.parts = []           # (V, F, colour, bind): bind is 'auto' or one bone name

    def add(self, geom, colour, bind='auto'):
        V, F = geom
        self.parts.append((np.asarray(V, float), np.asarray(F, int), colour, bind))

    def both(self, geom_fn, colour, bind='auto'):
        """Left (+X) and right (-X) copies of a part built by geom_fn(side) -> geom."""
        self.add(geom_fn(1), colour, bind)
        self.add(geom_fn(-1), colour, bind)


def humanoid(H):
    sw, lx = .115 * H, .065 * H
    j = {'root': (0, 0, 0), 'hips': (0, .50 * H, 0), 'spine': (0, .58 * H, 0), 'neck': (0, .83 * H, 0),
         'head': (0, .88 * H, 0), 'hat_tip': (0, .97 * H, -.04 * H), 'cape': (0, .56 * H, -.05 * H),
         'bird': (sw + .02 * H, .36 * H, -.02 * H)}
    for s, d in ((1, '.L'), (-1, '.R')):
        j['arm_upper' + d] = (s * sw, .80 * H, 0)
        j['arm_lower' + d] = (s * (sw + .01 * H), .63 * H, 0)
        j['hand' + d] = (s * (sw + .012 * H), .49 * H, .01 * H)
        j['leg' + d] = (s * lx, .50 * H, 0)
        j['foot' + d] = (s * lx, .04 * H, .02 * H)
        j['hairB' + d] = (s * .05 * H, .92 * H, -.04 * H)
        j['hairT' + d] = (s * .06 * H, .86 * H, -.07 * H)
    segs = {'hips': (j['hips'], j['spine']), 'spine': (j['spine'], j['neck']), 'neck': (j['neck'], j['head']),
            'head': (j['head'], (0, .97 * H, 0))}
    for d in ('.L', '.R'):
        segs['arm_upper' + d] = (j['arm_upper' + d], j['arm_lower' + d])
        segs['arm_lower' + d] = (j['arm_lower' + d], j['hand' + d])
        segs['hand' + d] = (j['hand' + d], (j['hand' + d][0], j['hand' + d][1] - .06 * H, j['hand' + d][2]))
    return j, segs


def bird_skeleton():
    j = {'root': (0, 0, 0), 'hips': (0, .30, 0), 'spine': (0, .42, 0), 'neck': (0, .60, 0), 'head': (0, .64, 0),
         'hat_tip': (0, .84, -.02), 'cape': (0, .34, -.12), 'bird': (.15, .36, -.02)}
    for s, d in ((1, '.L'), (-1, '.R')):
        j['arm_upper' + d] = (s * .12, .52, 0)
        j['arm_lower' + d] = (s * .17, .42, 0)
        j['hand' + d] = (s * .15, .34, -.02)
        j['leg' + d] = (s * .05, .30, 0)
        j['foot' + d] = (s * .05, .05, .02)
        j['hairB' + d] = (s * .05, .74, -.03)
        j['hairT' + d] = (s * .07, .80, -.05)
    segs = {'hips': (j['hips'], j['spine']), 'spine': (j['spine'], j['neck']), 'neck': (j['neck'], j['head']),
            'head': (j['head'], (0, .80, 0))}
    for d in ('.L', '.R'):
        segs['arm_upper' + d] = (j['arm_upper' + d], j['arm_lower' + d])
        segs['arm_lower' + d] = (j['arm_lower' + d], j['hand' + d])
        segs['hand' + d] = (j['hand' + d], (j['hand' + d][0], j['hand' + d][1] - .03, j['hand' + d][2]))
    return j, segs


def arm(fig, side_d, shoulder, elbow, wrist, colour, hand_geom, hand_colour, r=(.045, .038, .032)):
    """Sleeve (two tubes, skinned to the arm bones) and a rigid hand on the hand bone."""
    fig.add(tube(shoulder, elbow, r[0], r[1]), colour, 'arm_upper' + side_d)
    fig.add(tube(elbow, wrist, r[1], r[2]), colour, 'arm_lower' + side_d)
    if hand_geom is not None:
        fig.add(hand_geom, hand_colour, 'hand' + side_d)


def leg(fig, side_d, hip, ankle, colour, boot_geom, boot_colour, r=(.05, .04)):
    fig.add(tube(hip, ankle, r[0], r[1]), colour, 'leg' + side_d)
    fig.add(boot_geom, boot_colour, 'foot' + side_d)


# ---- the characters ----------------------------------------------------------------------------------------------
def miron():
    """First Love: tall and slender, a long camel coat with the collar up, short brown hair, a rust scarf and a small
    magenta sigil on the chest (reference 16's man in a long coat)."""
    H = 1.80
    j, segs = humanoid(H)
    f = Figure(H, j, segs)
    f.add(profile([(.27 * H, .122 * H, .088 * H), (.42 * H, .118 * H, .084 * H), (.56 * H, .100 * H, .074 * H),
                   (.66 * H, .112 * H, .082 * H), (.74 * H, .124 * H, .086 * H), (.80 * H, .120 * H, .080 * H),
                   (.835 * H, .064 * H, .056 * H)]), 'coat')
    f.add(tube((0, .81 * H, 0), (0, .89 * H, 0), .068 * H, .064 * H), 'collar')
    f.add(tube((0, .79 * H, 0), (0, .89 * H, 0), .03 * H, .03 * H), 'skin')
    f.add(ellipsoid((0, .895 * H, 0), (.046 * H, .07 * H, .058 * H)), 'skin', 'head')
    f.add(ellipsoid((0, .92 * H, -.006 * H), (.05 * H, .054 * H, .062 * H)), 'hair', 'head')
    f.both(lambda s: ellipsoid((s * .016 * H, .895 * H, .06 * H), (.007 * H, .006 * H, .004 * H), 3, 6), 'ink', 'head')
    f.add(ellipsoid((0, .79 * H, .07 * H), (.03 * H, .02 * H, .02 * H)), 'scarf', 'spine')
    f.add(box((0, .70 * H, .08 * H), (.028 * H, .08 * H, .012 * H)), 'scarf', 'spine')
    f.add(tube((-.05 * H, .74 * H, .086 * H), (-.05 * H, .74 * H, .09 * H), .02 * H, .02 * H), 'sigil', 'spine')
    for d, s in (('.L', 1), ('.R', -1)):
        arm(f, d, j['arm_upper' + d], j['arm_lower' + d], j['hand' + d], 'coat', ellipsoid((j['hand' + d][0], .47 * H, .02 * H),
            (.03 * H, .04 * H, .025 * H), 3, 6), 'skin', (.045 * H, .038 * H, .032 * H))
        leg(f, d, j['leg' + d], (s * .065 * H, .08 * H, .01 * H), 'trous',
            ellipsoid((s * .065 * H, .045 * H, .02 * H), (.045 * H, .045 * H, .07 * H), 3, 6), 'boot', (.05 * H, .04 * H))
    return f, {'coat': (.66, .50, .32), 'collar': (.42, .30, .20), 'trous': (.30, .29, .36), 'boot': (.24, .16, .12),
               'skin': (.93, .74, .62), 'hair': (.34, .24, .18), 'scarf': (.74, .24, .22), 'ink': (.12, .08, .14),
               'sigil': (.86, .36, .80)}


def elian():
    """Need and care: a slight young man in a short blue jacket with a peplum, a plum flat cap held in the left hand
    (he comes in cap in hand, act II), messy dark hair."""
    H = 1.68
    j, segs = humanoid(H)
    f = Figure(H, j, segs)
    f.add(profile([(.47 * H, .108 * H, .08 * H), (.56 * H, .088 * H, .066 * H), (.68 * H, .098 * H, .07 * H),
                   (.79 * H, .112 * H, .076 * H), (.835 * H, .07 * H, .06 * H)]), 'jacket')
    f.add(tube((0, .79 * H, 0), (0, .88 * H, 0), .03 * H, .03 * H), 'skin')
    f.add(ellipsoid((0, .895 * H, 0), (.043 * H, .066 * H, .055 * H)), 'skin', 'head')
    f.add(ellipsoid((0, .918 * H, -.008 * H), (.046 * H, .046 * H, .056 * H)), 'hair', 'head')
    f.add(ellipsoid((.006 * H, .936 * H, .03 * H), (.04 * H, .02 * H, .025 * H)), 'hair2', 'head')
    f.both(lambda s: ellipsoid((s * .016 * H, .895 * H, .053 * H), (.007 * H, .006 * H, .004 * H), 3, 6), 'ink', 'head')
    for d, s in (('.L', 1), ('.R', -1)):
        hand = ellipsoid((j['hand' + d][0], .47 * H, .02 * H), (.03 * H, .04 * H, .025 * H), 3, 6)
        arm(f, d, j['arm_upper' + d], j['arm_lower' + d], j['hand' + d], 'jacket', hand, 'skin', (.042 * H, .036 * H, .03 * H))
        leg(f, d, j['leg' + d], (s * .065 * H, .08 * H, .01 * H), 'trous',
            ellipsoid((s * .065 * H, .045 * H, .02 * H), (.045 * H, .045 * H, .07 * H), 3, 6), 'boot', (.042 * H, .036 * H))
    # the cap, held in the left hand: a crown and a brim, both on the hand bone
    hx, hy, hz = j['hand.L']
    f.add(tube((hx, hy - .03 * H, hz + .03 * H), (hx, hy - .015 * H, hz + .03 * H), .05 * H, .052 * H), 'cap', 'hand.L')
    f.add(box((hx, hy - .03 * H, hz + .065 * H), (.034 * H, .004 * H, .03 * H)), 'cap', 'hand.L')
    return f, {'jacket': (.24, .38, .62), 'trous': (.36, .36, .44), 'boot': (.34, .22, .14), 'skin': (.93, .74, .62),
               'hair': (.26, .17, .12), 'hair2': (.22, .14, .10), 'ink': (.12, .08, .14), 'cap': (.52, .24, .30)}


def vera():
    """Vera, the apothecary: a bell of a moss-green dress (the widest silhouette), a plum shawl, a rust headscarf, a
    thick brown braid over the shoulder, a cream blouse with wide sleeves and a bandolier of bottles."""
    H = 1.66
    j, segs = humanoid(H)
    f = Figure(H, j, segs)
    f.add(profile([(.02 * H, .25 * H, .21 * H), (.12 * H, .235 * H, .20 * H), (.30 * H, .175 * H, .15 * H),
                   (.48 * H, .135 * H, .11 * H), (.56 * H, .118 * H, .10 * H), (.64 * H, .13 * H, .11 * H),
                   (.70 * H, .124 * H, .10 * H)]), 'dress')
    f.add(profile([(.63 * H, .142 * H, .12 * H), (.70 * H, .15 * H, .124 * H), (.765 * H, .132 * H, .11 * H),
                   (.80 * H, .10 * H, .085 * H)]), 'shawl')
    f.add(tube((0, .79 * H, 0), (0, .88 * H, 0), .03 * H, .03 * H), 'skin')
    f.add(ellipsoid((0, .895 * H, 0), (.043 * H, .066 * H, .055 * H)), 'skin', 'head')
    f.add(ellipsoid((0, .925 * H, -.01 * H), (.05 * H, .05 * H, .058 * H)), 'scarf', 'head')
    f.add(ellipsoid((0, .905 * H, -.06 * H), (.022 * H, .02 * H, .02 * H)), 'scarf', 'head')
    f.both(lambda s: ellipsoid((s * .016 * H, .895 * H, .053 * H), (.007 * H, .006 * H, .004 * H), 3, 6), 'ink', 'head')
    f.add(tube((.05 * H, .90 * H, .05 * H), (.10 * H, .76 * H, .09 * H), .024 * H, .022 * H), 'braid', 'head')
    f.add(tube((.10 * H, .76 * H, .09 * H), (.095 * H, .60 * H, .11 * H), .022 * H, .018 * H), 'braid', 'head')
    f.add(tube((-.105 * H, .79 * H, .085 * H), (.105 * H, .52 * H, .09 * H), .013 * H, .013 * H), 'leather')
    for x, y, z, col in ((-.02 * H, .70 * H, .105 * H, 'glass'), (.03 * H, .63 * H, .10 * H, 'amber'),
                         (-.005 * H, .58 * H, .105 * H, 'glass')):
        f.add(tube((x, y - .025 * H, z), (x, y + .025 * H, z), .016 * H, .016 * H, 6), col)
    for d, s in (('.L', 1), ('.R', -1)):
        hand = ellipsoid((j['hand' + d][0], .47 * H, .02 * H), (.03 * H, .04 * H, .025 * H), 3, 6)
        arm(f, d, j['arm_upper' + d], j['arm_lower' + d], j['hand' + d], 'blouse', hand, 'skin', (.055 * H, .05 * H, .04 * H))
    return f, {'dress': (.28, .45, .36), 'shawl': (.44, .22, .46), 'skin': (.93, .74, .62), 'scarf': (.70, .30, .20),
               'ink': (.12, .08, .14), 'braid': (.40, .26, .16), 'blouse': (.92, .86, .74), 'leather': (.36, .24, .14),
               'glass': (.30, .62, .60), 'amber': (.82, .52, .20)}


def ilya():
    """Wonder without use: short and round, a puffed blue coat, a gold scarf, a big round head with round spectacles and
    a brass telescope carried forward in the left hand."""
    H = 1.52
    j, segs = humanoid(H)
    f = Figure(H, j, segs)
    f.add(profile([(.40 * H, .135 * H, .125 * H), (.52 * H, .152 * H, .142 * H), (.66 * H, .158 * H, .145 * H),
                   (.76 * H, .148 * H, .13 * H), (.815 * H, .09 * H, .08 * H)]), 'coat')
    f.add(tube((0, .78 * H, 0), (0, .85 * H, 0), .066 * H, .062 * H), 'gold')
    f.add(tube((0, .79 * H, 0), (0, .88 * H, 0), .03 * H, .03 * H), 'skin')
    f.add(ellipsoid((0, .895 * H, 0), (.055 * H, .075 * H, .065 * H)), 'skin', 'head')
    f.add(ellipsoid((0, .945 * H, -.012 * H), (.058 * H, .03 * H, .068 * H)), 'hair', 'head')
    f.both(lambda s: ellipsoid((s * .022 * H, .905 * H, .064 * H), (.008 * H, .008 * H, .004 * H), 3, 6), 'ink', 'head')
    f.both(lambda s: tube((s * .022 * H, .905 * H, .066 * H), (s * .022 * H, .905 * H, .071 * H), .02 * H, .02 * H, 8), 'gold', 'head')
    for d, s in (('.L', 1), ('.R', -1)):
        hand = ellipsoid((j['hand' + d][0], .47 * H, .02 * H), (.03 * H, .04 * H, .025 * H), 3, 6)
        arm(f, d, j['arm_upper' + d], j['arm_lower' + d], j['hand' + d], 'coat', hand, 'skin', (.05 * H, .045 * H, .036 * H))
        leg(f, d, j['leg' + d], (s * .065 * H, .08 * H, .01 * H), 'trous',
            ellipsoid((s * .065 * H, .045 * H, .02 * H), (.045 * H, .045 * H, .07 * H), 3, 6), 'boot', (.045 * H, .04 * H))
    hx, hy, hz = j['hand.L']
    f.add(tube((hx + .01 * H, hy, hz + .02 * H), (hx - .02 * H, hy, hz + .32 * H), .018 * H, .014 * H), 'brass', 'hand.L')
    f.add(tube((hx - .02 * H, hy, hz + .32 * H), (hx - .02 * H, hy, hz + .325 * H), .016 * H, .016 * H), 'ink', 'hand.L')
    return f, {'coat': (.30, .40, .62), 'gold': (.92, .72, .30), 'skin': (.93, .74, .62), 'hair': (.78, .76, .80),
               'ink': (.12, .08, .14), 'trous': (.34, .28, .42), 'boot': (.30, .20, .14), 'brass': (.76, .58, .28)}


def janitor():
    """The town's lamplighter and sweeper (reference 17's janitor): a tall, thin blue uniform with brass buttons, a peaked
    cap, a grey moustache, a broom in the right hand and a bucket in the left."""
    H = 1.76
    j, segs = humanoid(H)
    f = Figure(H, j, segs)
    f.add(profile([(.48 * H, .112 * H, .085 * H), (.56 * H, .094 * H, .074 * H), (.72 * H, .108 * H, .08 * H),
                   (.82 * H, .118 * H, .08 * H), (.85 * H, .07 * H, .06 * H)]), 'uniform')
    f.add(profile([(.552 * H, .097 * H, .077 * H), (.575 * H, .097 * H, .077 * H)]), 'belt')
    for y in (.70, .63, .77):
        f.add(tube((0, y * H, .086 * H), (0, y * H, .09 * H), .012 * H, .012 * H, 6), 'brass')
    f.add(tube((0, .79 * H, 0), (0, .88 * H, 0), .03 * H, .03 * H), 'skin')
    f.add(ellipsoid((0, .895 * H, 0), (.043 * H, .066 * H, .055 * H)), 'skin', 'head')
    f.add(ellipsoid((0, .868 * H, .058 * H), (.024 * H, .008 * H, .01 * H)), 'hair', 'head')
    f.add(tube((0, .94 * H, 0), (0, .975 * H, 0), .052 * H, .054 * H), 'cap', 'head')
    f.add(box((0, .955 * H, .06 * H), (.048 * H, .004 * H, .03 * H)), 'cap', 'head')
    f.both(lambda s: ellipsoid((s * .016 * H, .895 * H, .053 * H), (.007 * H, .006 * H, .004 * H), 3, 6), 'ink', 'head')
    for d, s in (('.L', 1), ('.R', -1)):
        hand = ellipsoid((j['hand' + d][0], .47 * H, .02 * H), (.03 * H, .04 * H, .025 * H), 3, 6)
        arm(f, d, j['arm_upper' + d], j['arm_lower' + d], j['hand' + d], 'uniform', hand, 'skin', (.046 * H, .04 * H, .033 * H))
        leg(f, d, j['leg' + d], (s * .065 * H, .08 * H, .01 * H), 'trous',
            ellipsoid((s * .065 * H, .045 * H, .02 * H), (.045 * H, .045 * H, .07 * H), 3, 6), 'boot', (.045 * H, .04 * H))
    rx, ry, rz = j['hand.R']
    f.add(tube((rx, ry, rz), (rx - .05 * H, .06 * H, rz + .12 * H), .014 * H, .014 * H), 'wood', 'hand.R')
    f.add(box((rx - .06 * H, .02 * H, rz + .13 * H), (.07 * H, .02 * H, .03 * H)), 'straw', 'hand.R')
    lx, ly, lz = j['hand.L']
    f.add(tube((lx + .01 * H, ly - .04 * H, lz + .02 * H), (lx + .01 * H, ly - .10 * H, lz + .02 * H), .006 * H, .006 * H, 6), 'metal', 'hand.L')
    f.add(tube((lx + .01 * H, ly - .14 * H, lz + .02 * H), (lx + .01 * H, ly - .10 * H, lz + .02 * H), .04 * H, .05 * H), 'metal', 'hand.L')
    return f, {'uniform': (.24, .40, .64), 'belt': (.30, .20, .12), 'brass': (.95, .76, .38), 'cap': (.18, .24, .44),
               'trous': (.22, .24, .34), 'boot': (.18, .13, .10), 'skin': (.93, .74, .62), 'hair': (.66, .62, .60),
               'ink': (.12, .08, .14), 'wood': (.52, .36, .20), 'straw': (.86, .72, .36), 'metal': (.60, .64, .70)}


def concierge():
    """Портье: a bird at the hotel desk (reference 04): a grey-white head with a yellow beak, a red pillbox hat, a dark red
    coat with a gold crescent and grey wings held at the sides. About 0.9 m standing."""
    H = .9
    j, segs = bird_skeleton()
    f = Figure(H, j, segs)
    f.add(ellipsoid((0, .38, 0), (.13, .17, .12)), 'jacket')
    f.add(ellipsoid((0, .42, .10), (.07, .10, .03)), 'white')
    f.add(tube((0, .45, .135), (0, .45, .14), .03, .03, 8), 'gold')
    f.add(ellipsoid((0, .66, .01), (.10, .10, .10)), 'white', 'head')
    f.add(tube((0, .665, .10), (0, .645, .23), .045, .008, 6), 'beak', 'head')
    f.both(lambda s: ellipsoid((s * .045, .69, .085), (.018, .018, .012), 3, 6), 'ink', 'head')
    f.add(tube((0, .73, 0), (0, .83, 0), .10, .10, 10), 'hat', 'head')
    f.add(tube((0, .73, 0), (0, .745, 0), .105, .105, 10), 'band', 'head')
    for d, s in (('.L', 1), ('.R', -1)):
        f.add(tube(j['arm_upper' + d], j['arm_lower' + d], .045, .04), 'wing', 'arm_upper' + d)
        f.add(tube(j['arm_lower' + d], j['hand' + d], .04, .03), 'wing', 'arm_lower' + d)
        f.add(ellipsoid(j['hand' + d], (.035, .05, .02), 3, 6), 'wing', 'hand' + d)
        f.add(tube((s * .05, .30, 0), (s * .05, .06, .02), .018, .014, 6), 'legs', 'leg' + d)
        f.add(box((s * .05, .03, .05), (.035, .02, .06)), 'legs', 'foot' + d)
    f.add(ellipsoid((0, .34, -.13), (.07, .06, .04)), 'jacket')
    return f, {'jacket': (.52, .14, .20), 'white': (.94, .94, .96), 'gold': (.95, .76, .38), 'beak': (.96, .80, .24),
               'ink': (.12, .08, .14), 'hat': (.80, .16, .22), 'band': (.30, .08, .14), 'wing': (.46, .46, .54),
               'legs': (.92, .72, .22)}


CHARACTERS = {'miron': miron, 'elian': elian, 'vera': vera, 'ilya': ilya, 'janitor': janitor, 'concierge': concierge}


# ---- export --------------------------------------------------------------------------------------------------------
def export(fig, palette, out_path, log=print):
    names = list(witch.BONES)
    B = {n: (witch.BONES[n][0], np.asarray(fig.joints[n], float) * K) for n in names}
    model = types.SimpleNamespace(B=B, names=names, ix={n: i for i, n in enumerate(names)})
    swatch = {}
    picture = Image.new('RGB', (ATLAS, ATLAS), (0, 0, 0))
    for slot, key in enumerate(sorted(palette)):
        x0, y0 = (slot % (ATLAS // CELL)) * CELL, (slot // (ATLAS // CELL)) * CELL
        picture.paste(tuple(int(round(c * 255)) for c in palette[key]), (x0, y0, x0 + CELL, y0 + CELL))
        swatch[key] = ((x0 + CELL / 2) / ATLAS, (y0 + CELL / 2) / ATLAS)
    Vs, Fs, colours, binds, off = [], [], [], [], 0
    for V, F, colour, bind in fig.parts:
        F = orient(V, F)
        Vs.append(V)
        Fs.append(F + off)
        colours += [colour] * len(V)
        binds += [bind] * len(V)
        off += len(V)
    V = np.vstack(Vs) * K
    F = np.vstack(Fs)
    J = np.zeros((len(V), 4), int)
    W = np.zeros((len(V), 4))
    auto = np.array([b == 'auto' for b in binds])
    seg = {n: (np.asarray(a, float) * K, np.asarray(b, float) * K) for n, (a, b) in fig.segs.items()}
    if auto.any():
        Ja, Wa = tr.skin_weights(V[auto], B, seg)
        J[auto], W[auto] = Ja, Wa
    for i in np.nonzero(~auto)[0]:
        J[i, 0], W[i, 0] = model.ix[binds[i]], 1.0
    UV = np.array([swatch[c] for c in colours], float)
    tri = F.reshape(-1)
    T = V[tri].reshape(-1, 3, 3)
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    arr = {'P': V[tri], 'N': np.repeat(n, 3, axis=0), 'UV': UV[tri], 'J': J[tri], 'W': W[tri]}
    clips = witch.clip_set(model, base=tr.neutral_base)
    count = glb.export(str(out_path), model, arr, picture, clips, tr.GAME_H / tr.KIT_H, mesh_name='Figure',
                       generator='tools/characters/npc_crude.py', extras={'height_m': fig.H})
    log('%s: %d triangles, 1 surface, %d-px atlas with %d flat colours, %d clips, %.2f m tall' % (
        out_path, count, ATLAS, len(palette), len(clips), fig.H))
    return arr, picture, count


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--out', default='assets/characters')
    ap.add_argument('--only', action='append', default=[], help='build just these ids (repeatable)')
    ap.add_argument('--preview', default=None, help='write a six-view PNG per character here')
    a = ap.parse_args(argv)
    ids = a.only or list(CHARACTERS)
    os.makedirs(a.out, exist_ok=True)
    for cid in ids:
        fig, palette = CHARACTERS[cid]()
        arr, picture, count = export(fig, palette, os.path.join(a.out, cid + '.glb'))
        if a.preview:
            os.makedirs(a.preview, exist_ok=True)
            witch_preview.sixview(arr, picture, os.path.join(a.preview, cid + '_sixview.png'), '%s  %d tris' % (cid, count))


if __name__ == '__main__':
    main()
