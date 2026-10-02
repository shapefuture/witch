#!/usr/bin/env python3
"""Offline checks for image2rig.py (no network, no quota, no credits): python3 tools/characters/test_image2rig.py"""
import io
import json
import os
import struct
import sys
import tempfile
from argparse import Namespace
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import image2rig as ir  # noqa: E402

FAKE_HF, FAKE_TRIPO = "hf_" + "A" * 30, "tsk_" + "B" * 30


def _views(folder, rgba=True, names=("front", "left", "back", "right", "front34", "back34")):
    (folder / "views").mkdir(parents=True)
    for n in names:
        im = Image.new("RGBA" if rgba else "RGB", (64, 64), (120, 40, 150, 255))
        if rgba:
            im.putpixel((0, 0), (0, 0, 0, 0))
        im.save(folder / "views" / (n + ".png"))
    return folder


def _glb(path, tris=3000, joints=24, surfaces=1, tex=(1024, 1024)):
    png = io.BytesIO()
    Image.new("RGB", tex).save(png, "PNG")
    png = png.getvalue()
    png += b"\0" * (-len(png) % 4)
    gltf = {"asset": {"version": "2.0"},
            "accessors": [{"count": 900, "type": "VEC3", "min": [-0.5, 0, -0.2], "max": [0.5, 1.6, 0.2]}, {"count": tris * 3, "type": "SCALAR"}],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "mode": 4}] * surfaces}],
            "nodes": [{"name": "joint_%d" % i} for i in range(max(joints, 1))],
            "skins": [{"joints": list(range(joints))}] if joints else [],
            "images": [{"bufferView": 0}], "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(png)}],
            "buffers": [{"byteLength": len(png)}]}
    js = json.dumps(gltf).encode()
    js += b" " * (-len(js) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(png), b"BIN\0") + png
    path.write_bytes(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)
    return path


class FakeClient:
    src = "fake/space"

    def __init__(self, files, fail=None, answers=None):
        self.calls, self.files, self.fail, self.answers = [], files, fail, answers or {}

    def predict(self, api_name, **kw):
        self.calls.append((api_name, kw))
        if self.fail:
            raise RuntimeError(self.fail)
        if api_name in self.answers:
            return self.answers[api_name]
        return (*self.files, "<html>", {"faces": 1}, 1234)


def test_keys_come_from_the_env_file_and_are_never_printed():
    tmp = Path(tempfile.mkdtemp())
    (tmp / "env").write_text("# c\nHF_TOKEN=%s\nTRIPO_API_KEY=\"%s\"\n" % (FAKE_HF, FAKE_TRIPO), encoding="utf-8")
    for n in ("HF_TOKEN", "TRIPO_API_KEY"):
        os.environ.pop(n, None)
    ir.load_env(tmp / "env")
    assert ir.secret("HF_TOKEN") == FAKE_HF and os.environ["TRIPO_API_KEY"] == FAKE_TRIPO
    text = ir.redact("failed with %s and %s in the header" % (FAKE_HF, FAKE_TRIPO))
    assert FAKE_HF not in text and FAKE_TRIPO not in text and "<HF_TOKEN>" in text
    buf, old = io.StringIO(), sys.stdout
    sys.stdout = buf
    try:
        ir.log("x", "token %s" % FAKE_HF)
        code = ir.main(["run", str(tmp / "nowhere")])
    finally:
        sys.stdout = old
    assert FAKE_HF not in buf.getvalue() and FAKE_TRIPO not in buf.getvalue() and code == 2, buf.getvalue()


def test_four_views_are_taken_from_a_multiview_result_and_the_34_views_are_left_out():
    folder = _views(Path(tempfile.mkdtemp()) / "witch")
    v = ir.find_views(folder)
    assert sorted(v) == sorted(ir.SLOTS) and all(p.name == s + ".png" for s, p in v.items())
    assert ir.all_transparent(v)
    other = Path(tempfile.mkdtemp())
    Image.new("RGB", (8, 8)).save(other / "mine.png")
    assert ir.find_views(folder, ["back=%s" % (other / "mine.png")])["back"].name == "mine.png"
    assert not ir.all_transparent(ir.find_views(_views(Path(tempfile.mkdtemp()) / "w", rgba=False)))
    try:
        ir.find_views(_views(Path(tempfile.mkdtemp()) / "x", names=("back", "left")))
        assert False, "a front view is required"
    except ir.Refused:
        pass


def test_mesh_paths_are_found_in_plain_and_updated_component_answers():
    assert ir._files(("/a/x.glb", "<html>", {"faces": 1}, 5)) == ["/a/x.glb"]
    assert ir._files(({"value": "/t/white_mesh.glb", "__type__": "update"}, "<html>", {"model": {}}, 1)) == ["/t/white_mesh.glb"]
    assert ir._files(({"value": {"path": "/t/a.glb"}}, {"path": "/t/b.obj"}, "/t/c.txt")) == ["/t/a.glb", "/t/b.obj"]
    assert ir._files("nothing") == []


def test_glb_inspection_counts_the_mesh_and_lists_the_gap_to_the_game():
    p = _glb(Path(tempfile.mkdtemp()) / "a.glb")
    st = ir.glb_inspect(p)
    assert st["triangles"] == 3000 and st["joints"] == 24 and st["textures"] == [(1024, 1024)] and st["size"] == [1.0, 1.6, 0.4], st
    notes = " | ".join(ir.game_fit(st))
    assert "texture 1024x1024" in notes and "retarget" in notes and "decimate" not in notes
    big = ir.glb_inspect(_glb(Path(tempfile.mkdtemp()) / "b.glb", tris=120000, joints=0, surfaces=3))
    notes = " | ".join(ir.game_fit(big))
    assert "decimate" in notes and "3 surfaces" in notes and "no skeleton" in notes
    assert ir.score(st) > 0 and ir.score({"ok": False}) == 0.0


def test_the_guards_stop_a_call_before_anything_is_spent():
    real = ir.zerogpu
    try:
        ir.zerogpu = lambda token: {"seconds": 40.0, "runs": 8}
        try:
            ir.gpu_guard("t", 90)
            assert False, "40 s left is below the floor"
        except ir.Refused as e:
            assert "40 s" in str(e)
        ir.zerogpu = lambda token: {"seconds": 300.0, "runs": 0}
        try:
            ir.gpu_guard("t", 90)
            assert False, "no runs left"
        except ir.Refused:
            pass
        ir.zerogpu = lambda token: {"seconds": 300.0, "runs": 8}
        assert ir.gpu_guard("t", 90)["runs"] == 8
    finally:
        ir.zerogpu = real
    try:
        ir.gpu_guard("", 90)
        assert False, "no token: anonymous quota is about 2 minutes"
    except ir.Refused as e:
        assert "HF_TOKEN" in str(e)
    try:
        ir.tripo_guard(0.0, 60)
        assert False, "a zero balance cannot cover the cap"
    except ir.Refused as e:
        assert "0 credits" in str(e)
    ir.tripo_guard(2000.0, 60)


def test_hunyuan_gets_the_four_views_by_name_and_a_space_refusal_says_what_to_do():
    tmp = Path(tempfile.mkdtemp())
    views = ir.find_views(_views(tmp / "w"))
    mesh = _glb(tmp / "m.glb")
    fake = FakeClient([str(tmp / "white.glb"), str(mesh)])
    (tmp / "white.glb").write_bytes(b"x")
    out = tmp / "out"
    out.mkdir()
    dest = ir.geo_hunyuan2mv(views, out, "tok", client=fake)
    api, kw = fake.calls[0]
    assert api == "/generation_all" and kw["image"] is None and kw["num_chunks"] == 8000 and kw["check_box_rembg"] is False
    assert all(kw["mv_image_" + s] is not None for s in ir.SLOTS) and kw["steps"] == 5 and kw["randomize_seed"] is False
    assert dest.read_bytes() == mesh.read_bytes(), "the textured mesh (the second file) is kept"
    m = FakeClient([], fail="'PyMeshLabException'")
    try:
        ir.geo_hunyuan2mv(views, out, "tok", client=m)
        assert False
    except ir.SpaceError as e:
        assert "--shape-only" in str(e) and "PyMeshLab" in str(e)
    q = FakeClient([], fail="You have exceeded your GPU quota (180s requested vs. 40s left)")
    try:
        ir.geo_hunyuan2mv(views, out, "tok", client=q)
        assert False
    except ir.QuotaError as e:
        assert "--steps" in str(e)


def test_anigen_keeps_the_skinned_mesh_first_and_the_skeleton_picture_apart():
    tmp = Path(tempfile.mkdtemp())
    skinned, bones = _glb(tmp / "skinned.glb", tris=15000, joints=26), _glb(tmp / "bones.glb", tris=900, joints=0)
    fake = FakeClient([], answers={"/extract_glb": ({"value": str(skinned), "__type__": "update"}, {"value": str(bones)}, "done")})
    front = tmp / "front.png"
    Image.new("RGBA", (8, 8)).save(front)
    out = tmp / "out"
    out.mkdir()
    dest = ir.rig_anigen(front, out, "tok", client=fake)
    assert [c[0] for c in fake.calls] == ["/prepare_input_for_generation", "/generate_preview", "/extract_glb"], fake.calls
    assert dest.name == "rig_anigen.glb" and ir.glb_inspect(dest)["joints"] == 26, "the first file is the skinned mesh"
    assert ir.glb_inspect(out / "skeleton_anigen.glb")["joints"] == 0


def test_run_keeps_a_stage_whose_inputs_are_unchanged():
    tmp = Path(tempfile.mkdtemp())
    _views(tmp / "w")
    calls = []
    real = (ir.geo_hunyuan2mv, ir.zerogpu, ir.secret)

    def fake_geo(views, out, token, steps, octree, textured, faces):
        calls.append(1)
        return _glb(out / "mesh_hunyuan2mv.glb")
    try:
        ir.geo_hunyuan2mv, ir.zerogpu, ir.secret = fake_geo, (lambda t: {"seconds": 300.0, "runs": 8}), (lambda n: "x" * 20 if n == "HF_TOKEN" else "")
        args = dict(source=str(tmp / "w"), view=[], out=str(tmp / "rig"), geometry="hunyuan2mv", all=False, rig="", rig_spec="tripo", parts=False,
                    steps=5, octree=256, shape_only=False, texture=1024, target_faces=0, min_gpu=90.0, max_credits=60.0, force=False)
        assert ir.run(Namespace(**args)) == 0 and len(calls) == 1
        assert ir.run(Namespace(**args)) == 0 and len(calls) == 1, "unchanged inputs: not run again"
        assert ir.run(Namespace(**{**args, "steps": 8})) == 0 and len(calls) == 2, "a changed setting runs it"
        assert ir.run(Namespace(**{**args, "force": True})) == 0 and len(calls) == 3
        mf = json.loads((tmp / "rig" / "manifest.json").read_text(encoding="utf-8"))
        assert mf["stages"]["space:hunyuan2mv"]["files"] and mf["master"].endswith("mesh_hunyuan2mv.glb")
        try:
            ir.run(Namespace(**{**args, "rig": "tripo"}))
            assert False, "Tripo rigs only its own meshes"
        except ir.Refused as e:
            assert "--geometry tripo" in str(e)
        try:
            ir.run(Namespace(**{**args, "geometry": "tripo", "out": str(tmp / "r2")}))
            assert False, "no Tripo key"
        except ir.Refused as e:
            assert "TRIPO_API_KEY" in str(e)
    finally:
        ir.geo_hunyuan2mv, ir.zerogpu, ir.secret = real


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            try:
                fn()
                print("ok   " + name)
            except AssertionError as e:
                failed += 1
                print("FAIL " + name, e)
    sys.exit(1 if failed else 0)
