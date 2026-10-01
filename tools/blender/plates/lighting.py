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


def sun(scene, sun_dir, colour=(1.0, 0.84, 0.6), energy=9.0, angle_deg=3.2):
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


def beam_hull(coll, mats, oculus, sun_dir, radius=0.8, half_angle_deg=7.0):
    """The beam-shaped volume: a cone along the light's axis from just above the hole to below the
    floor, opening like the light through the hole does. Scattering lives only in here."""
    top = Vector(oculus) + Vector(sun_dir) * 1.0
    length = (oculus[1] + 1.0) / sun_dir[1]
    bottom = Vector(oculus) - Vector(sun_dir) * length
    b = geo.Builder("BeamHull")
    b.cyl(tuple(top), tuple(bottom), radius, radius + (length + 1.0) * math.tan(math.radians(half_angle_deg)), "beam", segs=20)
    obj = b.build(coll, mats)
    obj.visible_shadow = False
    return obj


def hole_light(scene, oculus, sun_dir, radius, energy, colour, spread_deg=14.0):
    """Sky light through the oculus: a disk the size of the hole, aimed down the beam, its spread
    limited so it makes the soft diverging cone of the reference (the sun inside it is the crisp pool)."""
    light = bpy.data.lights.new("HoleLight", "AREA")
    light.shape = "DISK"
    light.size = 2 * radius
    light.energy = energy
    light.color = colour
    light.spread = math.radians(spread_deg)
    obj = bpy.data.objects.new("HoleLight", light)
    scene.collection.objects.link(obj)
    at = Vector(oculus) - Vector(sun_dir) * 0.35
    obj.location = _gd(at)
    d = TO_BL.to_3x3() @ (-Vector(sun_dir))
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    obj.lightgroup = "key"
    return obj


def rig(scene, coll, mats, candles, sun_dir=None, dusk=False):
    """Every light in the hall. `candles` = [(flame object, world position)]."""
    setup_groups(scene)
    sd = Vector(sun_dir if sun_dir is not None else L.SUN_DIR)
    objs = {}
    objs["world"] = world(scene, colour=(1.0, 0.78, 0.55) if dusk else (1.0, 0.92, 0.76), strength=1.5 if dusk else 2.2)
    objs["sun"] = sun(scene, sd, colour=(1.0, 0.62, 0.34) if dusk else (1.0, 0.85, 0.62), energy=7.0 if dusk else 8.5)
    from .hall import OCULUS_R
    objs["hole"] = hole_light(scene, L.OCULUS, sd, OCULUS_R, 85.0 if dusk else 120.0, (1.0, 0.7, 0.42) if dusk else (1.0, 0.86, 0.64))
    for k, (flame, p) in enumerate(candles):
        flame.lightgroup = "glow"
        point(scene, "Candle%d" % k, tuple(p + Vector((0, 0.06, 0))), 2.6, (1.0, 0.58, 0.28), radius=0.03)
    # the warm stair: a glowing landing round the corner at the top of the side stair
    from .hall import PASS_HW, STAIR_Z0, STAIR_Z1
    sx = L.ARCH_X - PASS_HW
    sz = (STAIR_Z0 + STAIR_Z1) / 2
    area(scene, "StairLight", (sx - 3.4, 4.3, sz), (sx + 0.4, 1.2, sz), 1.6, 160.0, (1.0, 0.74, 0.45))
    # light spilling down the stair washes the passage's left wall, the one the camera sees
    ax = L.ARCH_X
    area(scene, "PassageLight", (ax + PASS_HW - 0.35, 3.6, L.ARCH_WALL_Z - 0.9), (ax - PASS_HW, 2.4, L.ARCH_WALL_Z - 1.6), 0.6, 280.0, (1.0, 0.88, 0.7))
    # the second room: a lamp over its shelves
    from .hall import THIRD_X, PASS_END_Z, ROOM2_BACK_Z
    area(scene, "Room2Light", (THIRD_X + 0.4, 4.2, PASS_END_Z - 1.2), (THIRD_X, 1.2, ROOM2_BACK_Z), 1.4, 20.0, (1.0, 0.72, 0.42))
    # fill: soft light from the hall's upper air (the beam's bounce off the floor and vault) and a
    # wash that keeps the wall with the eye readable
    k = 0.7 if dusk else 1.0
    area(scene, "Fill", (0.3, 8.6, 2.0), (0.0, 1.0, -4.0), 6.0, 50.0 * k, (0.95, 0.86, 0.68), group="fill")
    area(scene, "Wash", (0.4, 5.0, 1.5), (-2.2, 4.4, L.ARCH_WALL_Z), 4.0, 35.0 * k, (1.0, 0.88, 0.66), group="fill")
    area(scene, "VaultWash", (0.6, 3.5, 0.5), (0.4, 10.5, L.ARCH_WALL_Z - 0.5), 3.0, 110.0 * k, (1.0, 0.86, 0.62), group="fill")
    area(scene, "VaultSpill", (L.OCULUS[0] - 1.5, 2.0, L.OCULUS[2] + 2.5), (L.OCULUS[0] - 0.5, 9.0, L.OCULUS[2] - 0.5), 4.0, 200.0 * k, (1.0, 0.84, 0.58), group="key")
    area(scene, "AlcoveBounce", (3.9, 5.2, -5.2), (4.6, 2.6, L.ALCOVE_BACK_Z), 2.0, 60.0 * k, (1.0, 0.82, 0.56), group="key")
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
