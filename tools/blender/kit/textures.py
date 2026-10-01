"""Hand-painted, gently mottled 128px tiles (numpy + PIL; no Blender needed).

Each material is a small palette plus a painting style. The tiles carry ALBEDO only: light is baked
into vertex colours. They are deliberately low-contrast with soft gradients, directional dabs and a
paper-like grain: the "stained parchment" surface of the diorama, never a clean flat fill.
"""
import zlib

import numpy as np
from PIL import Image, ImageDraw

SIZE = 128

# name: palette (dark, mid, light), accent colours, stroke angle (deg, None = isotropic dabs),
# blotch contrast, stroke contrast
SPECS = {
    "grass_a":  dict(p=[(0.27, 0.36, 0.16), (0.38, 0.47, 0.20), (0.56, 0.64, 0.26)], acc=[(0.70, 0.74, 0.30), (0.30, 0.30, 0.20)], angle=80, blot=1.0, dabs=140),
    "grass_b":  dict(p=[(0.40, 0.38, 0.17), (0.60, 0.52, 0.22), (0.78, 0.66, 0.30)], acc=[(0.85, 0.74, 0.34), (0.45, 0.40, 0.20)], angle=75, blot=1.0, dabs=140),
    "dirt":     dict(p=[(0.30, 0.22, 0.17), (0.46, 0.34, 0.23), (0.62, 0.48, 0.31)], acc=[(0.70, 0.58, 0.40), (0.34, 0.26, 0.30)], angle=None, blot=1.1, dabs=170),
    "stone":    dict(p=[(0.38, 0.35, 0.42), (0.52, 0.48, 0.52), (0.68, 0.63, 0.58)], acc=[(0.50, 0.58, 0.40), (0.30, 0.28, 0.36)], angle=None, blot=1.2, dabs=120),
    "bark":     dict(p=[(0.22, 0.15, 0.13), (0.34, 0.24, 0.20), (0.50, 0.36, 0.26)], acc=[(0.26, 0.22, 0.30), (0.58, 0.42, 0.26)], angle=90, blot=1.1, dabs=190),
    "leaf_a":   dict(p=[(0.20, 0.30, 0.14), (0.32, 0.44, 0.18), (0.54, 0.64, 0.24)], acc=[(0.70, 0.78, 0.30), (0.20, 0.22, 0.20)], angle=None, blot=1.1, dabs=170),
    "leaf_b":   dict(p=[(0.62, 0.34, 0.14), (0.80, 0.58, 0.20), (0.90, 0.74, 0.30)], acc=[(0.78, 0.36, 0.22), (0.50, 0.24, 0.20)], angle=None, blot=1.0, dabs=170),
    "leaf_c":   dict(p=[(0.18, 0.22, 0.16), (0.26, 0.33, 0.20), (0.38, 0.46, 0.24)], acc=[(0.36, 0.28, 0.40), (0.54, 0.62, 0.26)], angle=None, blot=1.0, dabs=170),
    "wood":     dict(p=[(0.38, 0.25, 0.15), (0.54, 0.38, 0.22), (0.68, 0.50, 0.30)], acc=[(0.30, 0.20, 0.16), (0.74, 0.58, 0.36)], angle=0, blot=0.8, dabs=150),
    "wood_dark": dict(p=[(0.20, 0.14, 0.12), (0.31, 0.21, 0.16), (0.44, 0.31, 0.21)], acc=[(0.16, 0.12, 0.14), (0.52, 0.38, 0.26)], angle=0, blot=0.8, dabs=150),
    "plaster":  dict(p=[(0.74, 0.64, 0.46), (0.88, 0.79, 0.60), (0.96, 0.90, 0.74)], acc=[(0.80, 0.62, 0.48), (0.70, 0.66, 0.62)], angle=None, blot=0.9, dabs=120),
    "roof":     dict(p=[(0.60, 0.28, 0.14), (0.76, 0.40, 0.17), (0.88, 0.56, 0.26)], acc=[(0.84, 0.36, 0.28), (0.46, 0.20, 0.20)], angle=0, blot=0.9, dabs=160),
    "brass":    dict(p=[(0.58, 0.40, 0.14), (0.78, 0.58, 0.20), (0.94, 0.80, 0.40)], acc=[(0.98, 0.90, 0.60), (0.40, 0.28, 0.14)], angle=20, blot=0.9, dabs=110),
    "iron":     dict(p=[(0.18, 0.17, 0.24), (0.28, 0.27, 0.36), (0.42, 0.40, 0.50)], acc=[(0.50, 0.30, 0.20), (0.12, 0.12, 0.18)], angle=None, blot=1.0, dabs=110),
    "velvet":   dict(p=[(0.42, 0.12, 0.16), (0.62, 0.18, 0.18), (0.80, 0.30, 0.24)], acc=[(0.90, 0.46, 0.30), (0.28, 0.10, 0.18)], angle=90, blot=1.0, dabs=140),
    "purple":   dict(p=[(0.26, 0.16, 0.38), (0.38, 0.24, 0.52), (0.52, 0.38, 0.66)], acc=[(0.66, 0.50, 0.78), (0.18, 0.12, 0.28)], angle=None, blot=1.0, dabs=130),
    "gold":     dict(p=[(0.70, 0.52, 0.20), (0.86, 0.68, 0.28), (0.97, 0.84, 0.46)], acc=[(1.00, 0.92, 0.62), (0.56, 0.40, 0.18)], angle=None, blot=0.9, dabs=130),
    "crystal":  dict(p=[(0.30, 0.18, 0.46), (0.46, 0.28, 0.64), (0.70, 0.50, 0.84)], acc=[(0.86, 0.74, 0.96), (0.20, 0.12, 0.34)], angle=35, blot=1.2, dabs=90),
    "cream":    dict(p=[(0.82, 0.74, 0.58), (0.92, 0.85, 0.70), (0.99, 0.95, 0.84)], acc=[(0.86, 0.60, 0.44), (0.74, 0.70, 0.74)], angle=None, blot=0.8, dabs=100),
    "coral":    dict(p=[(0.70, 0.26, 0.22), (0.86, 0.38, 0.30), (0.96, 0.58, 0.44)], acc=[(0.98, 0.76, 0.56), (0.48, 0.18, 0.22)], angle=None, blot=0.9, dabs=120),
    "fur_a":    dict(p=[(0.40, 0.30, 0.24), (0.58, 0.44, 0.32), (0.76, 0.62, 0.46)], acc=[(0.92, 0.84, 0.70), (0.26, 0.20, 0.20)], angle=70, blot=0.9, dabs=150),
    "fur_b":    dict(p=[(0.38, 0.38, 0.42), (0.56, 0.54, 0.56), (0.76, 0.72, 0.70)], acc=[(0.90, 0.86, 0.82), (0.22, 0.22, 0.28)], angle=70, blot=0.9, dabs=150),
    "rock_a":   dict(p=[(0.46, 0.43, 0.30), (0.60, 0.56, 0.40), (0.76, 0.70, 0.50)], acc=[(0.84, 0.78, 0.58), (0.34, 0.30, 0.26), (0.46, 0.38, 0.46)], angle=None, blot=1.25, dabs=130),
    "rock_b":   dict(p=[(0.28, 0.25, 0.19), (0.40, 0.36, 0.27), (0.54, 0.48, 0.34)], acc=[(0.62, 0.56, 0.40), (0.20, 0.17, 0.16), (0.34, 0.27, 0.36)], angle=None, blot=1.3, dabs=130),
    "floor":    dict(p=[(0.22, 0.19, 0.16), (0.32, 0.27, 0.21), (0.44, 0.37, 0.28)], acc=[(0.46, 0.36, 0.44), (0.22, 0.19, 0.16), (0.62, 0.54, 0.38)], angle=None, blot=1.2, dabs=150),
    "carpet_purple": dict(p=[(0.22, 0.15, 0.30), (0.32, 0.22, 0.42), (0.44, 0.32, 0.54)], acc=[(0.56, 0.44, 0.66), (0.16, 0.11, 0.24)], angle=None, blot=1.1, dabs=140),
    "carpet_gold": dict(p=[(0.50, 0.46, 0.22), (0.66, 0.60, 0.31), (0.82, 0.76, 0.44)], acc=[(0.90, 0.84, 0.56), (0.40, 0.34, 0.20)], angle=None, blot=1.1, dabs=140),
    "carpet_dark": dict(p=[(0.14, 0.11, 0.10), (0.22, 0.17, 0.14), (0.32, 0.25, 0.19)], acc=[(0.10, 0.08, 0.10), (0.40, 0.30, 0.22)], angle=None, blot=0.9, dabs=100),
    "shelf":    dict(p=[(0.15, 0.10, 0.10), (0.25, 0.17, 0.15), (0.37, 0.26, 0.20)], acc=[(0.44, 0.30, 0.22), (0.12, 0.09, 0.12)], angle=0, blot=0.9, dabs=170),
    "book_red": dict(p=[(0.30, 0.15, 0.10), (0.42, 0.22, 0.14), (0.56, 0.32, 0.20)], acc=[(0.70, 0.52, 0.32), (0.20, 0.10, 0.08)], angle=90, blot=0.9, dabs=90),
    "book_olive": dict(p=[(0.26, 0.27, 0.14), (0.38, 0.38, 0.20), (0.52, 0.52, 0.30)], acc=[(0.70, 0.64, 0.38), (0.16, 0.18, 0.10)], angle=90, blot=0.9, dabs=90),
    "book_purple": dict(p=[(0.22, 0.16, 0.28), (0.32, 0.24, 0.38), (0.44, 0.34, 0.50)], acc=[(0.68, 0.58, 0.40), (0.15, 0.10, 0.20)], angle=90, blot=0.9, dabs=90),
    "book_tan": dict(p=[(0.50, 0.40, 0.27), (0.66, 0.55, 0.37), (0.82, 0.72, 0.52)], acc=[(0.36, 0.26, 0.18), (0.90, 0.84, 0.66)], angle=90, blot=0.9, dabs=90),
    "book_teal": dict(p=[(0.26, 0.28, 0.24), (0.37, 0.39, 0.33), (0.50, 0.52, 0.44)], acc=[(0.70, 0.62, 0.40), (0.16, 0.18, 0.16)], angle=90, blot=0.9, dabs=90),
    "scroll":   dict(p=[(0.68, 0.60, 0.42), (0.83, 0.75, 0.55), (0.94, 0.88, 0.70)], acc=[(0.60, 0.46, 0.32), (0.98, 0.94, 0.80)], angle=0, blot=0.8, dabs=80),
    "cloak":    dict(p=[(0.20, 0.18, 0.14), (0.31, 0.28, 0.21), (0.45, 0.41, 0.31)], acc=[(0.56, 0.50, 0.36), (0.12, 0.10, 0.10)], angle=None, blot=1.2, dabs=120),
    "crystal_grey": dict(p=[(0.38, 0.38, 0.40), (0.55, 0.54, 0.54), (0.74, 0.72, 0.70)], acc=[(0.86, 0.82, 0.74), (0.24, 0.24, 0.28)], angle=35, blot=1.2, dabs=90),
    "void":     dict(p=[(0.015, 0.014, 0.02), (0.03, 0.028, 0.04), (0.06, 0.055, 0.07)], acc=[(0.02, 0.02, 0.03), (0.08, 0.07, 0.09)], angle=None, blot=0.5, dabs=40),
    "mush_cap": dict(p=[(0.66, 0.20, 0.18), (0.82, 0.30, 0.24), (0.92, 0.46, 0.34)], acc=[(0.98, 0.92, 0.78), (0.40, 0.14, 0.20)], angle=None, blot=0.9, dabs=60),
}


# Architecture is nearly flat per facet with a faint paper grain (the reference's big crystalline
# planes); props and books keep the full painterly mottle.
CALM = {"rock_a": 0.34, "rock_b": 0.34, "floor": 0.45, "plaster": 0.5, "cloak": 0.5, "carpet_purple": 0.5, "carpet_gold": 0.5,
        "crystal_grey": 0.6, "wood_dark": 0.7, "void": 0.3, "carpet_dark": 0.5}


def _fft_noise(rng, n, beta):
    """Tileable noise with a 1/f^beta spectrum, normalised to 0..1."""
    white = rng.standard_normal((n, n))
    spec = np.fft.fft2(white)
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = spec / (f ** (beta / 2.0))
    spec[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def _lerp3(p, t):
    a, b, c = (np.array(x, dtype=np.float32) for x in p)
    t = t[..., None]
    lo = a + (b - a) * np.clip(t * 2.0, 0, 1)
    return lo + (c - b) * np.clip(t * 2.0 - 1.0, 0, 1)


def make_tile(name, size=SIZE, seed=0):
    spec = SPECS[name]
    rng = np.random.default_rng(zlib.crc32(name.encode()) + seed)
    big = _fft_noise(rng, size, 2.6)
    mid = _fft_noise(rng, size, 1.6)
    fine = _fft_noise(rng, size, 0.8)
    calm = CALM.get(name, 1.0)
    t = np.clip(0.5 + (big - 0.5) * 1.5 * spec["blot"] * calm + (mid - 0.5) * 0.7 * calm, 0, 1)
    img = _lerp3(spec["p"], t)
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
    # dabs: soft translucent ellipses of accent colour, drawn wrapped so the tile repeats cleanly
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer, "RGBA")
    for _ in range(spec["dabs"]):
        cx, cy = rng.uniform(0, size, 2)
        w = rng.uniform(2, 9)
        h = rng.uniform(1, 4)
        ang = spec["angle"] if spec["angle"] is not None else rng.uniform(0, 180)
        ang = np.radians(ang + rng.normal(0, 14))
        colour = spec["acc"][int(rng.integers(0, len(spec["acc"])))]
        alpha = int(rng.uniform(28, 80) * calm)
        pts = []
        for k in range(10):
            a = np.pi * 2 * k / 10
            x, y = np.cos(a) * w, np.sin(a) * h
            pts.append((x * np.cos(ang) - y * np.sin(ang), x * np.sin(ang) + y * np.cos(ang)))
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                draw.polygon([(cx + px + ox, cy + py + oy) for px, py in pts], fill=tuple(int(c * 255) for c in colour) + (alpha,))
    pil = Image.alpha_composite(pil, layer)
    arr = np.asarray(pil.convert("RGB"), dtype=np.float32) / 255.0
    arr *= (1.0 - 0.06 * calm + 0.12 * calm * fine)[..., None]
    arr += rng.normal(0, 0.012 * calm, arr.shape).astype(np.float32)
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGB")


# Pixel-stepped glyph art: the carved boxes and the eye on the wall. Edges are deliberately jagged.
GLYPH_INK = (40, 28, 22)


def _blocky(draw, grid, rects, scale, ox=0, oy=0):
    for (x0, y0, x1, y1) in rects:
        draw.rectangle([ox + x0 * scale, oy + y0 * scale, ox + (x1 + 1) * scale - 1, oy + (y1 + 1) * scale - 1], fill=GLYPH_INK)


def make_glyph_sheet(base="wood", size=128):
    """2x2 sheet of carved glyphs on a mottled tile: nested squares, a cross, a ring, a key."""
    tile = make_tile(base, size, seed=11).convert("RGB")
    draw = ImageDraw.Draw(tile)
    cell = size // 2
    sc = cell // 16
    glyphs = [
        [(3, 3, 12, 3), (3, 3, 3, 12), (3, 12, 12, 12), (12, 5, 12, 12), (5, 5, 10, 5), (5, 5, 5, 10), (5, 10, 10, 10), (8, 7, 8, 8)],
        [(7, 2, 8, 13), (2, 7, 13, 8), (5, 5, 5, 5), (10, 5, 10, 5), (5, 10, 5, 10), (10, 10, 10, 10)],
        [(4, 3, 11, 3), (3, 4, 3, 11), (12, 4, 12, 11), (4, 12, 11, 12), (6, 6, 9, 9)],
        [(7, 2, 8, 9), (5, 9, 10, 10), (6, 11, 9, 12), (4, 3, 11, 3), (4, 4, 4, 5), (11, 4, 11, 5)],
    ]
    for i, g in enumerate(glyphs):
        _blocky(draw, 16, g, sc, (i % 2) * cell, (i // 2) * cell)
    return tile


def make_mural_eye(w=256, h=128):
    """The wall's watching eye, as ink on a transparent sheet: it is cut out by the shader and sits IN
    the wall's own stone and light instead of on a lighter rectangle. 64x32 logical pixels."""
    mask = Image.new("L", (64, 32), 0)
    d = ImageDraw.Draw(mask)
    cx, cy = 32, 17
    for x in range(8, 57):
        t = (x - cx) / 24.0
        top = cy - int(round(9 * (1 - t * t) ** 0.8))
        bot = cy + int(round(7 * (1 - t * t) ** 0.8))
        d.point((x, top), 255)
        d.point((x, top + 1), 255)
        d.point((x, bot), 255)
        d.point((x, bot - 1), 255)
    for r in (7, 4):
        for a in range(0, 360, 3):
            px, py = int(round(cx + r * np.cos(np.radians(a)))), int(round(cy + r * np.sin(np.radians(a))))
            d.point((px, py), 255)
    d.rectangle([cx - 1, cy - 1, cx + 1, cy + 1], fill=255)
    for k in range(-5, 6):
        x = cx + k * 4
        t = (x - cx) / 24.0
        top = cy - int(round(9 * (1 - t * t) ** 0.8)) - 2
        length = 6 - abs(k) // 2
        for j in range(length):
            d.point((x, top - j), 255)
            if j < length - 2:
                d.point((x + (1 if k >= 0 else -1) * (j // 2 == 0), top - j), 255)
    big = mask.resize((w, h), Image.NEAREST)
    out = Image.new("RGBA", (w, h), GLYPH_INK + (0,))
    out.putalpha(big)
    return out.transpose(Image.FLIP_TOP_BOTTOM)   # the CENTERED UVs flip v: lashes end up on top


def mean_colour(name):
    if name in ("box_glyph", "mural_eye"):
        name = "wood" if name == "box_glyph" else "rock_a"
    p = SPECS[name]["p"]
    return tuple(float(np.mean([c[i] for c in p])) for i in range(3))


def write_all(out_dir):
    import os
    os.makedirs(out_dir, exist_ok=True)
    for name in SPECS:
        make_tile(name).save(os.path.join(out_dir, name + ".png"))
    make_glyph_sheet().save(os.path.join(out_dir, "box_glyph.png"))
    make_mural_eye().save(os.path.join(out_dir, "mural_eye.png"))
