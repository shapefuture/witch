"""STUB plates for the compositor, standing in for tools/blender/build_plates.py (Agent A's
producer) until the real ones land. It writes every file of docs/art/PLATE_CONTRACT.md, so the game
runs and the Godot side can be developed and tested against the contract.

    python tools/plates_stub/make_stub.py [--samples 8] [--out assets/archive] [--width 2048]

What it does (runs on the `bpy` module, numpy and PIL):
  * imports the existing vertex-colour set, assets/archive/archive_set.glb, and draws it EMISSION
    ONLY with the same arithmetic the old real-time set shader used (painted tile x baked vertex
    light x gain, a warm rim, the haze, the highlight shoulder), so the stub looks like the game did;
  * leaves out what Godot keeps drawing live: the machine, the bell, the camera-space frame;
  * renders the plates: `wide` (the bolted master shot), `inspect:machine` (one inspect pose) and
    two covers, `cover:magic` (the spell's low, tipped view) and `cover:conversation` (the two-shot
    side), plus a `dusk` variant of `wide`;
  * adds the beam and the floor glow analytically (the old shaft quad and pool glow, now baked);
  * writes beauty / beauty_m / depth / key / glow per plate, plates/shots.json, a decimated
    hall_proxy.glb and the layout keys of anchors.json, and the Godot .import settings the
    compositor relies on (depth/key/glow are imported as Images, never VRAM-compressed).

Shot plates are rendered with a little vertical OVERSCAN (OVERSCAN_ASPECT): the game adds the Dutch
roll at runtime and zooms just enough that the rolled frame stays inside the plate; with the
overscan, a 16:9 screen shows exactly the authored field of view. See docs/art/compositor.md.
"""
import argparse
import json
import math
import os
import sys
import time

import bpy  # noqa: I001  (bpy first: it makes bmesh and mathutils importable)
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

# Godot (x right, y up, -z forward) -> Blender (z up). Same as tools/blender/kit/common.py.
TO_BL = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

# ---- the old real-time set shader (render/psx/psx_set.gdshader + psx_materials.gd), mirrored --------
SET_GAIN = 1.05
GLOWING = {"glow": (1.0, 0.86, 0.5), "glow_warm": (1.0, 0.6, 0.26), "glow_green": (0.5, 1.0, 0.4), "glow_blue": (0.4, 0.65, 1.0), "glow_white": (0.78, 0.72, 0.56)}
SHINY = {"brass": 1.25, "gold": 1.3, "crystal": 1.1, "crystal_grey": 1.2, "iron": 1.1, "coral": 1.1}
CUTOUT = ["mural_eye"]
RIM = 0.16
FOG_COLOR = np.array([0.50, 0.44, 0.28], dtype=np.float32)
FOG_DENSITY = 0.016

# ---- layout: the numbers game/world/archive/archive_hall.gd used to hard-code ------------------------
ARCH_X = -4.2
MACHINE_AT = (-1.6, 0.0, -1.2)
BELL_POST_AT = (5.6, 0.0, -3.0)
TOMAS_AT = (0.7, 0.0, -0.9)
FRAMING = {"focus": [0.2, 3.3, -2.2], "distance": 11.0, "pitch_deg": -14.0, "yaw_deg": 24.0, "fov": 52.0, "roll_deg": 3.5}
NEAR, FAR = 0.1, 80.0
# The plate is overscanned so that this aspect, with the shot's roll, shows exactly the authored fov.
OVERSCAN_ASPECT = 16.0 / 9.0


def placement(look_at, distance, pitch_deg, yaw_deg):
    """CameraDirector.placement: yaw 0 puts the camera on +Z looking toward -Z; pitch > 0 is above."""
    p, y = math.radians(pitch_deg), math.radians(yaw_deg)
    return Vector(look_at) + Vector((math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p))) * distance


def looking_at(eye, target):
    """Godot's Basis.looking_at with up = +Y: columns x, y, z (the camera looks along -z). No roll."""
    z = (Vector(eye) - Vector(target)).normalized()
    x = Vector((0, 1, 0)).cross(z).normalized()
    y = z.cross(x).normalized()
    return x, y, z


def roll_fit(tan_half_v, plate_aspect, roll_deg, aspect):
    """Largest vertical half-tan of a screen of `aspect`, rolled by `roll_deg`, that stays inside a
    plate of half-tans (tan_half_v * plate_aspect, tan_half_v). Mirrors DioramaCamera.roll_fit."""
    c, s = abs(math.cos(math.radians(roll_deg))), abs(math.sin(math.radians(roll_deg)))
    return min(tan_half_v / (c + aspect * s), tan_half_v * plate_aspect / (aspect * c + s))


def compute_pose(mode, focus, framing):
    """CameraDirector.compute_pose for the modes the stub renders."""
    d, pitch, yaw, fov, roll = framing["distance"], framing["pitch_deg"], framing["yaw_deg"], framing["fov"], framing["roll_deg"]
    if mode == "inspect":
        return Vector(focus) + Vector((0, 1.1, 0)), d * 0.44, pitch - 3.0, yaw, fov - 8.0, roll - 1.5
    if mode == "conversation":
        return Vector(focus) + Vector((0, 1.0, 0)), d * 0.46, pitch - 3.0, yaw + 16.0, fov - 10.0, roll + 2.2
    if mode == "magic_reveal":
        return Vector(focus) + Vector((0, 1.2, 0)), d * 0.8, pitch - 11.0, yaw, fov + 8.0, roll - 45.0
    return Vector(framing["focus"]), d, pitch, yaw, fov, roll


def shot_spec(shot_id, mode, focus_ids, focus_point, role, size_hint, cover_fov=None):
    look_at, distance, pitch, yaw, fov, roll = compute_pose(mode, focus_point, FRAMING)
    eye = placement(look_at, distance, pitch, yaw)
    x, y, z = looking_at(eye, look_at)
    if role == "shot":
        w = size_hint
        h = int(round(w * 9.0 / 21.0))
        plate_aspect = w / h
        # overscan: the plate's vertical fov such that the rolled OVERSCAN_ASPECT frame fits at `fov`
        t = math.tan(math.radians(fov) * 0.5)
        lo, hi = t, t * 2.0
        for _ in range(60):
            mid = (lo + hi) * 0.5
            if roll_fit(mid, plate_aspect, roll, OVERSCAN_ASPECT) >= t:
                hi = mid
            else:
                lo = mid
        fov_v = math.degrees(2.0 * math.atan(hi))
    else:
        w, h = size_hint, int(round(size_hint * 3 / 4))
        fov_v = cover_fov
    return {
        "id": shot_id, "mode": mode if role == "shot" else "", "focus": list(focus_ids) if role == "shot" else [],
        "position": [round(c, 6) for c in eye], "basis": [[round(c, 6) for c in x], [round(c, 6) for c in y], [round(c, 6) for c in z]],
        "fov_v_deg": round(fov_v, 4), "near": NEAR, "far": FAR, "size": [w, h], "role": role,
        "dir": shot_id.replace(":", "_"),
    }


# ---- scene --------------------------------------------------------------------------------------

def load_set(glb):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    static = bpy.data.objects["StaticSet"]
    keep = {static.name}
    for o in list(bpy.data.objects):
        if o.name not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    return static


def tile_names(obj):
    return [s.material.name.split(".")[0] if s.material else "" for s in obj.material_slots]


def node(tree, kind, **props):
    n = tree.nodes.new(kind)
    for k, v in props.items():
        setattr(n, k, v)
    return n


def build_materials(tiles, tex_dir):
    """Per tile, a BEAUTY material (what psx_set drew) and a DATA material (view depth, height and
    the glow flag in RGB; the surface normal in a second pass)."""
    images = {}
    out = {"beauty": {}, "data": {}, "normal": {}}
    for tile in tiles:
        path = os.path.join(tex_dir, tile + ".png")
        img = None
        if os.path.exists(path):
            img = images.get(tile) or bpy.data.images.load(path)
            img.colorspace_settings.name = "Non-Color"   # the Compatibility renderer samples tiles raw
            images[tile] = img
        for kind in ("beauty", "data", "normal"):
            mat = bpy.data.materials.new("%s_%s" % (kind, tile))
            mat.use_nodes = True
            t = mat.node_tree
            t.nodes.clear()
            outn = node(t, "ShaderNodeOutputMaterial")
            emit = node(t, "ShaderNodeEmission")
            tex = node(t, "ShaderNodeTexImage", interpolation="Closest") if img is not None else None
            if tex is not None:
                tex.image = img
            if kind == "beauty":
                if tile in GLOWING:
                    emit.inputs["Color"].default_value = tuple(c * 1.15 for c in GLOWING[tile]) + (1.0,)
                else:
                    attr = node(t, "ShaderNodeVertexColor", layer_name="Color")
                    gain = SET_GAIN * SHINY[tile] / 1.5 if tile in SHINY else SET_GAIN
                    lit = node(t, "ShaderNodeVectorMath", operation="MULTIPLY")
                    t.links.new(attr.outputs["Color"], lit.inputs[0])
                    if tex is not None:
                        t.links.new(tex.outputs["Color"], lit.inputs[1])
                    else:
                        lit.inputs[1].default_value = (1, 1, 1)
                    scaled = node(t, "ShaderNodeVectorMath", operation="SCALE")
                    t.links.new(lit.outputs[0], scaled.inputs[0])
                    scaled.inputs["Scale"].default_value = gain
                    # rim: warm * pow(1 - |N.V|, 3) * rim * (C.r + C.g) / 2
                    geo = node(t, "ShaderNodeNewGeometry")
                    dot = node(t, "ShaderNodeVectorMath", operation="DOT_PRODUCT")
                    t.links.new(geo.outputs["Normal"], dot.inputs[0])
                    t.links.new(geo.outputs["Incoming"], dot.inputs[1])
                    absn = node(t, "ShaderNodeMath", operation="ABSOLUTE")
                    t.links.new(dot.outputs["Value"], absn.inputs[0])
                    inv = node(t, "ShaderNodeMath", operation="SUBTRACT")
                    inv.inputs[0].default_value = 1.0
                    t.links.new(absn.outputs[0], inv.inputs[1])
                    pw = node(t, "ShaderNodeMath", operation="POWER")
                    t.links.new(inv.outputs[0], pw.inputs[0])
                    pw.inputs[1].default_value = 3.0
                    sep = node(t, "ShaderNodeSeparateColor")
                    t.links.new(attr.outputs["Color"], sep.inputs[0])
                    rg = node(t, "ShaderNodeMath", operation="ADD")
                    t.links.new(sep.outputs[0], rg.inputs[0])
                    t.links.new(sep.outputs[1], rg.inputs[1])
                    amt = node(t, "ShaderNodeMath", operation="MULTIPLY")
                    t.links.new(pw.outputs[0], amt.inputs[0])
                    t.links.new(rg.outputs[0], amt.inputs[1])
                    amt2 = node(t, "ShaderNodeMath", operation="MULTIPLY")
                    t.links.new(amt.outputs[0], amt2.inputs[0])
                    amt2.inputs[1].default_value = 0.0 if tile in CUTOUT else RIM * 0.5
                    rim = node(t, "ShaderNodeVectorMath", operation="SCALE")
                    rim.inputs[0].default_value = (1.0, 0.78, 0.45)
                    t.links.new(amt2.outputs[0], rim.inputs["Scale"])
                    total = node(t, "ShaderNodeVectorMath", operation="ADD")
                    t.links.new(scaled.outputs[0], total.inputs[0])
                    t.links.new(rim.outputs[0], total.inputs[1])
                    t.links.new(total.outputs[0], emit.inputs["Color"])
            elif kind == "data":
                cam = node(t, "ShaderNodeCameraData")
                geo = node(t, "ShaderNodeNewGeometry")
                sepp = node(t, "ShaderNodeSeparateXYZ")
                t.links.new(geo.outputs["Position"], sepp.inputs[0])
                comb = node(t, "ShaderNodeCombineXYZ")
                t.links.new(cam.outputs["View Z Depth"], comb.inputs[0])
                t.links.new(sepp.outputs[2], comb.inputs[1])     # Blender z = Godot y (height)
                comb.inputs[2].default_value = 1.0 if tile in GLOWING else 0.0
                t.links.new(comb.outputs[0], emit.inputs["Color"])
            else:
                geo = node(t, "ShaderNodeNewGeometry")
                t.links.new(geo.outputs["Normal"], emit.inputs["Color"])
            emit.inputs["Strength"].default_value = 1.0
            shader_out = emit.outputs[0]
            transp = node(t, "ShaderNodeBsdfTransparent")
            if tile in CUTOUT and tex is not None:
                gt = node(t, "ShaderNodeMath", operation="GREATER_THAN")
                t.links.new(tex.outputs["Alpha"], gt.inputs[0])
                gt.inputs[1].default_value = 0.5
                mix = node(t, "ShaderNodeMixShader")
                t.links.new(gt.outputs[0], mix.inputs[0])
                t.links.new(transp.outputs[0], mix.inputs[1])
                t.links.new(emit.outputs[0], mix.inputs[2])
                shader_out = mix.outputs[0]
            # back faces are culled, as in the game (the spell's low camera looks up through the floor)
            back = node(t, "ShaderNodeNewGeometry")
            cull = node(t, "ShaderNodeMixShader")
            t.links.new(back.outputs["Backfacing"], cull.inputs[0])
            t.links.new(shader_out, cull.inputs[1])
            t.links.new(transp.outputs[0], cull.inputs[2])
            t.links.new(cull.outputs[0], outn.inputs["Surface"])
            out[kind][tile] = mat
    return out


def assign(obj, mats, kind, tiles):
    for slot, tile in zip(obj.material_slots, tiles):
        slot.material = mats[kind][tile]


def setup_render(scene, threads):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = False
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.max_bounces = 0
    scene.cycles.transparent_max_bounces = 16
    scene.cycles.seed = 7
    scene.render.film_transparent = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    scene.world = world


def place_camera(scene, spec):
    cam_data = bpy.data.cameras.new(spec["id"])
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(spec["fov_v_deg"])
    cam_data.clip_start = spec["near"]
    cam_data.clip_end = spec["far"]
    cam = bpy.data.objects.new("Cam_" + spec["dir"], cam_data)
    scene.collection.objects.link(cam)
    x, y, z = (Vector(c) for c in spec["basis"])
    p = Vector(spec["position"])
    m = Matrix(((x.x, y.x, z.x, p.x), (x.y, y.y, z.y, p.y), (x.z, y.z, z.z, p.z), (0, 0, 0, 1)))
    cam.matrix_world = TO_BL @ m   # camera-local axes follow the same convention in both programs
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = spec["size"]
    return cam


def render_exr(scene, path, samples, filter_width):
    scene.cycles.samples = samples
    scene.cycles.filter_width = filter_width
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    w, h = img.size
    arr = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    bpy.data.images.remove(img)
    return arr.reshape(h, w, 4)[::-1].copy()   # top row first, like the PNG


# ---- per-pixel geometry -------------------------------------------------------------------------

def pixel_rays(spec):
    """World-space (Godot) unit ray per pixel centre and the camera-space z of that ray (for planar
    depth -> distance). Same convention as PlateSet.project in the game."""
    w, h = spec["size"]
    tv = math.tan(math.radians(spec["fov_v_deg"]) * 0.5)
    th = tv * w / h
    xs = ((np.arange(w) + 0.5) / w) * 2.0 - 1.0
    ys = 1.0 - ((np.arange(h) + 0.5) / h) * 2.0
    gx, gy = np.meshgrid(xs * th, ys * tv)
    local = np.stack([gx, gy, -np.ones_like(gx)], axis=-1)    # camera space, at planar depth 1
    basis = np.array(spec["basis"], dtype=np.float64).T      # columns x, y, z
    world = local @ basis.T
    return world  # ray direction scaled so that planar depth 1 <=> this vector


def shoulder(col):
    return col / (1.0 + np.maximum(col - 0.55, 0.0) * 0.9)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def beam_and_glow(spec, rays, depth, anchors):
    """The light the old HallAtmosphere drew live: the shaft prism (render/psx/shaft.gdshader) and
    the floor glow (pool_glow.gdshader). Additive; both are now part of the plate."""
    eye = np.array(spec["position"])
    sun = np.array(anchors["sun_dir"], dtype=np.float64)
    sun /= np.linalg.norm(sun)
    pool = np.array(anchors["pool"], dtype=np.float64)
    oculus = np.array(anchors["oculus"], dtype=np.float64)
    seg = pool - oculus
    seg_len = np.linalg.norm(seg)
    axis = seg / seg_len
    ray_len = np.linalg.norm(rays, axis=-1)
    d = rays / ray_len[..., None]
    dist = np.where(np.isfinite(depth), depth * ray_len, np.inf)   # radial distance to the set
    # closest approach between each ray and the axis line
    w0 = eye - oculus
    b = d @ axis
    dd = d @ w0
    e = w0 @ axis
    denom = np.maximum(1.0 - b * b, 1e-6)
    s = (b * e - dd) / denom
    t = (e + b * s) / seg_len          # 0 at the hole, 1 on the floor
    gap = np.linalg.norm(eye + d * s[..., None] - (oculus + axis * (t * seg_len)[..., None]), axis=-1)
    radius = 1.7 * (0.85 + 0.4 * np.clip(t, 0, 1))
    inside = gap < radius
    sin_t = np.sqrt(denom)
    half = np.sqrt(np.maximum(radius ** 2 - gap ** 2, 0.0)) / np.maximum(sin_t, 1e-3)
    s_in = s - half
    facing = np.sqrt(np.maximum(1.0 - (gap / radius) ** 2, 0.0)) * sin_t
    body = smoothstep(0.04, 0.3, facing)
    v = np.clip(t, 0, 1)
    along = smoothstep(0.0, 0.06, v) * (1.0 + (0.55 - 1.0) * smoothstep(0.1, 0.9, v)) * (1.0 - smoothstep(0.78, 1.0, v))
    visible = inside & (s_in > 0.0) & (s_in < dist) & (t > 0.0) & (t < 1.0)
    shaft = np.where(visible, 0.34 * body * along * (1.0 - 0.3 * 0.28 * 0.5), 0.0)
    shaft_rgb = shaft[..., None] * np.array([1.0, 0.88, 0.56])
    # floor glow: a 7.2 x 5.2 ellipse at y = 0.04, its long axis turned toward the sun
    rot = math.atan2(-sun[0], -sun[2])
    lx = np.array([math.cos(rot), 0.0, -math.sin(rot)])
    lz = np.array([math.sin(rot), 0.0, math.cos(rot)])
    plane_y = 0.04
    sy = np.where(np.abs(d[..., 1]) > 1e-6, (plane_y - eye[1]) / np.where(np.abs(d[..., 1]) > 1e-6, d[..., 1], 1.0), -1.0)
    hit = eye + d * sy[..., None]
    rel = hit - np.array([pool[0], plane_y, pool[2]])
    u = (rel @ lx) / 3.6
    w_ = (rel @ lz) / 2.6
    r = np.sqrt(u * u + w_ * w_)
    a = smoothstep(1.0, 0.05, r)
    on_floor = (sy > 0.0) & (sy < dist + 0.08)
    glow = np.where(on_floor, 0.5 * a * a * 0.96, 0.0)
    glow_rgb = glow[..., None] * np.array([1.0, 0.86, 0.52])
    return shaft_rgb, glow_rgb


def in_beam(points, normals, anchors):
    """How much of a surface point's baked light came from the sun: inside the beam's cylinder and
    facing the sun. A stub's estimate of key.png."""
    sun = np.array(anchors["sun_dir"], dtype=np.float64)
    sun /= np.linalg.norm(sun)
    pool = np.array(anchors["pool"], dtype=np.float64)
    rel = points - pool
    along = rel @ sun
    radial = np.linalg.norm(rel - along[..., None] * sun, axis=-1)
    cyl = 1.0 - smoothstep(1.2, 2.5, radial)
    facing = np.clip((normals @ sun) * 1.6, 0.0, 1.0)
    return cyl * facing


def encode_depth(depth, near, far):
    v = np.clip((np.where(np.isfinite(depth), depth, far) - near) / (far - near), 0.0, 1.0)
    q = np.floor(v * 65535.0).astype(np.int64)
    q = np.minimum(q, 65535)
    out = np.zeros(depth.shape + (3,), dtype=np.uint8)
    out[..., 0] = (q >> 8).astype(np.uint8)
    out[..., 1] = (q & 255).astype(np.uint8)
    return out


def to_u8(x):
    return (np.clip(x, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def render_plate(scene, static, mats, tiles, spec, samples, scratch, anchors):
    t0 = time.time()
    place_camera(scene, spec)
    assign(static, mats, "beauty", tiles)
    beauty = render_exr(scene, os.path.join(scratch, spec["dir"] + "_beauty.exr"), samples, 1.5)
    assign(static, mats, "data", tiles)
    data = render_exr(scene, os.path.join(scratch, spec["dir"] + "_data.exr"), 1, 0.01)
    assign(static, mats, "normal", tiles)
    normal = render_exr(scene, os.path.join(scratch, spec["dir"] + "_normal.exr"), 1, 0.01)
    covered = data[..., 3] > 0.5
    depth = np.where(covered, data[..., 0], np.inf)
    height = data[..., 1]
    glow_flag = np.where(covered, data[..., 2], 0.0)
    n_bl = normal[..., :3]
    n_gd = np.stack([n_bl[..., 0], n_bl[..., 2], -n_bl[..., 1]], axis=-1)
    rays = pixel_rays(spec)
    eye = np.array(spec["position"])
    points = eye + rays * np.where(covered, depth, 0.0)[..., None]
    dist = np.where(covered, depth * np.linalg.norm(rays, axis=-1), 0.0)
    # the old fragment shader: tile x light (+ rim) -> haze -> shoulder
    alpha = np.clip(beauty[..., 3:4], 1e-4, 1.0)
    col = np.where(beauty[..., 3:4] > 1e-4, beauty[..., :3] / alpha, 0.0)
    fog_amount = np.where(glow_flag > 0.5, 0.5, 1.0)
    haze = (1.0 - np.exp(-FOG_DENSITY * dist)) * np.exp(-np.maximum(height, 0.0) * 0.035) * fog_amount
    haze = np.clip(haze, 0.0, 0.9)[..., None]
    col = col * (1.0 - haze) + FOG_COLOR * haze
    col = shoulder(col)
    shaft, floor_glow = beam_and_glow(spec, rays, depth, anchors)
    surface_key = in_beam(points, n_gd, anchors) * 0.72 * covered
    base = col
    col = col + shaft + floor_glow
    luma_w = np.array([0.299, 0.587, 0.114])
    total = np.maximum(col @ luma_w, 1e-4)
    key = np.clip(((base @ luma_w) * surface_key + (shaft + floor_glow) @ luma_w) / total, 0.0, 1.0)
    # background (only the oculus' sky): the fog colour, at the far plane
    col = np.where(covered[..., None] | (shaft[..., :1] > 0), col, FOG_COLOR)
    glow = np.clip(glow_flag, 0.0, 1.0)
    print("plate %-16s %dx%d  %.1fs  covered %.3f  key>0.5 %.3f  glow %.4f" % (spec["id"], spec["size"][0], spec["size"][1], time.time() - t0, covered.mean(), (key > 0.5).mean(), glow.mean()))
    return {"beauty": col, "depth": depth, "key": key, "glow": glow, "covered": covered, "points": points}


def write_plate(out_dir, spec, plate, mobile_width, with_depth=True):
    d = os.path.join(out_dir, "plates", spec["dir"])
    os.makedirs(d, exist_ok=True)
    beauty = Image.fromarray(to_u8(plate["beauty"]), "RGB")
    beauty.save(os.path.join(d, "beauty.png"), optimize=True)
    w, h = spec["size"]
    if spec["role"] == "shot" and w > mobile_width:
        beauty.resize((mobile_width, int(round(h * mobile_width / w))), Image.LANCZOS).save(os.path.join(d, "beauty_m.png"), optimize=True)
    if with_depth:
        Image.fromarray(encode_depth(plate["depth"], spec["near"], spec["far"]), "RGB").save(os.path.join(d, "depth.png"), optimize=True)
    Image.fromarray(to_u8(plate["key"]), "L").save(os.path.join(d, "key.png"), optimize=True)
    Image.fromarray(to_u8(plate["glow"]), "L").save(os.path.join(d, "glow.png"), optimize=True)
    write_imports(d, spec, with_depth)


TEXTURE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=1
process/fix_alpha_border=false
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=0
"""

IMAGE_IMPORT = """[remap]

importer="image"
type="Image"

[params]

"""


def write_imports(d, spec, with_depth):
    """The import settings the compositor relies on. Godot keeps a file's existing .import params
    when the file is replaced, so Agent A's plates inherit these."""
    names = {"beauty.png": TEXTURE_IMPORT, "key.png": IMAGE_IMPORT, "glow.png": IMAGE_IMPORT}
    if with_depth:
        names["depth.png"] = IMAGE_IMPORT
    if os.path.exists(os.path.join(d, "beauty_m.png")):
        names["beauty_m.png"] = TEXTURE_IMPORT
    for name, text in names.items():
        path = os.path.join(d, name + ".import")
        if os.path.exists(path):
            with open(path) as f:
                old = f.read()
            if ('importer="%s"' % ("image" if text is IMAGE_IMPORT else "texture")) in old:
                continue   # keep Godot's completed file (uid, dest paths) when the importer is right
        with open(path, "w") as f:
            f.write(text)


def dusk(plate):
    """A late-afternoon variant of a plate: the sun almost gone, the lamps the main light."""
    key, glow = plate["key"], plate["glow"]
    sun_left = 0.22
    light = (1.0 - key + key * sun_left)
    beauty = plate["beauty"] * light[..., None] * np.array([0.92, 0.80, 0.98]) * (1.0 + glow * 0.6)[..., None]
    beauty = beauty * 0.9 + np.array([0.02, 0.012, 0.035])
    new_key = np.clip(key * sun_left / np.maximum(light, 1e-3), 0.0, 1.0)
    return {"beauty": beauty, "depth": plate["depth"], "key": new_key, "glow": glow, "covered": plate["covered"]}


# ---- the proxy ----------------------------------------------------------------------------------

def build_proxy(static, tiles, tex_dir, target_tris, out_path):
    """The set merged into one welded mesh, decimated, coloured with a dim baked fallback."""
    tile_mean = {}
    for tile in tiles:
        path = os.path.join(tex_dir, tile + ".png")
        if tile in GLOWING:
            tile_mean[tile] = np.array(GLOWING[tile]) * 1.15
        elif os.path.exists(path):
            tile_mean[tile] = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32).reshape(-1, 3).mean(axis=0) / 255.0
        else:
            tile_mean[tile] = np.ones(3)
    me = static.data.copy()
    proxy = bpy.data.objects.new("HallProxy", me)
    bpy.context.scene.collection.objects.link(proxy)
    attr = me.color_attributes["Color"]
    cols = np.zeros(len(attr.data) * 4, dtype=np.float32)
    attr.data.foreach_get("color", cols)
    cols = cols.reshape(-1, 4)
    loop_mat = np.zeros(len(me.loops), dtype=np.int32)
    for poly in me.polygons:
        loop_mat[poly.loop_start:poly.loop_start + poly.loop_total] = poly.material_index
    means = np.stack([tile_mean[t] for t in tiles])
    gains = np.array([SET_GAIN * SHINY[t] / 1.5 if t in SHINY else SET_GAIN for t in tiles])
    glowing = np.array([t in GLOWING for t in tiles])
    fallback = np.where(glowing[loop_mat][:, None], means[loop_mat], cols[:, :3] * means[loop_mat] * gains[loop_mat][:, None])
    fallback = shoulder(fallback) * 0.72   # dim on purpose: a hole in the plates should read as shade
    cols[:, :3] = fallback
    cols[:, 3] = 1.0
    attr.data.foreach_set("color", cols.reshape(-1))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.002)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    tris = len(me.polygons)
    if tris > target_tris:
        mod = proxy.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = target_tris / tris * 0.97
        mod.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        evaluated = proxy.evaluated_get(dg)
        new_me = bpy.data.meshes.new_from_object(evaluated)
        proxy.modifiers.clear()
        proxy.data = new_me
    me = proxy.data
    me.materials.clear()
    mat = bpy.data.materials.new("proxy")
    me.materials.append(mat)
    for poly in me.polygons:
        poly.material_index = 0
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("proxy: %d triangles (from %d)" % (tris, sum(len(p.vertices) - 2 for p in static.data.polygons)))
    bpy.ops.object.select_all(action="DESELECT")
    proxy.select_set(True)
    bpy.context.view_layer.objects.active = proxy
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_apply=False,
                              export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True,
                              export_materials="PLACEHOLDER", export_normals=False, export_texcoords=False,
                              export_cameras=False, export_lights=False, export_extras=False, export_yup=True)
    return proxy, tris


def proxy_error(static, proxy):
    """How far the proxy strays from the set (the depth-test bias must cover it)."""
    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(proxy, dg)
    me = static.data
    rng = np.random.default_rng(3)
    polys = list(me.polygons)
    picks = rng.choice(len(polys), size=min(4000, len(polys)), replace=False)
    errs = []
    for i in picks:
        p = polys[i]
        loc, _, _, dist = tree.find_nearest(p.center)
        if loc is not None:
            errs.append(dist)
    errs = np.array(errs)
    print("proxy deviation from the set: median %.3f m, p95 %.3f m, max %.3f m" % (np.median(errs), np.percentile(errs, 95), errs.max()))


# ---- anchors -------------------------------------------------------------------------------------

def walkable_polygon():
    """The floor the witch may stand on: the open floor, trimmed so the bolted wide shot sees her at
    4:3, plus the way out under the arch. (Was ArchiveHall.stage_allows.)"""
    pts = [(0.55, 4.3)]
    for z in np.linspace(4.3, -0.6, 6)[1:]:
        pts.append((-4.4 + (z - 1.0) * 1.5, z))
    r = 8.6
    pts.append((-6.8, -math.sqrt(r * r - 6.8 * 6.8)))
    for x in np.linspace(-6.8, ARCH_X - 1.5, 4)[1:]:
        pts.append((x, -math.sqrt(r * r - x * x)))
    pts += [(ARCH_X - 1.5, -10.4), (ARCH_X + 1.5, -10.4)]
    x0 = ARCH_X + 1.5
    for x in np.linspace(x0, 6.4, 9):
        pts.append((x, -math.sqrt(r * r - x * x)))
    pts.append((6.4, -3.0))
    pts.append((0.56, 4.3))
    out = []
    for p in pts:
        q = [round(float(p[0]), 3), round(float(p[1]), 3)]
        if not out or out[-1] != q:
            out.append(q)
    return out


def layout_anchors(anchors):
    pool = Vector(anchors.get("pool", (1.0, 0.0, -0.2)))
    sun = Vector(anchors.get("sun_dir", (0.1, 0.84, -0.53))).normalized()
    beam_at = pool + sun * 1.5
    beam_to = pool + sun * 12.0
    anchors.update({
        "camera_wide": "wide",
        "framing": FRAMING,
        "spawn": [1.0, 0.0, 0.3],
        "tomas_at": list(TOMAS_AT),
        "tomas_yaw_deg": 12.0,
        "interactables": {
            "machine": {"at": list(MACHINE_AT), "radius": 1.7, "height": 0.8, "approach": [-0.7, 0.0, 0.5]},
            "bell": {"at": [BELL_POST_AT[0] - 1.3, 2.25, BELL_POST_AT[2]], "radius": 0.8, "height": 0.0, "approach": [BELL_POST_AT[0] - 1.3, 0.0, BELL_POST_AT[2] + 1.6]},
            "path_out": {"at": [ARCH_X, 0.0, -9.4], "radius": 2.6, "height": 3.2, "approach": [ARCH_X + 0.6, 0.0, -6.4]},
        },
        "walkable": walkable_polygon(),
        "obstacles": [
            {"at": [MACHINE_AT[0], MACHINE_AT[2]], "radius": 1.25, "height": 1.5},
            {"at": [BELL_POST_AT[0], BELL_POST_AT[2]], "radius": 0.95, "height": 3.0},
            {"at": [-6.2, -5.4], "radius": 1.7, "height": 2.4},
            {"at": [5.4, -8.0], "radius": 1.3, "height": 3.0},
            {"at": [-6.4, -7.7], "radius": 1.3, "height": 3.0},
            {"at": [2.6, -3.0], "radius": 1.3, "height": 3.0},
            {"at": [2.4, -0.4], "radius": 0.5, "height": 0.6},
            {"at": [-3.2, -2.6], "radius": 1.0, "height": 1.0},
        ],
        "hero_regions": [
            {"at": [round(pool.x, 4), 0.0, round(pool.z, 4)], "radius": 2.0, "height": 0.3},
            {"at": [round(c, 4) for c in beam_at], "to": [round(c, 4) for c in beam_to], "radius": 1.4, "height": 0.0},
            {"at": [ARCH_X, 0.0, -9.4], "radius": 2.2, "height": 5.0},
            {"at": [2.6, 0.0, -3.0], "radius": 0.7, "height": 3.0},
        ],
    })
    return anchors


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "archive"))
    ap.add_argument("--samples", type=int, default=8)
    ap.add_argument("--width", type=int, default=2048)
    ap.add_argument("--mobile-width", type=int, default=1280)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--proxy-tris", type=int, default=19000)
    ap.add_argument("--scratch", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "plates_stub"))
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    os.makedirs(a.scratch, exist_ok=True)
    t0 = time.time()
    with open(os.path.join(out, "anchors.json")) as f:
        anchors = json.load(f)
    anchors = layout_anchors(anchors)

    static = load_set(os.path.join(out, "archive_set.glb"))
    tiles = tile_names(static)
    mats = build_materials(sorted(set(tiles)), os.path.join(out, "textures"))
    scene = bpy.context.scene
    setup_render(scene, a.threads)

    machine_focus = Vector(MACHINE_AT) + Vector((0, 0.8, 0))
    specs = [
        shot_spec("wide", "wide", [], None, "shot", a.width),
        shot_spec("inspect:machine", "inspect", ["machine"], machine_focus, "shot", a.width),
        shot_spec("cover:magic", "magic_reveal", [], machine_focus, "cover", 1024, cover_fov=96.0),
        # the two-shot between the witch at her start and Tomas braced (game: focus ["player", "tomas"])
        shot_spec("cover:conversation", "conversation", [], (Vector((1.0, 1.0, 0.3)) + Vector(TOMAS_AT) + Vector((0, 1.0, 0))) * 0.5, "cover", 1024, cover_fov=72.0),
    ]
    entries = []
    for spec in specs:
        plate = render_plate(scene, static, mats, tiles, spec, a.samples, a.scratch, anchors)
        write_plate(out, spec, plate, a.mobile_width)
        entries.append(spec)
        if spec["id"] == "wide":
            variant = dict(spec)
            variant["variant"] = "dusk"
            variant["dir"] = "wide_dusk"
            write_plate(out, variant, dusk(plate), a.mobile_width, with_depth=False)
            entries.append(variant)
            check_projection(spec, plate)

    with open(os.path.join(out, "plates", "shots.json"), "w") as f:
        json.dump({"version": 1, "stub": True, "shots": entries}, f, indent=1)
    proxy, tris = build_proxy(static, tiles, os.path.join(out, "textures"), a.proxy_tris, os.path.join(out, "hall_proxy.glb"))
    proxy_error(static, proxy)
    with open(os.path.join(out, "anchors.json"), "w") as f:
        json.dump(anchors, f, indent=1)
    print("stub plates done in %.1fs" % (time.time() - t0))


def check_projection(spec, plate):
    """Self-check of the shared projection convention: a pixel's own 3D point projects back onto it."""
    w, h = spec["size"]
    tv = math.tan(math.radians(spec["fov_v_deg"]) * 0.5)
    th = tv * w / h
    basis = np.array(spec["basis"], dtype=np.float64)
    eye = np.array(spec["position"])
    worst = 0.0
    for (px, py) in ((w // 2, h // 2), (w // 5, h // 3), (4 * w // 5, 2 * h // 3)):
        if not plate["covered"][py, px]:
            continue
        p = plate["points"][py, px]
        rel = p - eye
        cam = np.array([rel @ basis[0], rel @ basis[1], rel @ basis[2]])
        z = -cam[2]
        u = (cam[0] / (z * th)) * 0.5 + 0.5
        v = 0.5 - (cam[1] / (z * tv)) * 0.5
        worst = max(worst, abs(u * w - (px + 0.5)), abs(v * h - (py + 0.5)))
    print("projection round trip: worst %.4f px" % worst)
    assert worst < 0.01


if __name__ == "__main__":
    main()
