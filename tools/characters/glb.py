"""Helpers shared by the raccoon and Shadow builders (not by the witch modules).

Geometry primitives (rings, lofts, tubes, blobs, ragged hems), a small skinned model
container that flattens to flat-shaded triangle soup, animation clips sampled from
functions of time, and a self-contained glTF 2.0 binary writer and reader.

Conventions: glTF space, +Y up, the character faces +Z, +X is its LEFT. Builders author
in whatever units suit them and `Model.finish(height)` scales to metres with the feet on
y = 0. Bones are translation-only in the rest pose (identity rotations), so an animation
rotation is expressed in rest-pose world axes, and the inverse bind matrix of a joint is a
plain translation by minus its head.

Colours are display-referred (what the game's unshaded PSX shaders draw), snapped to 5 bits
per channel, and written to glTF as linear factors so Godot's importer (which converts
baseColorFactor linear -> sRGB) gives back exactly the authored value.
"""

import json
import os
import math
import struct

import numpy as np

A = np.array


# ---------------------------------------------------------------------------- math

def nz(v):
    v = A(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def rot_axis(axis, deg):
    """3x3 rotation about a unit axis (right-handed)."""
    x, y, z = nz(axis)
    a = math.radians(deg)
    c, s, C = math.cos(a), math.sin(a), 1 - math.cos(a)
    return A([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
              [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
              [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def align(d):
    """Rotation taking +Y onto direction d."""
    d = nz(d)
    y = A((0, 1.0, 0))
    v = np.cross(y, d)
    c = y @ d
    if np.linalg.norm(v) < 1e-8:
        return np.eye(3) if c > 0 else np.diag([1, -1, -1.0])
    vx = A([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))


def frame_x(d, up=(0, 1.0, 0)):
    """Rotation taking +X onto d, keeping +Y as close to `up` as possible."""
    x = nz(d)
    z = np.cross(x, up)
    if np.linalg.norm(z) < 1e-6:
        z = np.cross(x, (0, 0, 1.0))
    z = nz(z)
    y = np.cross(z, x)
    return np.stack([x, y, z], 1)


def minrot(a, b):
    """Shortest-arc rotation taking direction a onto direction b."""
    a, b = nz(a), nz(b)
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else rot_axis(np.cross(a, (0, 0, 1.0)) if abs(a[2]) < .9 else (1, 0, 0), 180)
    return rot_axis(v, math.degrees(math.atan2(np.linalg.norm(v), c)))


def q_axis(axis, deg):
    h = math.radians(deg) / 2
    x, y, z = nz(axis)
    return A([x * math.sin(h), y * math.sin(h), z * math.sin(h), math.cos(h)])


def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return A([aw * bx + ax * bw + ay * bz - az * by,
              aw * by - ax * bz + ay * bw + az * bx,
              aw * bz + ax * by - ay * bx + az * bw,
              aw * bw - ax * bx - ay * by - az * bz])


def q_euler(x=0.0, y=0.0, z=0.0):
    """Degrees; applied roll (Z) first, then pitch (X), then yaw (Y): q = qy * qx * qz."""
    return q_mul(q_axis((0, 1, 0), y), q_mul(q_axis((1, 0, 0), x), q_axis((0, 0, 1), z)))


def q_mat(q):
    x, y, z, w = q
    return A([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
              [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
              [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def q_slerp(a, b, t):
    d = float(a @ b)
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        q = a + (b - a) * t
        return q / np.linalg.norm(q)
    th = math.acos(d)
    return (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)


def srgb_to_linear(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def q5(c):
    """Snap a display colour to 5 bits per channel (the PSX framebuffer depth)."""
    return tuple(float(round(v * 31) / 31) for v in c)


def hash3(p, k=0):
    """Deterministic pseudo-random in [-1, 1]^3 from a point; mirror-symmetric in x."""
    x, y, z = abs(p[0]), p[1], p[2]
    d = A([math.sin(x * 127.1 + y * 311.7 + z * 74.7 + (i + 3 * k) * 19.19) * 43758.5453 for i in range(3)])
    d = (d - np.floor(d)) * 2 - 1
    d[0] *= math.copysign(1, p[0]) if abs(p[0]) > 1e-6 else 0
    return d


def jitter(V, amp, k=0):
    """Hand-modelled facet irregularity: a symmetric, deterministic nudge per vertex."""
    if not amp:
        return V
    return V + A([hash3(p, k) for p in V]) * amp


# ---------------------------------------------------------------------------- geometry

def ring(c, u, w, N=12, e=2.0, ph=0.0):
    """N points of a superellipse in the plane spanned by u (sin side) and w (cos side)."""
    c, u, w = A(c, float), A(u, float), A(w, float)
    out = []
    for k in range(N):
        t = 2 * math.pi * (k + ph) / N
        s, co = math.sin(t), math.cos(t)
        if e != 2:
            s = math.copysign(abs(s) ** (2 / e), s)
            co = math.copysign(abs(co) ** (2 / e), co)
        out.append(c + u * s + w * co)
    return A(out)


def hring(y, rx, rz, cz=0.0, cx=0.0, N=12, e=2.0, ph=0.0):
    """Horizontal ring: k=0 points to +Z (front), k=N/4 to +X (the character's left)."""
    return ring((cx, y, cz), (rx, 0, 0), (0, 0, rz), N, e, ph)


def loft(rings, cap=(0.01, 0.01), closed=True, ax=None):
    """Skin a list of equal-length rings. Caps are cones (cap = apex lift along the axis);
    cap=None leaves the ends open. `ax` are interior points used to orient the winding."""
    rings = [A(r, float) for r in rings]
    R, N = len(rings), len(rings[0])
    V = np.vstack(rings)
    F, FB = [], []
    for k in range(R - 1):
        for m in range(N if closed else N - 1):
            a = k * N + m
            b = k * N + (m + 1) % N
            F += [(a, b, a + N), (b, b + N, a + N)]
            FB += [k, k]
    cen = [r.mean(0) for r in rings]
    if closed and cap:
        t0 = nz(cen[0] - cen[1])
        t1 = nz(cen[-1] - cen[-2])
        V = np.vstack([V, cen[0] + t0 * cap[0], cen[-1] + t1 * cap[1]])
        c0, c1 = R * N, R * N + 1
        F += [(c0, (m + 1) % N, m) for m in range(N)]
        F += [(c1, (R - 1) * N + m, (R - 1) * N + (m + 1) % N) for m in range(N)]
        FB += [0] * N + [R - 1] * N
    if ax is None:
        ax = resample(cen, 6)
    rid = np.repeat(np.arange(R), N)
    if len(V) > R * N:
        rid = np.concatenate([rid, [0, R - 1]])
    return dict(V=V, F=A(F, int), ax=A(ax, float), rid=rid, fb=A(FB, int))


def resample(pts, n=6):
    pts = A(pts, float)
    out = []
    for i in range(len(pts) - 1):
        for t in np.linspace(0, 1, n, endpoint=False):
            out.append(pts[i] * (1 - t) + pts[i + 1] * t)
    out.append(pts[-1])
    return A(out)


def catmull(P, n=4):
    P = A(P, float)
    Pp = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    Q = []
    for i in range(1, len(Pp) - 2):
        p0, p1, p2, p3 = Pp[i - 1], Pp[i], Pp[i + 1], Pp[i + 2]
        for k in range(n):
            t = k / n
            Q.append(.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                           + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    Q.append(P[-1])
    return A(Q)


def path_frames(P, up=(0, 1.0, 0)):
    """Tangent-bisecting frames along a polyline (no pinch at the joints)."""
    P = A(P, float)
    M = len(P)
    T = []
    for i in range(M):
        T.append(nz(P[min(i + 1, M - 1)] - P[max(i - 1, 0)]))
    out = []
    prev_w = None
    for i in range(M):
        t = T[i]
        w = np.cross(t, up)
        if np.linalg.norm(w) < 1e-6:
            w = np.cross(t, (0, 0, 1.0))
        w = nz(w)
        if prev_w is not None and w @ prev_w < 0:
            w = -w
        u = np.cross(w, t)
        out.append((t, w, u))
        prev_w = w
    return out


def tube(path, radii, N=6, ratio=1.0, up=(0, 1.0, 0), cap=(0.004, 0.01), twist=0.0, e=2.0):
    """Loft along a path; `radii` is resampled along it; `ratio` squashes the u axis."""
    P = A(path, float)
    M = len(P)
    rr = np.interp(np.linspace(0, 1, M), np.linspace(0, 1, len(radii)), radii)
    rings = []
    for i, (t, w, u) in enumerate(path_frames(P, up)):
        rings.append(ring(P[i], u * rr[i] * ratio, w * rr[i], N, e, twist))
    g = loft(rings, cap, ax=resample(P, 4))
    return g


def blob(c, r, d=(0, 1, 0), N=8, k=3):
    """Faceted ellipsoid of radii r=(rx, ry, rz), its y axis along d."""
    R = align(d)
    rx, ry, rz = r
    hs = np.linspace(-1, 1, k + 2)[1:-1]
    rings = []
    for h in hs:
        q = math.sqrt(1 - h * h)
        rings.append([A(c, float) + R @ A((rx * q * math.sin(2 * math.pi * m / N), ry * h,
                                           rz * q * math.cos(2 * math.pi * m / N))) for m in range(N)])
    cp = ry * (1 - abs(hs[0]))
    g = loft(rings, (cp, cp))
    g['ax'] = A([c], float)
    return g


def box(c, half, R=None):
    """Axis box (or rotated by R) as 12 triangles; winding from its centre."""
    c = A(c, float)
    hx, hy, hz = half
    V = A([(x, y, z) for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)], float)
    if R is not None:
        V = V @ A(R).T
    V = V + c
    F = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
         (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
    return dict(V=V, F=A(F, int), ax=A([c]))


def transform(g, R=None, t=(0, 0, 0), piv=(0, 0, 0)):
    """Rotate about piv by R then translate; returns g (modified)."""
    piv = A(piv, float)
    R = np.eye(3) if R is None else A(R)
    g['V'] = (g['V'] - piv) @ R.T + piv + A(t, float)
    g['ax'] = (g['ax'] - piv) @ R.T + piv + A(t, float)
    return g


def scale_about(g, s, piv):
    piv = A(piv, float)
    g['V'] = (g['V'] - piv) * s + piv
    g['ax'] = (g['ax'] - piv) * s + piv
    return g


def ragged_hem(top, lower, depth, rnd, tips=1, jag=0.35):
    """Open band from ring `top` down to ring `lower` (same length, closed loop) whose lower
    edge is torn into pointed tatters: each column gets its own drop and `tips` points.

    Returns V, F (faces only for the band) - winding is fixed later by the owner part."""
    top = A(top, float)
    lower = A(lower, float)
    N = len(top)
    V = list(top)
    F = []
    drops = [depth * (1 + rnd.uniform(-jag, jag)) for _ in range(N)]
    low = []
    for m in range(N):
        d = nz(lower[m] - top[m])
        low.append(lower[m] + d * drops[m] * rnd.uniform(0.0, 0.35))
    base = len(V)
    V += low
    for m in range(N):
        m1 = (m + 1) % N
        F += [(m, m1, base + m), (m1, base + m1, base + m)]
    # the tatters: a triangle fan hanging from each lower edge segment
    for m in range(N):
        m1 = (m + 1) % N
        a, b = low[m], low[m1]
        dn = nz((lower[m] - top[m]) + (lower[m1] - top[m1]))
        idx = [base + m]
        for k in range(tips):
            f = (k + 0.5) / tips
            tip = a * (1 - f) + b * f + dn * drops[m] * rnd.uniform(0.55, 1.0)
            V.append(tip)
            idx.append(len(V) - 1)
            if k < tips - 1:
                f2 = (k + 1.0) / tips
                notch = a * (1 - f2) + b * f2 + dn * drops[m] * rnd.uniform(0.0, 0.25)
                V.append(notch)
                idx.append(len(V) - 1)
        idx.append(base + m1)
        for k in range(1, len(idx) - 1):
            F.append((idx[0], idx[k], idx[k + 1]))
        # close the fan back against the segment (single sheet)
    return A(V, float), F


# ---------------------------------------------------------------------------- decals

class Surface:
    """Ray caster over the triangles of some parts, for laying decals flush on facets."""

    def __init__(self, parts):
        T = np.concatenate([A(p['V'], float)[A(p['F'], int)] for p in parts])
        self.T = T
        self.e1 = T[:, 1] - T[:, 0]
        self.e2 = T[:, 2] - T[:, 0]
        n = np.cross(self.e1, self.e2)
        ln = np.linalg.norm(n, axis=1, keepdims=True)
        self.n = n / np.where(ln > 0, ln, 1)

    def cast(self, o, d):
        """Farthest hit along the ray (the outer skin when cast from inside); returns the
        point and the facet normal facing along d, or (None, None)."""
        o = A(o, float)
        d = nz(d)
        p = np.cross(d, self.e2)
        det = (self.e1 * p).sum(1)
        ok = np.abs(det) > 1e-12
        inv = 1 / np.where(ok, det, 1)
        s = o - self.T[:, 0]
        u = (s * p).sum(1) * inv
        q = np.cross(s, self.e1)
        v = (q @ d) * inv
        t = (q * self.e2).sum(1) * inv
        hit = ok & (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1 + 1e-7) & (t > 0)
        if not hit.any():
            return None, None
        i = int(np.argmax(np.where(hit, t, -np.inf)))
        n = self.n[i] if self.n[i] @ d > 0 else -self.n[i]
        return o + d * t[i], n

    def project(self, pts, mapfn, off):
        """pts: 2D decal coordinates; mapfn(u, v) -> (ray origin, ray dir)."""
        V = []
        for u, v in pts:
            o, d = mapfn(u, v)
            p, n = self.cast(o, d)
            if p is None:
                raise ValueError('decal point (%.3f, %.3f) misses the surface' % (u, v))
            V.append(p + n * off)
        return A(V)


def fan2d(pts):
    """Convex-ish outline -> centroid fan (centroid first)."""
    pts = [tuple(p) for p in pts]
    c = tuple(np.mean(pts, 0))
    n = len(pts)
    return [c] + pts, [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)]


def grid2d(fn, NS, NK):
    """fn(s, k) for s, k in [0, 1] -> 2D point; a (NS x NK) quad grid."""
    P, F = [], []
    for i in range(NS):
        for j in range(NK):
            P.append(fn(i / (NS - 1), j / (NK - 1)))
    for i in range(NS - 1):
        for j in range(NK - 1):
            a, b = i * NK + j, (i + 1) * NK + j
            F += [(a, b, b + 1), (a, b + 1, a + 1)]
    return P, F


def stroke2d(pts, width):
    """A 2D polyline as a ribbon of constant width."""
    pts = A(pts, float)
    n = len(pts)
    L, R = [], []
    for i in range(n):
        t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t = t / np.linalg.norm(t)
        nn = A((-t[1], t[0])) * width / 2
        L.append(pts[i] + nn)
        R.append(pts[i] - nn)
    P = L + R
    F = []
    for i in range(n - 1):
        F += [(i, i + 1, n + i + 1), (i, n + i + 1, n + i)]
    return [tuple(p) for p in P], F


# ---------------------------------------------------------------------------- model

class Model:
    """Bones (translation-only rest pose) plus parts with dense per-vertex bone weights."""

    def __init__(self, name):
        self.name = name
        self.bones = {}  # name -> (parent, head)
        self.parts = []
        self.scale = 1.0
        self.offset = np.zeros(3)

    # ---- skeleton
    def bone(self, name, parent, head):
        assert parent is None or parent in self.bones, parent
        self.bones[name] = (parent, A(head, float))

    @property
    def names(self):
        return list(self.bones)

    @property
    def ix(self):
        return {n: i for i, n in enumerate(self.bones)}

    def head(self, name):
        return self.bones[name][1]

    # ---- skin weights (dense: n x bones)
    def rigid(self, n, bone):
        W = np.zeros((n, len(self.bones)))
        W[:, self.ix[bone]] = 1
        return W

    def blend(self, values, stops):
        """Piecewise smoothstep blend along a scalar: stops = [(value, bone), ...] ascending."""
        values = np.asarray(values, float)
        ix = self.ix
        W = np.zeros((len(values), len(self.bones)))
        pos = [s[0] for s in stops]
        for i, v in enumerate(values):
            if v <= pos[0]:
                W[i, ix[stops[0][1]]] = 1
            elif v >= pos[-1]:
                W[i, ix[stops[-1][1]]] = 1
            else:
                k = int(np.searchsorted(pos, v)) - 1
                f = float(smooth((v - pos[k]) / (pos[k + 1] - pos[k])))
                W[i, ix[stops[k][1]]] += 1 - f
                W[i, ix[stops[k + 1][1]]] += f
        return W

    def add(self, g, mat, skin, inv=False, orient='ax'):
        """mat: name, callable(centroid, normal) -> name, or list indexed by g['fb'].
        skin: bone name or dense weights. orient: 'ax' (away from nearest axis point),
        a 3-vector (outward direction) or 'keep' (authored winding)."""
        n = len(g['V'])
        W = self.rigid(n, skin) if isinstance(skin, str) else A(skin, float)
        assert W.shape == (n, len(self.bones)), (W.shape, n)
        g = dict(g)
        g.update(mat=mat, W=W, inv=inv, orient=orient)
        self.parts.append(g)
        return g

    # ---- re-posing the bind pose
    def pose_bind(self, rots):
        """Bake a pose into the rest pose: rots = {bone: 3x3 local rotation}. Vertices move by
        linear blend skinning, bones move to their posed heads, rest rotations stay identity.
        Lets a part be authored in a convenient pose (the source's T-pose arms) and shipped in
        another (arms down, or holding scrolls)."""
        names = self.names
        G = {}
        for n in names:
            par, h = self.bones[n]
            M = np.eye(4)
            M[:3, :3] = rots.get(n, np.eye(3))
            M[:3, 3] = h - (self.bones[par][1] if par else 0)
            G[n] = G[par] @ M if par else M
        S = np.stack([G[n] @ np.vstack([np.hstack([np.eye(3), -self.bones[n][1][:, None]]), [0, 0, 0, 1]])
                      for n in names])
        for p in self.parts:
            W = p['W']
            M = np.einsum('vb,bij->vij', W, S)
            V = p['V']
            p['V'] = np.einsum('vij,vj->vi', M[:, :3, :3], V) + M[:, :3, 3]
            ax = A(p['ax'], float)
            near = np.argmin(((ax[:, None, :] - V[None]) ** 2).sum(2), 1)
            Ma = M[near]
            p['ax'] = np.einsum('vij,vj->vi', Ma[:, :3, :3], ax) + Ma[:, :3, 3]
            if 'vn' in p:
                vn = np.einsum('vij,vj->vi', M[:, :3, :3], p['vn'])
                p['vn'] = vn / np.linalg.norm(vn, axis=1, keepdims=True)
        for n in names:
            self.bones[n] = (self.bones[n][0], G[n][:3, 3].copy())

    # ---- finishing
    def bbox(self):
        V = np.vstack([p['V'] for p in self.parts])
        return V.min(0), V.max(0)

    def finish(self, height, ground_extra=()):
        """Scale to `height` metres, feet on y=0, root bone at the origin."""
        lo, hi = self.bbox()
        s = height / (hi[1] - lo[1])
        off = A((0.0, -lo[1], 0.0))
        for p in self.parts:
            p['V'] = (p['V'] + off) * s
            p['ax'] = (A(p['ax'], float) + off) * s
        for k, (par, h) in list(self.bones.items()):
            self.bones[k] = (par, (h + off) * s)
        self.scale = s
        self.offset = off
        root = self.names[0]
        self.bones[root] = (None, np.zeros(3))  # the root is the feet origin
        return s

    def flatten(self):
        """Triangle soup per material: P (3n,3), N (3n,3), W (3n,bones), UV (3n,2) if any."""
        out = {}
        for p in self.parts:
            V, F = p['V'], A(p['F'], int)
            Q = V[F]
            n = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
            ln = np.linalg.norm(n, axis=1)
            C = Q.mean(1)
            ax = A(p['ax'], float)
            for i in range(len(F)):
                if ln[i] < 1e-12:
                    continue
                f = F[i]
                nn = n[i] / ln[i]
                o = p['orient']
                if isinstance(o, str) and o == 'keep':
                    bad = False
                elif isinstance(o, str):
                    a = ax[np.argmin(((ax - C[i]) ** 2).sum(1))]
                    bad = nn @ (C[i] - a) < 0
                else:
                    bad = nn @ A(o, float) < 0
                if p['inv']:
                    bad = not bad
                if bad:
                    f = f[[0, 2, 1]]
                    nn = -nn
                m = p['mat']
                if isinstance(m, str):
                    mm = m
                elif isinstance(m, list):
                    mm = m[int(p['fb'][i])]
                else:
                    mm = m(C[i], nn)
                d = out.setdefault(mm, dict(P=[], N=[], W=[], UV=[]))
                d['P'] += list(V[f])
                if 'vn' in p:
                    vn = p['vn'][f]
                    vn = vn * (1 if (vn.sum(0) @ nn) >= 0 else -1)
                    d['N'] += list(vn / np.linalg.norm(vn, axis=1, keepdims=True))
                else:
                    d['N'] += [nn] * 3
                d['W'] += list(p['W'][f])
                if 'uv' in p:
                    d['UV'] += list(p['uv'][f])
        for d in out.values():
            for k in ('P', 'N', 'W'):
                d[k] = A(d[k], float)
            d['UV'] = A(d['UV'], float) if len(d['UV']) else None
        return out

    def triangles(self, out=None):
        out = out or self.flatten()
        return sum(len(d['P']) // 3 for d in out.values())


def top4(W):
    """Dense weights -> JOINTS_0 / WEIGHTS_0 (four largest, renormalised)."""
    idx = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, idx, 1)
    w[w < 1e-4] = 0
    s = w.sum(1, keepdims=True)
    assert (s > 0).all(), 'vertex without weights'
    w = w / s
    idx = np.where(w > 0, idx, 0)
    return idx.astype(np.uint8), w.astype(np.float32)


# ---------------------------------------------------------------------------- animation

class Clip:
    """A clip sampled from fn(t) -> {bone: quat | (rx, ry, rz) degrees | dict(r=..., t=offset)}.

    Translation offsets are in authoring units (scaled by the model at export). For a loop
    the last key equals the first, so the clip closes exactly."""

    def __init__(self, name, duration, fn, fps=15, loop=True):
        self.name, self.duration, self.fn, self.fps, self.loop = name, duration, fn, fps, loop

    def times(self):
        n = max(2, int(round(self.duration * self.fps)) + 1)
        return np.linspace(0, self.duration, n)

    @staticmethod
    def _q(v):
        v = A(v, float)
        return v / np.linalg.norm(v) if v.shape == (4,) else q_euler(*v)

    def sample(self):
        T = self.times()
        frames = [self.fn(t % self.duration if self.loop and t >= self.duration else t) for t in T]
        if self.loop:
            frames[-1] = self.fn(0.0)
        bones = []
        for f in frames:
            for b in f:
                if b not in bones:
                    bones.append(b)
        tracks = {}
        for b in bones:
            rot, tra = [], []
            has_t = False
            for f in frames:
                v = f.get(b)
                if isinstance(v, dict):
                    rot.append(self._q(v.get('r', (0, 0, 0))))
                    tra.append(A(v.get('t', (0, 0, 0)), float))
                    has_t = has_t or 't' in v
                elif v is None:
                    rot.append(A((0, 0, 0, 1.0)))
                    tra.append(np.zeros(3))
                else:
                    rot.append(self._q(v))
                    tra.append(np.zeros(3))
            for i in range(1, len(rot)):  # shortest-arc continuity for LINEAR slerp
                if rot[i] @ rot[i - 1] < 0:
                    rot[i] = -rot[i]
            tracks[b] = dict(r=A(rot), t=A(tra) if has_t else None)
        return T, tracks


def wave(t, period, phase=0.0):
    return math.sin(2 * math.pi * (t / period - phase))


# ---------------------------------------------------------------------------- glTF writer

def write_glb(path, model, out, palette, clips, textures=None, generator='tools/characters'):
    """model: finished Model; out: model.flatten(); palette: name -> display colour;
    textures: material name -> PNG bytes (the material then samples it, nearest)."""
    textures = textures or {}
    blob = bytearray()
    views, accs = [], []

    def pad():
        while len(blob) % 4:
            blob.append(0)

    def acc(arr, ctype, typ, minmax=False, target=None):
        pad()
        b = arr.tobytes()
        v = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(b)}
        if target:
            v['target'] = target
        views.append(v)
        blob.extend(b)
        a = {'bufferView': len(views) - 1, 'componentType': ctype, 'count': len(arr), 'type': typ}
        if minmax:
            a['min'] = np.atleast_1d(arr.min(0)).astype(float).tolist()
            a['max'] = np.atleast_1d(arr.max(0)).astype(float).tolist()
        accs.append(a)
        return len(accs) - 1

    names = model.names
    ix = model.ix
    nb = len(names)
    nodes = []
    for n in names:
        par, h = model.bones[n]
        loc = h - (model.bones[par][1] if par else 0)
        nodes.append({'name': n, 'translation': [float(x) for x in loc]})
    for n in names:
        par = model.bones[n][0]
        if par:
            nodes[ix[par]].setdefault('children', []).append(ix[n])
    nodes.append({'name': model.name, 'mesh': 0, 'skin': 0})
    ibm = np.zeros((nb, 16), np.float32)
    for i, n in enumerate(names):
        m = np.eye(4)
        m[:3, 3] = -model.bones[n][1]
        ibm[i] = m.flatten('F')
    skin = {'name': model.name + '_skin', 'joints': list(range(nb)), 'skeleton': 0,
            'inverseBindMatrices': acc(ibm, 5126, 'MAT4')}

    images, texs = [], []
    tex_index = {}
    for m, png in textures.items():
        if m not in out:
            continue
        pad()
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(png)})
        blob.extend(png)
        images.append({'bufferView': len(views) - 1, 'mimeType': 'image/png', 'name': model.name + '_' + m})
        texs.append({'sampler': 0, 'source': len(images) - 1, 'name': m})
        tex_index[m] = len(texs) - 1

    prims, mats = [], []
    for mi, (m, d) in enumerate(out.items()):
        P = d['P'].astype(np.float32)
        Nn = d['N'] / np.linalg.norm(d['N'], axis=1, keepdims=True)
        J, Wt = top4(d['W'])
        at = {'POSITION': acc(P, 5126, 'VEC3', True, 34962),
              'NORMAL': acc(Nn.astype(np.float32), 5126, 'VEC3', False, 34962),
              'JOINTS_0': acc(J, 5121, 'VEC4', False, 34962),
              'WEIGHTS_0': acc(Wt, 5126, 'VEC4', False, 34962)}
        pm = {'metallicFactor': 0.0, 'roughnessFactor': 1.0}
        if m in tex_index and d['UV'] is not None:
            at['TEXCOORD_0'] = acc(d['UV'].astype(np.float32), 5126, 'VEC2', False, 34962)
            pm['baseColorFactor'] = [1.0, 1.0, 1.0, 1.0]
            pm['baseColorTexture'] = {'index': tex_index[m]}
        else:
            pm['baseColorFactor'] = [float(x) for x in srgb_to_linear(palette[m])] + [1.0]
        prims.append({'attributes': at, 'material': mi, 'mode': 4})
        mats.append({'name': m, 'pbrMetallicRoughness': pm})

    anims = []
    for clip in clips:
        T, tracks = clip.sample()
        ti = acc(T.astype(np.float32), 5126, 'SCALAR', True)
        sm, ch = [], []
        for b, tr in tracks.items():
            sm.append({'input': ti, 'output': acc(tr['r'].astype(np.float32), 5126, 'VEC4'), 'interpolation': 'LINEAR'})
            ch.append({'sampler': len(sm) - 1, 'target': {'node': ix[b], 'path': 'rotation'}})
            if tr['t'] is not None:
                par, h = model.bones[b]
                rest = h - (model.bones[par][1] if par else 0)
                tv = (rest + tr['t'] * model.scale).astype(np.float32)
                sm.append({'input': ti, 'output': acc(tv, 5126, 'VEC3'), 'interpolation': 'LINEAR'})
                ch.append({'sampler': len(sm) - 1, 'target': {'node': ix[b], 'path': 'translation'}})
        anims.append({'name': clip.name, 'samplers': sm, 'channels': ch})

    g = {'asset': {'version': '2.0', 'generator': generator},
         'scene': 0, 'scenes': [{'name': model.name, 'nodes': [0, nb]}], 'nodes': nodes,
         'skins': [skin], 'meshes': [{'name': model.name, 'primitives': prims}], 'materials': mats,
         'animations': anims, 'buffers': [{'byteLength': 0}], 'bufferViews': views, 'accessors': accs}
    if images:
        g['images'] = images
        g['textures'] = texs
        g['samplers'] = [{'magFilter': 9728, 'minFilter': 9728, 'wrapS': 33071, 'wrapT': 33071}]
    pad()
    g['buffers'][0]['byteLength'] = len(blob)
    js = json.dumps(g, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    with open(path, 'wb') as fh:
        fh.write(struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(blob)))
        fh.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        fh.write(struct.pack('<II', len(blob), 0x004E4942) + bytes(blob))
    return dict(triangles=sum(len(d['P']) // 3 for d in out.values()), bones=nb,
                materials=len(mats), animations=[c.name for c in clips], bytes=28 + len(js) + len(blob))


# ---------------------------------------------------------------------------- glTF reader

_CT = {5126: np.float32, 5121: np.uint8, 5123: np.uint16, 5125: np.uint32}
_NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


class GLB:
    """Minimal reader for what write_glb produces, used to preview the file itself (rest
    pose and any animation frame) so the previews check the export, not the builder."""

    def __init__(self, path):
        data = open(path, 'rb').read()
        magic, ver, ln = struct.unpack_from('<III', data, 0)
        assert magic == 0x46546C67 and ver == 2
        jl, _ = struct.unpack_from('<II', data, 12)
        self.js = json.loads(data[20:20 + jl])
        bl, _ = struct.unpack_from('<II', data, 20 + jl)
        self.bin = data[28 + jl:28 + jl + bl]

    def accessor(self, i):
        a = self.js['accessors'][i]
        v = self.js['bufferViews'][a['bufferView']]
        dt = _CT[a['componentType']]
        n = _NC[a['type']]
        arr = np.frombuffer(self.bin, dt, a['count'] * n, v.get('byteOffset', 0) + a.get('byteOffset', 0))
        return arr.reshape(a['count'], n) if n > 1 else arr.copy()

    def image(self, i):
        from PIL import Image
        import io
        im = self.js['images'][i]
        v = self.js['bufferViews'][im['bufferView']]
        return Image.open(io.BytesIO(self.bin[v['byteOffset']:v['byteOffset'] + v['byteLength']]))

    def skeleton(self):
        nodes = self.js['nodes']
        joints = self.js['skins'][0]['joints']
        parent = {}
        for i, nd in enumerate(nodes):
            for c in nd.get('children', []):
                parent[c] = i
        return joints, parent

    def world(self, local):
        """local: node -> (R 3x3, t) ; returns node -> 4x4 world matrix."""
        joints, parent = self.skeleton()
        nodes = self.js['nodes']
        Wm = {}

        def get(i):
            if i in Wm:
                return Wm[i]
            R, t = local.get(i, (np.eye(3), A(nodes[i].get('translation', (0, 0, 0)), float)))
            M = np.eye(4)
            M[:3, :3] = R
            M[:3, 3] = t
            if i in parent:
                M = get(parent[i]) @ M
            Wm[i] = M
            return M
        for j in joints:
            get(j)
        return Wm

    def pose_locals(self, anim=None, t=0.0):
        nodes = self.js['nodes']
        local = {}
        if anim is None:
            return local
        an = [a for a in self.js['animations'] if a['name'] == anim][0]
        for ch in an['channels']:
            s = an['samplers'][ch['sampler']]
            T = self.accessor(s['input'])
            Y = self.accessor(s['output']).astype(float)
            t2 = min(max(t, T[0]), T[-1])
            k = int(np.clip(np.searchsorted(T, t2) - 1, 0, len(T) - 2))
            f = (t2 - T[k]) / max(T[k + 1] - T[k], 1e-9)
            node = ch['target']['node']
            R, tr = local.get(node, (np.eye(3), A(nodes[node].get('translation', (0, 0, 0)), float)))
            if ch['target']['path'] == 'rotation':
                R = q_mat(q_slerp(Y[k], Y[k + 1], f))
            else:
                tr = Y[k] * (1 - f) + Y[k + 1] * f
            local[node] = (R, tr)
        return local

    def triangles(self, anim=None, t=0.0):
        """Posed triangle soup: list of dicts (material name, P (n,3,3), N (n,3,3), UV or None)."""
        joints, _ = self.skeleton()
        ibm = self.accessor(self.js['skins'][0]['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
        Wm = self.world(self.pose_locals(anim, t))
        S = np.stack([Wm[j] @ ibm[k] for k, j in enumerate(joints)])
        res = []
        for pr in self.js['meshes'][0]['primitives']:
            at = pr['attributes']
            P = self.accessor(at['POSITION']).astype(float)
            Nn = self.accessor(at['NORMAL']).astype(float)
            J = self.accessor(at['JOINTS_0']).astype(int)
            Wt = self.accessor(at['WEIGHTS_0']).astype(float)
            M = np.einsum('vk,vkij->vij', Wt, S[J])
            Pp = np.einsum('vij,vj->vi', M[:, :3, :3], P) + M[:, :3, 3]
            Np = np.einsum('vij,vj->vi', M[:, :3, :3], Nn)
            uv = self.accessor(at['TEXCOORD_0']).astype(float) if 'TEXCOORD_0' in at else None
            mat = self.js['materials'][pr['material']]
            res.append(dict(mat=mat['name'], P=Pp.reshape(-1, 3, 3), N=Np.reshape(-1, 3, 3),
                            UV=None if uv is None else uv.reshape(-1, 3, 2), pbr=mat['pbrMetallicRoughness']))
        return res


# ---------------------------------------------------------------------------- Godot import

def write_import(glb_path, loops, embed_textures=False):
    """Godot import settings beside the GLB, written once (Godot then owns the file):
    looping clips (glTF has no loop flag), no generated LODs (they would melt the facets),
    no shadow meshes (the hall has no lights), and an embedded, uncompressed texture so the
    nearest-filtered face stays crisp and no extra image file appears."""
    imp = glb_path + '.import'
    if os.path.exists(imp):
        return False
    res = 'res://' + os.path.relpath(os.path.abspath(glb_path), _repo_root(glb_path)).replace(os.sep, '/')
    anims = ',\n'.join('"%s": {\n"settings/loop_mode": 1\n}' % n for n in loops)
    with open(imp, 'w') as fh:
        fh.write('[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n'
                 '[deps]\n\nsource_file="%s"\n\n[params]\n\n'
                 'meshes/generate_lods=false\nmeshes/create_shadow_meshes=false\nmeshes/light_baking=0\n'
                 'animation/import=true\nanimation/trimming=false\nanimation/remove_immutable_tracks=true\n'
                 '_subresources={\n"animations": {\n%s\n}\n}\n'
                 'gltf/embedded_image_handling=%d\n' % (res, anims, 3 if embed_textures else 1))
    return True


def _repo_root(path):
    d = os.path.dirname(os.path.abspath(path))
    while d != os.path.dirname(d):
        if os.path.exists(os.path.join(d, 'project.godot')):
            return d
        d = os.path.dirname(d)
    return os.path.dirname(os.path.abspath(path))
