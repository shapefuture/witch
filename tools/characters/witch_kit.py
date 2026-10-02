"""Faceted-mesh kit shared by the two witches (ported from the user's `witch_psx` model).

Authoring space is the source model's: y up, the character faces +Z, +X is her left, the
feet at y=0, about 3.3 units tall. `witch_glb.export` scales to game metres.

A *part* is a dict: V (n,3), F (m,3) int, ax (k,3) axis points used to orient faces outward,
plus `mat` (colour name, per-band list, or callable(centroid, normal) -> name), optional
`tex` + `uv` (per vertex, tile-local, v down) or `fuv` (per face), `vn` (smooth normals),
`inv` (faces point toward the axis) and `both` (double sided). `Model.flatten()` turns the
parts into one flat-shaded triangle soup with per-corner UVs into the atlas.
"""
import math
import numpy as np

A = np.array


def N_(v):
    v = A(v, float)
    return v / np.linalg.norm(v)


def hsh(p, a):
    """Deterministic, mirror-symmetric jitter -> hand-modelled facet irregularity."""
    x, y, z = abs(p[0]), p[1], p[2]
    d = A([math.sin(x * 127.1 + y * 311.7 + z * 74.7 + k * 19.19) * 43758.5453 for k in range(3)])
    d = (d - np.floor(d)) * 2 - 1
    d[0] *= math.copysign(1, p[0]) if abs(p[0]) > 1e-6 else 0
    return d * a


def loft(rings, N=12, e=2., cap=(0, 0), j=0., o=0.):
    """Rings of (centre, u, w) -> closed tube with fan caps. `e` is the superellipse exponent."""
    R = len(rings)
    V = []
    for c, u, w in rings:
        c, u, w = A(c, float), A(u, float), A(w, float)
        for k in range(N):
            t = 2 * math.pi * (k + o) / N
            cc, ss = math.cos(t), math.sin(t)
            if e != 2:
                cc = math.copysign(abs(cc) ** (2 / e), cc)
                ss = math.copysign(abs(ss) ** (2 / e), ss)
            V.append(c + w * cc + u * ss)
    ax = A([A(r[0], float) for r in rings])
    V = A(V)
    t0 = ax[0] - ax[1]
    t0 /= np.linalg.norm(t0)
    t1 = ax[-1] - ax[-2]
    t1 /= np.linalg.norm(t1)
    if j:
        V = V + A([hsh(p, j) for p in V])
    V = np.vstack([V, ax[0] + t0 * cap[0], ax[-1] + t1 * cap[1]])
    c0, c1 = R * N, R * N + 1
    F, FB = [], []
    for k in range(R - 1):
        for m in range(N):
            a = k * N + m
            b = k * N + (m + 1) % N
            F += [(a, b, a + N), (b, b + N, a + N)]
            FB += [k, k]
    if cap[0] is not None:
        F += [(c0, (m + 1) % N, m) for m in range(N)]
        FB += [0] * N
    if cap[1] is not None:
        F += [(c1, (R - 1) * N + m, (R - 1) * N + (m + 1) % N) for m in range(N)]
        FB += [R - 1] * N
    rid = np.concatenate([np.repeat(np.arange(R), N), [0, R - 1]])
    # cylindrical UV per vertex (u around, v along); caps sample the first/last ring
    uv = np.zeros((len(V), 2))
    for k in range(R):
        for m in range(N):
            uv[k * N + m] = (m / N, k / max(1, R - 1))
    uv[c0] = (.5, 0)
    uv[c1] = (.5, 1)
    return dict(V=V, F=A(F, int), ax=ax, fb=A(FB), rid=rid, N=N, R=R, uvc=uv)


def rotm(axis, deg):
    a = N_(axis)
    t = math.radians(deg)
    K = A([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + math.sin(t) * K + (1 - math.cos(t)) * K @ K


def xf(part, M, piv=(0, 0, 0), t=(0, 0, 0)):
    p = A(piv, float)
    part['V'] = (part['V'] - p) @ M.T + p + A(t, float)
    part['ax'] = (part['ax'] - p) @ M.T + p + A(t, float)
    if 'vn' in part:
        part['vn'] = part['vn'] @ M.T
    return part


def scale_part(part, s, piv=(0, 0, 0)):
    p = A(piv, float)
    s = A(s, float) if np.ndim(s) else A((s, s, s), float)
    part['V'] = (part['V'] - p) * s + p
    part['ax'] = (part['ax'] - p) * s + p
    return part


def align(d):
    d = N_(d)
    y = A((0, 1., 0))
    v = np.cross(y, d)
    c = y @ d
    if np.linalg.norm(v) < 1e-8:
        return np.eye(3) if c > 0 else np.diag([1, -1, -1.])
    vx = A([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))


def blob(c, r, d=(0, 1, 0), N=8, k=3, j=0., e=2.):
    """Faceted ellipsoid with radii r, long axis along d."""
    R = align(d)
    rx, ry, rz = r
    rings = []
    hs_ = np.linspace(-1, 1, k + 2)[1:-1]
    for h in hs_:
        q = math.sqrt(1 - h * h)
        rings.append((A(c, float) + R @ A((0, ry * h, 0)), R @ A((rx * q, 0, 0)), R @ A((0, 0, rz * q))))
    cp = ry * (1 - abs(hs_[0]))
    return loft(rings, N, e, cap=(cp, cp), j=j)


def catmull(Pt, n=4):
    Pt = A(Pt, float)
    Pp = np.vstack([2 * Pt[0] - Pt[1], Pt, 2 * Pt[-1] - Pt[-2]])
    Q = []
    for i in range(1, len(Pp) - 2):
        p0, p1, p2, p3 = Pp[i - 1], Pp[i], Pp[i + 1], Pp[i + 2]
        for k in range(n):
            t = k / n
            Q.append(.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                           + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    Q.append(Pt[-1])
    return A(Q)


def tube(Pt, radii, N=5, ratio=.9, flat=(0, 0, 1.), cap=(0, .05), e=2., o=0.):
    """Sweep along a polyline; `ratio` flattens the section across `flat`."""
    Pt = A(Pt, float)
    M = len(Pt)
    rr = np.interp(np.linspace(0, 1, M), np.linspace(0, 1, len(radii)), radii)
    rings = []
    for i in range(M):
        t = N_(Pt[min(i + 1, M - 1)] - Pt[max(i - 1, 0)])
        w = np.cross(t, flat)
        if np.linalg.norm(w) < 1e-6:
            w = np.cross(t, (0, 1., 0))
        w = N_(w)
        u = np.cross(w, t)
        rings.append((Pt[i], u * rr[i] * ratio, w * rr[i]))
    return loft(rings, N, e, cap=cap, o=o)


def spiral_e(p, c, rx, ry, turns, dirn, n, z1, f1=.1):
    """Elliptical spiral in XY continuing from p around centre c, shrinking to f1."""
    p = A(p, float)
    c = A(c, float)
    ux = (p[0] - c[0]) / rx
    uy = (p[1] - c[1]) / ry
    m0 = math.hypot(ux, uy)
    a0 = math.atan2(uy, ux)
    out = []
    for i in range(1, n + 1):
        f = i / n
        a = a0 + dirn * turns * 2 * math.pi * f
        m = m0 + (f1 - m0) * f
        out.append((c[0] + rx * m * math.cos(a), c[1] + ry * m * math.sin(a), p[2] + (z1 - p[2]) * f))
    return out


# ---- 2D shapes for decals ---------------------------------------------------------------------
def star2d(n, ro, ri):
    V = [(0, 0)] + [((ro if k % 2 == 0 else ri) * math.cos(math.pi / 2 + k * math.pi / n),
                     (ro if k % 2 == 0 else ri) * math.sin(math.pi / 2 + k * math.pi / n)) for k in range(2 * n)]
    return V, [(0, 1 + k, 1 + (k + 1) % (2 * n)) for k in range(2 * n)]


def cres2d(R, n=7, d=.46, rb=.80):
    d *= R
    rb *= R
    xx = (d * d + R * R - rb * rb) / (2 * d)
    yy = math.sqrt(R * R - xx * xx)
    th0 = math.atan2(yy, xx)
    bt = math.atan2(yy, xx - d)
    o = [(R * math.cos(t), R * math.sin(t)) for t in np.linspace(th0, 2 * math.pi - th0, n)]
    i = [(d + rb * math.cos(t), rb * math.sin(t)) for t in np.linspace(bt, 2 * math.pi - bt, n)]
    sh = (-R + xx) / 2
    V = [(x - sh, y) for x, y in o + i]
    F = []
    for k in range(n - 1):
        F += [(k, k + 1, n + k + 1), (k, n + k + 1, n + k)]
    return V, F


def poly2d(pts):
    return [tuple(p) for p in pts], [(0, k, k + 1) for k in range(1, len(pts) - 1)]


def disc2d(r, n=8):
    return ([(0, 0)] + [(r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n)) for k in range(n)],
            [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)])


def star3d(n, ro, ri, h):
    """Embossed star: raised centre so the facets shade two-tone."""
    V = [(0, 0, h)] + [((ro if k % 2 == 0 else ri) * math.cos(math.pi / 2 + k * math.pi / n),
                        (ro if k % 2 == 0 else ri) * math.sin(math.pi / 2 + k * math.pi / n), 0.) for k in range(2 * n)]
    return V, [(0, 1 + k, 1 + (k + 1) % (2 * n)) for k in range(2 * n)]


def cres3d(R, n=8, d=.52, rb=.76, h=.01):
    """Embossed crescent with a raised ridge."""
    d *= R
    rb *= R
    xx = (d * d + R * R - rb * rb) / (2 * d)
    yy = math.sqrt(R * R - xx * xx)
    th0 = math.atan2(yy, xx) + .20
    bt = math.atan2(yy, xx - d) + .24
    o = [(R * math.cos(t), R * math.sin(t)) for t in np.linspace(th0, 2 * math.pi - th0, n)]
    i = [(d + rb * math.cos(t), rb * math.sin(t)) for t in np.linspace(bt, 2 * math.pi - bt, n)]
    sh = (-R + xx) / 2
    V = ([(x - sh, y, 0.) for x, y in o] + [((a[0] + b[0]) / 2 - sh, (a[1] + b[1]) / 2, h) for a, b in zip(o, i)]
         + [(x - sh, y, 0.) for x, y in i])
    F = []
    for k in range(n - 1):
        F += [(k, k + 1, n + k + 1), (k, n + k + 1, n + k), (n + k, n + k + 1, 2 * n + k + 1), (n + k, 2 * n + k + 1, 2 * n + k)]
    return V, F


def kind2d(kind, sz, lo=False):
    """Decal shape by kind: m (crescent), s8/s6/s5/s4 (stars), else a disc. `lo` = fewer triangles."""
    if kind == 'm':
        return cres3d(sz, 5 if lo else 7, h=.14 * sz)
    if kind == 's8':
        return star3d(8, sz, .44 * sz, .14 * sz)
    if kind == 's6':
        return star3d(6, sz, .46 * sz, .14 * sz)
    if kind == 's5':
        return star3d(5, sz, .47 * sz, .16 * sz)
    if kind == 's4':
        return star3d(4, sz, .36 * sz, .14 * sz)
    return disc2d(sz, 6)


def frame_n(n, up=(0, 1, 0)):
    n = N_(n)
    u = A(up, float)
    t2 = u - n * (u @ n)
    if np.linalg.norm(t2) < 1e-3:
        t2 = N_((1, 0, 0)) - n * n[0]
    t2 = N_(t2)
    return np.cross(t2, n), t2, n


def seg(w, h, p=1.8, n=14, tilt=0., side=1):
    pts = []
    for k in range(n):
        th = 2 * math.pi * k / n
        c, s_ = math.cos(th), math.sin(th)
        x = w * math.copysign(abs(c) ** (2 / p), c)
        y = h * math.copysign(abs(s_) ** (2 / p), s_) - tilt * side * x / w
        pts.append((x, y))
    return pts


def fan(pts):
    return [(0, 0)] + list(pts), [(0, 1 + k, 1 + (k + 1) % len(pts)) for k in range(len(pts))]


def strip(top, bot):
    n = len(top)
    V = list(top) + list(bot)
    F = []
    for k in range(n - 1):
        F += [(k, k + 1, n + k + 1), (k, n + k + 1, n + k)]
    return V, F


def ringp(y, rx, rz, cz=0., N=10, e=2., o=0., cx=0.):
    out = []
    for k in range(N):
        t = 2 * math.pi * (k + o) / N
        s_, c_ = math.sin(t), math.cos(t)
        if e != 2:
            s_ = math.copysign(abs(s_) ** (2 / e), s_)
            c_ = math.copysign(abs(c_) ** (2 / e), c_)
        out.append((cx + rx * s_, y, cz + rz * c_))
    return out


class Grid:
    """Quad-facet surface (robe parts) that can carry decals and a texture.

    UVs come from the grid indices: u = column / columns (a wrapping grid's last facet runs
    to u=1, never back to 0), v = row / (rows-1), so a seam never smears across a tile.
    """

    def __init__(s, Pm, wrap, rc):
        s.P = A(Pm, float)
        s.R, s.C = s.P.shape[:2]
        s.wrap = wrap
        s.rc = A(rc, float)
        s.ax = A([s.rc[0] + (s.rc[-1] - s.rc[0]) * t for t in np.linspace(0, 1, 10)])

    def frame(s, r, c, fu=.5, fv=.5, up=(0, 1, 0)):
        c2 = (c + 1) % s.C
        a, b, cc, d = s.P[r, c], s.P[r, c2], s.P[r + 1, c], s.P[r + 1, c2]
        o = (a * (1 - fu) + b * fu) * (1 - fv) + (cc * (1 - fu) + d * fu) * fv
        n = N_(np.cross((b - a) + (d - cc), (cc - a) + (d - b)))
        q = s.ax[np.argmin(((s.ax - o) ** 2).sum(1))]
        if n @ (o - q) < 0:
            n = -n
        t1, t2, n = frame_n(n, up)
        return o, t1, t2, n

    def part(s, inv=False, th=0., uspan=(0., 1.), vspan=(0., 1.)):
        V = s.P.reshape(-1, 3).copy()
        if th:
            for r in range(s.R):
                for c in range(s.C):
                    p = V[r * s.C + c]
                    d = s.rc[r] - p
                    l_ = np.linalg.norm(d)
                    if l_ > th * 2:
                        V[r * s.C + c] = p + d / l_ * th
        F, FUV = [], []
        cols = s.C if s.wrap else s.C - 1
        u0, u1 = uspan
        v0, v1 = vspan
        for r in range(s.R - 1):
            for m in range(cols):
                a = r * s.C + m
                b = r * s.C + (m + 1) % s.C
                ua, ub = u0 + (u1 - u0) * m / cols, u0 + (u1 - u0) * (m + 1) / cols
                va, vb = v0 + (v1 - v0) * r / (s.R - 1), v0 + (v1 - v0) * (r + 1) / (s.R - 1)
                F += [(a, b, a + s.C), (b, b + s.C, a + s.C)]
                FUV += [((ua, va), (ub, va), (ua, vb)), ((ub, va), (ub, vb), (ua, vb))]
        return dict(V=V, F=A(F, int), ax=s.ax, fb=None, inv=inv, fuv=A(FUV, float))


class Model:
    """Parts + skeleton + skinning for one character."""

    def __init__(s, bones, col):
        s.B = dict(bones)
        s.names = list(s.B)
        s.ix = {n: i for i, n in enumerate(s.names)}
        s.COL = dict(col)
        s.P = []

    # ---- skinning ----------------------------------------------------------------------------
    def rigid(s, n, b):
        J = np.zeros((n, 4), int)
        J[:, 0] = s.ix[b]
        W = np.zeros((n, 4))
        W[:, 0] = 1
        return J, W

    def chainw(s, sv, joints, bones, bl):
        """Smooth blend weights along a bone chain, by a scalar coordinate per vertex."""
        n = len(sv)
        k = len(bones)
        w = np.zeros((n, k))
        cum = np.ones(n)
        for i, (jt, b) in enumerate(zip(joints, bl)):
            t = np.clip((sv - (jt - b)) / (2 * b), 0, 1)
            t = t * t * (3 - 2 * t)
            w[:, i] = cum * (1 - t)
            cum = cum * t
        w[:, k - 1] = cum
        J = np.zeros((n, 4), int)
        W = np.zeros((n, 4))
        # keep the 4 strongest influences per vertex
        order = np.argsort(-w, axis=1)[:, :4]
        for r in range(n):
            for c, i in enumerate(order[r]):
                J[r, c] = s.ix[bones[i]]
                W[r, c] = w[r, i]
        return J, W

    def add(s, part, mat, J=None, W=None, bone=None, **kw):
        if bone:
            J, W = s.rigid(len(part['V']), bone)
        part.update(mat=mat, J=J, W=W, **kw)
        s.P.append(part)
        return part

    def patch(s, V, F, n0, mat, bone, **kw):
        V = A(V, float)
        return s.add(dict(V=V, F=A(F, int), ax=A([V.mean(0) - .05 * N_(n0)]), fb=None), mat, bone=bone, **kw)

    def place(s, V2, F, o, t1, t2, n, sc=1., rot=0., off=.012, mat='gold', bone='hips'):
        c, sn = math.cos(rot), math.sin(rot)
        V = []
        for q in V2:
            x, y = q[0], q[1]
            z = q[2] if len(q) > 2 else 0.
            V.append(A(o) + A(n) * (off + z * sc) + (x * c - y * sn) * sc * A(t1) + (x * sn + y * c) * sc * A(t2))
        return s.patch(V, F, n, mat, bone)

    def stamp(s, G, r, c, fu, fv, kind, sz, rot=0., mat='gold', up=(0, 1, 0), bone='hips', off=.014, lo=False):
        o, t1, t2, n = G.frame(r, c, fu, fv, up)
        V2, F = kind2d(kind, sz, lo)
        return s.place(V2, F, o, t1, t2, n, 1., rot, off, mat, bone)

    def grid_rim(s, G, th):
        """Thickness band joining a grid's outer and inner shells along the open edges."""
        Vo = G.P.reshape(-1, 3)
        Vi = G.part(True, th)['V']
        n = len(Vo)
        V = np.vstack([Vo, Vi])
        F = []

        def quad(a, b):
            F.extend([(a, b, b + n), (a, b + n, a + n)])
        C, R = G.C, G.R
        for m in range(C if G.wrap else C - 1):
            for r in (0, R - 1):
                quad(r * C + m, r * C + (m + 1) % C)
        if not G.wrap:
            for r in range(R - 1):
                for c in (0, C - 1):
                    quad(r * C + c, (r + 1) * C + c)
        return dict(V=V, F=A(F, int), ax=G.ax, fb=None, both=True)

    # ---- transforms over many parts ------------------------------------------------------------
    def parts_on(s, bone):
        bi = s.ix[bone]
        return [p for p in s.P if (p['J'][:, 0] == bi).all() and (p['W'][:, 0] > .999).all()]

    # ---- output ----------------------------------------------------------------------------------
    def tri_count(s):
        n = 0
        for p in s.P:
            n += len(p['F']) * (2 if p.get('both') else 1)
        return n

    def flatten(s):
        """-> list of triangles: dict(P (3,3), N (3,3), J, W, key, luv (3,2) or None)."""
        tris = []
        for p in s.P:
            V, F, ax = p['V'], p['F'], p['ax']
            Q = V[F]
            nrm = np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0])
            ln = np.linalg.norm(nrm, axis=1)
            C = Q.mean(1)
            for i, f in enumerate(F):
                if ln[i] < 1e-10:
                    continue
                q = Q[i]
                n = nrm[i] / ln[i]
                c = C[i]
                if 'fuv' in p:
                    luv = A(p['fuv'][i], float)
                elif 'uv' in p:
                    luv = A(p['uv'][f], float)
                else:
                    luv = None
                m = p['mat']
                key = m if isinstance(m, str) else (m[p['fb'][i]] if isinstance(m, list) else m(c, n))
                vn = p['vn'][f] if 'vn' in p else None
                if p.get('both'):
                    for flip in (False, True):
                        o = [0, 2, 1] if flip else [0, 1, 2]
                        tris.append(dict(P=q[o], N=np.tile(-n if flip else n, (3, 1)), J=p['J'][f][o], W=p['W'][f][o],
                                         key=key, tex=p.get('tex'), luv=None if luv is None else luv[o]))
                    continue
                a = ax[np.argmin(((ax - c) ** 2).sum(1))]
                bad = n @ (c - a) < 0
                if p.get('inv'):
                    bad = not bad
                o = [0, 2, 1] if bad else [0, 1, 2]
                if bad:
                    n = -n
                nn = np.tile(n, (3, 1)) if vn is None else vn[o]
                tris.append(dict(P=q[o], N=nn, J=p['J'][f][o], W=p['W'][f][o], key=key, tex=p.get('tex'),
                                 luv=None if luv is None else luv[o]))
        return tris


def bake_uvs(tris, atlas, col, soft=()):
    """Register swatches for every flat colour, pack the atlas, and resolve per-corner UVs.

    Returns arrays P, N, UV, J, W ready for the exporter and the preview renderer; with `soft` (tile names), also C:
    per-corner RGBA whose alpha is 0 on those tiles' faces (psx_lit_actor.gdshader lights them softly) and 1 elsewhere.
    """
    for t in tris:
        if t['tex'] is None and not atlas.has('c:' + t['key']):
            atlas.swatch('c:' + t['key'], col[t['key']])
    atlas.pack()
    P, Nn, UV, J, W, Cc = [], [], [], [], [], []
    for t in tris:
        Cc.append(np.tile((1., 1., 1., 0. if t['tex'] in soft else 1.), (3, 1)))
        if t['tex'] is None:
            u, v = atlas.centre('c:' + t['key'])
            uv = np.tile((u, v), (3, 1))
        else:
            u, v = atlas.uv(t['tex'], t['luv'][:, 0], t['luv'][:, 1])
            uv = np.stack([u, v], 1)
        P.append(t['P'])
        Nn.append(t['N'])
        UV.append(uv)
        J.append(t['J'])
        W.append(t['W'])
    W = np.concatenate(W).astype(float)
    W /= W.sum(1, keepdims=True)
    out = dict(P=np.concatenate(P), N=np.concatenate(Nn), UV=np.concatenate(UV),
               J=np.concatenate(J).astype(np.uint8), W=W)
    if soft:
        out['C'] = np.concatenate(Cc)
    return out
