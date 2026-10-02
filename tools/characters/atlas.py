"""Texture atlas for the witch characters.

Reimplements the `fw_core.ATL` the antler witch's painters were written against
(`alloc(name, w, h)`, `paste(name, img)`, `.img`) and adds what a game export needs:

* deferred shelf packing (tallest first) so allocation order does not waste space,
* a per-tile `scale` so a painter can draw at its native size and land smaller,
* flat colour swatches for untextured materials (one atlas, one material, one surface),
* edge bleed around every tile, so nearest sampling at a tile border never picks a neighbour,
* PS1 15-bit colour (5 bits per channel) on the final image.

UV convention: glTF (origin top-left, v down), so `uv()` returns what goes into TEXCOORD_0.
"""
import numpy as np
from PIL import Image

PAD = 2          # bleed pixels around every tile
SWATCH = 4       # swatch tile edge in pixels


def quantize5(a):
    """5 bits per channel, replicated into the low bits (31 -> 255)."""
    a = np.asarray(a).astype(np.uint8)
    return ((a >> 3) << 3) | (a >> 5)


class Atlas:
    def __init__(self, size=512, bg=(0, 0, 0)):
        self.W = self.H = int(size)
        self.bg = tuple(bg)
        self.req = {}        # name -> (w, h) requested (already scaled)
        self.order = []
        self.rect = {}       # name -> (x, y, w, h) after packing
        self.tiles = {}      # name -> PIL RGB image of (w, h)
        self.swatches = {}   # name -> rgb tuple (0..1)
        self._img = None

    # ---- allocation ------------------------------------------------------------------------
    def alloc(self, name, w, h, scale=1.0):
        w, h = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
        if name not in self.req:
            self.order.append(name)
        self.req[name] = (w, h)
        self.rect.clear()
        self._img = None
        return w, h

    def swatch(self, name, rgb):
        """A flat colour tile. Re-registering the same name with a new colour repaints it."""
        if name not in self.req:
            self.alloc(name, SWATCH, SWATCH)
        self.swatches[name] = tuple(float(c) for c in rgb)
        self.tiles[name] = Image.new('RGB', (SWATCH, SWATCH), _c8(rgb))
        self._img = None

    def has(self, name):
        return name in self.req

    def pack(self):
        """Shelf packing, tallest first, each tile on the first shelf with room (so the swatches fill the space beside
        a tall tile); raises if the requests do not fit."""
        names = sorted(self.order, key=lambda n: (-self.req[n][1], -self.req[n][0], n))
        shelves = []         # [y, height, x used]
        top = 0
        for n in names:
            w, h = self.req[n]
            W2, H2 = w + 2 * PAD, h + 2 * PAD
            for sh in shelves:
                if H2 <= sh[1] and sh[2] + W2 <= self.W:
                    break
            else:
                if W2 > self.W or top + H2 > self.H:
                    used = sum((a + 2 * PAD) * (b + 2 * PAD) for a, b in self.req.values())
                    raise ValueError('atlas %dx%d overflow at %s (%d%% of area requested)'
                                     % (self.W, self.H, n, 100 * used // (self.W * self.H)))
                sh = [top, H2, 0]
                shelves.append(sh)
                top += H2
            self.rect[n] = (sh[2] + PAD, sh[0] + PAD, w, h)
            sh[2] += W2
        return self.rect

    # ---- painting ----------------------------------------------------------------------------
    def paste(self, name, img):
        w, h = self.req[name]
        img = img.convert('RGB')
        if img.size != (w, h):
            img = img.resize((w, h), Image.LANCZOS if img.size[0] > w else Image.NEAREST)
        self.tiles[name] = img
        self._img = None

    @property
    def img(self):
        if self._img is None:
            if not self.rect:
                self.pack()
            canvas = np.zeros((self.H, self.W, 3), np.uint8)
            canvas[:] = _c8(self.bg)
            for n, (x, y, w, h) in self.rect.items():
                t = self.tiles.get(n)
                if t is None:
                    continue
                a = np.asarray(t)
                # bleed: clamp-extend the tile PAD pixels on every side
                a = np.pad(a, ((PAD, PAD), (PAD, PAD), (0, 0)), mode='edge')
                canvas[y - PAD:y + h + PAD, x - PAD:x + w + PAD] = a
            self._img = Image.fromarray(quantize5(canvas))
        return self._img

    @img.setter
    def img(self, im):
        self._img = im

    # ---- UVs -----------------------------------------------------------------------------------
    def uv(self, name, u, v):
        """Tile-local (u, v) in [0, 1] (v down) -> atlas UV. Clamped half a texel inside the tile."""
        if not self.rect:
            self.pack()
        x, y, w, h = self.rect[name]
        u = np.clip(np.asarray(u, float), .5 / w, 1 - .5 / w)
        v = np.clip(np.asarray(v, float), .5 / h, 1 - .5 / h)
        return (x + u * w) / self.W, (y + v * h) / self.H

    def centre(self, name):
        return self.uv(name, .5, .5)

    def usage(self):
        if not self.rect:
            self.pack()
        used = sum((w + 2 * PAD) * (h + 2 * PAD) for _, _, w, h in self.rect.values())
        return used / float(self.W * self.H)


def _c8(rgb):
    return tuple(int(round(max(0.0, min(1.0, float(c))) * 255)) for c in rgb)
