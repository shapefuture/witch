"""Assemble the whole hall in a fresh Blender scene: architecture, shelves, props, dynamic props as
shadow-casters, the beam hull and the lights."""
import random

import bpy
import numpy as np

from . import geo, hall, layout as L, lighting, materials, props, shelves


class Hall:
    def __init__(self):
        self.static = []        # architecture and big props (the proxy is made from these)
        self.instances = []     # shelf props
        self.candles = []
        self.machine = None
        self.bell = None
        self.beam = None
        self.lights = {}


def tower_b_at():
    return np.array([2.85, 0.0, -5.0])


def build(quick=False, dusk=False, blockout=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    coll = bpy.data.collections.new("Hall")
    scene.collection.children.link(coll)
    pcoll = bpy.data.collections.new("ShelfProps")
    scene.collection.children.link(pcoll)
    mats = materials.make_all()
    h = Hall()
    h.mats = mats
    add = h.static.extend

    add([hall.floor(coll, mats)])
    add(hall.enclosure(coll, mats))
    add([hall.nave_walls(coll, mats)])
    add(hall.arch_wall(coll, mats))
    add(hall.passage(coll, mats))
    add([hall.alcove(coll, mats)])
    add([hall.pilaster(coll, mats)])
    add([hall.statue(coll, mats)])
    ta, tiers_a = hall.tower_frame("TowerA", tuple(L.TOWER_A_AT), 4.0, 1.85, 0.95, 5.1, 1.25, coll, mats, seed=1)
    tb, tiers_b = hall.tower_frame("TowerB", tuple(tower_b_at()), -8.0, 1.35, 0.8, 4.5, 1.15, coll, mats, seed=2)
    add([ta, tb])
    add(props.orb(coll, mats))
    add(props.foreground(coll, mats))

    rng = random.Random(1234)
    lib = shelves.Library(pcoll, mats)
    run = 0
    sl, run, _ = shelves.bookcase_run(lib, coll, mats, "ShelvesL", L.NAVE_LEFT, hall.FRONT_Z - 0.3, L.LEFT_END_Z, +1, 8.7, rng, run,
                                      candles=h.candles)
    perch = L.RACCOON_PERCH
    sr, run, _ = shelves.bookcase_run(lib, coll, mats, "ShelvesR", L.NAVE_RIGHT, hall.FRONT_Z - 0.3, L.RIGHT_END_Z, -1, 8.2, rng, run,
                                      board_gap=L.RIGHT_BOARD_GAP, first_board=L.RIGHT_FIRST_BOARD,
                                      skips=[(perch[1], perch[2] - 0.55, perch[2] + 0.55), (2.5, L.BELL_HANG[2] - 0.2, L.BELL_HANG[2] + 0.2)],
                                      candles=h.candles)
    add([sl, sr, hall.right_post(coll, mats)])
    run = shelves.fill_tower(lib, tiers_a, tuple(L.TOWER_A_AT), 4.0, rng, run, candles=h.candles)
    run = shelves.fill_tower(lib, tiers_b, tuple(tower_b_at()), -8.0, rng, run, candles=h.candles)
    al, run = shelves.wall_shelves(lib, coll, mats, "AlcoveShelves", 2.95, 6.4, L.ALCOVE_BACK_Z + 0.25, 0.3, 6.2, rng, run, candles=h.candles)
    r2, run = shelves.wall_shelves(lib, coll, mats, "Room2Shelves", hall.THIRD_X - 2.3, hall.THIRD_X + 2.3, hall.ROOM2_BACK_Z + 0.12, 0.2, 4.3, rng, run,
                                   board_gap=0.85, candles=h.candles)
    add([al, r2])
    h.instances = lib.instances
    h.library = lib
    # keep a few candles only: the reference is lit by one beam, not a chandelier
    # (mid-distance ones only, so no candle blazes at the frame's edge)
    _, depth = L.REF.project([tuple(p) for _, p in h.candles]) if h.candles else (None, [])
    deep = [k for k, d in enumerate(depth) if 7.0 < d < 15.0]
    keep = set(rng.sample(deep, min(6, len(deep))))
    for k, (flame, p) in enumerate(list(h.candles)):
        if k not in keep:
            flame.hide_render = True     # an unlit wick
    h.candles = [h.candles[k] for k in sorted(keep)]

    # dynamic props: their own glTF; in the plates they only cast shadows and bounce
    h.machine = props.build_machine(coll, mats)
    h.bell = props.build_bell(coll, mats)
    for o in h.machine[1] + h.bell[1]:
        o.visible_camera = False

    if dusk:
        for o in h.instances:
            if o.get("dusk_gap"):
                o.hide_render = True
    sun_dir = L.SUN_DIR if not dusk else dusk_sun()
    h.beam = lighting.beam_hull(coll, mats, L.OCULUS, sun_dir)
    h.lights = lighting.rig(scene, coll, mats, h.candles, sun_dir=sun_dir, dusk=dusk)
    if blockout:
        for o in h.static + h.instances:
            if o.type == "MESH":
                o.data.materials.clear()
                o.data.materials.append(mats["blockout"])
    h.scene = scene
    return h


def dusk_sun():
    """Lower and warmer: the same hole, a sun 18 degrees lower, so the pool slides toward the camera."""
    d = np.array(L.SUN_DIR, float)
    horiz = np.array([d[0], 0.0, d[2]])
    el = np.arctan2(d[1], np.linalg.norm(horiz)) - np.radians(18.0)
    horiz /= np.linalg.norm(horiz)
    out = horiz * np.cos(el) + np.array([0, 1.0, 0]) * np.sin(el)
    return out / np.linalg.norm(out)
