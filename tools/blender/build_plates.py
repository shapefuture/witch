"""Build the archive hall's pre-rendered plates (docs/art/PLATE_CONTRACT.md).

    python tools/blender/build_plates.py --out assets/archive [--quick] [--width 2048] [--samples 64]

Needs the `bpy` module (pip install bpy), numpy, scipy, scikit-image and Pillow. It builds the hall
(tools/blender/plates), renders it with Cycles from each shot, finishes every plate (tone, a
procedural matte-painting pass, a grade fitted to the reference when `--reference` is given, paper
grain) and writes, in assets/archive:

  plates/<shot>/{beauty,beauty_m,depth,key,glow}.png and plates/shots.json
  hall_proxy.glb          the low-poly set (actor occlusion and the surface the plates project onto)
  props/machine.glb, props/bell.glb   the live props, in world space
  anchors.json, light_map.png         the layout (spawn, interactables, walkable floor) and actor light

The shot poses come from the same arithmetic as game/camera/camera_director.gd, so what a plate
shows is what the game's camera sees. The shared writers (depth encoding, the Godot .import files,
the overscan that keeps a rolled frame inside the plate) live in tools/plates_stub/make_stub.py.
"""
import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "plates_stub"))
sys.path.insert(0, os.path.join(ROOT, "tools", "visual_gauntlet"))

import bpy  # noqa: E402,I001  (bpy first: it makes bmesh and mathutils importable)
import bmesh  # noqa: E402
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import make_stub as MS  # noqa: E402
from plates import geo, hall, layout as L, materials, post as P, render as R, scene as S, space  # noqa: E402

ROLL_DEG = 3.5          # the bolted camera's Dutch tilt, added at runtime (game/world/archive)
BELL_BRACKET_YAW = 0.0


def framing():
    f = L.WIDE_FRAMING
    return {"focus": [round(float(c), 5) for c in f["focus"]], "distance": float(f["distance"]), "pitch_deg": float(f["pitch_deg"]),
            "yaw_deg": float(f["yaw_deg"]), "fov": float(f["fov"]), "roll_deg": ROLL_DEG}


def shot_specs(width):
    MS.FRAMING = framing()
    machine_focus = Vector(L.MACHINE_AT) + Vector((0, 0.8, 0))
    bell_focus = Vector(L.BELL_HANG) + Vector((0, -0.4, 0))
    witch_tomas = (Vector(L.SPAWN) + Vector((0, 1.0, 0)) + Vector(L.TOMAS_AT) + Vector((0, 1.0, 0))) * 0.5
    return [
        MS.shot_spec("wide", "wide", [], None, "shot", width),
        MS.shot_spec("inspect:machine", "inspect", ["machine"], machine_focus, "shot", width),
        MS.shot_spec("inspect:bell", "inspect", ["bell"], bell_focus, "shot", width),
        MS.shot_spec("cover:conversation", "conversation", [], witch_tomas, "cover", 1024, cover_fov=72.0),
        MS.shot_spec("cover:magic", "magic_reveal", [], machine_focus, "cover", 1024, cover_fov=96.0),
    ]


def spec_cam(spec):
    return space.Cam(spec["position"], np.array(spec["basis"], dtype=np.float64).T, spec["fov_v_deg"], spec["size"], spec["near"], spec["far"])


def finish(res, spec, grade_ref, exposure, grade_strength, paint, shoulder=1.0):
    """Cycles passes -> the plate dict the writers expect."""
    near, far = spec["near"], spec["far"]
    z = np.where(res["z"] < far * 1.2, res["z"], np.inf).astype(np.float32)
    covered = np.isfinite(z)
    total = res["key"] + res["glow"] + res["fill"]
    key = P.share(res["key"], total)
    glow = P.share(res["glow"], total)
    expo = exposure if exposure else P.auto_exposure(res["rgb"])
    img = P.tone(res["rgb"], expo)
    img = P.paint_over(img, res["z"], key, glow, spec["fov_v_deg"], strength=paint)
    # the reference is a low-key picture (99th percentile luma 0.63 for a median of 0.16): the
    # beam and the lit passage must roll off instead of clipping to white
    luma = P.lum(img)
    img = img / (1.0 + np.maximum(luma - 0.5, 0.0) * shoulder)[..., None]
    if grade_ref is not None and grade_strength > 0:
        ref = np.asarray(grade_ref.resize((img.shape[1], img.shape[0]), Image.LANCZOS), np.float32) / 255.0
        img = P.apply_grade(img, P.fit_grade(img, ref, strength=grade_strength))
    img = P.paper(img, seed=7 + len(spec["id"]))
    return {"beauty": img, "depth": z, "key": key, "glow": glow, "covered": covered, "exposure": expo}


def world_points(spec, depth):
    """Godot-space point of every pixel (for the fallback colours and the projection self-check)."""
    cam = spec_cam(spec)
    w, h = spec["size"]
    tv = math.tan(math.radians(cam.fov_v) * 0.5)
    th = tv * w / h
    xs = ((np.arange(w) + 0.5) / w * 2 - 1) * th
    ys = (1 - (np.arange(h) + 0.5) / h * 2) * tv
    dirs = np.stack([np.broadcast_to(xs[None, :], (h, w)), np.broadcast_to(ys[:, None], (h, w)), -np.ones((h, w))], -1)
    rays = dirs @ cam.basis.T
    d = np.where(np.isfinite(depth), depth, 0.0)
    return cam.position + rays * d[..., None]


# ---- the proxy ----------------------------------------------------------------------------------

def build_proxy(static, wide_spec, wide_plate, target_tris, out_path):
    objs = []
    for o in static:
        if o.type != "MESH":
            continue
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.scene.collection.objects.link(c)
        objs.append(c)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    proxy = bpy.context.view_layer.objects.active
    proxy.name = "HallProxy"
    me = proxy.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.004)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    before = len(me.polygons)
    if before > target_tris:
        mod = proxy.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = target_tris / before * 0.97
        mod.use_collapse_triangulate = True
        ev = proxy.evaluated_get(bpy.context.evaluated_depsgraph_get())
        new_me = bpy.data.meshes.new_from_object(ev)
        proxy.modifiers.clear()
        proxy.data = new_me
        me = new_me
    me.materials.clear()
    me.materials.append(bpy.data.materials.new("proxy"))
    for p in me.polygons:
        p.material_index = 0
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("proxy: %d triangles (from %d)" % (tris, before))
    # the fallback colour: what the wide plate sees at each vertex, dimmed (a hole in the plates
    # should read as shade, not as a bright patch)
    n = len(me.vertices)
    co = np.zeros(n * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    bl = co.reshape(-1, 3)
    gd = np.stack([bl[:, 0], bl[:, 2], -bl[:, 1]], 1)
    cam = spec_cam(wide_spec)
    rel = gd - cam.position
    cx, cy, cz = rel @ cam.basis[:, 0], rel @ cam.basis[:, 1], -(rel @ cam.basis[:, 2])
    w, h = wide_spec["size"]
    tv = math.tan(math.radians(cam.fov_v) * 0.5)
    th = tv * w / h
    ok = cz > 0.2
    u = np.where(ok, (cx / np.maximum(cz, 1e-3) / th * 0.5 + 0.5) * w, -1)
    v = np.where(ok, (0.5 - cy / np.maximum(cz, 1e-3) / tv * 0.5) * h, -1)
    inside = ok & (u >= 0) & (u < w) & (v >= 0) & (v < h)
    ui, vi = np.clip(u.astype(int), 0, w - 1), np.clip(v.astype(int), 0, h - 1)
    seen = inside & (np.abs(wide_plate["depth"][vi, ui] - cz) < 0.25 + 0.03 * cz)
    img = wide_plate["beauty"]
    colour = np.where(seen[:, None], img[vi, ui], np.array([0.20, 0.17, 0.15], np.float32)) * 0.7
    attr = me.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    rgba = np.concatenate([colour.astype(np.float32), np.ones((n, 1), np.float32)], 1)
    attr.data.foreach_set("color", rgba.reshape(-1))
    me.color_attributes.active_color = attr
    bpy.ops.object.select_all(action="DESELECT")
    proxy.select_set(True)
    bpy.context.view_layer.objects.active = proxy
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_apply=False,
                              export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True,
                              export_materials="PLACEHOLDER", export_normals=False, export_texcoords=False,
                              export_cameras=False, export_lights=False, export_extras=False, export_yup=True)
    print("proxy: %.0f%% of vertices seen by the wide plate" % (100.0 * seen.mean()))
    return proxy, tris


# ---- the live props -----------------------------------------------------------------------------

GLTF_TILE = {"lamp_glow": "glow_warm", "flame": "glow_warm", "stair_glow": "glow_warm", "sky": "glow_white"}


def export_prop(root, objs, path):
    """One glTF per live prop, in world space. Materials become plain colours named after the
    painted tile (the game restyles them), or after a glowing tile."""
    swatches = materials.SWATCHES
    cache = {}
    made = []
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        c.parent = None
        c.matrix_world = o.matrix_world.copy()
        bpy.context.scene.collection.objects.link(c)
        c.visible_camera = True
        for i, slot in enumerate(c.data.materials):
            name = slot.name if slot else "iron"
            base = name.split(".")[0]
            tile = GLTF_TILE.get(base, base)
            if tile not in cache:
                m = bpy.data.materials.new(tile)
                m.use_nodes = True
                rgb = swatches.get(base, ((160, 150, 130),))[0]
                m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*materials.lin(rgb), 1.0)
                cache[tile] = m
            c.data.materials[i] = cache[tile]
        made.append(c)
    bpy.ops.object.select_all(action="DESELECT")
    for c in made:
        c.select_set(True)
    bpy.context.view_layer.objects.active = made[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_materials="EXPORT",
                              export_normals=True, export_texcoords=False, export_cameras=False, export_lights=False,
                              export_yup=True)
    for c in made:
        bpy.data.objects.remove(c, do_unlink=True)


# ---- layout and actor light ---------------------------------------------------------------------

def in_frame(cam, point, aspect=4.0 / 3.0, margin=0.07):
    """Is a Godot-space point inside the bolted frame on a 4:3 screen (the narrowest we support: the
    camera never follows, so the witch must be visible wherever she can stand)? The Dutch roll is
    covered by the margin."""
    rel = np.asarray(point, float) - cam.position
    x, y, z = rel @ cam.basis[:, 0], rel @ cam.basis[:, 1], -(rel @ cam.basis[:, 2])
    if z <= 0.2:
        return False
    tv = math.tan(math.radians(L.FOV_V) * 0.5)
    th = tv * aspect
    return abs(x / z) < th * (1 - margin) and abs(y / z) < tv * (1 - margin)


def walkable():
    """The floor the witch may stand on: the nave, trimmed so her whole figure (feet to hat) is in the
    bolted wide shot at 4:3, plus the way out under the arch."""
    cam = L.REF
    left0, right0 = L.NAVE_LEFT + 0.95, L.NAVE_RIGHT - 0.95
    back = L.ARCH_WALL_Z + 0.6
    ax = float(L.ARCH_X)
    end = hall.PASS_END_Z + 0.5
    zs = np.arange(4.0, back - 0.01, -0.25)
    left, right = [], []
    for z in zs:
        xs = np.arange(left0, right0 + 0.01, 0.1)
        ok = [x for x in xs if in_frame(cam, (x, 0.0, z)) and in_frame(cam, (x, 1.4, z))]
        if ok:
            left.append((min(ok), z))
            right.append((max(ok), z))
    pts = [right[0]] + [p for p in left] + [(ax - 1.1, back), (ax - 1.1, end), (ax + 1.1, end), (ax + 1.1, back)] + list(reversed(right))[:-1]
    out = []
    for x, z in pts:
        q = [round(float(x), 3), round(float(z), 3)]
        if not out or out[-1] != q:
            out.append(q)
    return out


def anchors_for(old):
    pool = np.array(L.POOL, float)
    sun = np.array(L.SUN_DIR, float)
    ax = float(L.ARCH_X)
    arch_z = float(L.ARCH_WALL_Z)
    hang = np.array(L.BELL_HANG, float)
    machine = np.array(L.MACHINE_AT, float)
    out = dict(old)
    out.update({
        "oculus": [round(float(c), 4) for c in L.OCULUS], "pool": [round(float(c), 4) for c in pool],
        "sun_dir": [round(float(c), 4) for c in sun],
        "raccoon_perch": [round(float(c), 4) for c in L.RACCOON_PERCH],
        "bell": [round(float(c), 4) for c in hang],
        "camera_wide": "wide", "framing": framing(),
        "spawn": [round(float(c), 4) for c in L.SPAWN],
        "tomas_at": [round(float(c), 4) for c in L.TOMAS_AT], "tomas_yaw_deg": float(L.TOMAS_YAW),
        "interactables": {
            "machine": {"at": [round(float(c), 4) for c in machine], "radius": 1.7, "height": 0.8,
                        "approach": [round(float(machine[0]) - 0.8, 3), 0.0, round(float(machine[2]) + 1.4, 3)]},
            "bell": {"at": [round(float(hang[0]) - 0.1, 3), 2.25, round(float(hang[2]), 3)], "radius": 0.8, "height": 0.0,
                     "approach": [round(float(hang[0]) - 0.8, 3), 0.0, round(float(hang[2]) + 0.5, 3)]},
            "path_out": {"at": [round(ax, 3), 0.0, round(arch_z - 1.2, 3)], "radius": 2.0, "height": 3.2,
                         "approach": [round(ax + 0.5, 3), 0.0, round(arch_z + 2.6, 3)]},
        },
        "walkable": walkable(),
        "obstacles": [
            {"at": [round(float(machine[0]), 3), round(float(machine[2]), 3)], "radius": 1.25, "height": 1.5},
            {"at": [round(float(L.TOWER_A_AT[0]), 3), round(float(L.TOWER_A_AT[2]), 3)], "radius": 1.3, "height": 3.0},
            {"at": [round(float(S.tower_b_at()[0]), 3), round(float(S.tower_b_at()[2]), 3)], "radius": 1.0, "height": 3.0},
            {"at": [round(float(L.STATUE_AT[0]), 3), round(float(L.STATUE_AT[2]), 3)], "radius": 0.9, "height": 3.0},
            {"at": [round(float(L.ORB_AT[0]), 3), round(float(L.ORB_AT[2]), 3)], "radius": 0.9, "height": 1.2},
        ],
        "hero_regions": [
            {"at": [round(float(pool[0]), 4), 0.0, round(float(pool[2]), 4)], "radius": 1.6, "height": 0.3},
            {"at": [round(float(c), 4) for c in pool + sun * 1.5], "to": [round(float(c), 4) for c in pool + sun * 12.0], "radius": 1.2, "height": 0.0},
            {"at": [round(ax, 3), 0.0, round(arch_z, 3)], "radius": 1.9, "height": 4.6},
            {"at": [round(float(L.STATUE_AT[0]), 3), 0.0, round(float(L.STATUE_AT[2]), 3)], "radius": 0.7, "height": 3.0},
        ],
    })
    return out


def light_map(anchors, path):
    """What the floor looks like from above, for the actors: shade (cool, dim) with the warm pool of
    the sun where the beam lands. Same rectangle and scale as the old baked map."""
    rect = anchors["light_map"]
    scale = float(rect["scale"])
    w = int(round((rect["x1"] - rect["x0"]) * scale * 6))
    h = int(round((rect["z1"] - rect["z0"]) * scale * 6))
    xs = rect["x0"] + (np.arange(w) + 0.5) / w * (rect["x1"] - rect["x0"])
    zs = rect["z0"] + (np.arange(h) + 0.5) / h * (rect["z1"] - rect["z0"])
    gx, gz = np.meshgrid(xs, zs)
    pool = np.array(L.POOL, float)
    sun = np.array(L.SUN_DIR, float)
    horiz = np.array([sun[0], sun[2]])
    el = math.asin(sun[1])
    horiz /= np.linalg.norm(horiz)
    # the beam's footprint: a circle stretched along the sun's azimuth
    r0 = hall.OCULUS_R + 10.4 * math.tan(math.radians(7.0))
    along = ((gx - pool[0]) * horiz[0] + (gz - pool[2]) * horiz[1]) / (r0 / math.sin(el))
    across = ((gx - pool[0]) * -horiz[1] + (gz - pool[2]) * horiz[0]) / r0
    d = np.sqrt(along ** 2 + across ** 2)
    pool_mask = 1.0 - np.clip((d - 0.75) / 0.5, 0, 1) ** 1.5
    # the shader multiplies by the map's scale (1.4): the pool must not blow the actors out. In the
    # reference the witch is a dark figure in the brightest place, rimmed with gold
    shade = np.array([0.22, 0.20, 0.26])
    lit = np.array([0.62, 0.52, 0.36])
    img = shade[None, None, :] * (1 - pool_mask[..., None]) + lit[None, None, :] * pool_mask[..., None]
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(path)
    luma = lambda c: float(c @ np.array([0.299, 0.587, 0.114]))
    rect["lit_range"] = [round(luma(shade), 4), round(luma(lit), 4)]


# ---- main ---------------------------------------------------------------------------------------

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "archive"))
    ap.add_argument("--width", type=int, default=2048)
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument("--quick", action="store_true", help="640 px wide, 12 samples: for iterating")
    ap.add_argument("--only", default="", help="comma separated shot ids to render")
    ap.add_argument("--reference", default="", help="a reference image to fit the grade to (never committed)")
    ap.add_argument("--grade", type=float, default=0.6)
    ap.add_argument("--paint", type=float, default=1.0)
    ap.add_argument("--shoulder", type=float, default=1.0)
    ap.add_argument("--exposure", type=float, default=0.0)
    ap.add_argument("--mobile-width", type=int, default=1280)
    ap.add_argument("--proxy-tris", type=int, default=19000)
    ap.add_argument("--no-dusk", action="store_true")
    ap.add_argument("--from-raw", action="store_true", help="re-finish plates from the Cycles passes saved in --scratch (no rendering)")
    ap.add_argument("--scratch", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "build_plates"))
    a = ap.parse_args(argv)
    if a.quick:
        a.width, a.samples = 640, 12
    out = os.path.abspath(a.out)
    os.makedirs(a.scratch, exist_ok=True)
    os.makedirs(os.path.join(out, "props"), exist_ok=True)
    t0 = time.time()
    grade_ref = Image.open(a.reference).convert("RGB") if a.reference else None
    with open(os.path.join(out, "anchors.json")) as f:
        old_anchors = json.load(f)

    h = S.build()
    specs = shot_specs(a.width)
    wanted = set(filter(None, a.only.split(",")))
    entries, wide = [], None
    exposure = a.exposure
    for spec in specs:
        if wanted and spec["id"] not in wanted:
            if spec["id"] == "wide":
                raise SystemExit("the wide plate is needed for the proxy; include it in --only")
            continue
        w, hh = spec["size"]
        cam = spec_cam(spec)
        raw = os.path.join(a.scratch, spec["dir"] + "_raw.npz")
        if a.from_raw and os.path.exists(raw):
            res = dict(np.load(raw))
            res["seconds"] = 0.0
        else:
            res = R.render(h.scene, cam, (w, hh), a.samples if spec["role"] == "shot" else max(24, a.samples // 2),
                           os.path.join(a.scratch, spec["dir"] + ".exr"), quick=a.quick)
            np.savez_compressed(raw, **{k: v for k, v in res.items() if k != "seconds"})
        plate = finish(res, spec, grade_ref, exposure, a.grade, a.paint, a.shoulder)
        if spec["id"] == "wide":
            exposure = plate["exposure"]     # the other shots share the wide's exposure
            wide = (spec, plate)
        MS.write_plate(out, spec, plate, a.mobile_width)
        entries.append(spec)
        print("plate %-20s %dx%d  %.0fs  exposure %.3f" % (spec["id"], w, hh, res["seconds"], plate["exposure"]))
        if spec["id"] == "wide" and not a.no_dusk:
            variant = dict(spec)
            variant["variant"] = "dusk"
            variant["dir"] = "wide_dusk"
            MS.write_plate(out, variant, MS.dusk(plate), a.mobile_width, with_depth=False)
            entries.append(variant)
    with open(os.path.join(out, "plates", "shots.json"), "w") as f:
        json.dump({"version": 1, "shots": entries}, f, indent=1)

    build_proxy(h.static, wide[0], wide[1], a.proxy_tris, os.path.join(out, "hall_proxy.glb"))
    export_prop(*h.machine, os.path.join(out, "props", "machine.glb"))
    export_prop(*h.bell, os.path.join(out, "props", "bell.glb"))
    anchors = anchors_for(old_anchors)
    light_map(anchors, os.path.join(out, "light_map.png"))
    with open(os.path.join(out, "anchors.json"), "w") as f:
        json.dump(anchors, f, indent=1)
    print("plates done in %.0fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
