"""Six-view and close-up previews of the exported arrays (textured, nearest-sampled atlas).

Orthographic, flat-shaded with a soft key from the front-left, z-buffered, 2x supersampled.
Used to judge the model against the concept sheet; it is not the game's renderer.
"""
import numpy as np
from PIL import Image, ImageDraw

A = np.array
BG = (.16, .53, .19)
VIEWS = [('FRONT', (0, 0, -1), (0, 1, 0)), ('BACK', (0, 0, 1), (0, 1, 0)), ('RIGHT SIDE', (1, 0, 0), (0, 1, 0)),
         ('FRONT-LEFT 3/4', (-.7, -.12, -.7), (0, 1, 0)), ('BACK-LEFT 3/4', (-1, -.15, 1), (0, 1, 0)),
         ('TOP', (0, -1, 0), (0, 0, -1))]


def _n(v):
    v = A(v, float)
    return v / np.linalg.norm(v)


def render(arr, atlas, fwd, up, W=460, H=600, SS=2, bg=BG, crop=None, light=(-.2, .38, .9)):
    """`fwd` is the viewing direction (camera looks along fwd)."""
    tex = np.asarray(atlas.convert('RGB')).astype(float) / 255.
    th, tw = tex.shape[:2]
    T = arr['P'].reshape(-1, 3, 3)
    Nn = arr['N'].reshape(-1, 3, 3).mean(1)
    Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)
    UV = arr['UV'].reshape(-1, 3, 2)
    fwd = _n(fwd)
    up = _n(up)
    right = _n(np.cross(fwd, up))
    up = np.cross(right, fwd)
    Xc, Yc, Zc = T @ right, T @ up, T @ fwd
    face = (Nn @ fwd) < 0
    Lc = _n(light)
    Lw = right * Lc[0] + up * Lc[1] - fwd * Lc[2]
    shade = .58 + .42 * np.clip(Nn @ Lw, 0, 1) ** .8
    if crop:
        x0, x1, y0, y1 = crop
    else:
        x0, x1, y0, y1 = Xc.min(), Xc.max(), Yc.min(), Yc.max()
    w, h = W * SS, H * SS
    sc = min(w / (x1 - x0), h / (y1 - y0)) * .94
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    SX = (Xc - cx) * sc + w / 2
    SY = h / 2 - (Yc - cy) * sc
    img = np.tile(A(bg, float), (h, w, 1))
    zb = np.full((h, w), 1e9)
    for i in np.where(face)[0]:
        xs, ys, zs = SX[i], SY[i], Zc[i]
        xa, xb = max(int(xs.min()), 0), min(int(xs.max()) + 1, w)
        ya, yb = max(int(ys.min()), 0), min(int(ys.max()) + 1, h)
        if xa >= xb or ya >= yb:
            continue
        px, py = np.meshgrid(np.arange(xa, xb) + .5, np.arange(ya, yb) + .5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-9:
            continue
        l1 = ((ys[1] - ys[2]) * (px - xs[2]) + (xs[2] - xs[1]) * (py - ys[2])) / d
        l2 = ((ys[2] - ys[0]) * (px - xs[2]) + (xs[0] - xs[2]) * (py - ys[2])) / d
        l3 = 1 - l1 - l2
        m = (l1 >= -1e-4) & (l2 >= -1e-4) & (l3 >= -1e-4)
        z = l1 * zs[0] + l2 * zs[1] + l3 * zs[2]
        sub = zb[ya:yb, xa:xb]
        m &= z < sub - 1e-6
        if not m.any():
            continue
        sub[m] = z[m]
        u = l1 * UV[i, 0, 0] + l2 * UV[i, 1, 0] + l3 * UV[i, 2, 0]
        v = l1 * UV[i, 0, 1] + l2 * UV[i, 1, 1] + l3 * UV[i, 2, 1]
        tx = np.clip((u[m] * tw).astype(int), 0, tw - 1)
        ty = np.clip((v[m] * th).astype(int), 0, th - 1)
        img[ya:yb, xa:xb][m] = np.clip(tex[ty, tx] * shade[i], 0, 1)
    img = img.reshape(H, SS, W, SS, 3).mean((1, 3))
    return Image.fromarray((img * 255 + .5).astype(np.uint8))


def sixview(arr, atlas, path, title=None, cell=(330, 430)):
    W, H = cell
    sheet = Image.new('RGB', (W * 3, H * 2 + (24 if title else 0)), tuple(int(c * 255) for c in BG))
    d = ImageDraw.Draw(sheet)
    oy = 24 if title else 0
    if title:
        d.text((8, 6), title, fill=(255, 255, 255))
    # one scale for every view so proportions compare
    T = arr['P']
    ext = max(np.ptp(T[:, 0]), np.ptp(T[:, 1]), np.ptp(T[:, 2])) * .55
    c = (T.min(0) + T.max(0)) / 2
    for k, (name, f, u) in enumerate(VIEWS):
        fw = _n(f)
        uu = _n(u)
        rt = _n(np.cross(fw, uu))
        uu = np.cross(rt, fw)
        cx, cy = c @ rt, c @ uu
        crop = (cx - ext * W / H, cx + ext * W / H, cy - ext, cy + ext)
        im = render(arr, atlas, f, u, W, H, crop=crop)
        sheet.paste(im, ((k % 3) * W, oy + (k // 3) * H))
        d.text(((k % 3) * W + 6, oy + (k // 3) * H + 4), name, fill=(255, 255, 255))
    sheet.save(path)
    return sheet


def closeup(arr, atlas, path, box, fwd=(0, 0, -1), size=640):
    im = render(arr, atlas, fwd, (0, 1, 0), size, size, crop=box)
    im.save(path)
    return im
