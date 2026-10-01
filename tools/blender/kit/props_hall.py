"""The archive hall: a rough-hewn gothic chamber lined with tall shelves, an eye on the wall, a pointed
arch to a glowing stair, a hooded statue, a spiral-painted floor and one hole in the vault where the
light comes in. Everything is flat-shaded facets with hand-painted tiles; light is baked later.

Authored in Godot space (x right, y up, -z toward the back wall). The gameplay anchors (machine,
bell, house/tower, path-out arch) keep the coordinates the game code uses.
"""
import math
import random

from mathutils import Vector

from .common import Part, fbm, smoothstep

HALL_W = 9.5
BACK_Z = -10.0
FRONT_Z = 13.0
STRAIGHT = 9.0       # walls are vertical this high, then the vault closes in
H = 14.0
CARPET_C = (0.8, -1.8)
ARCH_W = 2.4
ARCH_STRAIGHT = 4.2
ARCH_TOP = 7.9
CORRIDOR_END = -27.5
HOLE_RADIUS = 2.4     # the hole in the vault: one ragged oculus, so the beam is a single clear event
STEPS_FROM = -17.0

BOOKS = ["book_red", "book_olive", "book_purple", "book_tan", "book_teal", "book_red", "book_tan", "book_olive"]


def half_w(y):
    if y <= STRAIGHT:
        return HALL_W
    t = (y - STRAIGHT) / (H - STRAIGHT)
    return HALL_W * max(0.0, 1.0 - t) ** 0.62


def arch_hw(y, scale=1.0):
    if y <= ARCH_STRAIGHT * scale:
        return ARCH_W * scale
    t = (y - ARCH_STRAIGHT * scale) / ((ARCH_TOP - ARCH_STRAIGHT) * scale)
    return ARCH_W * scale * max(0.0, 1.0 - t) ** 0.7


def inside_arch(x, y, scale=1.0):
    return y <= ARCH_TOP * scale and abs(x) < arch_hw(y, scale)


def ray_distance(p, origin, direction):
    d = Vector(p) - origin
    along = max(0.0, d.dot(direction))
    return (d - direction * along).length


def oculus_point(pool, sun_dir):
    """Where the key light's ray, leaving the pool, meets the vault: the hole goes there."""
    lo, hi = 0.0, 40.0
    for _ in range(40):
        t = (lo + hi) / 2
        p = pool + sun_dir * t
        if abs(p.x) < half_w(p.y) and p.y < H:
            lo = t
        else:
            hi = t
    return pool + sun_dir * lo


# ---- the shell ----------------------------------------------------------------------------------

def _row_heights():
    ys, y = [0.0], 0.0
    while y < H - 1e-6:
        y = min(H, y + (1.3 if y < STRAIGHT else 1.0))
        ys.append(y)
    return ys


def shell(oculus, seed=1):
    """Side walls and vault as one jagged surface, seen from inside. A hole at the oculus."""
    part = Part("Shell")
    ys = _row_heights()
    zs = []
    z = BACK_Z - 1.9
    while z < FRONT_Z + 0.01:
        zs.append(z)
        z += 1.9
    verts = {}
    for side in (-1, 1):
        for yi, y in enumerate(ys):
            for zj, z in enumerate(zs):
                w = half_w(y)
                top = yi == len(ys) - 1
                bump = 0.0 if (top or yi == 0) else (fbm((side * 3.0 + w * 0.2, y * 0.33, z * 0.3), 3, seed) * 0.5 + 0.5) * (1.5 if y < STRAIGHT else 2.2)
                # keep the rock around the oculus smooth, so the light that enters is where it was aimed
                near = (Vector((side * w, y, z)) - oculus).length
                bump *= smoothstep(HOLE_RADIUS - 0.3, HOLE_RADIUS + 3.7, near)
                jz = (math.sin(zj * 12.9 + yi * 78.2 + side) * 43758.5453 % 1.0 - 0.5) * 0.9 if 0 < zj < len(zs) - 1 else 0.0
                x = side * (w + bump * (0.9 if y < STRAIGHT else 0.8))
                yy = y + (bump * 0.5 if y > STRAIGHT and not top else 0.0)
                verts[(side, yi, zj)] = Vector((x if not top else 0.0, yy, z + jz))
    for side in (-1, 1):
        for yi in range(len(ys) - 1):
            for zj in range(len(zs) - 1):
                a, b, c, d = verts[(side, yi, zj)], verts[(side, yi, zj + 1)], verts[(side, yi + 1, zj + 1)], verts[(side, yi + 1, zj)]
                centre = (a + b + c + d) / 4.0
                tris = ((a, b, c), (a, c, d)) if (yi + zj) % 2 else ((a, b, d), (b, c, d))
                for tri in tris:
                    mid = (tri[0] + tri[1] + tri[2]) / 3.0
                    if mid.y > 9.0 and (mid - oculus).length < HOLE_RADIUS:
                        continue
                    n = fbm((mid.x * 0.2, mid.y * 0.2, mid.z * 0.2), 2, 3.0)
                    mat = "rock_b" if (mid.y > STRAIGHT - 0.5 or n > 0.3) else "rock_a"
                    part.tri_toward(tri[0], tri[1], tri[2], mat, Vector((0, mid.y * 0.35, mid.z)))
    return part


def vault_ribs(seed=2):
    """Big rough ribs running across the vault, so the ceiling has structure and scale."""
    part = Part("Ribs")
    for z in (-7.0, -1.0, 5.0, 11.0):
        pts = []
        for k in range(0, 15):
            y = STRAIGHT - 1.0 + (H - STRAIGHT + 1.0) * k / 14.0
            pts.append(Vector((-half_w(y) + 0.5, y, z)))
        right = [Vector((-p.x, p.y, p.z)) for p in reversed(pts)]
        path = pts + right[1:]
        part.tube(path, [0.65, 0.5, 0.4, 0.5, 0.65], mat="rock_a", segs=6, per_segment=1, jitter=0.05, seed=int(z * 3), caps=False, twist=0.5)
    return part


def floor(seed=3):
    part = Part("Floor")

    def height(x, z):
        return 0.05 * fbm((x * 0.5, 0, z * 0.5), 2, 5.0)

    def material(x, z):
        return "rock_b" if fbm((x * 0.3, 0, z * 0.3), 2, 8.0) > 0.25 else "floor"

    part.grid(-HALL_W, HALL_W, BACK_Z, FRONT_Z, 0.8, height, material, jitter=0.3)
    return part


def back_wall(seed=4):
    """The wall with the pointed arch cut through it, and the stone ring that frames it."""
    part = Part("BackWall")
    xs = [-HALL_W - 0.4 + i * 0.8 for i in range(int((2 * HALL_W + 0.8) / 0.8) + 1)]
    ys = _row_heights()
    verts = {}
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            bump = 0.0 if (i in (0, len(xs) - 1) or j == 0) else (fbm((x * 0.3, y * 0.3, 9.0), 3, seed) * 0.5 + 0.5) * 0.7
            jx = (math.sin(i * 12.9 + j * 78.2) * 43758.5453 % 1.0 - 0.5) * 0.35 if 0 < i < len(xs) - 1 and 0 < j < len(ys) - 1 else 0.0
            verts[(i, j)] = Vector((x + jx, y, BACK_Z - bump))
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            a, b, c, d = verts[(i, j)], verts[(i + 1, j)], verts[(i + 1, j + 1)], verts[(i, j + 1)]
            cx, cy = (a.x + c.x) / 2, (a.y + c.y) / 2
            if abs(cx) > half_w(cy) + 0.3 or inside_arch(cx, cy):
                continue
            tris = ((a, b, c), (a, c, d)) if (i + j) % 2 else ((a, b, d), (b, c, d))
            for tri in tris:
                mid = (tri[0] + tri[1] + tri[2]) / 3.0
                mat = "rock_b" if mid.y > 9.0 or fbm((mid.x * 0.25, mid.y * 0.25, 1.0), 2, 2.0) > 0.3 else "rock_a"
                if (mid.x / 6.0) ** 2 + ((mid.y - 10.3) / 3.6) ** 2 < 1.0:
                    mat = "plaster"      # the pale stucco the eye is painted on
                part.tri_toward(tri[0], tri[1], tri[2], mat, Vector((mid.x, mid.y, 5.0)))
    # voussoirs: chunky stones around the opening
    outline = []
    for k in range(0, 13):
        y = ARCH_TOP * k / 12.0
        outline.append((-arch_hw(y), y))
    outline += [(-x, y) for (x, y) in reversed(outline[:-1])]
    rnd = random.Random(seed)
    for k in range(len(outline) - 1):
        (x0, y0), (x1, y1) = outline[k], outline[k + 1]
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
        length = math.hypot(x1 - x0, y1 - y0)
        nx, ny = -(y1 - y0), (x1 - x0)
        nl = math.hypot(nx, ny) or 1.0
        nx, ny = nx / nl, ny / nl
        if ny < 0 and my > ARCH_STRAIGHT:
            nx, ny = -nx, -ny
        if my <= ARCH_STRAIGHT:
            nx, ny = (-1.0 if mx < 0 else 1.0), 0.0
        off = 0.5
        part.box((mx + nx * off, my + ny * off, BACK_Z + 0.35), (max(length, 0.6) * 1.1, 0.95 + rnd.uniform(-0.1, 0.18), 1.1 + rnd.uniform(0, 0.25)),
                 "rock_a" if k % 2 else "rock_b", rot=(0, 0, ang + rnd.uniform(-3, 3)), bevel=0.06)
    part.box((0, ARCH_TOP + 0.7, BACK_Z + 0.4), (1.3, 1.2, 1.4), "rock_a", rot=(0, 0, 3), bevel=0.08, taper=(0.8, 1.0))
    return part


def mural_eye(centre=(0.0, 10.2, BACK_Z + 0.04), size=(9.6, 4.8)):
    part = Part("Mural")
    cx, cy, cz = centre
    hw, hh = size[0] / 2, size[1] / 2
    part.quad_out((cx - hw, cy - hh, cz), (cx + hw, cy - hh, cz), (cx + hw, cy + hh, cz), (cx - hw, cy + hh, cz), "mural_eye", (cx, cy, cz - 5.0))
    return part


def corridor(seed=5):
    """What lies beyond the arch: a short tunnel, a second arch, steps climbing to a blaze of light."""
    part = Part("Corridor")
    ys = [0.0]
    y = 0.0
    while y < ARCH_TOP * 0.97:
        y += 0.7
        ys.append(min(y, ARCH_TOP * 0.97))
    zs = [BACK_Z - 0.4 - 1.3 * i for i in range(int((BACK_Z - CORRIDOR_END) / 1.3) + 1)]
    cw = lambda yy: arch_hw(yy, 0.92) + 0.0
    verts = {}
    for side in (-1, 1):
        for yi, y in enumerate(ys):
            for zj, z in enumerate(zs):
                top = yi == len(ys) - 1
                bump = 0.0 if (top or yi == 0) else (fbm((side * 2.0, y * 0.4, z * 0.3), 2, seed) * 0.5 + 0.5) * 0.45
                x = 0.0 if top else side * (cw(y) + bump)
                verts[(side, yi, zj)] = Vector((x, y, z))
    for side in (-1, 1):
        for yi in range(len(ys) - 1):
            for zj in range(len(zs) - 1):
                a, b, c, d = verts[(side, yi, zj)], verts[(side, yi, zj + 1)], verts[(side, yi + 1, zj + 1)], verts[(side, yi + 1, zj)]
                for tri in (((a, b, c), (a, c, d)) if (yi + zj) % 2 else ((a, b, d), (b, c, d))):
                    mid = (tri[0] + tri[1] + tri[2]) / 3.0
                    part.tri_toward(tri[0], tri[1], tri[2], "rock_a" if mid.y < 5.0 else "rock_b", Vector((0, mid.y * 0.4, mid.z)))
    # floor and steps
    zf = BACK_Z - 0.4
    part.box((0, -0.15, (zf + STEPS_FROM) / 2), (arch_hw(0, 0.92) * 2 + 1.0, 0.3, abs(zf - STEPS_FROM)), "floor")
    for k in range(9):
        z0 = STEPS_FROM - 0.9 * k
        part.box((0, 0.15 + 0.3 * k, z0 - 0.45), (arch_hw(0, 0.92) * 2 + 1.0, 0.3 * (k + 1) + 0.3, 0.9), "rock_a" if k % 2 else "floor", bevel=0.03)
    # the second arch ring
    outline = [(-arch_hw(yy, 0.8), yy) for yy in [ARCH_TOP * 0.8 * k / 9.0 for k in range(10)]]
    outline += [(-x, yy) for (x, yy) in reversed(outline[:-1])]
    for k in range(len(outline) - 1):
        (x0, y0), (x1, y1) = outline[k], outline[k + 1]
        part.box(((x0 + x1) / 2 + (-0.4 if (x0 + x1) < 0 else 0.4 if (x0 + x1) > 0 else 0), (y0 + y1) / 2 + (0.3 if abs(x0 + x1) < 0.2 else 0), -15.0),
                 (max(math.hypot(x1 - x0, y1 - y0), 0.5) * 1.1, 0.7, 0.9), "rock_b" if k % 2 else "rock_a", rot=(0, 0, math.degrees(math.atan2(y1 - y0, x1 - x0))), bevel=0.05)
    # end wall: the blaze
    part.quad_out((-2.6, 0.0, CORRIDOR_END), (2.6, 0.0, CORRIDOR_END), (2.6, 8.0, CORRIDOR_END), (-2.6, 8.0, CORRIDOR_END), "glow_white", (0, 3, CORRIDOR_END - 5.0))
    return part


def pilaster(x, z, h=12.0, seed=0):
    part = Part("Pilaster")
    part.box((x, 0.35, z), (1.9, 0.7, 1.9), "rock_b", bevel=0.08)
    part.lathe([(0.78, 0.7), (0.66, 1.5), (0.6, 5.0), (0.66, h - 1.2), (0.92, h - 0.3), (1.0, h)], segs=8, mat="rock_a", center=(x, 0, z), jitter=0.07, seed=seed)
    return part


# ---- shelves --------------------------------------------------------------------------------------

def _fill_tier(part, y0, x0, x1, z_front, tier_h, rnd, density=0.88, skip=None):
    """Books, scrolls, glyph boxes, jars and a few crystals along one board (local frame, +z front)."""
    x = x0 + 0.1
    while x < x1 - 0.2:
        if skip and skip[0] <= x <= skip[1]:
            x = skip[1] + 0.01
            continue
        roll = rnd.random()
        if roll > density:
            x += rnd.uniform(0.15, 0.4)
            continue
        if roll < 0.56:
            w = rnd.uniform(0.12, 0.3)
            h = rnd.uniform(0.45, min(1.0, tier_h - 0.14))
            d = rnd.uniform(0.4, 0.56)
            lean = rnd.choice([0, 0, 0, 0, 10, -12]) if rnd.random() < 0.25 else 0
            part.book((x + w / 2, y0 + 0.04 + h / 2, z_front - d / 2), (w, h, d), rnd.choice(BOOKS), rot_z=lean)
            x += w + 0.01
        elif roll < 0.68:
            r = rnd.uniform(0.12, 0.18)
            ln = rnd.uniform(0.46, 0.6)
            rows = 2 if rnd.random() < 0.6 else 1
            for k in range(rows):
                part.cyl((x + r + k * r * 1.9, y0 + 0.04 + r, z_front - ln), (x + r + k * r * 1.9, y0 + 0.04 + r, z_front), r, r, "scroll", segs=5, caps=True)
            if rows == 2:
                part.cyl((x + r * 1.95, y0 + 0.04 + r * 2.8, z_front - ln), (x + r * 1.95, y0 + 0.04 + r * 2.8, z_front), r, r, "scroll", segs=5, caps=True)
            part.cyl((x + r, y0 + 0.04 + r, z_front - 0.01), (x + r, y0 + 0.04 + r, z_front + 0.015), r * 1.05, r * 1.05, "iron", segs=5, caps=False)
            x += r * 2 * rows + 0.1
        elif roll < 0.80:
            s = rnd.uniform(0.46, 0.66)
            part.book((x + s / 2, y0 + 0.04 + s * 0.45, z_front - s / 2), (s, s * 0.9, s), "box_glyph")
            x += s + 0.04
        elif roll < 0.86:
            h = rnd.uniform(0.42, 0.66)
            part.lathe([(0.14, 0.0), (0.2, h * 0.4), (0.12, h * 0.8), (0.07, h)], segs=5, mat=rnd.choice(["cream", "crystal", "coral"]), center=(x + 0.14, y0 + 0.04, z_front - 0.22), closed_bottom=False)
            x += 0.46
        elif roll < 0.89:
            part.blob((x + 0.18, y0 + 0.22, z_front - 0.24), (0.17, 0.2, 0.17), rnd.choice(["crystal", "crystal_grey"]), subdiv=1, amp=0.25, seed=int(x * 100))
            x += 0.4
        else:
            x += rnd.uniform(0.1, 0.3)


def bookcase(at, yaw, w, h, d, seed, tier_h=1.1, density=0.88, skip_tiers=None):
    """A tall wooden bookcase. Local frame: +z is the front; `at` is the floor centre of the unit."""
    part = Part("Case")
    rnd = random.Random(seed)
    m = part.mark()
    part.box((0, h / 2, -d / 2 + 0.05), (w, h, 0.1), "shelf")
    for sx in (-1, 1):
        part.box((sx * (w / 2 - 0.05), h / 2, 0), (0.1, h, d), "shelf")
    tiers = int(h / tier_h)
    for k in range(tiers + 1):
        y = k * tier_h
        part.box((0, y, 0), (w, 0.07, d), "shelf", rot=(0, 0, rnd.uniform(-0.6, 0.6)))
        if k < tiers:
            skip = (skip_tiers or {}).get(k)
            tier_density = density * rnd.uniform(0.45, 1.05)
            if rnd.random() < 0.12:
                continue                      # an empty tier: the shelves are not wallpaper
            if rnd.random() < 0.25 and skip is None:
                gap = rnd.uniform(-w / 2 + 0.3, w / 2 - 1.2)
                skip = (gap, gap + rnd.uniform(0.5, 1.1))
            _fill_tier(part, y, -w / 2 + 0.1, w / 2 - 0.1, d / 2 - 0.02, tier_h, rnd, min(tier_density, 0.96), skip)
    _place(part, m, at, yaw)
    return part


def _place(part, mark, at, yaw, lean=0.0):
    from .common import xf
    def lean_fn(v):
        return Vector((v.x + lean * v.y * v.y, v.y, v.z))
    if lean:
        part.deform(mark, lean_fn)
    part.transform_since(mark, xf(at, (0, yaw, 0)))


def tower(at, yaw, w, d, h, taper, seed, lean=0.0, tier_h=0.85, skip_tiers=None, finial=True):
    """A free-standing gothic bookcase tower: tapering, pointed, a dark orb on top."""
    part = Part("Tower")
    rnd = random.Random(seed)
    m = part.mark()
    part.box((0, h / 2, 0), (w, h, d * 0.55), "shelf", taper=(1.0 - taper, 1.0 - taper * 0.6), bevel=0.05)
    part.box((0, 0.2, d * 0.1), (w + 0.5, 0.4, d + 0.4), "rock_b", bevel=0.06)
    tiers = int((h - 0.8) / tier_h)
    for k in range(tiers):
        y = 0.45 + k * tier_h
        t = y / h
        wk = w * (1.0 - taper * t)
        part.box((0, y, d * 0.22), (wk + 0.12, 0.07, d * 0.62), "shelf")
        skip = (skip_tiers or {}).get(k)
        _fill_tier(part, y, -wk / 2 + 0.05, wk / 2 - 0.05, d * 0.53, tier_h, rnd, 0.9, skip)
    top_w = w * (1.0 - taper)
    part.cyl((0, h, 0), (0, h + 2.0, 0), top_w * 0.72, 0.06, "shelf", segs=4, spin=45)
    if finial:
        part.cyl((0, h + 1.9, 0), (0, h + 2.25, 0), 0.05, 0.05, "iron", segs=4)
        part.blob((0, h + 2.55, 0), (0.3, 0.38, 0.3), "crystal", subdiv=1, amp=0.1, seed=seed)
    _place(part, m, at, yaw, lean)
    return part


def hooded_statue(at, yaw, scale=1.0):
    """A tall, slim robed figure with a pointed hood, an empty face and an open scroll held at the chest,
    on a stepped plinth, with a crown of crystals behind its head. Big flat folds so it reads as a
    statue (not a cone) even in shade."""
    part = Part("Statue")
    m = part.mark()
    part.box((0, 0.18, 0), (1.9, 0.36, 1.9), "rock_b")
    part.box((0, 0.56, 0), (1.45, 0.4, 1.45), "rock_a", rot=(0, 8, 0))
    # robe: long folds, flaring at the hem
    part.lathe([(0.66, 0.76), (0.58, 1.3), (0.50, 2.0), (0.44, 2.6), (0.40, 3.05), (0.34, 3.3)], segs=9, mat="cloak", jitter=0.14, seed=3, closed_top=True)
    part.lathe([(0.68, 0.76), (0.69, 0.9), (0.66, 1.05)], segs=9, mat="carpet_purple", closed_top=False, closed_bottom=False, jitter=0.04, seed=4)
    part.lathe([(0.45, 2.34), (0.47, 2.42), (0.44, 2.5)], segs=9, mat="gold", closed_top=False, closed_bottom=False, jitter=0.03, seed=5)
    # shoulders, hood and the dark empty face
    part.blob((0, 3.15, 0), (0.62, 0.3, 0.42), "carpet_purple", subdiv=1, amp=0.12, seed=2)
    part.blob((0, 3.7, 0.02), (0.38, 0.52, 0.4), "cloak", subdiv=2, amp=0.12, seed=6)
    part.cyl((0, 4.05, 0.02), (0, 4.75, 0.14), 0.33, 0.0, "cloak", segs=7)
    part.blob((0, 3.66, 0.3), (0.30, 0.40, 0.24), "void", subdiv=1, amp=0.04, seed=1)
    # arms folded forward around the scroll
    for sx in (-1, 1):
        part.cyl((sx * 0.46, 3.0, 0.05), (sx * 0.26, 2.5, 0.52), 0.13, 0.11, "cloak", segs=5)
    part.cyl((-0.4, 2.48, 0.56), (0.4, 2.48, 0.56), 0.1, 0.1, "scroll", segs=6)
    part.box((0.0, 2.1, 0.62), (0.62, 0.7, 0.03), "scroll", rot=(8, 0, 2))
    for k, ang in enumerate((-55, -28, 0, 28, 55)):
        a = math.radians(ang)
        part.cyl((math.sin(a) * 0.3, 4.2, -0.34), (math.sin(a) * 1.05, 4.2 + 1.0 * math.cos(a) + (0.3 if k in (1, 3) else 0.0), -0.55), 0.16, 0.0, "crystal", segs=4, spin=15)
    if scale != 1.0:
        part.deform(m, lambda v: Vector((v.x * scale, v.y * scale, v.z * scale)))
    _place(part, m, at, yaw)
    return part


def compass_plate(at):
    part = Part("Compass")
    x, y, z = at
    part.cyl((x, y, z), (x, y, z + 0.12), 1.15, 1.15, "brass", segs=12)
    part.cyl((x, y, z + 0.1), (x, y, z + 0.18), 0.95, 0.95, "cream", segs=12)
    for k in range(8):
        part.box((x, y, z + 0.2), (1.9, 0.07, 0.04), "iron", rot=(0, 0, k * 22.5), taper=(1.0, 1.0))
    part.blob((x, y, z + 0.24), (0.14, 0.14, 0.1), "brass", subdiv=1, amp=0.0)
    return part


def sconce(at, yaw=0.0):
    """A bracket and a dark purple orb: the small purple notes along the walls."""
    part = Part("Sconce")
    m = part.mark()
    part.box((0, 0, -0.1), (0.16, 0.5, 0.1), "iron")
    part.tube([Vector((0, 0, 0)), Vector((0, 0.1, 0.3)), Vector((0, 0.35, 0.45))], 0.04, mat="iron", segs=4, per_segment=2)
    part.blob((0, 0.55, 0.45), (0.2, 0.22, 0.2), "crystal", subdiv=1, amp=0.12, seed=3)
    _place(part, m, at, yaw)
    return part


def pedestal_gem(at, size=1.0):
    part = Part("Pedestal")
    x, y, z = at
    part.box((x, y + 0.5 * size, z), (1.2 * size, 1.0 * size, 1.2 * size), "rock_b", bevel=0.08 * size)
    part.blob((x, y + 1.0 * size + 0.65 * size, z), (0.6 * size, 0.9 * size, 0.6 * size), "crystal_grey", subdiv=1, amp=0.18, seed=7)
    return part


def rubble(at, size, seed):
    part = Part("Rubble")
    rnd = random.Random(seed)
    for k in range(4):
        part.blob((at[0] + rnd.uniform(-size, size), at[1] + size * 0.3, at[2] + rnd.uniform(-size, size)), (size * rnd.uniform(0.5, 1.0), size * 0.45, size * rnd.uniform(0.5, 0.9)), "rock_b" if k % 2 else "rock_a", subdiv=1, amp=0.4, seed=seed + k, rot=(0, rnd.uniform(0, 180), 0), flat_bottom=-0.3)
    return part


def column(at, h=11.0, seed=0):
    """The carved wooden post that carries the bell's arm."""
    part = Part("Column")
    x, _, z = at
    part.lathe([(0.9, 0.0), (0.7, 0.4), (0.55, 1.2), (0.5, 3.0), (0.52, 5.0), (0.56, 7.5), (0.62, 9.5), (0.8, h - 0.6), (1.0, h)], segs=6, mat="wood_dark", center=(x, 0, z), jitter=0.05, seed=seed)
    for yb in (1.6, 5.2, 8.6):
        part.lathe([(0.62 - (0.08 if yb < 5 else 0.0), yb), (0.74, yb + 0.12), (0.62, yb + 0.28)], segs=6, mat="shelf", center=(x, 0, z), jitter=0.03, seed=seed + 1, closed_bottom=False, closed_top=False)
    return part


# ---- foreground frame ---------------------------------------------------------------------------------
# Big dark things cropped by the edges of the picture, like the shelf and the glass globe in the
# reference. They are authored in CAMERA space (x right, y up, -z forward) and ride on the camera
# in the game, so the frame is there at every aspect ratio and every shot that wants it.

# The frame is authored in camera space for a 60 degree lens and squeezed to the wide shot's real lens,
# so its place on the screen does not change when the lens does (GameRoot._fit_foreground agrees).
FG_LENS_DEG = 52.0
FG_K = math.tan(math.radians(FG_LENS_DEG / 2.0)) / math.tan(math.radians(30.0))


def _squeeze(parts):
    out = []
    for part, loc in parts:
        part.deform(0, lambda v: Vector((v.x * FG_K, v.y * FG_K, v.z)))
        out.append((part, (loc[0] * FG_K, loc[1] * FG_K, loc[2])))
    return out


def foreground_left(seed=40):
    """A tall shelf seen edge-on, a purple glass globe on a turned stand, a wooden tablet, a rock."""
    parts = []
    shelf = bookcase((0, 0, 0), 20, 2.6, 11.0, 1.4, seed=seed, tier_h=1.0)
    shelf.name = "FgShelfL"
    parts.append((shelf, (-4.9, -4.6, -4.5)))
    globe = Part("FgGlobe")
    globe.lathe([(0.7, 0.0), (0.45, 0.2), (0.22, 0.55), (0.3, 0.95), (0.62, 1.15), (0.5, 1.2)], segs=8, mat="wood", jitter=0.03, seed=2)
    globe.blob((0, 2.0, 0), (0.86, 0.86, 0.86), "crystal", subdiv=1, amp=0.06, seed=9)
    globe.blob((0.25, 2.35, 0.45), (0.12, 0.1, 0.12), "gold", subdiv=1, amp=0.1, seed=3)   # one hot facet
    globe.cyl((0, 1.1, 0), (0, 1.3, 0), 0.5, 0.46, "brass", segs=9)
    parts.append((globe, (-2.9, -3.55, -3.9)))
    rock = Part("FgRockL")
    rock.blob((0, 0.7, 0), (1.9, 1.1, 1.4), "rock_b", subdiv=1, amp=0.45, seed=5, flat_bottom=-0.2)
    parts.append((rock, (-4.4, -3.6, -3.2)))
    return _squeeze(parts)


def foreground_right(seed=41):
    """The other edge: the end of a shelf, a stone pedestal with a grey crystal, more rubble."""
    parts = []
    shelf = bookcase((0, 0, 0), -22, 2.6, 11.0, 1.4, seed=seed, tier_h=1.0)
    shelf.name = "FgShelfR"
    parts.append((shelf, (4.9, -4.6, -4.5)))
    gem = pedestal_gem((0, 0, 0), 1.25)
    gem.name = "FgGem"
    parts.append((gem, (3.2, -3.7, -3.6)))
    rock = Part("FgRockR")
    rock.blob((0, 0.6, 0), (1.7, 1.0, 1.3), "rock_b", subdiv=1, amp=0.45, seed=8, flat_bottom=-0.2)
    parts.append((rock, (4.6, -3.7, -3.0)))
    return _squeeze(parts)


def oculus_ring(oculus, sun_dir, radius=HOLE_RADIUS, seed=9):
    """Rough stones around the hole in the vault, so it reads as an opening cut through rock."""
    part = Part("OculusRing")
    rnd = random.Random(seed)
    axis = Vector(sun_dir).normalized()
    u = axis.cross(Vector((0, 1, 0))).normalized()
    v = axis.cross(u).normalized()
    count = 11
    for k in range(count):
        a = math.tau * k / count + rnd.uniform(-0.15, 0.15)
        centre = oculus + (u * math.cos(a) + v * math.sin(a)) * (radius + rnd.uniform(0.0, 0.5)) - axis * rnd.uniform(0.0, 0.6)
        r = rnd.uniform(0.7, 1.15)
        part.blob((centre.x, centre.y, centre.z), (r, r * 0.8, r), "rock_a" if k % 2 else "rock_b", subdiv=1, amp=0.4, seed=seed + k)
    return part


def carpet(seed=7):
    """The spiral carpet as real strips of quads laid 1.5 cm above the floor: band edges are mesh
    edges, so the spiral reads as bands (not as the floor's triangulation), with a dark border."""
    part = Part("Carpet")
    pitch = 2.4
    turns = 2.7
    steps = int(turns * 72)

    def band(ph0, ph1, mat, lift):
        for i in range(steps):
            t0, t1 = i / 72.0, (i + 1) / 72.0   # turns
            quads = []
            for t in (t0, t1):
                th = t * math.tau
                r0 = (t + ph0) * pitch
                r1 = (t + ph1) * pitch
                quads.append((Vector((CARPET_C[0] + math.cos(th) * r0, lift, CARPET_C[1] + math.sin(th) * r0)), Vector((CARPET_C[0] + math.cos(th) * r1, lift, CARPET_C[1] + math.sin(th) * r1))))
            (a0, a1), (b0, b1) = quads
            if max((a1 - CARPET_C_V).length, (b1 - CARPET_C_V).length) > 7.0 or min((a0 - CARPET_C_V).length, (b0 - CARPET_C_V).length) < 0.0:
                continue
            part.quad_out(a0, a1, b1, b0, mat, Vector((a0.x, -5.0, a0.z)))

    CARPET_C_V = Vector((CARPET_C[0], 0.0, CARPET_C[1]))
    band(-0.03, 0.37, "wood_dark", 0.012)      # dark border under the purple
    band(0.00, 0.34, "carpet_purple", 0.02)
    band(0.31, 0.67, "wood_dark", 0.012)
    band(0.34, 0.64, "carpet_gold", 0.02)
    return part
