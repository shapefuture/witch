#!/usr/bin/env python3
"""Tomas, the young mechanic: a procedural low-poly PSX character, written straight to glTF.

    python tools/characters/tomas.py --out assets/characters            # -> tomas.glb
    python tools/characters/tomas.py --out assets/characters --sheet SHEET.webp   # also re-cut the face

Everything is numpy: lofted rings, tubes and blobs, skinned to a 20-bone skeleton, flat shaded
(every triangle has its own three corners and its face normal), coloured per vertex with a small
per-facet tone, plus one photo-projected relief FACE PLATE textured from the concept sheet's front
view. Root at the feet, facing +Z (his left hand, holding the wrench, is +X), 1.55 m tall.

Two surfaces: `tomas_body` (vertex colour, base colour white) and `tomas_face` (the face texture,
vertex colour white), so `psx_lit_actor` (COLOR x albedoTex) draws both with one shader.

Rebuilding without the sheet uses the committed face texture `assets/characters/tomas_face.png`.
See docs/art/characters_tomas.md.
"""
import argparse
import json
import math
import os
import struct
import sys

import numpy as np

A = np.array
X_AXIS, Y_AXIS, Z_AXIS = A((1., 0, 0)), A((0, 1., 0)), A((0, 0, 1.))

# ------------------------------------------------------------------------------------- palette
# Display-referred sRGB (the game's shaders write display colour). Measured from the concept sheet
# and muted a little so he sits in the olive/ochre hall; the vest is the purple accent.
PALETTE = {
	'skin': (.78, .56, .45), 'skin_d': (.64, .44, .36), 'neck': (.70, .49, .40),
	'hair': (.50, .32, .19), 'hair_l': (.61, .41, .26), 'hair_d': (.36, .22, .14),
	'shirt': (.80, .74, .63), 'shirt_d': (.68, .61, .52),
	'vest': (.37, .24, .32), 'vest_d': (.29, .19, .26), 'vest_in': (.18, .12, .16),
	'belt': (.37, .22, .15), 'belt_d': (.25, .15, .11),
	'pouch': (.53, .33, .19), 'pouch_d': (.43, .26, .15),
	'metal': (.60, .59, .56), 'metal_d': (.40, .40, .39), 'handle': (.22, .15, .12),
	'trousers': (.34, .32, .21), 'trousers_d': (.28, .26, .18), 'cuff': (.31, .27, .19),
	'boot': (.34, .22, .15), 'boot_d': (.26, .17, .12), 'sole': (.14, .11, .09),
	'white': (1., 1., 1.),
}
FACET_TONE = .05          # +- value jitter per facet: the crystalline mosaic of the hall

# ------------------------------------------------------------------------------------ skeleton
# name: (parent, rest head position). Rest rotations are identity, so every animation rotation is
# expressed in the parent's (model-aligned at rest) frame. Side suffix _l is +X.
BONES = {
	'root': (None, (0, 0, 0)),
	'hips': ('root', (0, .66, 0)),
	'spine': ('hips', (0, .78, -.005)),
	'chest': ('spine', (0, .92, -.01)),
	'neck': ('chest', (0, 1.075, -.01)),
	'head': ('neck', (0, 1.135, .005)),
}
for _s, _d in ((1, '_l'), (-1, '_r')):
	BONES['shoulder' + _d] = ('chest', (_s * .07, 1.03, -.01))
	BONES['upper_arm' + _d] = ('shoulder' + _d, (_s * .19, 1.03, -.01))
	BONES['forearm' + _d] = ('upper_arm' + _d, (_s * .283, .79, -.01))
	BONES['hand' + _d] = ('forearm' + _d, (_s * .322, .635, .0))
	BONES['thigh' + _d] = ('hips', (_s * .105, .62, 0))
	BONES['shin' + _d] = ('thigh' + _d, (_s * .113, .345, .01))
	BONES['foot' + _d] = ('shin' + _d, (_s * .118, .085, -.01))
BONE_NAMES = list(BONES)
BONE_INDEX = {n: i for i, n in enumerate(BONE_NAMES)}


def bone_pos(name):
	return A(BONES[name][1], float)


# ------------------------------------------------------------------------------------ mesh kit
def unit(v):
	v = A(v, float)
	return v / np.linalg.norm(v)


def signed_pow(x, p):
	return math.copysign(abs(x) ** p, x)


def ring(y, rx, rz, cz=0., cx=0., n=12, e=2., phase=.5):
	"""A horizontal super-ellipse ring; e > 2 is boxier. Index 0 starts at the front (+Z)."""
	out = []
	for k in range(n):
		t = 2 * math.pi * (k + phase) / n
		s, c = math.sin(t), math.cos(t)
		if e != 2:
			s, c = signed_pow(s, 2 / e), signed_pow(c, 2 / e)
		out.append((cx + rx * s, y, cz + rz * c))
	return A(out)


def resample(points, n=6):
	points = A(points, float)
	out = [points[i] * (1 - t) + points[i + 1] * t for i in range(len(points) - 1)
		for t in np.linspace(0, 1, n, endpoint=False)]
	return A(out + [points[-1]])


def loft(rings, caps=(.0, .0), closed=True, axis=None):
	"""Quads between consecutive rings (same vertex count). Closed rings get pointed end caps
	(a cap of None leaves that end open)."""
	rings = [A(r, float) for r in rings]
	nr, n = len(rings), len(rings[0])
	verts = [np.vstack(rings)]
	faces = []
	for k in range(nr - 1):
		for m in range(n if closed else n - 1):
			a, b = k * n + m, k * n + (m + 1) % n
			faces += [(a, b, a + n), (b, b + n, a + n)]
	centres = [r.mean(0) for r in rings]
	if closed and caps is not None:
		nv = nr * n
		if caps[0] is not None:
			verts.append((centres[0] + unit(centres[0] - centres[1]) * caps[0])[None])
			faces += [(nv, (m + 1) % n, m) for m in range(n)]
			nv += 1
		if caps[1] is not None:
			verts.append((centres[-1] + unit(centres[-1] - centres[-2]) * caps[1])[None])
			faces += [(nv, (nr - 1) * n + m, (nr - 1) * n + (m + 1) % n) for m in range(n)]
	return dict(V=np.vstack(verts), F=A(faces, int), ax=resample(centres) if axis is None else A(axis, float))


def frame_from(t, hint):
	t = unit(t)
	w = np.cross(t, hint)
	if np.linalg.norm(w) < 1e-6:
		w = np.cross(t, Y_AXIS if abs(t[1]) < .9 else X_AXIS)
	w = unit(w)
	return w, np.cross(w, t)


def tube(path, radii, n=6, ratio=1., flat=Z_AXIS, caps=(.004, .006), phase=0.):
	"""A tube along a polyline; `ratio` squashes it along the second frame axis."""
	path = A(path, float)
	m = len(path)
	rr = np.interp(np.linspace(0, 1, m), np.linspace(0, 1, len(radii)), radii)
	rings = []
	for i in range(m):
		t = path[min(i + 1, m - 1)] - path[max(i - 1, 0)]
		w, u = frame_from(t, flat)
		rings.append([path[i] + w * rr[i] * math.cos(2 * math.pi * (k + phase) / n)
			+ u * rr[i] * ratio * math.sin(2 * math.pi * (k + phase) / n) for k in range(n)])
	return loft(rings, caps, axis=path)


def rot_to(d):
	"""Rotation taking +Y to direction d."""
	d = unit(d)
	v = np.cross(Y_AXIS, d)
	c = float(Y_AXIS @ d)
	if np.linalg.norm(v) < 1e-9:
		return np.eye(3) if c > 0 else np.diag([1., -1, -1])
	vx = A([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
	return np.eye(3) + vx + vx @ vx / (1 + c)


def blob(centre, radii, up=Y_AXIS, n=8, k=3):
	"""A faceted ellipsoid: k rings of n plus two poles."""
	rot = rot_to(up)
	rx, ry, rz = radii
	hs = np.linspace(-1, 1, k + 2)[1:-1]
	rings = []
	for h in hs:
		q = math.sqrt(1 - h * h)
		rings.append([A(centre, float) + rot @ A((rx * q * math.cos(2 * math.pi * m / n), ry * h,
			rz * q * math.sin(2 * math.pi * m / n))) for m in range(n)])
	cap = ry * (1 - abs(hs[0]))
	return loft(rings, (cap, cap))


def box(centre, size, basis=np.eye(3)):
	"""A box; basis columns are its local x, y, z axes."""
	c = A(centre, float)
	hx, hy, hz = A(size, float) / 2
	corners = A([(x, y, z) for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)])
	verts = c + corners @ A(basis, float).T
	quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
	faces = [f for a, b, cc, d in quads for f in ((a, b, cc), (a, cc, d))]
	return dict(V=verts, F=A(faces, int), ax=c[None])


def basis_from(forward, up_hint=Y_AXIS):
	"""Columns: x (right), y (up), z (forward)."""
	z = unit(forward)
	x = unit(np.cross(up_hint, z))
	return np.column_stack([x, np.cross(z, x), z])


def rot_y(g, deg, pivot):
	a = math.radians(deg)
	c, s = math.cos(a), math.sin(a)
	m = A([[c, 0, s], [0, 1, 0], [-s, 0, c]])
	p = A(pivot, float)
	g['V'] = (g['V'] - p) @ m.T + p
	g['ax'] = (g['ax'] - p) @ m.T + p
	return g


def hash01(p):
	return (math.sin(p[0] * 127.1 + p[1] * 311.7 + p[2] * 74.7) * 43758.5453) % 1.0


class Rng:
	"""A tiny deterministic generator (identical across numpy versions)."""

	def __init__(self, seed):
		self.s = seed

	def uniform(self, a, b):
		self.s = (self.s * 1103515245 + 12345) % 2147483648
		return a + (b - a) * self.s / 2147483648


# ------------------------------------------------------------------------------------- the body
class Builder:
	def __init__(self):
		self.parts = []

	def add(self, g, colour, skin, orient='out', surface='body'):
		"""colour: palette key or f(centroid, normal) -> key. skin: bone name, or (J, W) arrays.
		orient: 'out' (face away from the part's axis), 'in' (toward it), 'keep' (as built)."""
		n = len(g['V'])
		if isinstance(skin, str):
			j = np.zeros((n, 4), int)
			j[:, 0] = BONE_INDEX[skin]
			w = np.zeros((n, 4))
			w[:, 0] = 1
		else:
			j, w = skin
		g.update(colour=colour, J=j, W=w, orient=orient, surface=surface)
		self.parts.append(g)
		return g


def blend(values, stops):
	"""Weights along a scalar (height, distance...): stops are (value, bone), smoothstep between."""
	values = np.asarray(values, float)
	pos = [s[0] for s in stops]
	bones = [BONE_INDEX[s[1]] for s in stops]
	j = np.zeros((len(values), 4), int)
	w = np.zeros((len(values), 4))
	w[:, 0] = 1
	for i, v in enumerate(values):
		if v <= pos[0]:
			j[i, 0] = bones[0]
		elif v >= pos[-1]:
			j[i, 0] = bones[-1]
		else:
			k = int(np.searchsorted(pos, v)) - 1
			f = (v - pos[k]) / (pos[k + 1] - pos[k])
			f = f * f * (3 - 2 * f)
			if bones[k] == bones[k + 1]:
				j[i, 0] = bones[k]
			else:
				j[i, 0], w[i, 0], j[i, 1], w[i, 1] = bones[k], 1 - f, bones[k + 1], f
	return j, w


# ----------------------------------------------------------------------------------------- head
# The skin head, from the sheet (front half-width, front z, back z) at each height. Hair covers
# the crown and the back; the face plate covers the front.
HEAD = [  # y,     rx,   z front, z back
	(1.112, .050, .135, .010),
	(1.130, .100, .185, -.010),
	(1.155, .124, .203, -.030),
	(1.190, .138, .212, -.045),
	(1.225, .147, .219, -.068),
	(1.260, .153, .225, -.082),
	(1.300, .155, .229, -.090),
	(1.345, .155, .231, -.096),
	(1.390, .149, .226, -.099),
	(1.430, .137, .210, -.097),
	(1.465, .117, .184, -.087),
	(1.495, .087, .146, -.069),
	(1.515, .045, .092, -.040),
]
HEAD_E = 2.5
_HY = A([h[0] for h in HEAD])


def head_dims(y):
	y = min(max(y, _HY[0]), _HY[-1])
	rx = float(np.interp(y, _HY, [h[1] for h in HEAD]))
	zf = float(np.interp(y, _HY, [h[2] for h in HEAD]))
	zb = float(np.interp(y, _HY, [h[3] for h in HEAD]))
	return rx, (zf - zb) / 2, (zf + zb) / 2


def head_front_z(x, y):
	rx, rz, cz = head_dims(y)
	q = max(0., 1 - abs(x / rx) ** HEAD_E)
	return cz + rz * q ** (1 / HEAD_E)


# Where the face sits in the sheet's front view (pixels), and the sheet's scale.
SHEET_PPM = 187.1             # Tomas is 290 px tall
SHEET_FEET = 640.0
SHEET_CX = 728.5              # refined by a mirror search in the face extractor
FACE_BOX = (696, 370, 760, 434)   # crop (x0, y0, x1, y1) in sheet pixels, 64 x 64
FACE_UPSCALE = 3


def face_uv(x, y, cx=SHEET_CX):
	x0, y0, x1, y1 = FACE_BOX
	return ((cx + SHEET_PPM * x - x0) / (x1 - x0), (SHEET_FEET - SHEET_PPM * y - y0) / (y1 - y0))


def gauss(v, s):
	return math.exp(-(v / s) ** 2)


def relief(x, y):
	"""Height above the head surface: nose, brows, sockets, lips, chin, cheekbones."""
	ax = abs(x)
	h = 0.
	if 1.226 <= y <= 1.315:                         # nose: bridge -> tip -> under
		if y >= 1.244:
			t = min(1., max(0., (1.312 - y) / .068))
			hn, sg = .004 + .021 * t ** 1.5, .010 + .006 * t
		else:
			hn, sg = .025 * max(0., (y - 1.226) / .018), .016
		h += hn * gauss(ax, sg)
	h += .007 * gauss(ax - .017, .007) * gauss(y - 1.236, .007)       # alae
	h += .006 * gauss(y - 1.348, .010) * (1 if ax < .085 else gauss(ax - .085, .025))   # brows
	h -= .006 * gauss(ax - .068, .024) * gauss(y - 1.294, .013)       # eye sockets
	h += .004 * gauss(ax, .030) * gauss(y - 1.192, .008)              # lips
	h += .010 * gauss(ax, .045) * gauss(y - 1.142, .014)              # chin
	h += .004 * gauss(ax - .095, .030) * gauss(y - 1.255, .022)       # cheekbones
	return h


def build_face_plate(b, cx):
	ys = [1.122, 1.134, 1.148, 1.162, 1.176, 1.190, 1.204, 1.218, 1.230, 1.242, 1.256, 1.272,
		1.288, 1.304, 1.322, 1.342, 1.362, 1.385, 1.410]
	fs = [-.92, -.74, -.56, -.40, -.26, -.14, -.05, .05, .14, .26, .40, .56, .74, .92]
	verts, uvs, faces = [], [], []
	ncol = len(fs)
	for j, y in enumerate(ys):
		rx = head_dims(y)[0]
		for i, f in enumerate(fs):
			x = f * rx
			edge = i in (0, ncol - 1) or j in (0, len(ys) - 1)
			verts.append((x, y, head_front_z(x, y) + (.0012 if edge else .0030 + relief(x, y))))
			uvs.append(face_uv(x, y, cx))
	for j in range(len(ys) - 1):
		for i in range(ncol - 1):
			a = j * ncol + i
			faces += [(a, a + 1, a + ncol + 1), (a, a + ncol + 1, a + ncol)]
	g = dict(V=A(verts), F=A(faces, int), ax=A([(0, y, head_dims(y)[2] - .05) for y in ys]), uv=A(uvs))
	b.add(g, 'white', 'head', surface='face')


def build_head(b, cx):
	rings = [ring(y, rx, rz, cz, n=16, e=HEAD_E, phase=0.) for y, rx, rz, cz in
		((h[0],) + head_dims(h[0]) for h in HEAD)]
	b.add(loft(rings, (.006, .004)), 'skin', 'head')
	neck = loft([ring(1.05, .080, .066, -.014, n=10), ring(1.10, .078, .064, -.008, n=10),
		ring(1.17, .074, .064, .006, n=10)], (0, 0))
	b.add(neck, 'neck', blend(neck['V'][:, 1], [(1.07, 'chest'), (1.10, 'neck'), (1.14, 'head')]))
	for s in (1, -1):
		ear = blob((s * .163, 1.286, .010), (.029, .052, .036), unit((s * .25, 1, -.12)), 6, 3)
		b.add(ear, lambda c, n: 'skin_d' if n[0] * np.sign(c[0]) < .3 else 'skin', 'head')
	build_face_plate(b, cx)


# ----------------------------------------------------------------------------------------- hair
def hair_colour(c, n):
	h = hash01(c * 7.3)
	if n[1] > .62:
		return 'hair_l' if h > .25 else 'hair'
	if n[1] < -.2 or (c[1] < 1.29 and h < .5):
		return 'hair_d'
	return 'hair_l' if h > .85 else 'hair'


# Outer silhouette of the hair, measured on the sheet's front and side views.
HAIR = [  # y,     rx,   z front, z back
	(1.205, .112, .040, -.084),
	(1.250, .142, .060, -.095),
	(1.290, .160, .100, -.103),
	(1.330, .174, .200, -.113),
	(1.370, .180, .245, -.123),
	(1.400, .182, .258, -.128),
	(1.432, .178, .257, -.119),
	(1.464, .164, .240, -.100),
	(1.490, .150, .218, -.083),
	(1.513, .128, .188, -.056),
	(1.531, .088, .156, -.020),
	(1.546, .032, .112, .036),
]
_HAY = A([h[0] for h in HAIR])
# The hairline, by azimuth (degrees, 0 = front, + = his left): high in the middle, a lock dipping
# over his right brow, sideburns in front of the ears, the nape at the back.
HAIRLINE = [(-180, 1.212), (-140, 1.226), (-112, 1.282), (-96, 1.330), (-82, 1.302), (-68, 1.338),
	(-50, 1.372), (-30, 1.366), (-14, 1.392), (0, 1.408), (16, 1.424), (34, 1.414), (52, 1.380),
	(68, 1.338), (82, 1.302), (96, 1.330), (112, 1.282), (140, 1.226), (180, 1.212)]


def hair_dims(y):
	y = min(max(y, _HAY[0]), _HAY[-1])
	rx = float(np.interp(y, _HAY, [h[1] for h in HAIR]))
	zf = float(np.interp(y, _HAY, [h[2] for h in HAIR]))
	zb = float(np.interp(y, _HAY, [h[3] for h in HAIR]))
	return rx, (zf - zb) / 2, (zf + zb) / 2


def hairline(deg):
	return float(np.interp(deg, [h[0] for h in HAIRLINE], [h[1] for h in HAIRLINE]))


def build_hair(b):
	"""A helmet of chunky facets whose rings start ON the hairline (so the edge is a real curve),
	tucked to the skull at the lip, then out to the measured silhouette."""
	rng = Rng(11)
	m = 18
	levels = [-1, 0., .14, .32, .52, .72, .88, 1.]       # -1: the lip tucked onto the skull
	top = 1.531
	rings = []
	for li, lv in enumerate(levels):
		r = []
		for k in range(m):
			deg = -180 + 360 * k / m
			t = math.radians(deg)
			ye = hairline(deg)
			s, c = signed_pow(math.sin(t), 2 / 2.3), signed_pow(math.cos(t), 2 / 2.3)
			if lv < 0:
				hx, hz, hc = head_dims(ye + .002)
				sk, ck = signed_pow(math.sin(t), 2 / HEAD_E), signed_pow(math.cos(t), 2 / HEAD_E)
				r.append((hx * sk * 1.02, ye + .002, hc + hz * ck * 1.02))
				continue
			y = ye + (top - ye) * lv ** .9 if lv > 0 else ye - .004
			rx, rz, cz = hair_dims(y)
			jit = 1 + rng.uniform(-.03, .03) * (lv > 0)
			r.append((rx * s * jit, y + rng.uniform(-.005, .005) * (0 < lv < 1), cz + rz * c * jit))
		rings.append(r)
	ax = [(0, 1.30, .03), (0, 1.38, .05), (0, 1.46, .05), (0, 1.52, .05)]
	g = loft(rings, (None, .017), axis=resample(ax, 4))
	b.add(g, hair_colour, 'head')


# ---------------------------------------------------------------------------------------- torso
TORSO = [  # y,    rx,   z front, z back
	(0.640, .156, .104, -.098),
	(0.700, .154, .106, -.097),
	(0.760, .155, .116, -.099),
	(0.830, .157, .132, -.104),
	(0.900, .161, .146, -.108),
	(0.960, .165, .147, -.108),
	(1.010, .170, .132, -.101),
	(1.050, .168, .108, -.090),
	(1.085, .142, .082, -.078),
	(1.105, .085, .060, -.062),
]
TORSO_E = 2.4
_TY = A([t[0] for t in TORSO])


def torso_dims(y):
	rx = float(np.interp(y, _TY, [t[1] for t in TORSO]))
	zf = float(np.interp(y, _TY, [t[2] for t in TORSO]))
	zb = float(np.interp(y, _TY, [t[3] for t in TORSO]))
	return rx, (zf - zb) / 2, (zf + zb) / 2


def torso_skin(v):
	return blend(v[:, 1], [(.70, 'hips'), (.80, 'spine'), (.86, 'spine'), (.95, 'chest')])


def build_torso(b):
	rings = [ring(y, *torso_dims(y), n=14, e=TORSO_E) for y in _TY]
	g = loft(rings, (.0, .01))
	b.add(g, 'shirt', torso_skin(g['V']))


VEST_Y = [.745, .80, .86, .92, .98, 1.03, 1.065, 1.092]
VEST_OPEN = [.060, .060, .062, .066, .074, .084, .092, .098]   # half-width of the front opening


def super_point(t, rx, rz, cz, e):
	s, c = math.sin(t), math.cos(t)
	return signed_pow(s, 2 / e) * rx, cz + signed_pow(c, 2 / e) * rz


def build_vest(b):
	m = 17
	outer, inner = [], []
	for y, xo in zip(VEST_Y, VEST_OPEN):
		rx, rz, cz = torso_dims(y)
		lo, hi = 0., math.pi / 2                   # solve x(t) = opening on the front quarter
		for _ in range(40):
			mid = (lo + hi) / 2
			if super_point(mid, rx, rz, cz, TORSO_E)[0] < xo:
				lo = mid
			else:
				hi = mid
		t0 = lo
		ro, ri = [], []
		for k in range(m):
			t = t0 + (2 * math.pi - 2 * t0) * k / (m - 1)
			x, z = super_point(t, rx, rz, cz, TORSO_E)
			d = unit((x / rx ** 2, 0, (z - cz) / rz ** 2))
			ro.append(A((x, y, z)) + d * .013)
			ri.append(A((x, y, z)) + d * .007)
		outer.append(ro)
		inner.append(ri)
	ax = [(0, y, -.01) for y in VEST_Y]

	def vest_colour(c, n):
		return 'vest_d' if (n[2] < -.3 and c[1] > 1.0) or n[1] < -.4 else 'vest'
	go, gi = loft(outer, None, False, axis=ax), loft(inner, None, False, axis=ax)
	b.add(go, vest_colour, torso_skin(go['V']))
	b.add(gi, 'vest_in', torso_skin(gi['V']), orient='in')


def arm_skin(v, d):
	return blend(v[:, 1], [(.625, 'hand' + d), (.66, 'forearm' + d), (.76, 'forearm' + d),
		(.83, 'upper_arm' + d), (.97, 'upper_arm' + d), (1.0, 'shoulder' + d)])


def build_arms(b):
	for s, d in ((1, '_l'), (-1, '_r')):
		sh, el, wr = bone_pos('upper_arm' + d), bone_pos('forearm' + d), bone_pos('hand' + d)
		sleeve = tube([(s * .12, 1.045, -.012), sh + (0, .005, 0), (sh + el) / 2, el + (s * -.008, .04, 0)],
			[.064, .074, .075, .070], 8, 1., X_AXIS, caps=(0, .01))
		b.add(sleeve, 'shirt', arm_skin(sleeve['V'], d))
		cuff = tube([el + (s * -.006, .045, 0), el + (s * .001, .002, 0), el + (s * .006, -.03, 0)],
			[.080, .082, .074], 8, 1., X_AXIS, caps=(.0, .012), phase=.5)
		b.add(cuff, lambda c, n: 'shirt_d' if n[1] < -.35 else 'shirt', arm_skin(cuff['V'], d))
		fore = tube([el + (s * .003, -.01, 0), (el + wr) / 2, wr + (0, .01, 0)], [.055, .049, .043], 6, 1., X_AXIS, caps=(0, .005))
		b.add(fore, 'skin', arm_skin(fore['V'], d))
		build_hand(b, s, d, wr)


def build_hand(b, s, d, wr):
	"""Big stylised hands (the sheet's are ~17 cm wrist to fingertip)."""
	bone = 'hand' + d
	down = unit((s * .12, -1, .03))
	turn = math.radians(35 if s < 0 else 0)   # the open hand turns its back a little to the front
	med = A((-s * math.cos(turn), 0., -math.sin(turn)))     # palm faces the thigh
	fwd = A((-s * math.sin(turn), 0., math.cos(turn)))
	palm_c = wr + down * .048
	b.add(blob(palm_c, (.023, .050, .044), down, 6, 3), 'skin', bone)   # thickness, length, width
	if s > 0:                             # left: a fist round the wrench shaft
		grip = wr + down * .070 + med * .024
		for zf in (-.032, -.011, .011, .032):
			pts = [grip + down * -.010 - med * .034 + fwd * zf, grip + down * .028 - med * .008 + fwd * zf,
				grip + down * .022 + med * .026 + fwd * zf, grip + down * -.010 + med * .030 + fwd * zf]
			b.add(tube(pts, [.0140, .0135, .0125, .011], 5, 1., fwd, caps=(.003, .005)), 'skin', bone)
		thumb = [wr + down * .028 + fwd * .038 + med * .006, grip + down * -.014 + fwd * .052 + med * .022,
			grip + down * .008 + fwd * .048 + med * .034]
		b.add(tube(thumb, [.015, .013, .011], 5, 1., med, caps=(.003, .006)), 'skin', bone)
	else:                                 # right: open, fingers relaxed and a little curled
		for zf, ln in ((-.031, .064), (-.011, .078), (.011, .080), (.031, .068)):
			k0 = palm_c + down * .044 + fwd * zf
			pts = [k0, k0 + down * ln * .55 + med * .008, k0 + down * ln * .95 + med * .028]
			b.add(tube(pts, [.0128, .0115, .0095], 5, 1., fwd, caps=(.002, .006)), 'skin', bone)
		thumb = [wr + down * .024 + fwd * .038 + med * .010, wr + down * .062 + fwd * .056 + med * .024,
			wr + down * .092 + fwd * .054 + med * .030]
		b.add(tube(thumb, [.015, .013, .010], 5, 1., med, caps=(.002, .006)), 'skin', bone)


# -------------------------------------------------------------------------- trousers and boots
PELVIS = [  # y,     rx,   z front, z back
	(0.735, .150, .098, -.094),
	(0.690, .158, .103, -.097),
	(0.625, .166, .106, -.100),
	(0.565, .170, .100, -.102),
	(0.520, .152, .086, -.088),
	(0.497, .085, .050, -.055),
]


def leg_skin(v, d):
	return blend(v[:, 1], [(.11, 'foot' + d), (.16, 'shin' + d), (.33, 'shin' + d), (.39, 'thigh' + d),
		(.58, 'thigh' + d), (.66, 'hips')])


def build_legs(b):
	rings = [ring(y, rx, (zf - zb) / 2, (zf + zb) / 2, n=14, e=2.3) for y, rx, zf, zb in PELVIS]
	b.add(loft(rings, (0, .01)), 'trousers', 'hips')
	for s, d in ((1, '_l'), (-1, '_r')):
		legs = [(.605, .088, .105, .000), (.505, .088, .108, .004), (.425, .082, .111, .008),
			(.360, .080, .113, .013), (.300, .077, .115, .008), (.250, .079, .117, .002)]
		g = loft([ring(y, r, r * 1.02, z, cx=s * x, n=10, e=2.2) for y, r, x, z in legs], (0, 0))

		def trouser_colour(c, n):
			return 'trousers_d' if (.33 < c[1] < .40 and hash01(c * 3.1) < .5) or n[1] < -.5 else 'trousers'
		b.add(g, trouser_colour, leg_skin(g['V'], d))
		cuff = loft([ring(y, r, r, z, cx=s * .118, n=10, e=2.2) for y, r, z in    # the boots' turned-down tops
			((.262, .080, .002), (.252, .093, .0), (.176, .095, -.004), (.166, .081, -.006))], (0, 0))
		b.add(cuff, lambda c, n: 'boot' if n[1] > .4 else 'boot_d', leg_skin(cuff['V'], d))
		build_boot(b, s, d)


def build_boot(b, s, d):
	bx, bone = s * .118, 'foot' + d
	shaft = loft([ring(y, .070, .072, -.012, cx=bx, n=10, e=2.4) for y in (.185, .14, .105)], (0, 0))
	b.add(shaft, 'boot', leg_skin(shaft['V'], d))
	foot = [  # z,     rx,   ry,   y centre
		(-.090, .050, .042, .062), (-.060, .062, .060, .070), (.000, .066, .060, .068),
		(.060, .064, .050, .058), (.120, .060, .041, .050), (.165, .052, .033, .043), (.190, .036, .022, .040)]
	rings = [A([(bx + rx * math.cos(2 * math.pi * (k + .5) / 10), yc + ry * math.sin(2 * math.pi * (k + .5) / 10), z)
		for k in range(10)]) for z, rx, ry, yc in foot]
	g = loft(rings, (.012, .014))
	b.add(rot_y(g, s * 6, (bx, 0, -.01)), lambda c, n: 'boot_d' if n[1] < -.3 else 'boot', bone)
	sole = [(-.096, .052), (-.06, .064), (.0, .068), (.06, .066), (.12, .062), (.17, .052), (.198, .034)]
	rings = [A([(bx + rx * math.cos(2 * math.pi * (k + .5) / 10), .011 + .011 * math.sin(2 * math.pi * (k + .5) / 10), z)
		for k in range(10)]) for z, rx in sole]
	g = loft(rings, (.004, .006))
	b.add(rot_y(g, s * 6, (bx, 0, -.01)), 'sole', bone)


# ------------------------------------------------------------------------- belt, pouches, tools
def build_belt(b):
	m = 18
	rows = []
	for y, off in ((.640, .004), (.647, .016), (.706, .016), (.714, .004)):
		rx, rz, cz = .158, .100, -.003
		rows.append([(math.sin(2 * math.pi * k / m) * (rx + off), y, cz + math.cos(2 * math.pi * k / m) * (rz + off))
			for k in range(m)])
	b.add(loft(rows, None, True, axis=[(0, .64, 0), (0, .71, 0)]), 'belt', 'hips')
	zf = .097 + .016
	b.add(box((0, .676, zf + .006), (.088, .062, .012)), 'metal', 'hips')          # the big buckle
	b.add(box((-.004, .676, zf + .010), (.056, .034, .010)), 'belt_d', 'hips')
	b.add(box((.002, .676, zf + .016), (.012, .036, .006)), 'metal', 'hips')
	for s in (1, -1):                                                             # big pouches
		fwd = unit((s * .62, 0, .78))
		bas = basis_from(fwd)
		c = A((s * .168, .585, .060))
		b.add(box(c, (.118, .150, .058), bas), 'pouch', 'hips')
		b.add(box(c + bas @ A((0, .052, .004)), (.124, .056, .066), bas), 'pouch_d', 'hips')
		b.add(box(c + bas @ A((0, .030, .038)), (.020, .016, .008), bas), 'metal', 'hips')
		b.add(box(c + bas @ A((0, .088, -.006)), (.030, .040, .040), bas), 'belt_d', 'hips')   # loop over the belt
	# his right pouch: a spanner's ring head sticking up, a screwdriver hanging behind
	b.add(box((-.215, .700, .062), (.016, .070, .030)), 'metal', 'hips')
	b.add(blob((-.215, .748, .062), (.014, .028, .028), X_AXIS, 6, 2), 'metal_d', 'hips')
	b.add(tube([(-.228, .560, -.010), (-.235, .490, -.016)], [.016, .015], 5, 1., X_AXIS, caps=(.004, .004)), 'handle', 'hips')
	b.add(tube([(-.235, .490, -.016), (-.240, .420, -.020)], [.0055, .005], 4, 1., X_AXIS, caps=(.001, .003)), 'metal', 'hips')
	# his left pouch: pliers handles
	for dz in (-.012, .012):
		b.add(tube([(.205, .64, .060 + dz), (.214, .728, .066 + dz * 1.7)], [.0085, .0075], 4, 1., X_AXIS, caps=(.002, .005)),
			'metal_d', 'hips')


WRENCH_AXIS = unit((-.12, -.26, .96))     # back end up, front end down and a little in (the sheet)
WRENCH_HALF = .232                        # grip to each jaw's centre is HALF + .030


def wrench_grip():
	return bone_pos('hand_l') + unit((.12, -1, .03)) * .070 + A((-.024, 0, 0))


def build_wrench(b):
	"""A big double open-ended spanner through the left fist, pointing forward and a bit down."""
	grip = wrench_grip()
	ax = WRENCH_AXIS
	nrm = unit(X_AXIS - (X_AXIS @ ax) * ax)  # the flat faces look sideways
	wd = np.cross(nrm, ax)                   # in-plane width direction
	half, thick = WRENCH_HALF, .011
	sv, sf = [], []
	for t, w in ((-half, .024), (0, .027), (half, .024)):
		for sw in (-1, 1):
			for sn in (-1, 1):
				sv.append(grip + ax * t + wd * w * sw + nrm * thick * sn)
	sv = A(sv)

	def idx(i, sw, sn):
		return i * 4 + (sw > 0) * 2 + (sn > 0)
	for i in range(2):
		for sw, sn, ow, on in ((1, -1, 1, 1), (1, 1, -1, 1), (-1, 1, -1, -1), (-1, -1, 1, -1)):
			a, bb = idx(i, sw, sn), idx(i, ow, on)
			c, dd = idx(i + 1, ow, on), idx(i + 1, sw, sn)
			sf += [(a, bb, c), (a, c, dd)]
	shaft = dict(V=sv, F=A(sf, int), ax=A([grip + ax * t for t in np.linspace(-half, half, 5)]))
	b.add(shaft, 'metal', 'hand_l')
	for end in (-1, 1):
		centre = grip + ax * end * (half + .030)
		tilt = math.radians(15 * end)            # open side faces away from the shaft, tilted 15 deg
		u2 = unit(ax * end * math.cos(tilt) + wd * math.sin(tilt))
		v2 = np.cross(nrm, u2)
		ro, ri, gap = .064, .030, math.radians(38)
		pts = []
		for a in np.linspace(gap, 2 * math.pi - gap, 9):
			d2 = u2 * math.cos(a) + v2 * math.sin(a)
			pts.append((centre + d2 * ro, centre + d2 * ri))
		vv, ff = [], []
		for po, pi_ in pts:
			for p in (po, pi_):
				vv += [p + nrm * thick * 1.15, p - nrm * thick * 1.15]
		vv = A(vv)
		# per angle i: 4i outer-top, 4i+1 outer-bottom, 4i+2 inner-top, 4i+3 inner-bottom
		for i in range(len(pts) - 1):
			ot, ob, it, ib = 4 * i, 4 * i + 1, 4 * i + 2, 4 * i + 3
			ot2, ob2, it2, ib2 = ot + 4, ob + 4, it + 4, ib + 4
			ff += [(ot, ot2, it2), (ot, it2, it)]            # top (+nrm), counter-clockwise about +nrm
			ff += [(ob, ib2, ob2), (ob, ib, ib2)]            # bottom
			ff += [(ob, ob2, ot2), (ob, ot2, ot)]            # outer wall
			ff += [(ib2, ib, it), (ib2, it, it2)]            # inner wall
		last = 4 * (len(pts) - 1)
		ff += [(1, 0, 2), (1, 2, 3), (last + 1, last + 3, last + 2), (last + 1, last + 2, last)]   # jaw tips
		g = dict(V=vv, F=A(ff, int), ax=centre[None])
		if np.dot(np.cross(u2, v2), nrm) < 0:    # the winding above assumes (u2, v2, nrm) right-handed
			g['F'] = g['F'][:, [0, 2, 1]]
		b.add(g, lambda c, n: 'metal_d' if abs(n @ nrm) < .5 else 'metal', 'hand_l', orient='keep')


# ------------------------------------------------------------------------------------- assembly
def build_parts(face_cx=SHEET_CX):
	b = Builder()
	build_legs(b)
	build_torso(b)
	build_vest(b)
	build_belt(b)
	build_arms(b)
	build_head(b, face_cx)
	build_hair(b)
	build_wrench(b)
	return b.parts


def flatten(parts):
	"""Unshared, flat-shaded triangles grouped by surface: positions, normals, colours, joints,
	weights (+ uv for the face)."""
	out = {}
	for p in parts:
		v, f, ax = p['V'], p['F'], p['ax']
		q = v[f]
		n = np.cross(q[:, 1] - q[:, 0], q[:, 2] - q[:, 0])
		ln = np.linalg.norm(n, axis=1)
		cen = q.mean(1)
		for i in range(len(f)):
			if ln[i] < 1e-12:
				continue
			c = cen[i]
			nn = n[i] / ln[i]
			fi = f[i]
			if p['orient'] != 'keep':
				a = ax[np.argmin(((ax - c) ** 2).sum(1))]
				bad = nn @ (c - a) < 0
				if p['orient'] == 'in':
					bad = not bad
				if bad:
					fi, nn = fi[[0, 2, 1]], -nn
			col = p['colour']
			key = col if isinstance(col, str) else col(c, nn)
			rgb = A(PALETTE[key], float)
			if p['surface'] == 'body':
				rgb = np.clip(rgb * (1 + FACET_TONE * (2 * hash01(c * 13.7) - 1)), 0, 1)
			d = out.setdefault(p['surface'], dict(P=[], N=[], C=[], J=[], W=[], UV=[]))
			d['P'] += list(v[fi])
			d['N'] += [nn] * 3
			d['C'] += [rgb] * 3
			d['J'] += list(p['J'][fi])
			d['W'] += list(p['W'][fi])
			if 'uv' in p:
				d['UV'] += list(p['uv'][fi])
	for d in out.values():
		for k in list(d):
			d[k] = A(d[k], float) if d[k] else None
		d['J'] = d['J'].astype(int)
		w = d['W']
		d['W'] = w / w.sum(1, keepdims=True)
	return out


# ------------------------------------------------------------------------------- face texture
def cut_face(sheet_path, out_png):
	"""Front-view face from the concept sheet -> a small symmetric 5-bit texture.

	The face is tiny on the sheet (about 57 x 55 px), so: find the mirror axis, crop, upscale x3
	Lanczos, mirror the key-lit half onto the other, pull only the broad colour to the palette skin
	(so the plate meets the vertex-coloured head without a seam; eyes, brows, nose shading and the
	frown keep their contrast), paint what lies outside the face (hair, background) with hair/skin,
	mild unsharp mask, quantise to 5 bits per channel. Returns the axis (sheet x pixel)."""
	from PIL import Image, ImageFilter
	from scipy import ndimage as ndi
	sheet = np.asarray(Image.open(sheet_path).convert('RGB')).astype(float) / 255
	x0, y0, x1, y1 = FACE_BOX
	band = sheet[392:424].mean(2)                 # brows to mouth
	cols = np.arange(sheet.shape[1])
	best, cx = 1e9, SHEET_CX
	for c2 in np.arange(SHEET_CX - 3, SHEET_CX + 3.01, .25):
		xs = np.arange(3, 22, .5)
		err = np.mean([(np.interp(c2 - xs, cols, row) - np.interp(c2 + xs, cols, row)) ** 2 for row in band])
		if err < best:
			best, cx = err, float(c2)
	ups = FACE_UPSCALE
	w, h = x1 - x0, y1 - y0
	crop = Image.fromarray((sheet[y0:y1, x0:x1] * 255 + .5).astype('uint8'))
	big = np.asarray(crop.resize((w * ups, h * ups), Image.LANCZOS)).astype(float) / 255
	acx = (cx - x0) * ups                          # axis in upscaled pixels
	W = w * ups
	xx = np.arange(W) + .5
	left = xx < acx
	keep_left = big[:, left].mean() > big[:, ~left].mean()
	sym = big.copy()
	for i in range(W):
		src = int(math.floor(2 * acx - xx[i]))
		if 0 <= src < W and (left[i] != keep_left):
			sym[:, i] = big[:, src]
	r, g, bl = sym[..., 0], sym[..., 1], sym[..., 2]
	lum = sym.mean(2)
	skin = (r > .38) & (r > g * 1.15) & (g > bl * 1.0) & (lum > .30) & (r - bl > .16)
	skin = ndi.binary_opening(skin, iterations=1)
	# the face: on each row, everything between the outermost skin pixels (keeps eyes and brows)
	rows = np.arange(h * ups)
	hair_row = (SHEET_FEET - SHEET_PPM * 1.392 - y0) * ups
	face = np.zeros_like(skin)
	for j in rows:
		idx = np.nonzero(skin[j])[0]
		if len(idx) > 4 and j >= hair_row - 2 * ups:
			face[j, idx[0]:idx[-1] + 1] = True
	face = ndi.binary_closing(face, iterations=2)
	# broad colour -> palette skin, measured on plain skin only, applied to the whole face
	target = A(PALETTE['skin'])
	est = (skin & face).astype(float)
	sg = 6 * ups
	den = ndi.gaussian_filter(est, sg) + 1e-6
	low = np.stack([ndi.gaussian_filter(sym[..., k] * est, sg) / den for k in range(3)], 2)
	gain = np.clip(target / np.maximum(low, .05), .6, 2.0)
	out = np.clip(sym * gain, 0, 1)
	out[~face & (rows[:, None] < hair_row)] = PALETTE['hair']
	out[~face & (rows[:, None] >= hair_row)] = target
	soft = ndi.gaussian_filter(face.astype(float), 1.5)[..., None]
	fill = np.where(rows[:, None, None] < hair_row, A(PALETTE['hair']), target)
	out = out * soft + fill * (1 - soft)
	img = Image.fromarray((out * 255 + .5).astype('uint8')).filter(ImageFilter.UnsharpMask(radius=1.2, percent=50, threshold=2))
	a = np.round(np.asarray(img).astype(float) / 255 * 31) / 31
	Image.fromarray((a * 255 + .5).astype('uint8')).save(out_png)
	return cx


# ------------------------------------------------------------------------------------ animation
def quat(axis, deg):
	a = math.radians(deg) / 2
	axis = unit(axis)
	return np.concatenate([axis * math.sin(a), [math.cos(a)]])     # x, y, z, w


def qmul(a, b):
	ax, ay, az, aw = a
	bx, by, bz, bw = b
	return A([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
		aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])


def qeuler(rx, ry, rz):
	"""X first, then Y, then Z (all about the parent's axes)."""
	return qmul(quat(Z_AXIS, rz), qmul(quat(Y_AXIS, ry), quat(X_AXIS, rx)))


def qmat(q):
	x, y, z, w = q
	return A([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
		[2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
		[2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def smooth(x):
	x = min(max(x, 0.), 1.)
	return x * x * (3 - 2 * x)


def keyed(t, keys):
	"""Piecewise smooth interpolation through (time, value) keys; value may be a tuple."""
	for i in range(len(keys) - 1):
		t0, v0 = keys[i]
		t1, v1 = keys[i + 1]
		if t0 <= t <= t1:
			f = smooth((t - t0) / max(t1 - t0, 1e-9))
			return A(v0, float) * (1 - f) + A(v1, float) * f
	return A(keys[-1][1], float)


def side(s, rx, ry, rz):
	"""Mirror an (x, y, z) Euler rotation authored for the left side to side s."""
	return (rx, s * ry, s * rz)


def pose_idle(t, dur):
	w = 2 * math.pi * t / dur
	b = math.sin(w)                                  # one breath per loop
	p = {'spine': (-.8 * b, 0, 0), 'chest': (-1.2 * b, 1.5 * math.sin(w + .6), 0),
		'neck': (.6 * b, 0, 0), 'head': (1.5 * math.sin(w * 2 + 1), 4 * math.sin(w + 2.2), 1.2 * math.sin(w)),
		'hips': (0, 0, 1.0 * math.sin(w))}
	for s, d in ((1, '_l'), (-1, '_r')):
		p['upper_arm' + d] = side(s, 1.5 * math.sin(w + 1.2 * s), 0, -1.0 + .8 * b)
		p['forearm' + d] = side(s, -4 - 2 * math.sin(w + .5), 0, 0)
		p['shoulder' + d] = side(s, 0, 0, .8 * b)
		p['thigh' + d] = side(s, 0, 0, -1.0 * math.sin(w) * s)
	p['hand_l'] = (0, 0, 0)
	return p, (0, -.002 * (1 - b) * .5, 0)


def pose_walk(t, dur):
	"""In place. Left leg forward at t=0; arms counter-swing; two bobs per cycle."""
	w = 2 * math.pi * t / dur
	p = {'hips': (0, 6 * math.sin(w), -2 * math.cos(w)), 'spine': (3, 0, 0), 'chest': (0, -9 * math.sin(w), 2 * math.cos(w)),
		'neck': (0, 2 * math.sin(w), 0), 'head': (-2, 1 * math.sin(w), 0)}
	for s, d, ph in ((1, '_l', 0.), (-1, '_r', math.pi)):
		c = math.cos(w + ph)                         # +1: this leg fully forward
		sw = math.sin(w + ph)                        # >0: leg moving back (stance), <0: swinging forward
		thigh = -26 * c
		knee = 6 + (44 * max(0., -sw) ** 1.3 if True else 0)
		knee *= 1 if c < .85 else .6
		p['thigh' + d] = side(s, thigh, 0, 0)
		p['shin' + d] = side(s, knee, 0, 0)
		p['foot' + d] = side(s, -(thigh + knee) * .75 - 6 * max(0., c) + 10 * max(0., -c) * max(0., sw), 0, 0)
		p['upper_arm' + d] = side(s, 22 * c * (.7 if s > 0 else 1.), 0, -2)
		p['forearm' + d] = side(s, -14 - 10 * max(0., -c), 0, 0)
		p['shoulder' + d] = side(s, 0, 0, 0)
	bob = .022 * math.cos(2 * w) - .006
	return p, (0, bob, 0)


def pose_talk(t, dur):
	"""Grumbling: the free right hand makes two points, head nods, a shrug at the end."""
	w = 2 * math.pi * t / dur
	beat = max(0., math.sin(w * 2)) ** 2
	shrug = keyed(t / dur, [(0, 0), (.70, 0), (.80, 1), (.92, 0), (1, 0)])
	shrug = float(shrug)
	p = {'chest': (-2 * beat, -6 + 3 * math.sin(w), 0), 'spine': (0, -3, 0),
		'neck': (2 * beat, 0, 0), 'head': (5 * beat - 3 * shrug, 6 + 4 * math.sin(w + .4), 4 * math.sin(w * .5) - 5 * shrug),
		'hips': (0, 2, 0)}
	p['upper_arm_r'] = side(-1, -28 - 8 * beat - 8 * shrug, 0, 4 - 3 * shrug)
	p['forearm_r'] = side(-1, -62 - 18 * beat + 10 * shrug, -30, 0)
	p['hand_r'] = side(-1, 10 - 25 * beat, -25 - 35 * shrug, 0)
	p['upper_arm_l'] = side(1, -4 + 3 * math.sin(w), 0, -2)
	p['forearm_l'] = side(1, -8 + 4 * math.sin(w), 0, 0)
	for s, d in ((1, '_l'), (-1, '_r')):
		p['shoulder' + d] = side(s, 0, 0, 9 * shrug)
	return p, (0, 0, 0)


WORK_KEYS = [  # (phase, upper_arm_l, forearm_l, hand_l, chest, spine)
	(0.00, (-35, 0, -16), (-50, 0, 0), (0, 0, 0), (0, 4, 0), (0, 0, 0)),
	(0.40, (-122, -10, -26), (-105, 0, 0), (-38, 0, 0), (-4, 14, 0), (-3, 4, 0)),      # wind up
	(0.55, (-78, -6, -22), (-34, 0, 0), (32, 0, 0), (6, -10, 0), (4, -4, 0)),          # strike
	(0.60, (-74, -6, -22), (-30, 0, 0), (36, 0, 0), (7, -12, 0), (4, -5, 0)),          # impact
	(0.70, (-80, -6, -20), (-42, 0, 0), (24, 0, 0), (5, -9, 0), (3, -3, 0)),           # recoil
	(1.00, (-35, 0, -16), (-50, 0, 0), (0, 0, 0), (0, 4, 0), (0, 0, 0)),
]


def pose_work(t, dur):
	"""Hitting the brass machine with the wrench at chest height; the right hand braces on it."""
	ph = t / dur
	ua = keyed(ph, [(k[0], k[1]) for k in WORK_KEYS])
	fa = keyed(ph, [(k[0], k[2]) for k in WORK_KEYS])
	ha = keyed(ph, [(k[0], k[3]) for k in WORK_KEYS])
	ch = keyed(ph, [(k[0], k[4]) for k in WORK_KEYS])
	sp = keyed(ph, [(k[0], k[5]) for k in WORK_KEYS])
	hit = float(keyed(ph, [(0, 0), (.58, 0), (.61, 1), (.75, 0), (1, 0)]))
	p = {'upper_arm_l': tuple(ua), 'forearm_l': tuple(fa), 'hand_l': tuple(ha), 'chest': tuple(ch), 'spine': tuple(sp),
		'hips': (0, -4, 0), 'neck': (6, 0, 0), 'head': (8 + 3 * hit, -4, 0),
		'upper_arm_r': side(-1, -58, 0, -6), 'forearm_r': side(-1, -40, 0, 0), 'hand_r': side(-1, -20, 0, 0),
		'thigh_l': (-8, 0, 0), 'shin_l': (10, 0, 0), 'foot_l': (-2, 0, 0),
		'thigh_r': (6, 0, 0), 'shin_r': (4, 0, 0), 'foot_r': (-10, 0, 0),
		'shoulder_l': side(1, 0, 0, 4 - 6 * hit)}
	return p, (0, -.01 - .006 * hit, .005)


ANIMATIONS = {  # name: (pose function, seconds) - every loop starts where it ends
	'idle': (pose_idle, 3.2),
	'walk': (pose_walk, 1.0),
	'talk': (pose_talk, 2.4),
	'work': (pose_work, 1.2),
}
ANIM_FPS = 15


def local_rotations(pose):
	return {n: qeuler(*pose.get(n, (0, 0, 0))) for n in BONE_NAMES}


def bone_matrices(pose=None, hips_offset=(0, 0, 0)):
	"""Global 4x4 per bone for a pose ({bone: euler degrees}); rest when pose is None."""
	rots = local_rotations(pose or {})
	g = {}
	for n in BONE_NAMES:
		parent, p = BONES[n]
		m = np.eye(4)
		m[:3, :3] = qmat(rots[n])
		m[:3, 3] = A(p, float) - (A(BONES[parent][1], float) if parent else 0)
		if n == 'hips':
			m[:3, 3] += A(hips_offset, float)
		g[n] = g[parent] @ m if parent else m
	return g


def skin_matrices(pose=None, hips_offset=(0, 0, 0)):
	g = bone_matrices(pose, hips_offset)
	out = np.zeros((len(BONE_NAMES), 4, 4))
	for i, n in enumerate(BONE_NAMES):
		inv = np.eye(4)
		inv[:3, 3] = -bone_pos(n)
		out[i] = g[n] @ inv
	return out


def wrench_tip(pose, hips_offset=(0, 0, 0)):
	"""World position of the wrench's front jaw centre in a pose (for tuning the work hit)."""
	tip = wrench_grip() + WRENCH_AXIS * (WRENCH_HALF + .030)
	m = skin_matrices(pose, hips_offset)[BONE_INDEX['hand_l']]
	return (m @ np.append(tip, 1))[:3]


# --------------------------------------------------------------------------------------- export
def export_glb(surfaces, face_png, path):
	buf = bytearray()
	views, accessors = [], []

	def accessor(arr, ctype, typ, minmax=False, target=None):
		while len(buf) % 4:
			buf.append(0)
		raw = arr.tobytes()
		view = {'buffer': 0, 'byteOffset': len(buf), 'byteLength': len(raw)}
		if target:
			view['target'] = target
		views.append(view)
		buf.extend(raw)
		acc = {'bufferView': len(views) - 1, 'componentType': ctype, 'count': len(arr), 'type': typ}
		if minmax:
			acc['min'] = np.atleast_1d(arr.min(0)).astype(float).tolist()
			acc['max'] = np.atleast_1d(arr.max(0)).astype(float).tolist()
		accessors.append(acc)
		return len(accessors) - 1

	nb = len(BONE_NAMES)
	nodes = []
	for n in BONE_NAMES:
		parent, p = BONES[n]
		off = A(p, float) - (A(BONES[parent][1], float) if parent else 0)
		nodes.append({'name': n, 'translation': off.tolist()})
	for n in BONE_NAMES:
		parent = BONES[n][0]
		if parent:
			nodes[BONE_INDEX[parent]].setdefault('children', []).append(BONE_INDEX[n])
	nodes.append({'name': 'Tomas', 'mesh': 0, 'skin': 0})
	ibm = np.zeros((nb, 16), np.float32)
	for i, n in enumerate(BONE_NAMES):
		m = np.eye(4)
		m[:3, 3] = -bone_pos(n)
		ibm[i] = m.flatten('F')
	skin = {'name': 'TomasSkin', 'joints': list(range(nb)), 'skeleton': 0, 'inverseBindMatrices': accessor(ibm, 5126, 'MAT4')}

	png = open(face_png, 'rb').read()
	while len(buf) % 4:
		buf.append(0)
	views.append({'buffer': 0, 'byteOffset': len(buf), 'byteLength': len(png)})
	buf.extend(png)
	image_view = len(views) - 1

	prims, materials = [], []
	for name in ('body', 'face'):
		d = surfaces[name]
		attrs = {'POSITION': accessor(d['P'].astype(np.float32), 5126, 'VEC3', True, 34962),
			'NORMAL': accessor(d['N'].astype(np.float32), 5126, 'VEC3', False, 34962),
			'COLOR_0': accessor(d['C'].astype(np.float32), 5126, 'VEC3', False, 34962),
			'JOINTS_0': accessor(d['J'].astype(np.uint8), 5121, 'VEC4', False, 34962),
			'WEIGHTS_0': accessor(d['W'].astype(np.float32), 5126, 'VEC4', False, 34962)}
		pbr = {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 1}
		if name == 'face':
			attrs['TEXCOORD_0'] = accessor(d['UV'].astype(np.float32), 5126, 'VEC2', False, 34962)
			pbr['baseColorTexture'] = {'index': 0}
		prims.append({'attributes': attrs, 'material': len(materials), 'mode': 4})
		materials.append({'name': 'tomas_' + name, 'pbrMetallicRoughness': pbr})

	anims = []
	for aname, (fn, dur) in ANIMATIONS.items():
		nk = int(round(dur * ANIM_FPS))
		times = A([i / ANIM_FPS for i in range(nk + 1)], np.float32)
		times[-1] = dur
		samples = [fn(float(t) % dur if i < nk else 0., dur) for i, t in enumerate(times)]
		tin = accessor(times, 5126, 'SCALAR', True)
		samplers, channels = [], []
		for bn in BONE_NAMES:
			if bn == 'root':
				continue
			q = A([qeuler(*s[0].get(bn, (0, 0, 0))) for s in samples], np.float32)
			if np.allclose(q, A([0, 0, 0, 1], np.float32), atol=1e-6):
				continue
			samplers.append({'input': tin, 'output': accessor(q, 5126, 'VEC4'), 'interpolation': 'LINEAR'})
			channels.append({'sampler': len(samplers) - 1, 'target': {'node': BONE_INDEX[bn], 'path': 'rotation'}})
		tr = A([bone_pos('hips') + A(s[1], float) for s in samples], np.float32)
		samplers.append({'input': tin, 'output': accessor(tr, 5126, 'VEC3'), 'interpolation': 'LINEAR'})
		channels.append({'sampler': len(samplers) - 1, 'target': {'node': BONE_INDEX['hips'], 'path': 'translation'}})
		anims.append({'name': aname, 'samplers': samplers, 'channels': channels})

	gltf = {'asset': {'version': '2.0', 'generator': 'witch tools/characters/tomas.py'},
		'scene': 0, 'scenes': [{'name': 'Tomas', 'nodes': [0, nb]}], 'nodes': nodes, 'skins': [skin],
		'meshes': [{'name': 'Tomas', 'primitives': prims}], 'materials': materials,
		'images': [{'bufferView': image_view, 'mimeType': 'image/png', 'name': 'tomas_face'}],
		'textures': [{'sampler': 0, 'source': 0}],
		'samplers': [{'magFilter': 9728, 'minFilter': 9728, 'wrapS': 33071, 'wrapT': 33071}],
		'animations': anims, 'buffers': [{'byteLength': 0}], 'bufferViews': views, 'accessors': accessors}
	while len(buf) % 4:
		buf.append(0)
	gltf['buffers'][0]['byteLength'] = len(buf)
	js = json.dumps(gltf, separators=(',', ':')).encode()
	js += b' ' * ((4 - len(js) % 4) % 4)
	with open(path, 'wb') as f:
		f.write(struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(buf)))
		f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
		f.write(struct.pack('<II', len(buf), 0x004E4942) + bytes(buf))


def stats(surfaces):
	tris = sum(len(d['P']) // 3 for d in surfaces.values())
	allp = np.vstack([d['P'] for d in surfaces.values()])
	return tris, allp.min(0), allp.max(0)


def main(argv=None):
	ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
	ap.add_argument('--out', default='assets/characters', help='output folder for tomas.glb')
	ap.add_argument('--sheet', help='concept sheet: re-cut tomas_face.png from its front view')
	args = ap.parse_args(argv)
	os.makedirs(args.out, exist_ok=True)
	face_png = os.path.join(args.out, 'tomas_face.png')
	meta_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tomas_face.json')
	cx = SHEET_CX
	if args.sheet:
		cx = cut_face(args.sheet, face_png)
		with open(meta_path, 'w') as f:
			json.dump({'sheet_cx': cx, 'box': FACE_BOX, 'ppm': SHEET_PPM, 'feet': SHEET_FEET}, f, indent=1)
	elif os.path.exists(meta_path):
		cx = json.load(open(meta_path))['sheet_cx']
	if not os.path.exists(face_png):
		sys.exit('no %s: run once with --sheet to cut the face from the concept sheet' % face_png)
	surfaces = flatten(build_parts(cx))
	export_glb(surfaces, face_png, os.path.join(args.out, 'tomas.glb'))
	tris, lo, hi = stats(surfaces)
	print('tomas.glb: %d triangles, %d bones, %d animations, bounds %s .. %s' % (
		tris, len(BONE_NAMES), len(ANIMATIONS), np.round(lo, 3), np.round(hi, 3)))
	return surfaces


if __name__ == '__main__':
	main()
