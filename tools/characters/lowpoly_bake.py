#!/usr/bin/env python3
"""A textured high-poly character .glb to a game-budget .glb on the CPU, in headless Blender (the `bpy` module: pip install bpy).

    python tools/characters/lowpoly_bake.py in.glb out.glb [--faces 9000] [--size 256] [--margin 4]

1. import the .glb and bake the node transforms in (Tencent's GLB is Z-up under a rotated node);
2. a copy is decimated (collapse) to about `--faces` triangles and given a fresh UV layout (smart project);
3. the high-poly material's colour is baked onto a `--size` square image of the low-poly mesh with Cycles on the CPU (selected to active, colour pass only: the lights do not matter);
4. the low-poly mesh with that one material and picture is exported as a .glb.

This is the free local stand-in for a paid retopology: the game's characters are at most 9000 triangles in 2 surfaces with a 256 px atlas (tests/render/test_character_models.gd).
It does not make a clean quad mesh and does not touch a skeleton; rig after this (or before, in a tool that keeps the skin).
"""
import argparse
import sys
from pathlib import Path


def bake(src, dest, faces=9000, size=256, margin=4):
    import bpy
    import math

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("no mesh in %s" % src)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    hi = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)        # bake the node's rotation in
    hi.name = "high"
    tri_count = sum(len(p.vertices) - 2 for p in hi.data.polygons)

    low = hi.copy()
    low.data = hi.data.copy()
    low.name = "low"
    bpy.context.collection.objects.link(low)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    if tri_count > faces:
        mod = low.modifiers.new("decimate", "DECIMATE")
        mod.ratio = faces / tri_count
        bpy.ops.object.modifier_apply(modifier=mod.name)
    while low.data.uv_layers:
        low.data.uv_layers.remove(low.data.uv_layers[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003, scale_to_bounds=True)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()                                                  # equal texel density, then fill the square
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")

    image = bpy.data.images.new("atlas", size, size, alpha=False)
    mat = bpy.data.materials.new("lowpoly")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
    nodes.active = tex                                                                 # the bake target is the active image node
    low.data.materials.clear()
    low.data.materials.append(mat)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    scene.render.bake.margin = margin
    scene.render.bake.cage_extrusion = 0.03
    scene.render.bake.max_ray_distance = 0.1
    bpy.ops.object.select_all(action="DESELECT")
    hi.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type="DIFFUSE")

    bpy.data.objects.remove(hi, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    Path(dest).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(dest), export_format="GLB", use_selection=True, export_image_format="AUTO", export_yup=True)
    return sum(len(p.vertices) - 2 for p in low.data.polygons)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("src")
    ap.add_argument("dest")
    ap.add_argument("--faces", type=int, default=9000)
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--margin", type=int, default=4)
    a = ap.parse_args(argv)
    n = bake(a.src, a.dest, a.faces, a.size, a.margin)
    print("%s: %d triangles, one %d px texture" % (a.dest, n, a.size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
