"""Painted pixel textures for the plates (numpy), handed to Blender as images (nothing is written).

They are line-and-mask sheets: RGBA where alpha says where the paint is. Pixel-stepped on purpose
(the reference's glyphs and the eye are pixel art): sampled with Closest interpolation.
"""
import math

import bpy
import numpy as np


def to_image(name, rgba, srgb=True):
    """numpy (h, w, 4) float 0..1, row 0 = TOP -> a packed Blender image."""
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).astype(np.float32).ravel())
    img.pack()
    return img


def _canvas(w, h):
    return np.zeros((h, w, 4), np.float32)


def eye(w=128, h=64, ink=(0.20, 0.13, 0.08)):
    """The wall eye: almond lids, ringed iris, a crown of spikes above and a few below."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w / 2.0, h * 0.56
    a = w * 0.36
    out = _canvas(w, h)
    m = np.zeros((h, w), bool)
    # lids: two arcs y = cy -/+ b * (1 - (x/a)^2)
    t = (xx - cx) / a
    inside = np.abs(t) <= 1.0
    for b, sgn in ((h * 0.25, -1), (h * 0.17, 1)):
        lid = cy + sgn * b * (1 - t ** 2)
        m |= inside & (np.abs(yy - lid) <= 1.6)
    # pointed corners
    for sx in (-1, 1):
        tip = (np.abs(yy - cy) <= 1.2) & (np.abs(xx - (cx + sx * (a + 3))) <= 4)
        m |= tip
    r = np.hypot(xx - cx, (yy - cy) * 1.0)
    m |= (np.abs(r - 11.5) <= 1.6) | (np.abs(r - 6.0) <= 1.5) | (r <= 2.2)
    # spikes above the upper lid, a few under the lower one
    for k in range(7):
        sx = cx + (k - 3) * a * 0.30
        tt = (sx - cx) / a
        base = cy - h * 0.25 * (1 - tt ** 2) - 3
        height = h * (0.17 if k in (2, 3, 4) else 0.13)
        lean = (sx - cx) * 0.18
        tip_x, tip_y = sx + lean, base - height
        # triangle by barycentric test
        p0, p1, p2 = (sx - 3.2, base), (sx + 3.2, base), (tip_x, tip_y)
        m |= _tri(xx, yy, p0, p1, p2)
    for k in range(4):
        sx = cx + a * (0.25 + 0.2 * k)
        tt = min((sx - cx) / a, 0.98)
        base = cy + h * 0.17 * (1 - tt ** 2) + 3
        m |= _tri(xx, yy, (sx - 2.6, base), (sx + 2.6, base), (sx + 2.5, base + h * 0.1))
    out[m] = (*ink, 1.0)
    return out


def _tri(xx, yy, p0, p1, p2):
    def side(a, b):
        return (xx - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (yy - b[1])
    d1, d2, d3 = side(p0, p1), side(p1, p2), side(p2, p0)
    neg = (d1 < 0) | (d2 < 0) | (d3 < 0)
    pos = (d1 > 0) | (d2 > 0) | (d3 > 0)
    return ~(neg & pos)


def glyphs(cells=4, px=16, seed=3, ink=(0.10, 0.07, 0.05)):
    """An atlas of carved box glyphs (seal-like: a frame and a few stepped bars)."""
    rng = np.random.default_rng(seed)
    out = _canvas(cells * px, cells * px)
    out[..., :3] = ink
    for gy in range(cells):
        for gx in range(cells):
            g = np.zeros((px, px), bool)
            g[2:px - 2, 2] = g[2:px - 2, px - 3] = True
            g[2, 2:px - 2] = g[px - 3, 2:px - 2] = True
            kind = rng.integers(0, 4)
            mid = px // 2
            if kind == 0:     # a T
                g[5, 4:px - 4] = True
                g[5:px - 4, mid - 1:mid + 1] = True
            elif kind == 1:   # a ring with a bar
                yy, xx = np.mgrid[0:px, 0:px]
                rr = np.hypot(xx - mid + 0.5, yy - mid + 0.5)
                g |= (np.abs(rr - 3.5) < 0.9)
                g[4:px - 4, mid - 1:mid] = True
            elif kind == 2:   # stepped meander
                for k in range(4, px - 4, 3):
                    g[k, 4:px - 6 + (k % 2) * 2] = True
                g[4:px - 4, px - 6] = True
            else:             # a cross of bars
                g[mid - 1:mid + 1, 4:px - 4] = True
                g[4:px - 4, 5] = g[4:px - 4, px - 6] = True
            out[gy * px:(gy + 1) * px, gx * px:(gx + 1) * px, 3] = g
    return out


def scroll_end(n=48, paper=(0.86, 0.79, 0.62), ink=(0.30, 0.22, 0.14)):
    """The rolled end of a scroll: an Archimedean spiral of paper edge."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2.0
    r = np.hypot(xx - c, yy - c) / (n / 2.0)
    th = np.arctan2(yy - c, xx - c)
    phase = (r * 4.2 - th / math.tau) % 1.0
    line = (np.abs(phase - 0.5) < 0.16) & (r < 0.97)
    out = _canvas(n, n)
    out[...] = (*paper, 1.0)
    out[line] = (*ink, 1.0)
    out[r > 0.97] = (*[c * 0.7 for c in paper], 1.0)
    return out


def star(n=96, ink=(0.32, 0.27, 0.20)):
    """The pale medallion over the third arch: an eight-point star in a ring."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2.0
    r = np.hypot(xx - c, yy - c) / (n / 2.0)
    th = np.arctan2(yy - c, xx - c)
    spikes = 0.35 + 0.5 * np.abs(np.cos(th * 4.0)) ** 6
    m = (np.abs(r - 0.93) < 0.04) | (np.abs(r - spikes) < 0.035) | (r < 0.08)
    for k in range(8):
        a = k * math.pi / 4
        d = np.abs(-(xx - c) * math.sin(a) + (yy - c) * math.cos(a)) / (n / 2)
        along = ((xx - c) * math.cos(a) + (yy - c) * math.sin(a)) / (n / 2)
        m |= (d < 0.02) & (along > 0.1) & (along < 0.85)
    out = _canvas(n, n)
    out[m] = (*ink, 1.0)
    return out


def carpet(n=1024, extent=8.4, pitch=1.18, purple=(0.30, 0.21, 0.35), gold=(0.47, 0.43, 0.27), seam=(0.15, 0.12, 0.10)):
    """A hexagonal spiral seen from above (the floor's inlay): purple band, dark seam, pale olive-gold
    band, dark seam. `extent` is the side of the square in metres; alpha fades the outer turns."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    x = (xx / (n - 1) - 0.5) * extent
    z = (yy / (n - 1) - 0.5) * extent
    th = np.arctan2(z, x)
    # hexagonal radius: the distance to the hexagon through this point
    sector = np.round(th / (math.pi / 3)) * (math.pi / 3)
    rh = np.hypot(x, z) * np.cos(th - sector)
    phase = rh / pitch - th / math.tau
    f = phase % 1.0
    out = _canvas(n, n)
    band = np.where(f < 0.40, 0, np.where(f < 0.47, 1, np.where(f < 0.90, 2, 3)))
    cols = np.array([purple, seam, gold, seam], np.float32)
    out[..., :3] = cols[band]
    r = np.hypot(x, z)
    out[..., 3] = np.clip((extent * 0.47 - r) / 0.25, 0, 1) * (r > 0.18)
    # a small star at the centre
    out[(r < 0.22)] = (*gold, 1.0)
    return out
