"""The archive hall's architecture, built for the solved camera (see layout.py).

Plan (Godot space, metres; the camera stands at about (-0.4, 1.3, 6.0) looking down -Z):

    nave        x NAVE_LEFT..NAVE_RIGHT (bookcases on both sides), from behind the camera to the arch wall
    arch wall   z ARCH_WALL_Z, the great pointed arch (left of centre), the eye above it
    passage     behind the arch: a vaulted tunnel, a side stair climbing left into warm light, the third
                arch at its end and the second shelf room past it
    alcove      right-back, behind the statue, lit by the beam; the oculus is in its vault
    statue      hooded, holding scrolls, crowned, on a two-step plinth, right of centre

Surfaces are dense, gently displaced sheets that `geo.facet` collapses into big irregular triangles.
"""
import math

import numpy as np
from mathutils import Vector

from . import geo, layout as L
from .geo import Builder, fbm

FRONT_Z = 9.5           # the wall behind the camera (closes the room for the light)
OUTER_L, OUTER_R = -8.5, 10.5
OUTER_BACK = -15.5
CEIL_TOP = 14.5
WALL_L = L.NAVE_LEFT - 1.0      # stone behind the left bookcases
WALL_R = L.NAVE_RIGHT + 1.0
SPRING_Y = 8.6                  # the nave walls stand this high, then the vault closes in
VAULT_APEX = 12.6
ALCOVE_L = 1.75                 # where the arch wall ends and the alcove opens
OCULUS_R = 0.95

# the great arch (opening; the molding ring sits outside it)
ARCH_HW = 1.6
ARCH_SPRING = 2.9
ARCH_APEX_Y = 4.95
# the passage and what lies past it
PASS_HW = 1.8
PASS_END_Z = -9.0
THIRD_X = -2.17
THIRD_HW = 0.98
THIRD_SPRING = 1.9
THIRD_APEX = 3.0
ROOM2_BACK_Z = -13.2
STAIR_Z0, STAIR_Z1 = -6.1, -8.1     # the side stair's opening in the passage's left wall


def pointed_hw(y, hw, spring, apex):
    """Half-width of a two-centred pointed arch at height y (0 above the apex)."""
    if y <= spring:
        return hw
    h = apex - spring
    if y >= apex:
        return 0.0
    c = (h * h - hw * hw) / (2 * hw)       # centres at +-c from the axis, radius hw + c
    rad = hw + c
    dy = y - spring
    return max(0.0, math.sqrt(max(rad * rad - dy * dy, 0.0)) - c)


def inside_arch(x, y, cx, hw, spring, apex, base=0.0):
    return base - 0.01 <= y <= apex and abs(x - cx) < pointed_hw(y - base + 0.0, hw, spring - base, apex - base) if base else (y <= apex and abs(x - cx) < pointed_hw(y, hw, spring, apex))


def _bump(p, amp, freq, seed, oct_=3):
    return amp * (fbm((p[0] * freq, p[1] * freq, p[2] * freq), oct_, seed) * 0.5 + 0.5)


# ---- floor ------------------------------------------------------------------------------------------

def floor(coll, mats):
    b = Builder("Floor")
    x0, x1, z0, z1 = WALL_L - 0.3, OUTER_R - 0.5, L.ALCOVE_BACK_Z - 0.4, FRONT_Z
    nx, nz = int((x1 - x0) / 0.16), int((z1 - z0) / 0.16)

    def fn(u, v):
        x = x0 + (x1 - x0) * u
        z = z1 + (z0 - z1) * v
        y = 0.035 * fbm((x * 0.7, 0.0, z * 0.7), 2, 5.0) + 0.012 * fbm((x * 3.1, 1.0, z * 3.1), 1, 9.0)
        return (x, y, z)

    def keep(u, v):
        x = x0 + (x1 - x0) * u
        z = z1 + (z0 - z1) * v
        if z < L.ARCH_WALL_Z - 0.2 and x < ALCOVE_L - 0.3:
            return False        # behind the arch wall: the passage has its own floor
        if x > WALL_R + 0.2 and z > L.RIGHT_END_Z + 0.4:
            return False
        return True

    b.surface(fn, nx, nz, "carpet", keep=keep, uv_mode="none")
    obj = b.build(coll, mats)
    geo.facet(obj, target_edge=0.6, seed=3)
    planar_uv(obj, L.CARPET_C, 8.4)
    return obj


def planar_uv(obj, centre, extent):
    """Top-down UVs over a square of side `extent` around `centre` (the carpet sheet)."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    vi = np.zeros(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", vi)
    co = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)[vi]
    gx, gz = co[:, 0], -co[:, 1]          # Blender (x, y) = Godot (x, -z)
    u = (gx - centre[0]) / extent + 0.5
    v = 0.5 - (gz - centre[2]) / extent
    uv.foreach_set("uv", np.stack([u, v], 1).astype(np.float32).ravel())


# ---- the enclosure and the vault ---------------------------------------------------------------------

def enclosure(coll, mats):
    """The vault over everything (with the oculus) and plain outer walls: they close the room so the
    sun enters only through the hole."""
    b = Builder("Vault")
    x0, x1, z0, z1 = OUTER_L, OUTER_R, OUTER_BACK, FRONT_Z + 0.5
    cx = (L.NAVE_LEFT + L.NAVE_RIGHT) / 2.0
    ox, oz = L.OCULUS[0], L.OCULUS[2]

    def height(x, z):
        # nave: pointed barrel between the side walls; alcove: a lower dome that holds the oculus
        t = min(1.0, abs(x - cx) / ((WALL_R - WALL_L) / 2.0))
        nave = SPRING_Y + (VAULT_APEX - SPRING_Y) * (1.0 - t ** 1.25)
        # the alcove's vault rises to the oculus (the hole is at the crown of a low dome)
        d = math.hypot(x - ox, z - oz)
        dome = L.OCULUS[1] + 0.12 - 0.22 * d * d
        h = max(nave, dome)
        if z < L.ARCH_WALL_Z - 0.5 and x < ALCOVE_L:
            h = min(h, 9.6)
        return h + 0.45 * fbm((x * 0.35, 3.0, z * 0.35), 3, 2.0) * min(1.0, d / 2.0)

    nx, nz = int((x1 - x0) / 0.3), int((z1 - z0) / 0.3)

    def fn(u, v):
        x = x0 + (x1 - x0) * u
        z = z0 + (z1 - z0) * v
        return (x, height(x, z), z)

    def keep(u, v):
        x = x0 + (x1 - x0) * u
        z = z0 + (z1 - z0) * v
        return math.hypot(x - ox, z - oz) > OCULUS_R

    b.surface(fn, nx, nz, "stone_dark", keep=keep)
    vault = b.build(coll, mats)
    geo.facet(vault, target_edge=0.85, seed=11)

    w = Builder("Outer")
    for (a, c) in (((x0, z0), (x1, z0)), ((x1, z0), (x1, z1)), ((x1, z1), (x0, z1)), ((x0, z1), (x0, z0))):
        w.quad((a[0], -0.5, a[1]), (c[0], -0.5, c[1]), (c[0], CEIL_TOP, c[1]), (a[0], CEIL_TOP, a[1]), "stone_dark")
    w.box(((x0 + x1) / 2, -0.6, (z0 + z1) / 2), (x1 - x0, 0.2, z1 - z0), "stone_dark")
    outer = w.build(coll, mats)
    geo.facet(outer, seed=12)
    # the rough lip of the oculus: a ring of broken stones, so the hole reads as cut through rock
    r = Builder("OculusLip")
    rng = np.random.default_rng(9)
    for k in range(9):
        a = math.tau * k / 9 + rng.uniform(-0.2, 0.2)
        rad = OCULUS_R + rng.uniform(0.5, 0.75)
        x, z = ox + math.cos(a) * rad, oz + math.sin(a) * rad
        r.sphere((x, height(x, z) + 0.05, z), (rng.uniform(0.3, 0.45), rng.uniform(0.22, 0.32), rng.uniform(0.3, 0.45)), "stone", subdiv=2, amp=0.45, seed=k)
    lip = r.build(coll, mats)
    geo.facet(lip, target_edge=0.22, seed=13)
    return [vault, outer, lip]


def _wall_sheet(b, p0, du, dv, nu, nv, mat, amp, freq, seed, normal, keep=None):
    """A displaced wall sheet: P = p0 + du*u + dv*v + normal * bump."""
    p0, du, dv, nrm = Vector(p0), Vector(du), Vector(dv), Vector(normal)

    def fn(u, v):
        p = p0 + du * u + dv * v
        return tuple(p + nrm * _bump(p, amp, freq, seed))

    return b.surface(fn, nu, nv, mat, keep=keep)


def nave_walls(coll, mats):
    b = Builder("NaveWalls")
    h = SPRING_Y + 1.5
    # left wall faces +x, runs from the front to the arch wall
    zf, zb = FRONT_Z, L.ARCH_WALL_Z
    _wall_sheet(b, (WALL_L, 0, zf), (0, 0, zb - zf), (0, h, 0), int((zf - zb) / 0.2), int(h / 0.2), "stone", 0.45, 0.45, 1.0, (1, 0, 0))
    # right wall faces -x, from the front to the alcove
    zb2 = L.RIGHT_END_Z
    _wall_sheet(b, (WALL_R, 0, zb2), (0, 0, zf - zb2), (0, h, 0), int((zf - zb2) / 0.2), int(h / 0.2), "stone", 0.45, 0.45, 2.0, (-1, 0, 0))
    # the wall behind the camera
    _wall_sheet(b, (WALL_R, 0, zf), (WALL_L - WALL_R, 0, 0), (0, h, 0), int((WALL_R - WALL_L) / 0.25), int(h / 0.25), "stone_dark", 0.3, 0.5, 3.0, (0, 0, -1))
    obj = b.build(coll, mats)
    geo.facet(obj, target_edge=0.55, seed=21)
    return obj


def arch_wall(coll, mats):
    """The wall with the great arch, the plaster panel and the eye; the voussoir ring; the mural."""
    b = Builder("ArchWall")
    z = L.ARCH_WALL_Z
    x0, x1 = WALL_L - 0.2, ALCOVE_L
    top = VAULT_APEX + 0.5
    nu, nv = int((x1 - x0) / 0.12), int(top / 0.12)
    eye_c = Vector((-2.43, 6.63))
    panel = (3.2, 1.25)            # half sizes of the plaster panel round the eye

    def in_panel(x, y):
        return ((x - eye_c.x) / panel[0]) ** 2 + ((y - eye_c.y) / panel[1]) ** 2 < 1.0

    def fn(u, v):
        x, y = x0 + (x1 - x0) * u, top * v
        e = ((x - eye_c.x) / panel[0]) ** 2 + ((y - eye_c.y) / panel[1]) ** 2
        fade = min(1.0, max(0.0, (e - 0.85) / 0.6))
        d = _bump((x, y, z), 0.32, 0.5, 4.0) * fade
        return (x, y, z + d)

    def keep(u, v):
        x, y = x0 + (x1 - x0) * u, top * v
        return not inside_arch(x, y, L.ARCH_X, ARCH_HW, ARCH_SPRING, ARCH_APEX_Y)

    def mat_of(u, v):
        return None

    faces = b.surface(fn, nu, nv, "stone", keep=keep)
    pi = b._mi("plaster")
    for f in faces:
        c = f.calc_center_median()
        if in_panel(c.x, c.y):
            f.material_index = pi
    # the voussoir ring: chunky stones following the opening
    rng = np.random.default_rng(5)
    pts = []
    n = 15
    for k in range(n + 1):
        y = ARCH_APEX_Y * k / n
        pts.append((L.ARCH_X - pointed_hw(y, ARCH_HW, ARCH_SPRING, ARCH_APEX_Y), y))
    pts += [(2 * L.ARCH_X - x, y) for (x, y) in reversed(pts[:-1])]
    for k in range(len(pts) - 1):
        (xa, ya), (xb, yb) = pts[k], pts[k + 1]
        mx, my = (xa + xb) / 2, (ya + yb) / 2
        ang = math.degrees(math.atan2(yb - ya, xb - xa))
        ln = math.hypot(xb - xa, yb - ya)
        nx, ny = -(yb - ya), (xb - xa)
        nl = math.hypot(nx, ny) or 1.0
        nx, ny = nx / nl, ny / nl
        if (mx - L.ARCH_X) * nx < 0:
            nx, ny = -nx, -ny
        if my < ARCH_SPRING:
            nx, ny = (1.0 if mx > L.ARCH_X else -1.0), 0.0
        off = 0.27
        b.box((mx + nx * off, my + ny * off, z + 0.22), (max(ln, 0.45) * 1.12, 0.62 + rng.uniform(-0.05, 0.1), 0.62 + rng.uniform(0, 0.2)),
              "stone_warm", r=(0, 0, ang + rng.uniform(-4, 4)))
    b.box((L.ARCH_X, ARCH_APEX_Y + 0.42, z + 0.28), (0.66, 0.78, 0.8), "stone_warm", r=(0, 0, 2), taper=(0.75, 1.0))
    wall = b.build(coll, mats)
    geo.facet(wall, target_edge=0.42, seed=31)
    # the eye: ONE quad in front of the flat panel, the whole sheet mapped once
    m = Builder("Mural")
    ew, eh = 2.75, 1.45
    m.quad((eye_c.x - ew / 2, eye_c.y - eh / 2, z + 0.03), (eye_c.x + ew / 2, eye_c.y - eh / 2, z + 0.03),
           (eye_c.x + ew / 2, eye_c.y + eh / 2, z + 0.03), (eye_c.x - ew / 2, eye_c.y + eh / 2, z + 0.03), "mural",
           uv=[(0, 0), (1, 0), (1, 1), (0, 1)])
    mural = m.build(coll, mats)
    geo.facet_attr(mural)
    return [wall, mural]


def passage(coll, mats):
    """Behind the great arch: the vaulted passage, the side stair into warm light, the third arch,
    the medallion over it and the second shelf room."""
    b = Builder("Passage")
    z0, z1 = L.ARCH_WALL_Z + 0.1, PASS_END_Z
    cx = L.ARCH_X
    top = ARCH_APEX_Y + 0.9

    def section(t, side):
        """Point on the tunnel's cross-section: t in [0,1] from floor (0) to apex (1)."""
        y = top * t
        return cx + side * (pointed_hw(y, PASS_HW, ARCH_SPRING + 0.3, top) + 0.02), y

    for side in (-1, 1):
        def fn(u, v, side=side):
            x, y = section(v, side)
            zz = z0 + (z1 - z0) * u
            return (x + side * _bump((x, y, zz), 0.22, 0.8, 6.0 + side), y, zz)

        def keep(u, v, side=side):
            zz = z0 + (z1 - z0) * u
            y = top * v
            return not (side < 0 and STAIR_Z1 < zz < STAIR_Z0 and y < 3.4)

        b.surface(fn, int((z0 - z1) / 0.15), 34, "stone", keep=keep)
    # floor of the passage
    b.surface(lambda u, v: (cx - PASS_HW - 0.1 + (2 * PASS_HW + 0.2) * u, 0.01 * fbm((u * 9, v * 9, 0), 1, 3), z0 + (z1 - z0) * v), 12, 30, "floor")
    # the end wall with the third arch
    xa, xb = cx - PASS_HW - 0.3, cx + PASS_HW + 0.3

    def end_fn(u, v):
        x, y = xa + (xb - xa) * u, top * v
        return (x, y, z1 + _bump((x, y, z1), 0.12, 0.9, 7.0))

    b.surface(end_fn, int((xb - xa) / 0.1), int(top / 0.1), "stone_warm", keep=lambda u, v: not inside_arch(xa + (xb - xa) * u, top * v, THIRD_X, THIRD_HW, THIRD_SPRING, THIRD_APEX))
    # third arch ring
    for k in range(13):
        y = THIRD_APEX * k / 12
        for side in (-1, 1):
            x = THIRD_X + side * (pointed_hw(y, THIRD_HW, THIRD_SPRING, THIRD_APEX) + 0.13)
            b.box((x, y + 0.1, z1 + 0.08), (0.3, 0.32, 0.3), "stone_warm", r=(0, 0, side * 8 * k / 12))
    obj = b.build(coll, mats)
    geo.facet(obj, target_edge=0.32, seed=41)

    # the side stair: steps climbing left (toward -x), walls round it, warm light at the top
    s = Builder("Stair")
    sx0 = cx - PASS_HW
    for k in range(9):
        y = 0.19 * (k + 1)
        s.box((sx0 - 0.35 - 0.38 * k, y / 2, (STAIR_Z0 + STAIR_Z1) / 2), (0.42, y, STAIR_Z0 - STAIR_Z1), "stone_warm")
    for zz in (STAIR_Z0, STAIR_Z1):
        s.box((sx0 - 2.0, 2.6, zz + (0.1 if zz == STAIR_Z0 else -0.1)), (4.2, 5.2, 0.25), "stone")
    s.box((sx0 - 4.0, 2.6, (STAIR_Z0 + STAIR_Z1) / 2), (0.3, 5.2, STAIR_Z0 - STAIR_Z1 + 0.4), "stone")
    s.box((sx0 - 2.0, 4.9, (STAIR_Z0 + STAIR_Z1) / 2), (4.2, 0.3, STAIR_Z0 - STAIR_Z1 + 0.4), "stone_dark")
    stair = s.build(coll, mats)
    geo.facet(stair, seed=42)
    # the warm source at the top of the stair (glow group)
    g = Builder("StairGlow")
    gz = (STAIR_Z0 + STAIR_Z1) / 2
    g.quad((sx0 - 3.8, 1.9, STAIR_Z0 - 0.15), (sx0 - 3.8, 1.9, STAIR_Z1 + 0.15), (sx0 - 3.8, 4.6, STAIR_Z1 + 0.15), (sx0 - 3.8, 4.6, STAIR_Z0 - 0.15), "stair_glow")
    glow = g.build(coll, mats)

    # the medallion on the end wall, over the third arch, left of it
    md = Builder("Medallion")
    mcx, mcy = THIRD_X - 0.72, 3.95
    md.cyl((mcx, mcy, z1 + 0.05), (mcx, mcy, z1 + 0.14), 0.52, 0.52, "stone_warm", segs=12)
    md.quad((mcx - 0.48, mcy - 0.48, z1 + 0.15), (mcx + 0.48, mcy - 0.48, z1 + 0.15), (mcx + 0.48, mcy + 0.48, z1 + 0.15), (mcx - 0.48, mcy + 0.48, z1 + 0.15),
            "medallion", uv=[(0, 0), (1, 0), (1, 1), (0, 1)])
    med = md.build(coll, mats)
    geo.facet_attr(med)

    # the second shelf room past the third arch
    r = Builder("Room2")
    rx0, rx1 = THIRD_X - 2.6, THIRD_X + 2.6
    r.box(((rx0 + rx1) / 2, -0.1, (z1 + ROOM2_BACK_Z) / 2), (rx1 - rx0, 0.2, z1 - ROOM2_BACK_Z), "floor")
    r.box(((rx0 + rx1) / 2, 4.6, (z1 + ROOM2_BACK_Z) / 2), (rx1 - rx0, 0.2, z1 - ROOM2_BACK_Z), "stone_dark")
    for xx in (rx0, rx1):
        r.box((xx, 2.3, (z1 + ROOM2_BACK_Z) / 2), (0.2, 4.6, z1 - ROOM2_BACK_Z), "stone")
    r.box(((rx0 + rx1) / 2, 2.3, ROOM2_BACK_Z), (rx1 - rx0, 4.6, 0.2), "stone")
    room = r.build(coll, mats)
    geo.facet(room, seed=43)
    return [obj, stair, glow, med, room]


def alcove(coll, mats):
    """Right-back recess behind the statue: side wall continuing the arch wall line, back wall with
    shelf niches (filled by shelves.py), lit by the beam."""
    b = Builder("Alcove")
    zb, zf = L.ALCOVE_BACK_Z, L.ARCH_WALL_Z
    xr = L.ALCOVE_RIGHT
    h = 9.4
    # back wall faces +z
    _wall_sheet(b, (ALCOVE_L - 0.4, 0, zb), (xr - ALCOVE_L + 0.4, 0, 0), (0, h, 0), int((xr - ALCOVE_L) / 0.18), int(h / 0.18), "stone_warm", 0.35, 0.55, 8.0, (0, 0, 1))
    # left side wall (continuing the arch wall into the recess) faces +x
    _wall_sheet(b, (ALCOVE_L, 0, zf), (0, 0, zb - zf), (0, h, 0), int((zf - zb) / 0.18), int(h / 0.18), "stone", 0.3, 0.6, 9.0, (1, 0, 0))
    # right side wall faces -x, from the end of the nave's right wall back
    _wall_sheet(b, (xr, 0, zb), (0, 0, L.RIGHT_END_Z - zb + 0.5), (0, h, 0), int((L.RIGHT_END_Z - zb) / 0.18), int(h / 0.18), "stone", 0.35, 0.55, 10.0, (-1, 0, 0))
    # the corner between the nave's right wall and the alcove: a pier
    b.box((WALL_R + 0.3, h / 2, L.RIGHT_END_Z - 0.2), (1.3, h, 1.0), "stone")
    obj = b.build(coll, mats)
    geo.facet(obj, target_edge=0.5, seed=51)
    return obj


def pilaster(coll, mats):
    """The massive column at the end of the left bookcases (screen x ~345..420)."""
    b = Builder("Pilaster")
    x, _, z = L.PILASTER_AT
    prof = [(0.55, 0.0), (0.55, 0.45), (0.42, 0.7), (0.36, 2.0), (0.34, 6.0), (0.37, 8.4), (0.55, 9.2), (0.62, 12.0)]
    b.lathe(prof, "stone", segs=10, matrix=geo.xf((x, 0, z)), jitter=0.07, seed=3)
    # a dark iron sconce with a purple orb (the ref's small purple note high on the column)
    b.cyl((x + 0.3, 6.55, z + 0.2), (x + 0.6, 6.85, z + 0.4), 0.04, 0.04, "iron", segs=5)
    b.box((x + 0.33, 6.4, z + 0.18), (0.08, 0.5, 0.14), "iron")
    b.sphere((x + 0.65, 7.1, z + 0.45), 0.2, "purple", subdiv=1, amp=0.15, seed=4)
    obj = b.build(coll, mats)
    geo.facet(obj, target_edge=0.3, seed=61)
    # its twin on the far side of the arch, where the arch wall meets tower A (mostly hidden)
    return obj


def statue(coll, mats):
    """Hooded and faceless, holding a bundle of scrolls, a crown of pale crystals behind the head,
    on a two-step plinth. A smooth form, collapsed into facets."""
    sx, _, sz = L.STATUE_AT
    yaw = -25.0
    m = geo.xf((sx, 0, sz), (0, yaw, 0))
    b = Builder("Statue")
    n0 = b.count()
    b.box((0, 0.17, 0), (1.7, 0.34, 1.6), "stone_dark")
    b.box((0, 0.46, 0), (1.35, 0.26, 1.3), "stone", r=(0, 6, 0))
    # robe: a lathe with folds (noise in angle), flaring at the hem
    prof = [(0.70, 0.58), (0.66, 0.9), (0.58, 1.5), (0.52, 2.1), (0.48, 2.6), (0.47, 2.9), (0.40, 3.1), (0.18, 3.2)]
    b.lathe(prof, "cloak", segs=28, jitter=0.0)
    n1 = b.count()
    # hood: a stretched sphere, pulled back to a soft peak
    b.sphere((0, 3.28, -0.02), (0.38, 0.47, 0.42), "cloak", subdiv=3, amp=0.05, seed=2)

    def hood_peak(p):
        if p.y > 3.45:
            k = (p.y - 3.45) / 0.3
            p.z -= 0.18 * k * k
        return p
    b.displace(n1, hood_peak)
    # the empty face
    b.sphere((0, 3.22, 0.22), (0.24, 0.3, 0.16), "void", subdiv=2, amp=0.02, seed=1)
    # arms folded forward to the chest, holding scrolls
    for s in (-1, 1):
        b.cyl((s * 0.45, 2.95, 0.02), (s * 0.18, 2.45, 0.42), 0.16, 0.13, "cloak", segs=8)
    for k, (dy, rad) in enumerate(((2.52, 0.085), (2.36, 0.08), (2.66, 0.07))):
        b.cyl((-0.42, dy, 0.48 + 0.03 * k), (0.4, dy + 0.05, 0.5 + 0.03 * k), rad, rad, "scroll", segs=8)
        for s in (-1, 1):
            xx = 0.4 if s > 0 else -0.42
            b.cyl((xx, dy + (0.05 if s > 0 else 0), 0.48 + 0.03 * k), (xx + s * 0.05, dy + (0.05 if s > 0 else 0), 0.48 + 0.03 * k), rad + 0.012, rad + 0.012, "scroll_end", segs=8)
    # the crown: pale crystals fanning behind the head
    for k, ang in enumerate((-58, -38, -19, 0, 19, 38, 58)):
        a = math.radians(ang)
        tall = 1.05 if k in (2, 3, 4) else 0.72
        base = Vector((math.sin(a) * 0.2, 3.45, -0.3))
        tip = Vector((math.sin(a) * 0.85, 3.45 + tall * math.cos(a), -0.48))
        b.cyl(base, tip, 0.12, 0.0, "crystal", segs=5, spin=18)
        b.sphere(tuple(tip + (base - tip) * 0.25), 0.1, "crystal", subdiv=1, amp=0.3, seed=k)
    b.transform(n0, m)
    obj = b.build(coll, mats)
    # keep the plinth's planes, facet the figure
    geo.facet(obj, target_edge=0.11, seed=71)
    return obj


def tower_frame(name, at, yaw, w, d, h, spire, coll, mats, taper=0.16, seed=0):
    """A gothic bookcase tower: tapering open-fronted case on a stone foot, a pointed spire and a
    finial with a purple gem. Returns (object, shelf boards [(y, half_width, depth)] in local space)."""
    b = Builder(name)
    n0 = b.count()
    b.box((0, 0.22, 0.05), (w + 0.45, 0.44, d + 0.4), "stone_dark")
    tiers = []
    y = 0.44
    tier_h = 0.86
    while y + tier_h < h - 0.2:
        t = y / h
        wk = w * (1.0 - taper * t)
        b.box((0, y, 0), (wk, 0.08, d), "wood_dark")
        tiers.append((y + 0.04, wk / 2 - 0.1, d / 2))
        y += tier_h
    # sides and back
    for s in (-1, 1):
        b.box((s * (w * (1 - taper / 2) / 2), h / 2, 0), (0.14, h, d + 0.06), "wood_dark", r=(0, 0, -s * math.degrees(math.atan(taper * w / 2 / h))))
    b.box((0, h / 2, -d / 2 + 0.04), (w, h, 0.08), "wood_dark", taper=(1 - taper, 1.0))
    top_w = w * (1 - taper)
    b.box((0, h, 0), (top_w + 0.2, 0.16, d + 0.1), "wood_dark")
    b.cyl((0, h + 0.05, 0), (0, h + spire, 0), top_w * 0.72, 0.04, "wood_dark", segs=4, spin=45)
    # small pinnacles on the shoulders
    for s in (-1, 1):
        b.cyl((s * top_w * 0.45, h + 0.05, d * 0.3), (s * top_w * 0.45, h + spire * 0.42, d * 0.3), 0.1, 0.0, "wood_dark", segs=4, spin=45)
    b.cyl((0, h + spire - 0.05, 0), (0, h + spire + 0.25, 0), 0.04, 0.04, "iron", segs=4)
    b.sphere((0, h + spire + 0.5, 0), (0.24, 0.3, 0.24), "purple", subdiv=1, amp=0.2, seed=seed)
    b.transform(n0, geo.xf(at, (0, yaw, 0)))
    obj = b.build(coll, mats)
    geo.facet(obj, seed=81 + seed)
    return obj, tiers
