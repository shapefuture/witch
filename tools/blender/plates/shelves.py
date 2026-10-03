"""Shelves, and the rule that fills them.

A board is filled in RUNS: 3-7 of one kind (a scroll bundle, a glyph crate, a book run, an octagon
ring, a gem finial, a candle, a jar), then the kind changes. Every prop is an instance of a small
prototype mesh (linked duplicates), so a packed hall stays cheap; Object Info random varies each
instance's tone. Some runs are tagged `dusk_gap` so the dusk variant can leave holes.
"""
import math
import random

import bpy
import numpy as np
from mathutils import Vector

from . import geo
from .geo import TO_BL, TO_GD, Builder, xf

BOOK_COLOURS = ["book_olive", "book_tan", "book_red", "book_green", "book_purple", "book_tan", "book_olive"]


class Library:
    """Prototype meshes (local Godot space: origin bottom-centre, front toward +z)."""

    def __init__(self, coll, mats):
        self.coll, self.mats = coll, mats
        self.protos = {}
        self.instances = []
        self._build()

    def _proto(self, name, b):
        obj = b.build(self.coll, self.mats)
        geo.facet(obj, seed=len(self.protos))
        me = obj.data
        bpy.data.objects.remove(obj)
        me.use_fake_user = True
        self.protos[name] = me

    def _build(self):
        # scroll bundles: 3-2-1 pyramids of scrolls, rolled ends facing out
        for k, (r, n) in enumerate(((0.12, 3), (0.145, 2), (0.105, 4))):
            b = Builder("scrolls%d" % k)
            row, y = n, r
            while row > 0:
                for i in range(row):
                    x = (i - (row - 1) / 2) * 2 * r * 1.02
                    faces = b.cyl((x, y, -0.3), (x, y, 0.3), r, r, "scroll", segs=7, spin=10 * i)
                    caps = [f for f in faces if len(f.verts) == 7]
                    end = b._mi("scroll_end")
                    for f in caps:
                        f.material_index = end
                    b.face_uv(caps)
                y += r * 1.75
                row -= 1
            self._proto("scrolls%d" % k, b)
        # books: unit boxes scaled per instance
        for c in set(BOOK_COLOURS):
            b = Builder(c)
            b.box((0, 0.5, 0), (1, 1, 1), c, skip=("-y",))
            self._proto(c, b)
        # glyph crates: the front carries one glyph of the atlas
        for k in range(6):
            b = Builder("crate%d" % k)
            faces = b.box((0, 0.27, 0), (0.58, 0.54, 0.56), "crate", r=(0, 0, 0), skip=("-y",))
            front = [f for f in faces if f.normal.z > 0.9]
            gi = b._mi("crate_glyph")
            for f in front:
                f.material_index = gi
            b.face_uv(front, cell=(k % 4, k // 4 + (1 if k > 3 else 0)), cells=4, inset=0.06)
            b.box((0, 0.545, 0), (0.6, 0.03, 0.58), "wood_dark")
            self._proto("crate%d" % k, b)
        # octagon rings on a foot
        for k, mat in enumerate(("stone_warm", "brass", "wood")):
            b = Builder("ring%d" % k)
            R, t = 0.26, 0.07
            for i in range(8):
                a = math.tau * (i + 0.5) / 8
                seg = 2 * R * math.tan(math.pi / 8) + 0.012
                b.box((math.cos(a) * R, 0.36 + math.sin(a) * R, 0), (t, seg, 0.09), mat, r=(0, 0, math.degrees(a)))
            b.box((0, 0.04, 0), (0.18, 0.08, 0.14), "wood_dark")
            self._proto("ring%d" % k, b)
        # finials: a short spire with a purple gem
        b = Builder("finial")
        b.box((0, 0.05, 0), (0.16, 0.1, 0.16), "wood_dark")
        b.cyl((0, 0.1, 0), (0, 0.42, 0), 0.06, 0.035, "wood_dark", segs=4, spin=45)
        b.sphere((0, 0.53, 0), (0.09, 0.12, 0.09), "purple", subdiv=1, amp=0.2, seed=3)
        self._proto("finial", b)
        # candles (the flame is its own prototype so it can join the glow group)
        b = Builder("candle")
        b.cyl((0, 0, 0), (0, 0.04, 0), 0.09, 0.09, "brass", segs=6)
        b.cyl((0, 0.04, 0), (0, 0.3, 0), 0.045, 0.042, "wax", segs=6)
        self._proto("candle", b)
        b = Builder("flame")
        b.sphere((0, 0.355, 0), (0.025, 0.05, 0.025), "flame", subdiv=1)
        self._proto("flame", b)
        # jars
        for k, mat in enumerate(("pale", "book_olive", "crystal")):
            b = Builder("jar%d" % k)
            b.lathe([(0.07, 0.0), (0.12, 0.08), (0.13, 0.2), (0.08, 0.32), (0.06, 0.36), (0.075, 0.4)], mat, segs=7, matrix=xf((0, 0, 0)), closed_top=True)
            self._proto("jar%d" % k, b)

    def place(self, proto, pos, yaw, scale=(1, 1, 1), tag=None):
        me = self.protos[proto]
        obj = bpy.data.objects.new(proto, me)
        self.coll.objects.link(obj)
        obj.matrix_basis = TO_BL @ xf(pos, (0, yaw, 0), scale) @ TO_GD
        if tag:
            for k, v in tag.items():
                obj[k] = v
        self.instances.append(obj)
        return obj


KINDS = ["books", "scrolls", "crates", "rings", "finials", "candles", "jars"]
WEIGHTS = [0.16, 0.36, 0.28, 0.08, 0.05, 0.03, 0.04]


def fill_board(lib, origin, along, out, length, depth, clear, rng, run_id, skip=None, gap_rate=0.12, candles=None):
    """Fill one board. `origin` is the board's front-left point (world), `along` the unit direction
    of the board, `out` the unit direction toward the viewer. Returns the next run id."""
    origin, along, out = Vector(origin), Vector(along), Vector(out)
    yaw = math.degrees(math.atan2(out.x, out.z))
    x = rng.uniform(0.02, 0.15)
    last = None
    while x < length - 0.15:
        if skip and skip[0] - 0.05 <= x <= skip[1]:
            x = skip[1] + 0.06
            continue
        kind = last
        while kind == last:
            kind = rng.choices(KINDS, WEIGHTS)[0]
        if kind == "candles" and candles is None:
            continue
        last = kind
        count = rng.randint(3, 7)
        if kind == "books":
            count = rng.randint(5, 13)
        tag = {"run": run_id, "dusk_gap": rng.random() < gap_rate}
        run_id += 1
        colours = rng.sample(BOOK_COLOURS, 2)
        variant = rng.randrange(6)
        for i in range(count):
            if x >= length - 0.12 or (skip and skip[0] - 0.05 <= x <= skip[1]):
                break
            if kind == "books":
                w = rng.uniform(0.09, 0.18)
                h = min(clear - 0.06, rng.uniform(0.55, 0.88) * (0.85 + 0.3 * (i % 3 == 1)))
                d = min(depth - 0.08, rng.uniform(0.36, 0.5))
                lean = 0.0
                c = colours[0] if rng.random() < 0.7 else colours[1]
                p = origin + along * (x + w / 2) + out * (-d / 2 - 0.02)
                lib.place(c, p, yaw, (w, max(h, 0.2), d), tag)
                x += w + 0.008
            elif kind == "scrolls":
                proto = "scrolls%d" % (variant % 3)
                width = {0: 0.74, 1: 0.6, 2: 0.88}[variant % 3]
                if x + width > length:
                    break
                p = origin + along * (x + width / 2) + out * (-0.33)
                lib.place(proto, p, yaw, (1, 1, 1), tag)
                x += width + rng.uniform(0.02, 0.08)
            elif kind == "crates":
                s = rng.uniform(0.85, 1.12) * min(1.0, (clear - 0.08) / 0.56)
                p = origin + along * (x + 0.3 * s) + out * (-0.3 * s - 0.02)
                lib.place("crate%d" % ((variant + i) % 6 if rng.random() < 0.3 else variant), p, yaw + rng.uniform(-5, 5), (s, s, s), tag)
                x += 0.6 * s + rng.uniform(0.02, 0.06)
            elif kind == "rings":
                p = origin + along * (x + 0.3) + out * (-0.2)
                lib.place("ring%d" % (variant % 3), p, yaw, (1, 1, 1), tag)
                x += 0.64
            elif kind == "finials":
                p = origin + along * (x + 0.1) + out * (-0.2)
                lib.place("finial", p, yaw, (1, 1, 1), tag)
                x += 0.26
            elif kind == "candles":
                p = origin + along * (x + 0.1) + out * (-0.15)
                s = rng.uniform(0.8, 1.2)
                lib.place("candle", p, yaw, (1, s, 1), tag)
                f = lib.place("flame", p + Vector((0, (s - 1) * 0.3, 0)), yaw, (1, 1, 1), tag)
                candles.append((f, p + Vector((0, 0.36 * s, 0))))
                x += 0.22
            elif kind == "jars":
                p = origin + along * (x + 0.14) + out * (-0.2)
                lib.place("jar%d" % (variant % 3), p, yaw, (1, rng.uniform(0.85, 1.3), 1), tag)
                x += 0.3
        x += rng.uniform(0.0, 0.12)
    return run_id


def bookcase_run(lib, coll, mats, name, front_x, z_from, z_to, out_sign, height, rng, run_id, board_gap=1.05, depth=0.85,
                 bay=2.3, skips=None, candles=None, first_board=0.32):
    """A wall of bookcases along the z axis. The front plane is x = front_x; `out_sign` = +1 if the
    shelves face +x. Returns (object, run_id, boards [(y, z0, z1)])."""
    b = Builder(name)
    z0, z1 = min(z_from, z_to), max(z_from, z_to)
    back_x = front_x - out_sign * depth
    b.box(((front_x + back_x) / 2 - out_sign * (depth / 2 - 0.04), height / 2, (z0 + z1) / 2), (0.08, height, z1 - z0), "wood_dark")
    nb = max(1, int(round((z1 - z0) / bay)))
    posts = [z0 + (z1 - z0) * k / nb for k in range(nb + 1)]
    for zp in posts:
        b.box(((front_x + back_x) / 2, height / 2, zp), (depth, height, 0.12), "wood_dark")
        b.box((front_x + out_sign * 0.03, height / 2, zp), (0.1, height, 0.16), "wood_dark")
    boards = []
    y = first_board
    while y < height - 0.4:
        b.box(((front_x + back_x) / 2, y, (z0 + z1) / 2), (depth, 0.07, z1 - z0), "wood_dark")
        b.box((front_x + out_sign * 0.02, y + 0.005, (z0 + z1) / 2), (0.06, 0.1, z1 - z0), "wood")
        boards.append(y + 0.035)
        y += board_gap
    b.box(((front_x + back_x) / 2, height, (z0 + z1) / 2), (depth + 0.1, 0.18, z1 - z0 + 0.1), "wood_dark")
    obj = b.build(coll, mats)
    geo.facet(obj, seed=hash(name) % 1000)
    out = Vector((out_sign, 0, 0))
    along = Vector((0, 0, -1)) if out_sign > 0 else Vector((0, 0, 1))
    filled = []
    for by in boards:
        for k in range(nb):
            za, zb = posts[k] + 0.07, posts[k + 1] - 0.07
            start_z = zb if out_sign > 0 else za
            origin = (front_x - out_sign * 0.02, by, start_z)
            skip = None
            for (sy, sz0, sz1) in (skips or []):
                if abs(sy - by) < 0.3 and sz0 < zb and sz1 > za:
                    s0 = (start_z - sz1) if out_sign > 0 else (sz0 - start_z)
                    skip = (max(0.0, s0), s0 + (sz1 - sz0))
            if rng.random() < 0.06:
                continue                   # an empty shelf: the walls are not wallpaper
            run_id = fill_board(lib, origin, along, out, zb - za, depth - 0.1, board_gap - 0.1, rng, run_id, skip=skip, candles=candles)
        filled.append(by)
    return obj, run_id, filled


def wall_shelves(lib, coll, mats, name, x0, x1, back_z, y0, y1, rng, run_id, board_gap=0.95, depth=0.6, candles=None):
    """Shelves on a wall facing +z (niches in the alcove, the second room's back wall)."""
    b = Builder(name)
    b.box(((x0 + x1) / 2, (y0 + y1) / 2, back_z + 0.04), (x1 - x0, y1 - y0, 0.08), "wood_dark")
    for xx in (x0, x1):
        b.box((xx, (y0 + y1) / 2, back_z + depth / 2), (0.12, y1 - y0, depth), "wood_dark")
    y = y0
    boards = []
    while y < y1 - 0.3:
        b.box(((x0 + x1) / 2, y, back_z + depth / 2), (x1 - x0, 0.07, depth), "wood_dark")
        boards.append(y + 0.035)
        y += board_gap
    obj = b.build(coll, mats)
    geo.facet(obj, seed=hash(name) % 997)
    for by in boards:
        run_id = fill_board(lib, (x0 + 0.08, by, back_z + depth - 0.02), (1, 0, 0), (0, 0, 1), x1 - x0 - 0.16, depth - 0.08, board_gap - 0.1, rng, run_id, candles=candles)
    return obj, run_id


def fill_tower(lib, tiers, at, yaw, rng, run_id, skip_tier=None, candles=None):
    th = math.radians(yaw)
    along = Vector((math.cos(th), 0, -math.sin(th)))
    out = Vector((math.sin(th), 0, math.cos(th)))
    for k, (y, hw, hd) in enumerate(tiers):
        if skip_tier is not None and k == skip_tier[0]:
            skip = skip_tier[1]
        else:
            skip = None
        origin = Vector(at) + Vector((0, y, 0)) + out * (hd - 0.02) - along * hw
        run_id = fill_board(lib, origin, along, out, 2 * hw, 2 * hd - 0.1, 0.76, rng, run_id, skip=skip, candles=candles)
    return run_id
