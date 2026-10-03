"""Render one plate: put the Blender camera on a Godot-space pose, render Cycles with Z and light
group passes into an uncompressed multilayer EXR, and read the passes back as numpy arrays."""
import os
import time

import bpy
import numpy as np
from mathutils import Matrix

from . import exr
from .geo import TO_BL


def camera(scene, cam):
    """cam: space.Cam (Godot space). Blender cameras look down local -Z with +Y up, like Godot's."""
    data = bpy.data.cameras.get("PlateCam") or bpy.data.cameras.new("PlateCam")
    obj = bpy.data.objects.get("PlateCam")
    if obj is None:
        obj = bpy.data.objects.new("PlateCam", data)
        scene.collection.objects.link(obj)
    b, p = cam.basis, cam.position
    m = Matrix(((b[0, 0], b[0, 1], b[0, 2], p[0]), (b[1, 0], b[1, 1], b[1, 2], p[1]), (b[2, 0], b[2, 1], b[2, 2], p[2]), (0, 0, 0, 1)))
    obj.matrix_world = TO_BL @ m
    data.sensor_fit = "VERTICAL"
    data.angle_y = np.radians(cam.fov_v)
    data.clip_start = cam.near
    data.clip_end = cam.far
    scene.camera = obj
    return obj


def render(scene, cam, size, samples, path, quick=False):
    from . import lighting
    lighting.render_settings(scene, samples, size, quick=quick)
    camera(scene, cam)
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    dt = time.time() - t
    ch = exr.read(path)
    layer = "ViewLayer."

    def rgb(name):
        return np.stack([ch[layer + name + ".R"], ch[layer + name + ".G"], ch[layer + name + ".B"]], -1)

    out = {"rgb": rgb("Combined"), "z": ch[layer + "Depth.Z"], "seconds": dt}
    for g in ("key", "glow", "fill"):
        k = layer + "Combined_%s.R" % g
        out[g] = rgb("Combined_%s" % g) if k in ch else np.zeros_like(out["rgb"])
    os.remove(path)
    return out
