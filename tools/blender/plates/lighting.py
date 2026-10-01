"""Light for the plates. The sun through the oculus is the only key; the rest is glow (candles, the
warm stair, the second room) and a little fill. Each source belongs to a Cycles light group, so the
render carries per-group passes from which key.png and glow.png (the shares) are made.

Groups: key (sun, and so the beam's scatter and the sun's bounce), glow (candles, stair, lamps),
fill (the sky seen through the hole, a dim bounce card behind the camera).
"""
import math

import bpy
import numpy as np
from mathutils import Vector

from . import geo, layout as L
from .geo import TO_BL

GROUPS = ("key", "glow", "fill")


def _gd(v):
    return TO_BL @ Vector(v)


def setup_groups(scene):
    vl = scene.view_layers[0]
    for g in GROUPS:
        if g not in vl.lightgroups:
            vl.lightgroups.add(name=g)


def world(scene, colour=(1.0, 0.9, 0.72), strength=2.2):
    w = bpy.data.worlds.new("Sky")
    scene.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*colour, 1.0)
    bg.inputs["Strength"].default_value = strength
    w.lightgroup = "fill"
    return w


def sun(scene, sun_dir, colour=(1.0, 0.84, 0.6), energy=9.0, angle_deg=4.5):
    light = bpy.data.lights.new("Sun", "SUN")
    light.energy = energy
    light.color = colour
    light.angle = math.radians(angle_deg)
    obj = bpy.data.objects.new("Sun", light)
    scene.collection.objects.link(obj)
    d = TO_BL.to_3x3() @ Vector(sun_dir).normalized()
    obj.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    obj.lightgroup = "key"
    return obj


def point(scene, name, at, energy, colour, radius=0.04, group="glow"):
    light = bpy.data.lights.new(name, "POINT")
    light.energy = energy
    light.color = colour
    light.shadow_soft_size = radius
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = _gd(at)
    obj.lightgroup = group
    return obj


def area(scene, name, at, target, size, energy, colour, group="glow", shape="DISK", size_y=None):
    light = bpy.data.lights.new(name, "AREA")
    light.shape = shape
    light.size = size
    if size_y is not None:
        light.size_y = size_y
    light.energy = energy
    light.color = colour
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = _gd(at)
    direction = TO_BL.to_3x3() @ (Vector(target) - Vector(at))
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    obj.lightgroup = group
    return obj


def beam_hull(coll, mats, oculus, sun_dir, radius=1.7):
    """The beam-shaped volume: a cylinder along the sun's ray from above the hole to below the floor.
    Scattering lives only in here, so the air elsewhere stays clear."""
    top = Vector(oculus) + Vector(sun_dir) * 2.0
    bottom = Vector(oculus) - Vector(sun_dir) * ((oculus[1] + 1.0) / sun_dir[1])
    b = geo.Builder("BeamHull")
    b.cyl(tuple(top), tuple(bottom), radius, radius * 1.45, "beam", segs=16)
    obj = b.build(coll, mats)
    obj.visible_shadow = False
    return obj


def rig(scene, coll, mats, candles, sun_dir=None, dusk=False):
    """Every light in the hall. `candles` = [(flame object, world position)]."""
    setup_groups(scene)
    sd = Vector(sun_dir if sun_dir is not None else L.SUN_DIR)
    objs = {}
    objs["world"] = world(scene, colour=(1.0, 0.78, 0.55) if dusk else (1.0, 0.92, 0.76), strength=1.5 if dusk else 2.2)
    objs["sun"] = sun(scene, sd, colour=(1.0, 0.62, 0.34) if dusk else (1.0, 0.85, 0.62), energy=7.5 if dusk else 9.5)
    for k, (flame, p) in enumerate(candles):
        flame.lightgroup = "glow"
        point(scene, "Candle%d" % k, tuple(p + Vector((0, 0.06, 0))), 2.6, (1.0, 0.58, 0.28), radius=0.03)
    # the warm stair: a glowing landing round the corner at the top of the side stair
    from .hall import PASS_HW, STAIR_Z0, STAIR_Z1
    sx = L.ARCH_X - PASS_HW
    sz = (STAIR_Z0 + STAIR_Z1) / 2
    area(scene, "StairLight", (sx - 3.4, 4.3, sz), (sx + 0.4, 1.2, sz), 1.6, 520.0, (1.0, 0.74, 0.45))
    # light spilling down the stair washes the passage's left wall, the one the camera sees
    ax = L.ARCH_X
    area(scene, "PassageLight", (ax + PASS_HW - 0.35, 3.9, L.ARCH_WALL_Z - 1.3), (ax - PASS_HW, 2.2, L.ARCH_WALL_Z - 2.6), 1.2, 320.0, (1.0, 0.86, 0.66))
    # the second room: a lamp over its shelves
    from .hall import THIRD_X, PASS_END_Z, ROOM2_BACK_Z
    area(scene, "Room2Light", (THIRD_X + 0.4, 4.2, PASS_END_Z - 1.2), (THIRD_X, 1.2, ROOM2_BACK_Z), 1.4, 70.0, (1.0, 0.72, 0.42))
    # fill: soft light from the hall's upper air (the beam's bounce off the floor and vault) and a
    # wash that keeps the wall with the eye readable
    k = 0.7 if dusk else 1.0
    area(scene, "Fill", (0.3, 8.6, 2.0), (0.0, 0.0, -2.5), 6.0, 90.0 * k, (0.95, 0.86, 0.68), group="fill")
    area(scene, "Wash", (0.4, 6.0, 1.5), (-2.2, 6.2, L.ARCH_WALL_Z), 4.0, 110.0 * k, (1.0, 0.88, 0.66), group="fill")
    area(scene, "VaultSpill", (L.OCULUS[0] - 1.5, 2.0, L.OCULUS[2] + 2.5), (L.OCULUS[0] - 0.5, 9.0, L.OCULUS[2] - 0.5), 3.0, 180.0 * k, (1.0, 0.84, 0.58), group="key")
    return objs


def render_settings(scene, samples, size, threads=4, quick=False):
    scene.render.engine = "CYCLES"
    c = scene.cycles
    c.device = "CPU"
    c.samples = samples
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.03 if quick else 0.015
    c.use_denoising = True
    c.denoiser = "OPENIMAGEDENOISE"
    c.max_bounces = 6
    c.diffuse_bounces = 3
    c.glossy_bounces = 2
    c.transmission_bounces = 0
    c.volume_bounces = 0
    c.transparent_max_bounces = 2
    c.sample_clamp_indirect = 6.0
    c.volume_step_rate = 4.0 if quick else 2.0
    c.use_light_tree = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    vl = scene.view_layers[0]
    vl.use_pass_z = True
    vl.use_pass_combined = True
    im = scene.render.image_settings
    im.media_type = "MULTI_LAYER_IMAGE"
    im.file_format = "OPEN_EXR_MULTILAYER"
    im.color_depth = "32"
    im.exr_codec = "NONE"
