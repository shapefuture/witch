"""Builds the archive hall (the game's first scene) and bakes its light.

    python tools/blender/build_hall.py --out assets/archive [--samples 64] [--no-bake]

Runs on the `bpy` module (pip install bpy). Output: archive_set.glb (one static batch plus the
animated machine and bell), textures/*.png, anchors.json (positions + lighting the game reads),
light_map.png (top-down sun/shade of the floor, so characters can be lit to match).
"""
import argparse
import json
import math
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

from kit import bake, common, props_built, props_hall, textures  # noqa: E402
from kit.common import Part, empty  # noqa: E402

# Gameplay anchors: identical to game/world/archive/archive_hall.gd.
BELL_PILLAR_AT = (5.6, 0.0, -3.0)
MACHINE_AT = (-1.6, 0.0, -1.2)
TOWER_AT = (-4.4, 0.0, -5.0)       # the crooked bookcase tower the raccoon watches from
PATH_AT = (0.0, 0.0, -7.8)
# The wide shot's camera, as set in game/world/archive/archive_hall.gd (yaw 22, pitch -4, distance 12).
CAMERA_FROM = (3.885, 1.763, 8.10)
CAMERA_AT = (-0.6, 2.6, -3.0)
CRATE_AT = (2.4, 0.0, -0.4)
BENCH_AT = (-3.2, 0.0, -2.6)

# The key light: a steep late-afternoon beam from the right-back, through a hole in the vault.
SUN_DIR = Vector((0.14, 0.88, -0.45)).normalized()
POOL = Vector((1.2, 0.0, -2.0))   # where the shaft lands: Tomas, the machine's edge, the spiral, the statue's side
AMBIENT_LIFT = np.array([0.045, 0.038, 0.030], dtype=np.float32)   # shade is never black: warm olive air


def build(out_dir, samples, do_bake):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    coll = bpy.data.collections.new("Hall")
    scene.collection.children.link(coll)
    mats = bake.make_materials()
    density = {"rock_a": 0.28, "rock_b": 0.28, "floor": 0.3, "carpet_purple": 0.3, "carpet_gold": 0.3, "shelf": 0.9, "wood": 0.6, "wood_dark": 0.6, "plaster": 0.35,
               "iron": 0.8, "brass": 0.8, "cream": 0.8, "coral": 0.8, "crystal": 0.9, "crystal_grey": 0.9, "scroll": 1.2, "cloak": 0.5,
               "book_red": 1.6, "book_olive": 1.6, "book_purple": 1.6, "book_tan": 1.6, "book_teal": 1.6}
    for name in list(textures.SPECS) + ["box_glyph", "mural_eye"]:
        common.UV_DENSITY[name] = density.get(name, 0.4)
    common.CENTERED["mural_eye"] = 1
    common.CENTERED["box_glyph"] = 2

    static = []
    anchors = {}
    oculus = props_hall.oculus_point(POOL, SUN_DIR)
    anchors["oculus"] = list(oculus)

    def add(part, max_edge=None):
        obj = part.build(coll, mats, max_edge=max_edge)
        static.append(obj)
        return obj

    # ---- architecture ------------------------------------------------------------------------------
    add(props_hall.shell(oculus))
    add(props_hall.floor())
    add(props_hall.back_wall())
    add(props_hall.mural_eye())
    add(props_hall.corridor())
    for sx in (-1, 1):
        add(props_hall.pilaster(sx * 4.3, props_hall.BACK_Z + 0.9, seed=sx + 3))
        add(props_hall.sconce((sx * 4.3, 4.6, props_hall.BACK_Z + 1.7), 0.0))
    add(props_hall.compass_plate((-6.3, 11.4, props_hall.BACK_Z + 0.12)))

    # ---- shelves: walls of them -----------------------------------------------------------------------
    zs = [-8.4, -6.0, -3.6, -1.2, 1.2, 3.6, 6.0]
    for i, z in enumerate(zs):
        add(props_hall.bookcase((8.95, 0, z), -90, 2.3, 10.0, 1.1, seed=100 + i))
        add(props_hall.bookcase((-8.95, 0, z), 90, 2.3, 10.0, 1.1, seed=200 + i, density=0.8))
    for sx in (-1, 1):
        add(props_hall.bookcase((sx * 6.9, 0, props_hall.BACK_Z + 0.55), 0, 3.0, 10.0, 1.1, seed=300 + sx))
    for (x, z) in ((8.95, 8.4), (-8.95, 8.4)):
        pass

    # ---- the towers and the statue ---------------------------------------------------------------------
    lean = 0.012
    yaw = 8.0
    add(props_hall.tower(TOWER_AT, yaw, 2.6, 1.7, 7.6, 0.38, seed=11, lean=lean, skip_tiers={2: (0.0, 1.2)}))
    th = math.radians(yaw)
    perch_local = (0.55, 0.6)
    px = TOWER_AT[0] + perch_local[0] * math.cos(th) + perch_local[1] * math.sin(th) + lean * 2.2 * 2.2
    pz = TOWER_AT[2] - perch_local[0] * math.sin(th) + perch_local[1] * math.cos(th)
    anchors["raccoon_perch"] = [px, 2.2, pz]
    add(props_hall.tower((3.9, 0, -8.3), -6, 2.4, 1.6, 8.6, 0.4, seed=12))
    add(props_hall.tower((-6.4, 0, -7.7), 4, 2.4, 1.6, 9.4, 0.42, seed=13))
    add(props_hall.hooded_statue((3.3, 0, -4.0), -40))
    add(props_hall.rubble((-7.2, 0, 6.6), 0.9, 21))
    add(props_hall.rubble((7.6, 0, 7.0), 0.8, 23))

    # ---- the bell on its pillar; the workbench and crate --------------------------------------------------
    add(props_hall.column(BELL_PILLAR_AT, seed=4))
    mount, bell_part, hang = props_built.bell_assembly(BELL_PILLAR_AT)
    add(mount, max_edge=0.9)
    anchors["bell"] = list(hang)
    add(props_built.bench(BENCH_AT), max_edge=0.6)
    add(props_built.crate(CRATE_AT), max_edge=0.4)

    # ---- animated: the machine and the bell ---------------------------------------------------------------
    dyn = []
    machine_root = empty("Machine", coll, location=MACHINE_AT)
    for name, (part, loc, rot) in props_built.machine_parts().items():
        obj = part.build(coll, mats, max_edge=0.7 if name == "Base" else None, parent=machine_root, location=loc, rotation=rot)
        obj.name = name
        dyn.append(obj)
    bell_obj = bell_part.build(coll, mats, max_edge=None, location=hang, rotation=(0, 0, 0))
    bell_obj.name = "Bell"
    dyn.append(bell_obj)

    # ---- foreground frame: authored in camera space, baked where the camera really is -------------------------
    cam_pos = Vector(CAMERA_FROM)
    forward = (Vector(CAMERA_AT) - cam_pos).normalized()
    right = forward.cross(Vector((0, 1, 0))).normalized()
    up = right.cross(forward).normalized()
    from mathutils import Matrix
    cam_m = Matrix(((right.x, up.x, -forward.x, cam_pos.x), (right.y, up.y, -forward.y, cam_pos.y), (right.z, up.z, -forward.z, cam_pos.z), (0, 0, 0, 1)))
    rig = empty("ForegroundRig", coll)
    rig.matrix_basis = common.TO_BL @ cam_m @ common.TO_GD
    fg_objects = []
    for group_name, parts in (("FgLeft", props_hall.foreground_left()), ("FgRight", props_hall.foreground_right())):
        members = []
        for part, loc in parts:
            members.append(part.build(coll, mats, max_edge=None, parent=rig, location=loc, rotation=(0, 0, 0)))
        bpy.ops.object.select_all(action="DESELECT")
        for o in members:
            o.select_set(True)
        bpy.context.view_layer.objects.active = members[0]
        bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = group_name
        # the frame receives the hall's shade but must not throw shadows into the hall
        joined.visible_shadow = False
        fg_objects.append(joined)

    # ---- bake-only: close the hall behind the camera so light and bounce behave --------------------------------
    closer = Part("Closer")
    for i in range(-12, 12):
        for j in range(0, 16):
            x0, x1 = i * 0.8, (i + 1) * 0.8
            y0, y1 = j * 1.0, (j + 1) * 1.0
            if abs((x0 + x1) / 2) > props_hall.half_w((y0 + y1) / 2) + 0.2:
                continue
            closer.quad_out((x0, y0, 14.0), (x1, y0, 14.0), (x1, y1, 14.0), (x0, y1, 14.0), "rock_b", (0, 5, 0))
    closer_obj = closer.build(coll, mats)

    for o in static:
        for m in o.data.materials:
            pass
    print("%-14s %s" % ("object", "tris"))
    total = 0
    for o in static + dyn:
        n = sum(len(p.vertices) - 2 for p in o.data.polygons)
        total += n
    print("tris before bake:", total, "corners:", sum(len(o.data.loops) for o in static + dyn))

    if os.environ.get("DEBUG_RAY"):
        dg = bpy.context.evaluated_depsgraph_get()
        origin = common.TO_BL @ (POOL + Vector((0, 0.05, 0)))
        direction = common.TO_BL.to_3x3() @ SUN_DIR
        hit, loc, nor, idx, obj, mat = scene.ray_cast(dg, origin, direction)
        print("DEBUG ray from pool along sun hits:", obj.name if hit else None, (common.TO_GD @ loc) if hit else None)
        for (x, z) in ((-5, 3), (4, 3), (0, 6), (-3, -2), (3, -2), (0.5, 0.5), (1.5, -0.5)):
            o2 = common.TO_BL @ Vector((x, 0.05, z))
            h2, l2, n2, i2, ob2, m2 = scene.ray_cast(dg, o2, direction)
            print("DEBUG ray from", (x, z), "->", ob2.name if h2 else None, (common.TO_GD @ l2).to_tuple(1) if h2 else None)
    # ---- light --------------------------------------------------------------------------------------------
    bake.setup_world(scene, strength=0.9)
    bake.add_sun(scene, "Key", tuple(SUN_DIR), (1.0, 0.70, 0.36), 7.0, 1.2)
    all_bake = static + dyn + fg_objects
    if do_bake:
        t1 = time.time()
        bake.bake_lighting(all_bake, samples)
        print("bake %.1fs" % (time.time() - t1))
        floor_obj = next(o for o in static if o.name.startswith("Floor"))
        g = floor_obj.data
        gv = np.zeros(len(g.loops), dtype=np.int32)
        g.loops.foreach_get("vertex_index", gv)
        gco = np.zeros(len(g.vertices) * 3, dtype=np.float32)
        g.vertices.foreach_get("co", gco)
        gco = gco.reshape(-1, 3)[gv]
        gcol = bake.read_corner_colours(floor_obj)[:, :3]
        core = np.hypot(gco[:, 0] - POOL.x, -gco[:, 1] - POOL.z) < 0.9
        w = np.array([0.3, 0.55, 0.15])
        core_luma = float((gcol[core] @ w).mean())
        fl = gcol @ w
        top = np.argsort(fl)[-40:]
        print("floor luma pct", np.percentile(fl, [50, 90, 99, 99.9]).round(3), "brightest corners at (x,z):", np.round(np.stack([gco[top, 0], -gco[top, 1]], 1).mean(axis=0), 2), "n>0.5:", int((fl > 0.5).sum()))
        print("shaft core luma %.3f (n=%d); floor median %.3f" % (core_luma, int(core.sum()), float(np.median(gcol @ w))))
        for o in all_bake:
            big = o.name.startswith(("Floor", "Shell", "BackWall", "Corridor", "Mural"))
            bake.smooth_light(o, radius=0.65 if big else 0.22)
        gcol = bake.read_corner_colours(floor_obj)[:, :3]
        gain = 1.0 / max(float(np.percentile(gcol @ w, 98.0)), 1e-4)
        print("exposure: floor p98 -> gain %.2f" % gain)
    else:
        gain = 1.0
        for o in all_bake:
            arr = bake.read_corner_colours(o)
            arr[:, :3] = 0.5
            bake.write_corner_colours(o, arr)

    for o in all_bake:
        bake.normalise(o, gain, None, lift=AMBIENT_LIFT)
        bake.facet_tone(o, strength=0.05, hue=0.02, seed=len(o.name))
        if os.environ.get('STATS'):
            c = bake.read_corner_colours(o)
            print('STAT %-12s mean %s max %.2f nan %d' % (o.name, c[:, :3].mean(axis=0).round(3), c[:, :3].max(), int(np.isnan(c).sum())))

    # ---- light map for actors: top-down sun/shade of the floor -----------------------------------------------
    floor_obj = next(o for o in static if o.name.startswith("Floor"))
    me = floor_obj.data
    vi = np.zeros(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    co = np.zeros(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    cols = bake.read_corner_colours(floor_obj)[:, :3]
    lm_x0, lm_x1, lm_z0, lm_z1, res = -10.0, 10.0, -11.0, 13.0, 96
    acc = np.zeros((res, res, 3), dtype=np.float32)
    cnt = np.zeros((res, res), dtype=np.float32)
    for k in range(len(vi)):
        gx, gz = co[vi[k], 0], -co[vi[k], 1]
        ix = int((gx - lm_x0) / (lm_x1 - lm_x0) * res)
        iz = int((gz - lm_z0) / (lm_z1 - lm_z0) * res)
        if 0 <= ix < res and 0 <= iz < res:
            acc[iz, ix] += cols[k]
            cnt[iz, ix] += 1
    lm = np.where(cnt[..., None] > 0, acc / np.maximum(cnt[..., None], 1), 0.0)
    mask = cnt > 0
    for _ in range(12):
        pad = np.pad(lm, ((1, 1), (1, 1), (0, 0)), mode="edge")
        pm = np.pad(mask.astype(np.float32), 1)
        s = sum(pad[1 + dy:1 + dy + res, 1 + dx:1 + dx + res] * pm[1 + dy:1 + dy + res, 1 + dx:1 + dx + res][..., None] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        n = sum(pm[1 + dy:1 + dy + res, 1 + dx:1 + dx + res] for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        fill = (n > 0) & ~mask
        lm[fill] = (s[fill] / n[fill][:, None])
        mask |= fill
    from PIL import Image
    os.makedirs(out_dir, exist_ok=True)
    Image.fromarray((np.clip(lm / 1.4, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(out_dir, "light_map.png"))
    luma = lm.reshape(-1, 3) @ np.array([0.3, 0.55, 0.15])
    anchors["light_map"] = {"x0": lm_x0, "x1": lm_x1, "z0": lm_z0, "z1": lm_z1, "scale": 1.4,
                            "lit_range": [float(np.percentile(luma, 8)), float(np.percentile(luma, 97))]}
    anchors["pool"] = list(POOL)
    anchors["sun_dir"] = list(SUN_DIR)

    # ---- export -------------------------------------------------------------------------------------------------
    bpy.data.objects.remove(closer_obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in static:
        o.select_set(True)
    bpy.context.view_layer.objects.active = static[0]
    bpy.ops.object.join()
    batch = bpy.context.view_layer.objects.active
    batch.name = "StaticSet"
    print("static tris:", sum(len(p.vertices) - 2 for p in batch.data.polygons), "materials:", len(batch.data.materials))
    textures.write_all(os.path.join(out_dir, "textures"))
    bake.export([batch] + dyn + fg_objects + [machine_root, rig], os.path.join(out_dir, "archive_set.glb"))
    with open(os.path.join(out_dir, "anchors.json"), "w") as f:
        json.dump(anchors, f, indent=1)
    print("done in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "assets", "archive"))
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument("--no-bake", action="store_true")
    a = ap.parse_args(argv)
    build(os.path.abspath(a.out), a.samples, not a.no_bake)
