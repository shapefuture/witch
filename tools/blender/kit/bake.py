"""Lighting rig, Cycles vertex bake, post-grade and glTF export (Blender side)."""
import math
import random

import bpy
import numpy as np
from mathutils import Vector

from . import common, textures


def make_materials(extra_glow=("glow", "glow_warm", "glow_green", "glow_blue", "glow_white")):
    """One Blender material per painted tile, with the tile's mean colour so light bounced between
    surfaces is tinted correctly during the bake (the baked surface's own albedo is excluded)."""
    mats = {}
    for name in textures.SPECS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        r, g, b = textures.mean_colour(name)
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value = 1.0
        mats[name] = m
    glow_colours = {"glow": (1.0, 0.82, 0.45), "glow_warm": (1.0, 0.55, 0.22), "glow_green": (0.45, 1.0, 0.35), "glow_blue": (0.3, 0.6, 1.0), "glow_white": (1.0, 0.93, 0.75)}
    for name in extra_glow:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        bsdf.inputs["Emission Color"].default_value = glow_colours[name] + (1.0,)
        bsdf.inputs["Emission Strength"].default_value = 1.2 if name == "glow_white" else 2.5
        mats[name] = m
    # Painted sheets that reuse a base tile's colour for bounce light but need their OWN material
    # name, because the game picks its texture by material name.
    for name, base in (("box_glyph", "wood"), ("mural_eye", "rock_a")):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        r, g, b = textures.mean_colour(base)
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (r, g, b, 1.0)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
        mats[name] = m
    return mats


def setup_world(scene, strength=0.9):
    """A late-afternoon sky as the ambient term: warm peach at the horizon, gold, then lilac overhead.
    Underneath, a warm earth bounce, so shade is never black."""
    world = bpy.data.worlds.new("Golden")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    bg = nt.nodes.new("ShaderNodeBackground")
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bg.inputs["Strength"].default_value = strength
    # Generated coords are 0..1; z=0.5 is the horizon.
    el = ramp.color_ramp.elements
    el[0].position, el[0].color = 0.0, (0.34, 0.22, 0.16, 1)
    el[1].position, el[1].color = 1.0, (0.40, 0.34, 0.62, 1)
    for pos, col in ((0.46, (0.60, 0.40, 0.26, 1)), (0.54, (1.0, 0.66, 0.36, 1)), (0.68, (0.78, 0.58, 0.52, 1))):
        e = el.new(pos)
        e.color = col
    scene.world = world


def add_sun(scene, name, direction_to_light, colour, energy, angle_deg, shadows=True):
    """`direction_to_light` is Godot-space: the unit vector from the surface toward the sun."""
    light = bpy.data.lights.new(name, "SUN")
    light.energy = energy
    light.color = colour
    light.angle = math.radians(angle_deg)
    light.use_shadow = shadows
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    d = common.TO_BL.to_3x3() @ Vector(direction_to_light).normalized()
    # A sun shines along its local -Z; point -Z away from the sun (toward the surface).
    obj.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    return obj


def add_area(scene, name, location, target, size, energy, colour):
    """A soft area light (Godot-space location and target) that shines from `location` toward `target`:
    the "limelight" that keeps the camera-facing sides of things readable."""
    light = bpy.data.lights.new(name, "AREA")
    light.shape = "DISK"
    light.size = size
    light.energy = energy
    light.color = colour
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = common.TO_BL @ Vector(location)
    direction = common.TO_BL.to_3x3() @ (Vector(target) - Vector(location))
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def bake_lighting(objs, samples=64):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 6
    scene.cycles.sample_clamp_indirect = 2.5
    scene.cycles.sample_clamp_direct = 0.0
    scene.render.bake.use_pass_direct = True
    scene.render.bake.use_pass_indirect = True
    scene.render.bake.use_pass_color = False
    scene.render.bake.target = "VERTEX_COLORS"
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.bake(type="DIFFUSE")


def read_corner_colours(obj):
    me = obj.data
    attr = me.color_attributes["Col"]
    arr = np.zeros(len(attr.data) * 4, dtype=np.float32)
    attr.data.foreach_get("color", arr)
    return arr.reshape(-1, 4)


def write_corner_colours(obj, arr):
    attr = obj.data.color_attributes["Col"]
    attr.data.foreach_set("color", arr.astype(np.float32).reshape(-1))
    obj.data.update()


def polygon_of_loop(obj):
    me = obj.data
    idx = np.zeros(len(me.loops), dtype=np.int32)
    me.loops.foreach_get("vertex_index", idx)  # placeholder to size
    poly = np.zeros(len(me.loops), dtype=np.int32)
    starts = np.zeros(len(me.polygons), dtype=np.int32)
    totals = np.zeros(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_start", starts)
    me.polygons.foreach_get("loop_total", totals)
    for i, (s, t) in enumerate(zip(starts, totals)):
        poly[s:s + t] = i
    return poly


def smooth_light(obj, radius=0.5, normal_dot=0.9):
    """Average each corner's light with nearby corners that face the same way. Cycles noise at a few
    dozen samples per corner is large next to the soft gradients we want; this keeps edges (corners
    on differently-oriented faces never mix) and kills the speckle."""
    from mathutils import Vector
    from mathutils.kdtree import KDTree
    me = obj.data
    arr = read_corner_colours(obj)
    n = len(me.loops)
    vi = np.zeros(n, dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    co = np.zeros(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    pos = co.reshape(-1, 3)[vi]
    poly = polygon_of_loop(obj)
    nor = np.zeros(len(me.polygons) * 3, dtype=np.float32)
    me.polygons.foreach_get("normal", nor)
    nor = nor.reshape(-1, 3)[poly]
    tree = KDTree(n)
    for i in range(n):
        tree.insert(Vector(pos[i]), i)
    tree.balance()
    out = arr.copy()
    for i in range(n):
        idx = [k for (_, k, _) in tree.find_range(Vector(pos[i]), radius)]
        idx = np.array(idx, dtype=np.int32)
        same = idx[(nor[idx] @ nor[i]) > normal_dot]
        out[i, :3] = arr[same, :3].mean(axis=0)
    write_corner_colours(obj, out)


def facet_tone(obj, strength=0.05, hue=0.02, seed=1):
    """Every facet gets its own faint value/hue shift: the crystalline mosaic of hand-painted low poly."""
    arr = read_corner_colours(obj)
    poly = polygon_of_loop(obj)
    rng = np.random.default_rng(seed + len(poly))
    n = poly.max() + 1 if len(poly) else 0
    dv = 1.0 + rng.normal(0, strength, n)
    dh = rng.normal(0, hue, n)
    v = dv[poly][:, None]
    arr[:, :3] *= v
    # a small warm/cool swing per facet
    arr[:, 0] *= 1.0 + dh[poly]
    arr[:, 2] *= 1.0 - dh[poly]
    write_corner_colours(obj, arr)


def normalise(obj, gain, sway=None, lift=None):
    """Scale baked light to the game's range, lift the shadows a little, set the alpha channel."""
    arr = read_corner_colours(obj)
    lit = arr[:, :3] * gain
    if lift is not None:
        lit = lit + lift
    # display-referred, like a PS1 framebuffer: the game multiplies these straight into painted tiles
    arr[:, :3] = np.clip(lit, 0.0, 1.6) ** (1.0 / 2.2)
    arr[:, 3] = 0.0 if sway is None else sway(obj, arr)
    write_corner_colours(obj, arr)


def export(objs, path, extra_nodes=()):
    bpy.ops.object.select_all(action="DESELECT")
    for o in list(objs) + list(extra_nodes):
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_vertex_color="ACTIVE",
        export_active_vertex_color_when_no_material=True,
        export_materials="EXPORT",
        export_normals=True,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_yup=True,
    )
