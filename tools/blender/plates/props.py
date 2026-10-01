"""Props that are not shelves: the purple globe, the dark foreground masses at the frame edges, and the
two dynamic things (the machine and the bell), which are exported as their own glTF files and are
NOT drawn into the plates (they only throw their shadows there)."""
import math

import bpy
from mathutils import Vector

from . import geo, layout as L
from .geo import Builder, xf


def orb(coll, mats):
    """The faceted purple globe on a turned stand with a meridian arm (left foreground)."""
    c = Vector(L.ORB_AT)
    b = Builder("Orb")
    b.sphere(tuple(c), 0.4, "purple", subdiv=2, amp=0.06, seed=9)
    stand = Builder("OrbStand")
    base = Vector((c.x + 0.05, 0.0, c.z + 0.05))
    stand.lathe([(0.42, 0.0), (0.38, 0.1), (0.16, 0.25), (0.11, 0.6), (0.16, 0.85), (0.26, 0.95), (0.2, 1.02)], "wood_dark", segs=9, matrix=xf(base))
    # the meridian: a brass arc half round the globe
    pts = []
    for k in range(13):
        a = math.radians(-100 + 200 * k / 12)
        pts.append(c + Vector((math.cos(a) * 0.0 + math.sin(a) * 0.0, math.sin(a) * 0.5, 0)) + Vector((math.cos(a) * 0.5, 0, 0)) * 0.0)
    for k in range(12):
        a0 = math.radians(-110 + 220 * k / 12)
        a1 = math.radians(-110 + 220 * (k + 1) / 12)
        p0 = c + Vector((math.cos(a0) * 0.49, math.sin(a0) * 0.49, 0.0))
        p1 = c + Vector((math.cos(a1) * 0.49, math.sin(a1) * 0.49, 0.0))
        stand.cyl(tuple(p0), tuple(p1), 0.035, 0.035, "brass", segs=5)
    stand.cyl((c.x + 0.05, 1.0, c.z + 0.05), (c.x + 0.02, c.y - 0.47, c.z), 0.05, 0.04, "brass", segs=6)
    o = b.build(coll, mats)
    geo.facet(o, seed=1)
    s = stand.build(coll, mats)
    geo.facet(s, seed=2)
    return [o, s]


def foreground(coll, mats):
    """Big dark things cropped by the frame: a boulder and a fallen tablet bottom-left, a tall crystal
    on a pedestal and a rock bottom-right, the end of a shelf at each side. World space."""
    out = []
    b = Builder("FgRocks")
    b.sphere((-2.55, 0.35, 3.05), (1.05, 0.95, 0.9), "stone_dark", subdiv=3, amp=0.45, seed=5, flat_bottom=-0.35, freq=1.2)
    b.sphere((-3.4, 0.25, 2.1), (0.8, 0.7, 0.9), "stone_dark", subdiv=3, amp=0.5, seed=6, flat_bottom=-0.3, freq=1.2)
    b.sphere((2.85, 0.32, 2.75), (0.62, 0.5, 0.55), "stone_dark", subdiv=3, amp=0.45, seed=8, flat_bottom=-0.5, freq=1.3)
    o = b.build(coll, mats)
    geo.facet(o, target_edge=0.2, seed=3)
    out.append(o)
    t = Builder("FgTablet")
    t.box((-1.42, 0.38, 1.62), (0.62, 0.8, 0.12), "stone_warm", r=(-24, 18, 4))
    o = t.build(coll, mats)
    geo.facet(o, seed=4)
    out.append(o)
    # the crystal on its pedestal, right edge
    p = Builder("FgCrystal")
    p.box((3.25, 0.45, 2.75), (0.85, 0.9, 0.85), "stone_dark", r=(0, 12, 0), taper=(0.85, 0.85))
    p.cyl((3.2, 0.85, 2.72), (3.12, 2.15, 2.68), 0.36, 0.0, "crystal_dark", segs=6, spin=10)
    p.cyl((3.2, 0.95, 2.72), (3.25, 0.55, 2.74), 0.33, 0.0, "crystal_dark", segs=6, spin=40)
    o = p.build(coll, mats)
    geo.facet(o, seed=5)
    out.append(o)
    return out


# ---- the dynamic props ---------------------------------------------------------------------------------

def gear(name, radius, teeth, thickness, hub=0.09):
    """A chunky gear with its axle along local +Z (it spins about local Z)."""
    b = Builder(name)
    m = xf((0, 0, 0), (90, 0, 0))     # build about Y, turn the axle onto Z
    n0 = b.count()
    b.cyl((0, -thickness / 2, 0), (0, thickness / 2, 0), radius * 0.84, radius * 0.84, "brass", segs=max(10, teeth * 2))
    for i in range(teeth):
        a = math.tau * i / teeth
        r = radius * 0.94
        b.box((math.cos(a) * r, 0, math.sin(a) * r), (radius * 0.2, thickness, radius * 0.22), "brass", r=(0, -math.degrees(a), 0), taper=(0.75, 0.75))
    for s in range(3):
        b.box((0, thickness * 0.55, 0), (radius * 1.45, thickness * 0.3, radius * 0.13), "gold", r=(0, 60 * s, 0))
    b.cyl((0, -thickness * 0.9, 0), (0, thickness * 0.9, 0), hub, hub, "iron", segs=8)
    b.transform(n0, m)
    return b


def machine_parts():
    """{node: (Builder, location, rotation_deg)} in the machine's local space (origin on the floor,
    front toward +z). Gear nodes are named Gear* and spin about their local Z."""
    parts = {}
    base = Builder("Base")
    base.box((0, 0.16, 0), (1.9, 0.32, 1.15), "wood")
    for sx in (-0.85, 0.85):
        for sz in (-0.48, 0.48):
            base.box((sx, 0.04, sz), (0.18, 0.1, 0.18), "brass")
    base.box((0.0, 1.1, -0.42), (1.75, 1.55, 0.12), "wood_dark", r=(0, 0, 1.5))
    base.cyl((-0.68, 0.32, -0.05), (-0.68, 1.15, -0.05), 0.27, 0.24, "brass", segs=10)
    base.sphere((-0.68, 1.2, -0.05), (0.24, 0.17, 0.24), "brass", subdiv=2)
    for k in range(10):
        a = math.tau * k / 10
        base.sphere((-0.68 + math.cos(a) * 0.268, 0.62, -0.05 + math.sin(a) * 0.268), 0.025, "iron", subdiv=1)
    base.cyl((-0.68, 0.85, 0.2), (-0.68, 0.85, 0.27), 0.11, 0.11, "pale", segs=10)
    base.box((0.35, 0.36, 0.1), (0.9, 0.08, 0.7), "iron")
    parts["Base"] = (base, (0, 0, 0), (0, 0, 0))
    parts["GearBig"] = (gear("GearBig", 0.46, 12, 0.11), (0.05, 0.98, -0.22), (0, 0, 0))
    parts["GearSmall"] = (gear("GearSmall", 0.26, 8, 0.11), (0.66, 0.74, -0.22), (0, 0, 9))
    parts["GearTiny"] = (gear("GearTiny", 0.17, 6, 0.09), (0.5, 1.44, -0.2), (0, 0, 0))
    pipe = Builder("Pipe")
    pts = [(0, 0, 0), (0, 0.55, 0), (0.1, 0.85, 0.04), (0.42, 1.0, 0.04)]
    for a, c in zip(pts[:-1], pts[1:]):
        pipe.cyl(a, c, 0.07, 0.07, "iron", segs=7)
    pipe.lathe([(0.07, 1.0), (0.17, 1.1), (0.24, 1.26)], "brass", segs=8, matrix=xf((0.42, 0, 0.04)), closed_top=False)
    parts["Pipe"] = (pipe, (-0.5, 0.32, -0.3), (0, 0, 0))
    lever = Builder("Lever")
    lever.cyl((0, 0, 0), (0, 0.62, 0), 0.035, 0.035, "iron", segs=5)
    lever.sphere((0, 0.66, 0), 0.075, "purple", subdiv=1, amp=0.1)
    parts["Lever"] = (lever, (0.78, 0.32, 0.32), (0, 0, -18))
    cam = Builder("Cam")
    cam.box((0, 0, 0), (0.14, 0.14, 0.14), "brass", r=(0, 0, 45))
    parts["Cam"] = (cam, (0.2, 0.62, 0.15), (0, 0, 0))
    ind = Builder("Indicator")
    ind.sphere((0, 0, 0), 0.075, "lamp_glow", subdiv=1)
    parts["Indicator"] = (ind, (-0.3, 1.78, -0.32), (0, 0, 0))
    return parts


def bell_parts():
    """{node: (Builder, location)} in the bell's local space: the origin is the hanger (the pivot).
    The bracket reaches back (+x) to the shelf post it is bolted to."""
    bracket = Builder("BellBracket")
    bracket.box((0.55, 0.18, 0), (1.25, 0.12, 0.12), "wood_dark")
    bracket.cyl((1.1, -0.6, 0), (0.55, 0.12, 0), 0.05, 0.05, "iron", segs=5)
    bracket.box((1.18, -0.2, 0), (0.1, 1.0, 0.2), "iron")
    for s in (-0.12, 0.12):
        bracket.cyl((s, 0.13, 0), (s * 1.1, -0.02, 0), 0.025, 0.025, "iron", segs=5)
    bracket.box((0, 0.1, 0), (0.36, 0.06, 0.12), "iron")
    bell = Builder("Bell")
    bell.cyl((0, 0, 0), (0, -0.16, 0), 0.025, 0.025, "iron", segs=5)
    bell.lathe([(0.27, -0.72), (0.24, -0.67), (0.19, -0.53), (0.13, -0.4), (0.08, -0.3), (0.05, -0.17)], "brass", segs=12, matrix=xf((0, 0, 0)), closed_bottom=False)
    bell.lathe([(0.29, -0.72), (0.27, -0.69), (0.24, -0.68)], "gold", segs=12, matrix=xf((0, 0, 0)), closed_bottom=False, closed_top=False)
    bell.sphere((0, -0.68, 0), 0.06, "iron", subdiv=1, amp=0.1)
    return {"BellBracket": bracket, "Bell": bell}


def build_machine(coll, mats):
    root = bpy.data.objects.new("Machine", None)
    coll.objects.link(root)
    root.matrix_basis = geo.TO_BL @ xf(tuple(L.MACHINE_AT), (0, L.MACHINE_YAW, 0)) @ geo.TO_GD
    objs = []
    for name, (b, loc, r) in machine_parts().items():
        o = b.build(coll, mats, location=loc, rotation=r, parent=root)
        o.name = name
        geo.facet(o, seed=len(objs))
        objs.append(o)
    return root, objs


def build_bell(coll, mats):
    root = bpy.data.objects.new("BellMount", None)
    coll.objects.link(root)
    root.matrix_basis = geo.TO_BL @ xf(tuple(L.BELL_HANG), (0, L.BELL_YAW, 0)) @ geo.TO_GD
    objs = []
    for name, b in bell_parts().items():
        o = b.build(coll, mats, parent=root)
        o.name = name
        geo.facet(o, seed=len(objs) + 7)
        objs.append(o)
    return root, objs
