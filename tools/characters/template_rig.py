#!/usr/bin/env python3
"""A rigged, textured, animated game character from a shape and its views, with no network, no GPU and no neural network.

    python tools/characters/template_rig.py build/views/witch_t_nolegs/views shape.glb out.glb [--faces 9000] [--size 256]

`shape.glb` is any mesh of the character in the sheet's pose (the silhouette hull, a Hunyuan3D shape, ...); the views are the cut-outs of tools/characters/multiview.py.
This inverts the usual order. Predicting a skeleton for every new mesh is the heavy, unreliable step; the game already has a fixed skeleton and clips (tools/characters/witch.py),
so the skeleton is placed on the mesh instead:

1. the shape is painted from the views (image2rig.paint_vertices), then decimated to the game's triangle budget;
2. landmarks come off the front cut-out of a T-pose figure (the arms are the widest row, their tips and the torso beside them give shoulders, elbows and wrists);
   the witch kit's bones (same names, same parents) are put at those places, so witch.clip_set drives them unchanged;
3. skin weights are the distance to each bone segment, softened (a hard core and a short blend at the joints): what a heat solver gives on a clean mesh and, unlike it,
   cannot fail on a generated one;
4. a fresh atlas (xatlas), filled by nearest-vertex lookup in the painted dense mesh; the .glb is written with witch_glb.export.

It is a humanoid with arms out, no legs (a long skirt), standing on y = 0, facing +Z, +X her left: the pose multiview.py's `--pose t --no-legs` draws.
Bones the mesh has no vertices for (cape, bird, hair, legs) stay in the skeleton so every clip still plays.
"""
import argparse
import sys
import types
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from silhouette_hull import landmarks  # noqa: E402  (the figure's arm row, span and torso width, off the front cut-out)

KIT_H = 2.8                 # witch.py's authored height in kit units
GAME_H = 1.3                # metres (tests/render/test_character_models.gd)
SLOTS = ("front", "right", "back", "left")
SKINNED = ("hips", "spine", "neck", "head", "arm_upper.L", "arm_lower.L", "hand.L", "arm_upper.R", "arm_lower.R", "hand.R")


def skeleton(lm):
    """The witch kit's bones (names and parents) at this figure's joints, in kit units; the segments the weights use."""
    import witch
    ay, span = lm["arm_y"], lm["span"]
    sh = lm["torso"] * .9
    pts = {"root": (0, 0, 0), "hips": (0, .36, 0), "spine": (0, ay - .17, 0), "neck": (0, ay + .015, 0), "head": (0, ay + .06, 0),
           "cape": (0, ay - .02, -.06), "bird": (span, ay, 0)}
    for s, d in ((1, ".L"), (-1, ".R")):
        pts["arm_upper" + d] = (s * sh, ay, 0)
        pts["arm_lower" + d] = (s * (sh + .42 * (span - sh)), ay, 0)
        pts["hand" + d] = (s * (sh + .78 * (span - sh)), ay, 0)
        pts["leg" + d] = (s * .05, .34, 0)
        pts["foot" + d] = (s * .05, .04, 0)
        pts["hairB" + d] = (s * .06, ay + .06, -.06)
        pts["hairT" + d] = (s * .12, ay - .04, -.08)
    bones = {n: (witch.BONES[n][0], np.array(pts[n], float) * KIT_H) for n in witch.BONES}
    h = lambda n: bones[n][1]
    seg = {"hips": (h("hips"), h("spine")), "spine": (h("spine"), h("neck")), "neck": (h("neck"), h("head")), "head": (h("head"), np.array([0, KIT_H, 0.]))}
    for s, d in ((1, ".L"), (-1, ".R")):
        seg["arm_upper" + d] = (h("arm_upper" + d), h("arm_lower" + d))
        seg["arm_lower" + d] = (h("arm_lower" + d), h("hand" + d))
        seg["hand" + d] = (h("hand" + d), np.array([s * span * KIT_H, ay * KIT_H, 0.]))
    return bones, seg


def skin_weights(P, bones, seg, tau=.06):
    """(n, 4) joint indices and weights from the distance to each bone segment: exp(-(d - d_min) / tau), the four nearest kept. P in kit units."""
    names = list(bones)
    ix = {n: i for i, n in enumerate(names)}
    active = [n for n in SKINNED if n in seg]
    D = np.empty((len(P), len(active)))
    for k, n in enumerate(active):
        a, b = seg[n]
        ab = b - a
        t = np.clip(((P - a) @ ab) / max(float(ab @ ab), 1e-9), 0, 1)
        D[:, k] = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
    W = np.exp(-(D - D.min(axis=1, keepdims=True)) / tau)
    top = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, top, axis=1)
    w = w / w.sum(axis=1, keepdims=True)
    j = np.array([ix[active[k]] for k in range(len(active))])[top]
    return j.astype(int), w


def atlas(P, F, dense_P, dense_C, size=256, pad=1):
    """xatlas charts packed into a `size` square, each texel coloured from the nearest vertex of the dense painted mesh.
    Returns (vertex map, triangles, uv in [0, 1] with v down the image, the picture as uint8, share of texels a triangle covers)."""
    import xatlas
    from scipy import ndimage
    from scipy.spatial import cKDTree
    a = xatlas.Atlas()
    a.add_mesh(np.ascontiguousarray(P, np.float32), np.ascontiguousarray(F, np.uint32))
    po, co = xatlas.PackOptions(), xatlas.ChartOptions()
    po.resolution, po.padding, po.bruteForce = size, pad, True
    co.max_cost = 64.0                                  # a decimated surface is faceted: fewer, bigger charts pack better (about half the texels are used; one pixel of padding, the sampler is NEAREST)
    a.generate(co, po, verbose=False)
    vmap, idx, uv = a[0]
    uv = np.asarray(uv, float)
    uv = uv / max(float(uv.max()), 1.0)
    px = uv * size
    Q = np.asarray(P, float)[vmap]
    pts, tex = [], []
    for tri in idx:
        t = px[tri]
        x0, y0 = np.floor(t.min(0)).astype(int)
        x1, y1 = np.ceil(t.max(0)).astype(int)
        gx, gy = np.meshgrid(np.arange(max(x0, 0), min(x1, size)), np.arange(max(y0, 0), min(y1, size)))
        c = np.stack([gx.ravel() + .5, gy.ravel() + .5], 1)
        d = (t[1, 1] - t[2, 1]) * (t[0, 0] - t[2, 0]) + (t[2, 0] - t[1, 0]) * (t[0, 1] - t[2, 1])
        if abs(d) < 1e-9 or not len(c):
            continue
        l0 = ((t[1, 1] - t[2, 1]) * (c[:, 0] - t[2, 0]) + (t[2, 0] - t[1, 0]) * (c[:, 1] - t[2, 1])) / d
        l1 = ((t[2, 1] - t[0, 1]) * (c[:, 0] - t[2, 0]) + (t[0, 0] - t[2, 0]) * (c[:, 1] - t[2, 1])) / d
        l2 = 1 - l0 - l1
        keep = (l0 >= -.02) & (l1 >= -.02) & (l2 >= -.02)
        if keep.any():
            pts.append(l0[keep, None] * Q[tri[0]] + l1[keep, None] * Q[tri[1]] + l2[keep, None] * Q[tri[2]])
            tex.append(np.floor(c[keep]).astype(int))
    pts, tex = np.concatenate(pts), np.concatenate(tex)
    img = np.zeros((size, size, 3), float)
    filled = np.zeros((size, size), bool)
    img[tex[:, 1], tex[:, 0]] = dense_C[cKDTree(dense_P).query(pts)[1]]
    filled[tex[:, 1], tex[:, 0]] = True
    near = ndimage.distance_transform_edt(~filled, return_distances=False, return_indices=True)
    out = img[near[0], near[1]]
    return vmap, idx, uv, (np.clip(out, 0, 1) * 255 + .5).astype(np.uint8), float(filled.mean())


def neutral_base():
    """Arms hanging at her sides: the base pose of the witch kit's clips, without the witch's wand and bird."""
    import witch
    return {**witch.arm_pose(1, (.12, -1, .05), (.10, -1, .2)), **witch.arm_pose(-1, (-.12, -1, .05), (-.10, -1, .2))}


def rig(views, shape, out, faces=9000, size=256, log=print):
    import image2rig as ir
    import witch
    import witch_glb
    from PIL import Image
    P, F = ir.load_mesh(shape)
    P = np.asarray(P, float)
    lo, hi = P.min(0), P.max(0)
    P = (P - np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])) / (hi[1] - lo[1])          # feet on y = 0, one unit tall
    dense_P, dense_F = ir.simplify(P, np.asarray(F), 120000)
    views = {s: Path(views) / (s + ".png") for s in SLOTS}
    col, stats = ir.paint_vertices(np.asarray(dense_P), np.asarray(dense_F), views)
    low_P, low_F = ir.simplify(dense_P, dense_F, faces)
    low_P = np.asarray(low_P, float)
    lm = landmarks(views["front"])
    bones, seg = skeleton(lm)
    vmap, idx, uv, picture, covered = atlas(low_P, low_F, np.asarray(dense_P), np.asarray(col), size)
    Pn = (low_P * KIT_H)[vmap]
    J, W = skin_weights(Pn, bones, seg)
    tri = idx.reshape(-1)
    T = Pn[tri].reshape(-1, 3, 3)
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    arr = {"P": Pn[tri], "N": np.repeat(n, 3, axis=0), "UV": uv[tri], "J": J[tri], "W": W[tri]}
    model = types.SimpleNamespace(B=bones, names=list(bones), ix={k: i for i, k in enumerate(bones)})
    clips = witch.clip_set(model, base=neutral_base)
    count = witch_glb.export(str(out), model, arr, Image.fromarray(picture), clips, GAME_H / KIT_H, mesh_name="Figure", generator="template_rig.py",
                             extras={"landmarks": lm})
    log("%s: %d triangles, one %d px atlas (%.0f%% of its texels covered), %d clips, silhouette iou %s" % (
        out, count, size, 100 * covered, len(clips), {k: v["silhouette_iou"] for k, v in stats.items() if isinstance(v, dict)}))
    return model, arr, picture, clips


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("views")
    ap.add_argument("shape")
    ap.add_argument("out")
    ap.add_argument("--faces", type=int, default=9000)
    ap.add_argument("--size", type=int, default=256)
    a = ap.parse_args(argv)
    rig(a.views, a.shape, a.out, a.faces, a.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
