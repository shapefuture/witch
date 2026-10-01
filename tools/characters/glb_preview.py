"""Flat-shaded previews of an exported character GLB (no GPU needed).

Reads the .glb back with glb.GLB, poses it (rest or any animation frame) and rasterises it
orthographically with numpy: per-face shading from one key light, nearest-sampled textures.
`sheet()` lays out the standard views; `compare()` stacks reference crops above our views at
the same height so silhouette and proportions can be judged side by side.

    python tools/characters/glb_preview.py assets/characters/raccoon.glb out.png
"""

import math
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, __import__('os').path.dirname(__file__))
from glb import GLB, nz  # noqa: E402

A = np.array
BG = (0.15, 0.15, 0.16)

# camera forward vectors (orthographic); the character faces +Z, +X is its left
VIEWS = {
    'front': ((0, 0, -1), (0, 1, 0)),
    'left side': ((-1, 0, 0), (0, 1, 0)),     # as the sheet: facing image-left
    'back': ((0, 0, 1), (0, 1, 0)),
    'right side': ((1, 0, 0), (0, 1, 0)),
    'front 3/4': ((-0.6, -0.12, -0.8), (0, 1, 0)),
    'back 3/4': ((0.65, -0.1, 0.75), (0, 1, 0)),
    'top': ((0, -1, 0), (0, 0, -1)),
}


def linear_to_srgb(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)


def groups_from_glb(g, anim=None, t=0.0):
    out = []
    texcache = {}
    for d in g.triangles(anim, t):
        pbr = d['pbr']
        grp = dict(P=d['P'], N=d['N'])
        if 'baseColorTexture' in pbr:
            ti = pbr['baseColorTexture']['index']
            if ti not in texcache:
                src = g.js['textures'][ti]['source']
                texcache[ti] = np.asarray(g.image(src).convert('RGB')).astype(float) / 255
            grp['tex'] = texcache[ti]
            grp['UV'] = d['UV']
        else:
            grp['color'] = linear_to_srgb(pbr['baseColorFactor'][:3])
        grp['mat'] = d['mat']
        out.append(grp)
    return out


def render(groups, view, W=300, H=420, SS=2, bg=BG, box=None, light=(-0.45, 0.6, 0.65), fill=0.94):
    """box: (x0, x1, y0, y1) in view-plane units; default fits everything."""
    fwd, up = view
    fwd = nz(fwd)
    up = nz(up)
    right = nz(np.cross(fwd, up))
    up = np.cross(right, fwd)
    Lw = nz(right * light[0] + up * light[1] - fwd * light[2])
    allP = np.concatenate([g['P'].reshape(-1, 3) for g in groups])
    X, Y = allP @ right, allP @ up
    if box is None:
        box = (X.min(), X.max(), Y.min(), Y.max())
    x0, x1, y0, y1 = box
    w, h = W * SS, H * SS
    sc = min(w / (x1 - x0), h / (y1 - y0)) * fill
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    img = np.tile(A(bg, float), (h, w, 1))
    zb = np.full((h, w), 1e9)
    for g in groups:
        P = g['P']
        SX = (P @ right - cx) * sc + w / 2
        SY = h / 2 - (P @ up - cy) * sc
        Z = P @ fwd
        gn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
        front = gn @ fwd < 0
        Nv = g['N'] / np.maximum(np.linalg.norm(g['N'], axis=2, keepdims=True), 1e-9)
        sh = 0.42 + 0.68 * np.clip(Nv @ Lw, 0, 1) ** 0.9  # per vertex
        for i in np.nonzero(front)[0]:
            xs, ys, zs = SX[i], SY[i], Z[i]
            xa, xb = max(int(xs.min()), 0), min(int(xs.max()) + 1, w)
            ya, yb = max(int(ys.min()), 0), min(int(ys.max()) + 1, h)
            if xa >= xb or ya >= yb:
                continue
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(d) < 1e-9:
                continue
            px, py = np.meshgrid(np.arange(xa, xb) + .5, np.arange(ya, yb) + .5)
            l1 = ((ys[1] - ys[2]) * (px - xs[2]) + (xs[2] - xs[1]) * (py - ys[2])) / d
            l2 = ((ys[2] - ys[0]) * (px - xs[2]) + (xs[0] - xs[2]) * (py - ys[2])) / d
            l3 = 1 - l1 - l2
            m = (l1 >= -1e-4) & (l2 >= -1e-4) & (l3 >= -1e-4)
            z = l1 * zs[0] + l2 * zs[1] + l3 * zs[2]
            sub = zb[ya:yb, xa:xb]
            m &= z < sub - 1e-7
            if not m.any():
                continue
            sub[m] = z[m]
            s = (l1 * sh[i, 0] + l2 * sh[i, 1] + l3 * sh[i, 2])[m]
            if 'tex' in g:
                T = g['tex']
                uv = g['UV'][i]
                u = l1 * uv[0, 0] + l2 * uv[1, 0] + l3 * uv[2, 0]
                v = l1 * uv[0, 1] + l2 * uv[1, 1] + l3 * uv[2, 1]
                tx = np.clip((u[m] * T.shape[1]).astype(int), 0, T.shape[1] - 1)
                ty = np.clip((v[m] * T.shape[0]).astype(int), 0, T.shape[0] - 1)
                col = T[ty, tx]
            else:
                col = np.broadcast_to(g['color'], (int(m.sum()), 3))
            img[ya:yb, xa:xb][m] = np.clip(col * s[:, None], 0, 1)
    img = img.reshape(H, SS, W, SS, 3).mean((1, 3))
    return img


def to_pil(img):
    return Image.fromarray((np.clip(img, 0, 1) * 255 + .5).astype(np.uint8))


def label(im, text, col=(230, 230, 230)):
    d = ImageDraw.Draw(im)
    d.text((6, 4), text, fill=col)
    return im


def fit_box(groups, views, pad=0.04):
    """One box (in view units) big enough for every view, so all panels share a scale."""
    allP = np.concatenate([g['P'].reshape(-1, 3) for g in groups])
    ext = 0
    ylo, yhi = 1e9, -1e9
    for fwd, up in views:
        fwd, up = nz(fwd), nz(up)
        right = nz(np.cross(fwd, up))
        up = np.cross(right, fwd)
        X, Y = allP @ right, allP @ up
        ext = max(ext, np.abs(X).max())
        ylo, yhi = min(ylo, Y.min()), max(yhi, Y.max())
    h = yhi - ylo
    return (-ext - pad * h, ext + pad * h, ylo - pad * h, yhi + pad * h)


def sheet(path_glb, out_png, views=('front', 'left side', 'back', 'right side', 'front 3/4', 'back 3/4'),
          W=260, H=380, anim=None, t=0.0, title=''):
    g = GLB(path_glb)
    groups = groups_from_glb(g, anim, t)
    vs = [VIEWS[v] for v in views]
    box = fit_box(groups, vs[:4])
    tiles = [label(to_pil(render(groups, VIEWS[v], W, H, box=box)), v) for v in views]
    cols = 3 if len(tiles) > 4 else len(tiles)
    rows = math.ceil(len(tiles) / cols)
    out = Image.new('RGB', (cols * W, rows * H + 18), tuple(int(c * 255) for c in BG))
    for k, t_ in enumerate(tiles):
        out.paste(t_, ((k % cols) * W, 18 + (k // cols) * H))
    label(out, title or path_glb)
    out.save(out_png)
    return out


def frames(path_glb, out_png, anim, n=6, view='front 3/4', W=200, H=300):
    g = GLB(path_glb)
    an = [a for a in g.js['animations'] if a['name'] == anim][0]
    T = g.accessor(an['samplers'][0]['input'])
    dur = float(T[-1])
    rest = groups_from_glb(g)
    box = fit_box(rest, [VIEWS[view]], pad=0.12)
    out = Image.new('RGB', (n * W, H + 18), tuple(int(c * 255) for c in BG))
    for k in range(n):
        t = dur * k / n
        im = to_pil(render(groups_from_glb(g, anim, t), VIEWS[view], W, H, box=box))
        out.paste(label(im, '%s t=%.2f' % (anim, t)), (k * W, 18))
    label(out, '%s  %s  (%d keys, %.2f s)' % (path_glb.split('/')[-1], anim, len(T), dur))
    out.save(out_png)
    return out


def compare(path_glb, ref_png, refs, out_png, views=('front', 'left side', 'back'), Hc=300, W=240,
            title='', anim=None, t=0.0, extra=()):
    """refs: per view (x_centre, y_top, y_bottom) of the character in the reference image.
    Both rows show the character Hc pixels tall from feet to top, so proportions compare
    directly. `extra` adds (label, view, box) close-ups in a third row."""
    ref = Image.open(ref_png).convert('RGB')
    g = GLB(path_glb)
    groups = groups_from_glb(g, anim, t)
    allP = np.concatenate([gr['P'].reshape(-1, 3) for gr in groups])
    top = allP[:, 1].max()
    m = 0.08 * Hc
    H = int(Hc + 2 * m)
    rows = 3 if extra else 2
    out = Image.new('RGB', (W * len(views), H * rows + 18), tuple(int(c * 255) for c in BG))
    for i, (v, (xc, yt, yb)) in enumerate(zip(views, refs)):
        k = Hc / (yb - yt)
        bw, bh = W / k, H / k
        crop = ref.crop((int(xc - bw / 2), int(yt - m / k), int(xc + bw / 2), int(yt - m / k + bh)))
        out.paste(label(crop.resize((W, H), Image.LANCZOS), 'sheet ' + v), (i * W, 18))
        u = top / Hc  # model units per pixel
        box = (-W / 2 * u, W / 2 * u, -m * u, (Hc + m) * u)
        im = to_pil(render(groups, VIEWS[v], W, H, box=box, fill=1.0))
        out.paste(label(im, 'ours ' + v), (i * W, 18 + H))
    for i, (lab, v, box) in enumerate(extra):
        im = to_pil(render(groups, VIEWS[v], W, H, box=box, fill=1.0))
        out.paste(label(im, lab), (i * W, 18 + 2 * H))
    label(out, title or path_glb)
    out.save(out_png)
    return out


if __name__ == '__main__':
    sheet(sys.argv[1], sys.argv[2])
