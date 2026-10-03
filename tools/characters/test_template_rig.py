#!/usr/bin/env python3
"""Offline checks for silhouette_hull.py and template_rig.py (no network, no GPU): python3 tools/characters/test_template_rig.py"""
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import image2rig as ir  # noqa: E402
import silhouette_hull as sh  # noqa: E402
import template_rig as tr  # noqa: E402
import witch  # noqa: E402

S = 256


def _figure(draw, side, colour):
    """A T-pose figure 200 px tall (standing on row 228) in a 256 px square: torso, head, arms, a skirt. `side` = the view is a profile (arms and torso are thin)."""
    cx = S // 2
    w = 22 if side else 54
    draw.rectangle([cx - w, 100, cx + w, 228], fill=colour)                        # skirt and torso
    draw.ellipse([cx - 22 if not side else cx - 24, 28, cx + 22 if not side else cx + 24, 76], fill=colour)
    draw.rectangle([cx - 8, 70, cx + 8, 100], fill=colour)
    if side:
        draw.rectangle([cx - 8, 92, cx + 8, 108], fill=colour)                     # the arm seen end on
    else:
        draw.rectangle([cx - 110, 92, cx + 110, 108], fill=colour)                 # arms out


def _views(folder, side_colour=(90, 60, 160, 255)):
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("front", "right", "back", "left"):
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        _figure(ImageDraw.Draw(im), name in ("right", "left"), (200, 80, 90, 255) if name in ("front", "back") else side_colour)
        im.save(folder / (name + ".png"))
    return folder


def test_the_hull_of_a_t_pose_figure_has_the_extents_of_its_views():
    tmp = Path(tempfile.mkdtemp())
    try:
        P, F = sh.hull(_views(tmp / "v"), faces=4000, size=64)
        ext = np.ptp(P, axis=0)
        assert 0.9 < ext[1] < 1.05, ext                       # one unit tall
        assert 0.8 < ext[0] < 1.2, ext                        # the arms
        assert 0.15 < ext[2] < 0.5, ext                       # the profile's depth, not the arms'
        assert len(F) <= 4000 and P[:, 1].min() > -0.03
    finally:
        shutil.rmtree(tmp)


def test_landmarks_and_the_kits_bones_follow_a_t_pose():
    tmp = Path(tempfile.mkdtemp())
    try:
        lm = sh.landmarks(_views(tmp / "v") / "front.png")
        assert 0.58 < lm["arm_y"] < 0.72 and 0.45 < lm["span"] < 0.65 and 0.15 < lm["torso"] < 0.35, lm
        bones, seg = tr.skeleton(lm)
        assert list(bones) == list(witch.BONES), "the skeleton is the witch kit's, name for name and in order"
        assert all(bones[n][0] == witch.BONES[n][0] for n in bones)
        for d, s in ((".L", 1), (".R", -1)):
            xs = [s * bones[n + d][1][0] for n in ("arm_upper", "arm_lower", "hand")]
            assert 0 < xs[0] < xs[1] < xs[2], (d, xs)
        assert bones["head"][1][1] > bones["neck"][1][1] > bones["spine"][1][1] > bones["hips"][1][1]
    finally:
        shutil.rmtree(tmp)


def test_skin_weights_follow_the_nearest_bone_and_sum_to_one():
    tmp = Path(tempfile.mkdtemp())
    try:
        bones, seg = tr.skeleton(sh.landmarks(_views(tmp / "v") / "front.png"))
        ix = {n: i for i, n in enumerate(bones)}
        h = lambda n: bones[n][1]
        pts = np.array([h("arm_lower.L") + [0, .02, 0], h("arm_lower.R") + [0, .02, 0], h("spine") + [0, 0, .1], h("hips") - [0, .6, 0], h("head") + [0, .3, 0]])
        J, W = tr.skin_weights(pts, bones, seg)
        assert np.allclose(W.sum(axis=1), 1) and J.shape == (5, 4)
        top = [list(bones)[J[i, int(np.argmax(W[i]))]] for i in range(5)]
        assert top[0].endswith(".L") and top[0].startswith(("arm_lower", "arm_upper", "hand")), top
        assert top[1].endswith(".R"), top
        assert top[2] in ("spine", "neck", "hips"), top
        assert top[3] == "hips", top                         # the skirt below the hips rides the hips
        assert top[4] == "head", top
        assert max(ix[n] for n in top) < len(bones)
    finally:
        shutil.rmtree(tmp)


def test_the_atlas_keeps_every_triangle_and_takes_colours_from_the_dense_mesh():
    import trimesh
    sphere = trimesh.creation.icosphere(subdivisions=3)
    P, F = np.asarray(sphere.vertices), np.asarray(sphere.faces)
    dense = trimesh.creation.icosphere(subdivisions=5)
    DP = np.asarray(dense.vertices)
    colour = np.clip(DP * .5 + .5, 0, 1)                                   # position encodes colour
    vmap, idx, uv, picture, covered = tr.atlas(P, F, DP, colour, size=128)
    assert len(idx) == len(F) and uv.min() >= 0 and uv.max() <= 1.0001
    assert 0.25 < covered <= 1.0 and picture.shape == (128, 128, 3)
    c = uv[idx[0]].mean(0)                                                 # a triangle's centre texel against the colour field at that triangle's centre
    texel = picture[min(int(c[1] * 128), 127), min(int(c[0] * 128), 127)] / 255.0
    centre = P[F[0]].mean(0)
    want = np.clip(centre / np.linalg.norm(centre) * .5 + .5, 0, 1)
    assert np.abs(texel - want).max() < 0.25, (texel, want)


def test_a_rigged_game_glb_comes_out_of_a_shape_and_its_views():
    tmp = Path(tempfile.mkdtemp())
    try:
        views = _views(tmp / "v")
        P, F = sh.hull(views, faces=20000, size=64)
        ir.write_glb(str(tmp / "shape.glb"), P, F)
        model, arr, picture, clips = tr.rig(views, tmp / "shape.glb", tmp / "out.glb", faces=2500, size=64, log=lambda *a: None)
        st = ir.glb_inspect(tmp / "out.glb")
        assert st["ok"] and st["triangles"] <= 2500 and st["joints"] == len(witch.BONES), st
        assert sorted(c.name for c in clips) == ["cast", "idle", "talk", "walk"]
        import witch_glb
        rots, trans = [c for c in clips if c.name == "idle"][0].fn(1.0)
        posed = witch_glb.pose_arrays(model, arr, rots, trans)["P"]
        assert posed.shape == arr["P"].shape and not np.allclose(posed, arr["P"]), "the idle clip moves the mesh"
        assert np.isfinite(posed).all()
        hand = np.abs(arr["P"][:, 0]) > .8 * np.abs(arr["P"][:, 0]).max()    # the wrists swing down when the arms drop from the T-pose
        assert posed[hand, 1].mean() < arr["P"][hand, 1].mean() - .2
    finally:
        shutil.rmtree(tmp)


def test_a_textured_mesh_keeps_its_uvs_and_picture_and_the_previewer_shows_the_atlas_per_pixel():
    tmp = Path(tempfile.mkdtemp())
    try:
        views = _views(tmp / "v")
        P, F = sh.hull(views, faces=20000, size=64)
        ir.write_glb(str(tmp / "shape.glb"), P, F)
        tr.rig(views, tmp / "shape.glb", tmp / "rigged.glb", faces=2500, size=64, log=lambda *a: None)
        P1, F1, UV1, picture = tr.read_textured(tmp / "rigged.glb")
        assert len(F1) <= 2500 and UV1.shape == (len(P1), 2) and picture.size == (64, 64)
        tr.rig_textured(views, tmp / "rigged.glb", tmp / "again.glb", log=lambda *a: None)
        a, b = ir.glb_inspect(tmp / "rigged.glb"), ir.glb_inspect(tmp / "again.glb")
        assert b["ok"] and b["joints"] == a["joints"] and b["triangles"] == a["triangles"], (a, b)
        P2, F2, UV2, picture2 = tr.read_textured(tmp / "again.glb")
        assert np.allclose(UV1[F1].reshape(-1, 2).mean(0), UV2[F2].reshape(-1, 2).mean(0), atol=1e-4) and picture2.size == picture.size
        # the previewer samples the atlas per pixel: the front view's red must show in the first tile (it used to be one sample per triangle)
        ir.preview(tmp / "rigged.glb", tmp / "prev.png", size=160)
        tile = np.asarray(Image.open(tmp / "prev.png").convert("RGB").crop((0, 0, 160, 160))).astype(int)
        red = (tile[..., 0] > 120) & (tile[..., 0] > tile[..., 2] + 30)
        assert red.sum() > 200, "the atlas colour is drawn (%d red pixels)" % red.sum()
    finally:
        shutil.rmtree(tmp)


def test_a_prop_comes_out_of_a_shape_and_its_views_as_a_small_static_textured_glb():
    import prop_bake as pb
    tmp = Path(tempfile.mkdtemp())
    try:
        views = _views(tmp / "v")
        P, F = sh.hull(views, faces=20000, size=64)
        ir.write_glb(str(tmp / "shape.glb"), P, F)
        count = pb.bake(views, tmp / "shape.glb", tmp / "prop.glb", faces=600, size=64, height=0.5, log=lambda *a: None)
        st = ir.glb_inspect(tmp / "prop.glb")
        assert st["ok"] and count == st["triangles"] <= 600 and not st["joints"] and st["surfaces"] == 1, st
        assert st["textures"] == [(64, 64)], st["textures"]
        assert abs(st["size"][1] - 0.5) < 0.02, st["size"]
        _, _, uv, picture = tr.read_textured(tmp / "prop.glb")
        assert uv.min() >= 0 and uv.max() <= 1.0001 and picture.size == (64, 64)
        # carried on a hand bone, it is the character's second surface with its own atlas
        tr.rig(views, tmp / "shape.glb", tmp / "holds.glb", faces=2500, size=64, log=lambda *a: None, parts=[(str(tmp / "prop.glb"), "hand.L", [0, -0.1, 0])])
        h = ir.glb_inspect(tmp / "holds.glb")
        assert h["ok"] and h["surfaces"] == 2 and h["triangles"] > count and len(h["textures"]) == 2, h
        assert h["joints"] == ir.glb_inspect(tmp / "prop.glb")["joints"] + 21 or h["joints"] == 21, h
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok  ", name)
            except Exception as e:  # noqa: BLE001
                failed += 1
                print("FAIL", name, "-", repr(e)[:300])
    sys.exit(1 if failed else 0)
