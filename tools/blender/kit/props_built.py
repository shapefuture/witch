"""Hand-made things in the hall: the brass machine, the bell and its mount, the bench, the crate.

Static builders take world (Godot-space) positions and bake into world space. Animated parts
(machine gears, the bell) are built around their own pivot and placed by the object transform.
"""
import math
import random

from mathutils import Vector

from .common import Part, fbm


def _lean(x_per_y2):
    return lambda v: Vector((v.x + x_per_y2 * v.y * v.y, v.y, v.z))


def crate(at):
    part = Part("Crate")
    x, _, z = at
    part.box((x, 0.3, z), (0.82, 0.6, 0.62), "wood", rot=(0, 10, 0), bevel=0.04)
    for dy in (0.1, 0.5):
        part.box((x, dy, z), (0.86, 0.08, 0.66), "wood_dark", rot=(0, 10, 0))
    for dx in (-0.4, 0.4):
        part.box((x + dx * math.cos(math.radians(10)), 0.3, z - dx * math.sin(math.radians(10))), (0.07, 0.62, 0.66), "wood_dark", rot=(0, 10, 0))
    part.tube([Vector((x - 0.2, 0.62, z + 0.1)), Vector((x - 0.05, 0.78, z + 0.2)), Vector((x + 0.15, 0.64, z + 0.15)), Vector((x + 0.08, 0.62, z - 0.05))], 0.03, mat="cream", segs=4, per_segment=3)
    part.box((x + 0.5, 0.18, z + 0.4), (0.26, 0.36, 0.26), "wood_dark", rot=(0, 30, 0), bevel=0.03)
    return part


def bench(at):
    part = Part("Workbench")
    x, _, z = at
    part.box((x, 0.92, z), (1.9, 0.12, 0.85), "wood", rot=(0, 4, 0), bevel=0.03)
    for dx in (-0.8, 0.8):
        for dz in (-0.3, 0.3):
            part.box((x + dx, 0.45, z + dz), (0.12, 0.9, 0.12), "wood_dark", rot=(0, 4, 0))
    part.box((x, 0.35, z), (1.7, 0.07, 0.7), "wood_dark", rot=(0, 4, 0))
    # clutter: spare gears, a jar of glowing seeds, a teacup that is far too good for this table
    part.lathe([(0.17, 0.98 + 0.0), (0.2, 1.1), (0.15, 1.22)], segs=7, mat="cream", center=(x - 0.7, 0, z + 0.05))
    part.lathe([(0.13, 1.0), (0.15, 1.14), (0.1, 1.24)], segs=6, mat="glow_green", center=(x - 0.7, 0, z + 0.05))
    part.cyl((x - 0.1, 0.98, z - 0.1), (x - 0.1, 1.04, z - 0.1), 0.2, 0.2, "brass", segs=10)
    part.cyl((x - 0.1, 1.04, z - 0.1), (x - 0.1, 1.08, z - 0.1), 0.06, 0.06, "iron", segs=6)
    part.lathe([(0.0, 0.98), (0.2, 0.98), (0.28, 1.1), (0.26, 1.22), (0.22, 1.22)], segs=8, mat="coral", center=(x + 0.55, 0, z + 0.15), closed_top=False)
    part.lathe([(0.3, 0.98), (0.3, 1.0)], segs=8, mat="cream", center=(x + 0.55, 0, z + 0.15))
    part.box((x + 0.2, 1.02, z + 0.2), (0.5, 0.06, 0.12), "iron", rot=(0, 25, 0))
    part.box((x + 0.55, 1.04, z + 0.1), (0.12, 0.1, 0.1), "brass", rot=(0, 20, 0))
    part.cyl((x + 0.25, 1.0, z - 0.2), (x + 0.65, 1.0, z - 0.25), 0.03, 0.05, "wood", segs=5)
    part.blob((x + 0.7, 1.04, z - 0.25), (0.1, 0.07, 0.07), "iron", subdiv=1, amp=0.15)
    return part


def gear(name, radius, teeth, thickness, mat_rim="brass", mat_face="iron", hub=0.14, spokes=4):
    """A chunky gear with its axle along local +Y (rotate the object to aim the axle)."""
    part = Part(name)
    part.cyl((0, -thickness / 2, 0), (0, thickness / 2, 0), radius * 0.86, radius * 0.86, mat_face, segs=max(8, teeth * 2))
    for i in range(teeth):
        a = math.tau * i / teeth
        r = radius * 0.93
        part.box((math.cos(a) * r, 0, math.sin(a) * r), (radius * 0.2, thickness * 1.05, radius * 0.24), mat_rim, rot=(0, -math.degrees(a), 0), taper=(0.82, 0.82))
    part.cyl((0, -thickness * 0.9, 0), (0, thickness * 0.9, 0), radius * 0.76, radius * 0.76, mat_rim, segs=max(8, teeth * 2), caps=False)
    for s in range(spokes):
        a = 180.0 * s / spokes
        part.box((0, thickness * 0.5, 0), (radius * 1.5, thickness * 0.4, radius * 0.14), mat_rim, rot=(0, a, 0), bevel=0.01)
    part.cyl((0, -thickness, 0), (0, thickness * 1.2, 0), hub, hub * 0.9, "brass", segs=8)
    return part


def machine_parts():
    """Returns {node_name: (Part, location, rotation_deg)} in the machine's local space (origin on the floor)."""
    parts = {}
    base = Part("Base")
    base.box((0, 0.17, 0), (2.5, 0.34, 1.6), "wood", bevel=0.05)
    for sx in (-1.2, 1.2):
        for sz in (-0.75, 0.75):
            base.box((sx, 0.04, sz), (0.22, 0.12, 0.22), "brass", bevel=0.03)
    # backboard so the gears read against wood
    base.box((-0.1, 1.15, -0.5), (2.3, 1.7, 0.14), "shelf", rot=(0, 0, 1.5), bevel=0.04)
    for (px, py) in ((-1.1, 1.8), (0.95, 1.7), (-1.1, 0.5), (0.95, 0.5)):
        base.blob((px, py, -0.4), (0.07, 0.07, 0.04), "brass", subdiv=1, amp=0.1)
    # copper boiler with rivets and a pressure gauge
    base.cyl((-1.05, 0.7, -0.15), (-1.05, 1.45, -0.15), 0.34, 0.3, "brass", segs=9)
    base.blob((-1.05, 1.5, -0.15), (0.3, 0.2, 0.3), "brass", subdiv=1, amp=0.06)
    for k in range(9):
        a = math.tau * k / 9
        base.blob((-1.05 + math.cos(a) * 0.335, 0.95, -0.15 + math.sin(a) * 0.335), (0.03, 0.03, 0.03), "iron", subdiv=1, amp=0.0)
    base.cyl((-1.05, 1.0, 0.16), (-1.05, 1.0, 0.24), 0.14, 0.14, "cream", segs=8)
    base.box((-1.05, 1.03, 0.25), (0.015, 0.1, 0.01), "coral", rot=(0, 0, 25))
    parts["Base"] = (base, (0, 0, 0), (0, 0, 0))
    big = gear("BigGear", 0.66, 11, 0.14)
    parts["BigGear"] = (big, (-0.35, 0.82, 0.05), (90, 0, 0))
    small = gear("SmallGear", 0.34, 8, 0.14, spokes=3)
    parts["SmallGear"] = (small, (0.5, 0.66, 0.05), (90, 0, 0))
    pipe = Part("Pipe")
    pipe.tube([Vector((0, 0, 0)), Vector((0, 0.7, 0)), Vector((0.12, 1.1, 0.05)), Vector((0.5, 1.3, 0.05))], [0.11, 0.11, 0.1, 0.1], mat="iron", segs=7, per_segment=3)
    pipe.lathe([(0.1, 1.3), (0.22, 1.42), (0.3, 1.6)], segs=7, mat="brass", center=(0.5, 0, 0.05), closed_top=False)
    parts["Pipe"] = (pipe, (-0.95, 0.35, -0.55), (0, 0, 0))
    lever = Part("Lever")
    lever.cyl((0, 0, 0), (0, 0.75, 0), 0.045, 0.045, "iron", segs=5)
    lever.blob((0, 0.8, 0), (0.1, 0.1, 0.1), "coral", subdiv=1, amp=0.08)
    parts["Lever"] = (lever, (1.0, 0.34, 0.35), (0, 0, -20))
    cam = Part("Cam")
    cam.box((0, 0, 0), (0.18, 0.18, 0.18), "brass", rot=(0, 0, 45), bevel=0.02)
    parts["Cam"] = (cam, (0.12, 1.0, 0.26), (0, 0, 0))
    ind = Part("Indicator")
    ind.blob((0, 0, 0), (0.1, 0.1, 0.1), "glow_warm", subdiv=1, amp=0.0)
    parts["Indicator"] = (ind, (-0.45, 1.88, -0.15), (0, 0, 0))
    return parts


def bell_assembly(tree_at):
    """The brass bell on its wooden mount. Returns (static_part, bell_part, bell_origin)."""
    tx, _, tz = tree_at
    hang = Vector((tx - 1.3, 2.75, tz))
    static = Part("BellMount")
    # the branch that carries it, a pulley beside the yoke and a rope with a bag
    static.tube([Vector((tx - 0.5, 2.5, tz)), Vector((tx - 0.95, 2.78, tz + 0.05)), Vector((tx - 1.45, 2.88, tz)), Vector((tx - 1.9, 2.7, tz - 0.05))], [0.22, 0.16, 0.12, 0.08], mat="wood", segs=6, per_segment=3, jitter=0.08)
    for sx in (-0.2, 0.2):
        static.cyl((hang.x + sx, hang.y + 0.12, hang.z), (hang.x + sx * 1.05, hang.y - 0.05, hang.z), 0.05, 0.05, "wood", segs=5)
    static.box((hang.x, hang.y + 0.14, hang.z), (0.5, 0.08, 0.14), "wood_dark", bevel=0.02)
    pulley = (hang.x - 0.62, hang.y + 0.02, hang.z)
    static.cyl((pulley[0], pulley[1], pulley[2] - 0.06), (pulley[0], pulley[1], pulley[2] + 0.06), 0.15, 0.15, "wood", segs=8)
    static.cyl((pulley[0], pulley[1], pulley[2] - 0.1), (pulley[0], pulley[1], pulley[2] + 0.1), 0.04, 0.04, "iron", segs=5)
    static.tube([Vector((hang.x - 0.1, hang.y - 0.5, hang.z)), Vector((pulley[0] + 0.1, pulley[1] + 0.12, pulley[2])), Vector((pulley[0] - 0.14, pulley[1] - 0.4, pulley[2])), Vector((pulley[0] - 0.12, 1.65, pulley[2]))], 0.022, mat="cream", segs=4, per_segment=4)
    static.blob((pulley[0] - 0.12, 1.45, pulley[2]), (0.2, 0.26, 0.2), "cream", subdiv=1, amp=0.2, seed=4)
    static.cyl((pulley[0] - 0.12, 1.66, pulley[2]), (pulley[0] - 0.12, 1.74, pulley[2]), 0.05, 0.03, "wood_dark", segs=5)
    bell = Part("Bell")
    bell.cyl((0, 0, 0), (0, -0.3, 0), 0.02, 0.02, "iron", segs=4)
    bell.lathe([(0.34, -0.9), (0.3, -0.84), (0.23, -0.66), (0.16, -0.5), (0.1, -0.38), (0.06, -0.33)], segs=9, mat="brass", jitter=0.02, closed_bottom=False)
    bell.blob((0, -0.9, 0), (0.08, 0.08, 0.08), "iron", subdiv=1, amp=0.1)
    bell.lathe([(0.36, -0.9), (0.34, -0.87), (0.31, -0.85)], segs=9, mat="gold", closed_bottom=False, closed_top=False)
    return static, bell, hang


