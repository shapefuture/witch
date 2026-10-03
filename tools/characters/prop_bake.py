#!/usr/bin/env python3
"""A generated shape and its views to a small textured static prop in the game's budget, on the CPU: no GPU, no credits.

    python tools/characters/prop_bake.py build/views/prop_cauldron/views shape.glb cauldron.glb [--faces 1500] [--size 128] [--height 0.6]

1. the shape (tools/characters/hunyuan_cpu.py: `batch`) is set on y = 0, centred, scaled to `--height` metres;
2. it is painted from the four axis views (image2rig.paint_vertices: each camera fitted to its silhouette, visible surface only);
3. decimated to `--faces` triangles (quadric), unwrapped with xatlas, and the atlas filled by nearest-vertex lookup in the painted dense mesh
   (template_rig.atlas), so one `--size` px picture carries the colour;
4. written as a static .glb: flat normals, one primitive, one material sampled NEAREST like the characters' (witch_glb.export does the same for a rig).

The prop budget is not in a test yet: this tool's defaults (1,500 triangles, one surface, a 128 px atlas) are about the size of the toy-box props in the
reference picture, and cheaper than a character by a factor of six.
"""
import argparse
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

SLOTS = ("front", "right", "back", "left")


def write_static_glb(path, P, N, UV, picture, name="Prop"):
    """P, N, UV per corner (3 per triangle); one mesh, one material with the picture as its base colour, sampler NEAREST."""
    blob, views, accs = bytearray(), [], []

    def view(b, target=None):
        while len(blob) % 4:
            blob.append(0)
        v = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(b)}
        if target:
            v["target"] = target
        views.append(v)
        blob.extend(b)
        return len(views) - 1

    def acc(a, ct, typ, minmax=False, target=None):
        a = np.ascontiguousarray(a)
        d = {"bufferView": view(a.tobytes(), target), "componentType": ct, "count": len(a), "type": typ}
        if minmax:
            d["min"], d["max"] = a.min(0).astype(float).tolist(), a.max(0).astype(float).tolist()
        accs.append(d)
        return len(accs) - 1

    attrs = {"POSITION": acc(P.astype(np.float32), 5126, "VEC3", True, 34962), "NORMAL": acc(N.astype(np.float32), 5126, "VEC3", False, 34962),
             "TEXCOORD_0": acc(UV.astype(np.float32), 5126, "VEC2", False, 34962)}
    png = io.BytesIO()
    picture.save(png, "PNG", optimize=True)
    img = view(png.getvalue())
    g = {"asset": {"version": "2.0", "generator": "tools/characters/prop_bake.py"}, "scene": 0, "scenes": [{"name": name, "nodes": [0]}],
         "nodes": [{"name": name, "mesh": 0}], "meshes": [{"name": name, "primitives": [{"attributes": attrs, "material": 0, "mode": 4}]}],
         "materials": [{"name": name.lower() + "_atlas", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}}],
         "textures": [{"sampler": 0, "source": 0}], "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
         "images": [{"bufferView": img, "mimeType": "image/png", "name": name.lower() + "_atlas"}],
         "buffers": [{"byteLength": 0}], "bufferViews": views, "accessors": accs}
    while len(blob) % 4:
        blob.append(0)
    g["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    return len(P) // 3


def bake(views, shape, out, faces=1500, size=128, height=1.0, name="Prop", log=print):
    import image2rig as ir
    import template_rig as tr
    from PIL import Image
    P, F = ir.load_mesh(shape)
    P = np.asarray(P, float)
    lo, hi = P.min(0), P.max(0)
    P = (P - np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])) / (hi[1] - lo[1]) * height
    dense_P, dense_F = ir.simplify(P, np.asarray(F), 120000)
    paths = {s: Path(views) / (s + ".png") for s in SLOTS}
    col, stats = ir.paint_vertices(np.asarray(dense_P), np.asarray(dense_F), paths)
    low_P, low_F = ir.simplify(dense_P, dense_F, faces)
    vmap, idx, uv, picture, covered = tr.atlas(np.asarray(low_P, float), low_F, np.asarray(dense_P), np.asarray(col), size)
    Q = np.asarray(low_P, float)[vmap]
    tri = idx.reshape(-1)
    T = Q[tri].reshape(-1, 3, 3)
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    count = write_static_glb(str(out), Q[tri], np.repeat(n, 3, axis=0), uv[tri], Image.fromarray(picture), name)
    log("%s: %d triangles, one %d px atlas (%.0f%% of its texels covered), %.2f m tall, silhouette iou %s" % (
        out, count, size, 100 * covered, height, {k: v["silhouette_iou"] for k, v in stats.items() if isinstance(v, dict)}))
    return count


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("views")
    ap.add_argument("shape")
    ap.add_argument("out")
    ap.add_argument("--faces", type=int, default=1500)
    ap.add_argument("--size", type=int, default=128)
    ap.add_argument("--height", type=float, default=1.0, help="metres")
    ap.add_argument("--name", default="Prop")
    a = ap.parse_args(argv)
    bake(a.views, a.shape, a.out, a.faces, a.size, a.height, a.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
