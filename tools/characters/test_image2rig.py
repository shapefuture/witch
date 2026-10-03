#!/usr/bin/env python3
"""Offline checks for image2rig.py (no network, no quota, no credits): python3 tools/characters/test_image2rig.py"""
import io
import json
import os
import shutil
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
    for n in ("HF_TOKEN", "HUGGINGFACE_TOKEN", "TRIPO_API_KEY"):
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


def test_our_hugging_face_variable_is_read_before_the_shared_one():
    other = "hf_" + "C" * 30
    saved = {n: os.environ.pop(n, None) for n in ("HF_TOKEN", "HUGGINGFACE_TOKEN")}
    real_file, tmp = ir.ENV_FILE, Path(tempfile.mkdtemp())
    (tmp / "env").write_text("HUGGINGFACE_TOKEN=%s\n" % FAKE_HF, encoding="utf-8")
    (tmp / "empty").write_text("", encoding="utf-8")
    try:
        os.environ["HF_TOKEN"] = other                       # another tool's (or another account's) token
        ir.ENV_FILE = tmp / "env"
        assert ir.hf_var() == "HUGGINGFACE_TOKEN" and ir.hf_token() == FAKE_HF, "ours wins over a stale HF_TOKEN"
        os.environ.pop("HUGGINGFACE_TOKEN")
        ir.ENV_FILE = tmp / "empty"                          # the file no longer supplies ours
        assert ir.hf_var() == "HF_TOKEN" and ir.hf_token() == other, "the shared name is the fallback"
        os.environ.pop("HF_TOKEN")
        assert ir.hf_var() == "" and ir.hf_token() == ""
    finally:
        ir.ENV_FILE = real_file
        for n, v in saved.items():
            os.environ.pop(n, None)
            if v:
                os.environ[n] = v


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
        assert "HUGGINGFACE_TOKEN" in str(e)
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


def _sphere(n=120):
    import numpy as np
    th, ph = np.meshgrid(np.linspace(0, np.pi, n), np.linspace(0, 2 * np.pi, n))
    P = np.stack([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)], -1).reshape(-1, 3)
    i = np.arange(n * n).reshape(n, n)
    F = np.concatenate([np.stack([i[:-1, :-1], i[1:, :-1], i[:-1, 1:]], -1).reshape(-1, 3), np.stack([i[1:, :-1], i[1:, 1:], i[:-1, 1:]], -1).reshape(-1, 3)])
    return P, F


def test_decimation_keeps_the_shape_and_skintokens_rigs_the_decimated_mesh():
    import numpy as np
    tmp = Path(tempfile.mkdtemp())
    P, F = _sphere()
    big = ir.write_glb(tmp / "big.glb", P, F)
    st = ir.glb_inspect(big)
    assert st["triangles"] == len(F) and all(abs(x - 2.0) < 0.01 for x in st["size"]) and st["surfaces"] == 1
    small = ir.decimate(big, tmp / "small.glb", 1500)
    st2 = ir.glb_inspect(small)
    assert 1000 < st2["triangles"] < 2200 and all(abs(x - 2.0) < 0.05 for x in st2["size"]), st2
    out = tmp / "out"
    out.mkdir()
    rigged = _glb(tmp / "rigged.glb", tris=1500, joints=22)
    fake = FakeClient([], answers={"/run_gradio": ("done", {"value": str(rigged), "__type__": "update"})})
    dest = ir.rig_skintokens(big, out, "tok", faces=1500, client=fake)
    api, kw = fake.calls[0]
    sent = Path(kw["files"][0]["path"] if isinstance(kw["files"][0], dict) else kw["files"][0])
    assert api == "/run_gradio" and len(kw["files"]) == 1
    assert (out / "rig_input.glb").exists() and ir.glb_inspect(out / "rig_input.glb")["triangles"] < 2200, "the mesh sent is the decimated one"
    assert dest.name == "rig_skintokens.glb" and ir.glb_inspect(dest)["joints"] == 22
    empty = FakeClient([], answers={"/run_gradio": ("Error: no skeleton found", None)})
    try:
        ir.rig_skintokens(big, out, "tok", faces=1500, client=empty)
        assert False
    except ir.SpaceError as e:
        assert "no skeleton found" in str(e) and "it answered" in str(e)


def test_the_front_view_providers_make_the_calls_their_spaces_expect():
    tmp = Path(tempfile.mkdtemp())
    out = tmp / "out"
    out.mkdir()
    front = tmp / "front.png"
    Image.new("RGBA", (8, 8)).save(front)
    glb = _glb(tmp / "m.glb")
    sf = FakeClient([], answers={"/run_button": ({"value": str(tmp / "bg.png")}, {"value": str(glb), "__type__": "update"})})
    assert ir.geo_sf3d(front, out, "t", client=sf).name == "mesh_sf3d.glb"
    assert sf.calls[0][0] == "/run_button" and sf.calls[0][1]["remesh_option"] == "None" and sf.calls[0][1]["vertex_count"] == -1
    tr = FakeClient([], answers={"/extract_glb": (str(glb), str(glb))})
    assert ir.geo_trellis2(front, out, "t", faces=50000, client=tr).name == "mesh_trellis2.glb"
    assert [c[0] for c in tr.calls] == ["/start_session", "/image_to_3d", "/extract_glb"] and tr.calls[2][1]["decimation_target"] == 50000
    px = FakeClient([], answers={"/generate_3d": ({"state": "/tmp/gradio/abc/state.pt"},), "/extract_glb_api": ({"path": "/home/user/app/tmp/m.glb", "url": "x"},)})
    real_fetch, ir.fetch = ir.fetch, (lambda c, h, dest, tok: Path(shutil.copyfile(glb, dest)))
    try:
        assert ir.geo_pixal3d(front, out, "t", client=px).name == "mesh_pixal3d.glb"
    finally:
        ir.fetch = real_fetch
    assert [c[0] for c in px.calls] == ["/generate_3d", "/extract_glb_api"]
    assert px.calls[1][1]["state_path"] == "/tmp/gradio/abc/state.pt" and px.calls[1][1]["session_id"] == px.calls[0][1]["session_id"]
    lost = FakeClient([], answers={"/generate_3d": ("nothing",)})
    try:
        ir.geo_pixal3d(front, out, "t", client=lost)
        assert False
    except ir.SpaceError as e:
        assert "no state path" in str(e)


def test_painting_from_the_views_recovers_a_known_colour_field_and_hidden_sides_stay_separate():
    import numpy as np
    P, F = _sphere(90)
    tmp = Path(tempfile.mkdtemp())
    views, S, up = {}, 256, np.array([0, 1.0, 0])
    j, i = np.meshgrid(np.arange(S), np.arange(S))
    uu, vv = (j - (S - 1) / 2) / 100.0, ((S - 1) / 2 - i) / 100.0
    inside = uu * uu + vv * vv < 1
    ww = np.sqrt(np.clip(1 - uu * uu - vv * vv, 0, 1))
    for slot, (d, r) in ir.CAMERAS.items():
        d, r = np.array(d, float), np.array(r, float)
        pt = uu[..., None] * r + vv[..., None] * up + ww[..., None] * (-d)         # the world point each pixel sees
        rgba = np.zeros((S, S, 4))
        rgba[..., :3], rgba[..., 3] = pt * 0.5 + 0.5, inside
        Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8)).save(tmp / (slot + ".png"))
        views[slot] = tmp / (slot + ".png")
    col, stats = ir.paint_vertices(P, F, views)
    err = np.abs(col - (P * 0.5 + 0.5)).mean(axis=1)
    belt = np.abs(P[:, 1]) < 0.7                                    # away from the poles, where no camera looks squarely
    assert np.median(err[belt]) < 0.03 and np.percentile(err[belt], 90) < 0.08, (np.median(err[belt]), np.percentile(err[belt], 90))
    assert all(stats[s]["silhouette_iou"] > 0.9 for s in ir.CAMERAS), stats
    assert stats["unseen_vertices"] < 0.25, stats            # the polar caps (a lat-long sphere packs many vertices there) face no side camera
    # only the front view: the far side is not painted from it (it takes the nearest coloured vertex, never the front's own colours)
    one, st1 = ir.paint_vertices(P, F, {"front": views["front"]})
    back = P[:, 2] < -0.9
    assert st1["unseen_vertices"] > 0.3 and back.any()
    out = tmp / "painted.glb"
    ir.write_glb(out, P, F, ir._srgb_to_linear(col))
    assert ir.glb_inspect(out)["triangles"] == len(F)
    ir.preview(out, tmp / "p.png", size=64)
    assert (tmp / "p.png").exists()


def test_unirig_cpu_and_gpu_spaces_are_called_the_way_each_expects():
    tmp = Path(tempfile.mkdtemp())
    out = tmp / "out"
    out.mkdir()
    mesh = _glb(tmp / "m.glb", tris=900, joints=0)
    rigged = _glb(tmp / "r.glb", tris=900, joints=44)
    cpu = FakeClient([], answers={"/process_pipeline": ({"value": str(rigged), "__type__": "update"},)})
    dest = ir.rig_unirig(mesh, out, "t", "cpu", client=cpu)
    assert cpu.calls[0][0] == "/process_pipeline" and cpu.calls[0][1]["output_format"] == "glb" and dest.name == "rig_unirig_cpu.glb"
    gpu = FakeClient([], answers={"/rig_model": (str(rigged), "ok")})
    dest = ir.rig_unirig(mesh, out, "t", "gpu", client=gpu)
    assert gpu.calls[0][0] == "/rig_model" and "input_glb" in gpu.calls[0][1] and ir.glb_inspect(dest)["joints"] == 44


def test_every_command_the_cli_offers_is_wired():
    tmp = Path(tempfile.mkdtemp())
    P, F = _sphere(30)
    g = ir.write_glb(tmp / "a.glb", P, F)
    views = _views(tmp / "v")
    assert ir.main(["inspect", str(g)]) == 0
    assert ir.main(["decimate", str(g), str(tmp / "b.glb"), "--faces", "300"]) == 0 and (tmp / "b.glb").exists()
    assert ir.main(["preview", str(g), str(tmp / "p.png")]) == 0 and (tmp / "p.png").exists()
    assert ir.main(["paint", str(g), str(views), str(tmp / "c.glb"), "--faces", "2000"]) == 0 and (tmp / "c.glb").exists()
    assert ir.main(["run", str(tmp / "nowhere")]) == 2           # a refusal, not a traceback


def test_tencent_jobs_are_submitted_polled_downloaded_and_refusals_say_why():
    calls, key = [], "sk-" + "Z" * 40
    out = Path(tempfile.mkdtemp())

    def fake_post(path, body, k):
        calls.append((path, body))
        if path.endswith("submit"):
            return 200, {"id": "42", "status": "queued"}
        n = sum(1 for c in calls if c[0].endswith("query"))
        return 200, ({"status": "in_progress"} if n < 2 else {"status": "completed", "data": [{"type": "fbx", "url": "https://cos.example/y.fbx?q-sign=1"}]})

    class Resp:
        def read(self):
            return b"FBXDATA"
    real = (ir.tencent_post, ir.urllib.request.urlopen)
    try:
        ir.tencent_post = fake_post
        ir.urllib.request.urlopen = lambda *a, **k: Resp()
        files = ir.tencent_job("rig", {"file_3d": {"url": "https://m/a.glb"}, "motion_type": 1}, key, out, poll=0)
        assert calls[0][1] == {"file_3d": {"url": "https://m/a.glb"}, "motion_type": 1, "model": "hy-3d-rigging"}
        assert calls[1][0].endswith("query") and calls[1][1] == {"model": "hy-3d-rigging", "id": "42"}
        assert files[0].name == "rig_0.fbx" and files[0].read_bytes() == b"FBXDATA"
        ir.tencent_post = lambda p, b, k: (400, {"Type": 2, "Code": 1001, "Msg": "file_3d is required for hy-3d-texture model"})
        try:
            ir.tencent_job("texture", {}, key, out)
            assert False
        except ir.TencentError as e:
            assert "file_3d is required" in str(e) and "HTTP 400" in str(e)
        ir.tencent_post = lambda p, b, k: (200, {"id": "", "status": "failed", "error": {"message": "The parameter is abnormal %s" % key, "code": "InvalidParameter.InvalidParameter"}})
        os.environ["TENCENT_HY3D_KEY"] = key
        try:
            ir.tencent_job("texture", {}, key, out)
            assert False
        except ir.TencentError as e:
            assert "InvalidParameter" in str(e) and key not in str(e), "the key never appears in a message"
        finally:
            os.environ.pop("TENCENT_HY3D_KEY", None)
    finally:
        ir.tencent_post, ir.urllib.request.urlopen = real


def test_a_local_mesh_is_never_published_without_the_explicit_flag_and_bodies_follow_the_field_rules():
    tmp = Path(tempfile.mkdtemp())
    mesh = _glb(tmp / "m.glb")
    assert ir.tencent_input("https://host/a.glb", None) == "https://host/a.glb"
    try:
        ir.tencent_input(str(mesh), None)
        assert False, "a local file must not leave the machine unasked"
    except ir.Refused as e:
        assert "--stage" in str(e) and "tmpfiles" in str(e)
    real = ir.STAGES["tmpfiles"]
    ir.STAGES["tmpfiles"] = (real[0], real[1], lambda path: "https://tmp.example/dl/" + Path(path).name)
    try:
        assert ir.tencent_input(str(mesh), "tmpfiles") == "https://tmp.example/dl/m.glb"
    finally:
        ir.STAGES["tmpfiles"] = real
    img = tmp / "f.png"
    Image.new("RGB", (8, 8), (200, 10, 10)).save(img)
    a = Namespace(image=str(img), prompt=None, pbr=False, texture_size=2048, motion_type=1, face_level="low", polygon_type="triangle", set=["foo=3", "bar=x"])
    body = ir.tencent_body("texture", "https://m/a.glb", a)
    assert body["file_3d"] == {"url": "https://m/a.glb"} and body["enable_pbr"] is False and body["texture_size"] == 2048
    assert body["foo"] == 3 and body["bar"] == "x" and len(body["image"]["base64"]) > 20, "the image goes inline as base64, in an object"
    assert ir.tencent_body("rig", "https://m/a.glb", a)["motion_type"] == 1
    assert ir.tencent_body("retopo", "https://m/a.glb", a)["face_level"] == "low"
    try:
        ir.tencent_body("texture", "u", Namespace(image=None, prompt=None, pbr=False, texture_size=1, motion_type=1, face_level="", polygon_type="", set=None))
        assert False
    except ir.Refused:
        pass
    os.environ["TENCENT_HY3D_KEY"] = "sk-" + "Q" * 40
    try:
        assert ir.main(["tencent", "rig", str(mesh)]) == 2, "a local mesh without --stage is refused before any network call"
    finally:
        os.environ.pop("TENCENT_HY3D_KEY", None)


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
                    steps=5, octree=256, shape_only=False, texture=1024, rig_faces=30000, target_faces=0, min_gpu=90.0, max_credits=60.0, force=False)
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
