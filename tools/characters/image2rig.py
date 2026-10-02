#!/usr/bin/env python3
"""Six views of a character (multiview.py) to a textured 3D mesh, a rig and parts, on free Hugging Face Spaces and the Tripo API.
Adapted from the user's draft (image2rig.py): the transport is gradio_client and the Tripo SDK instead of hand-rolled HTTP, the views come from
multiview.py's cut-outs, nothing spends without a guard, and no key is ever printed.

    python tools/characters/image2rig.py doctor                      # keys (set or not), account, ZeroGPU quota, Tripo credits, Spaces up or down
    python tools/characters/image2rig.py run witch_green_t2          # build/views/NAME/views/*.png -> build/rigs/NAME/  (free Space, one GPU run)
    python tools/characters/image2rig.py run witch_green_t2 --rig skintokens --parts   # more stages: each uses quota, so each is asked for
    python tools/characters/image2rig.py decimate in.glb out.glb --faces 30000       # local quadric decimation (free); --rig does it for you
    python tools/characters/image2rig.py run witch_green_t2 --geometry tripo --rig tripo --max-credits 60    # Tripo: credits, not quota
    python tools/characters/image2rig.py inspect a.glb b.glb         # triangles, joints, textures, size, and the gap to the game's budget
    python tools/characters/image2rig.py preview a.glb out.png       # four views of a mesh (flat shaded, textured when it has a texture), no GPU

Two budgets, and the quota is the tight one (free account: 300 GPU-seconds and 8 runs a day, rolling 24 h from the first call):
* **Spaces** (Hunyuan3D-2mv for geometry from the four views, SkinTokens to rig THAT mesh, AniGen for its own mesh with a skeleton from the front view, Hunyuan3D-Part for parts)
  are for sampling and validating. Every GPU call is checked against the live quota first (`--min-gpu`) and the seconds it really cost are written to
  the manifest. A provider that rejects a call for its GPU duration says so: lower `--steps` or `--octree`, or wait for the reset.
* **Tripo** (multiview to model, rig) is for volume: credits. The balance must cover `--max-credits` before anything is sent; the spend is measured.

Keys (never printed, not even in part): HUGGINGFACE_TOKEN (Hugging Face; HF_TOKEN is the fallback; NOT the Higgsfield HF_KEY) and TRIPO_API_KEY,
from the environment or the git-ignored .env.local. `run` does the geometry stage only; --rig and --parts are opt-in. Results are kept in build/rigs/NAME/ with manifest.json;
a stage whose inputs and settings are unchanged is not run again (--force).

The generated mesh is a REFERENCE, not a game asset: the game's characters are at most 9000 triangles in 2 surfaces with a 256 px atlas and a fixed
skeleton (tests/render/test_character_models.gd); `inspect` lists the gap. Decimating and retargeting onto the game's bones is a separate step.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ENV_FILE = Path(os.getenv("HF_ENV_FILE") or ROOT / ".env.local")
HF_NAMES = ("HUGGINGFACE_TOKEN", "HF_TOKEN")     # ours first: HF_TOKEN is what every other Hugging Face tool reads, so it may hold another account's token
SECRETS = HF_NAMES + ("TRIPO_API_KEY", "HF_KEY")

SLOTS = ("front", "left", "back", "right")           # Tripo's order; Hunyuan3D-2mv names the same four
SPACES = {"hunyuan2mv": "tencent/Hunyuan3D-2mv", "skintokens": "VAST-AI/SkinTokens", "anigen": "VAST-AI/AniGen", "parts": "tencent/Hunyuan3D-Part"}
GAME = {"triangles": 9000, "surfaces": 2, "texture": 256}
GEOMETRY = ("hunyuan2mv", "tripo")
RIGS = ("skintokens", "anigen", "tripo")


class Refused(Exception):
    """A guard stopped the call before anything was spent."""


class QuotaError(Exception):
    """A Space said no: quota, or the GPU duration it was asked for."""


class SpaceError(Exception):
    """A Space failed inside its own pipeline."""


# ---- keys -------------------------------------------------------------------------------------------------------------
ENV_BEFORE = frozenset(n for n in SECRETS if os.environ.get(n))      # the keys the environment itself already had: they win over the file


def source(name):
    """Where a key comes from: a real environment variable wins over .env.local (the repo's convention, as in hf.py)."""
    return "environment" if name in ENV_BEFORE else (".env.local" if secret(name) else "missing")


def load_env(path=None):
    path = Path(path or ENV_FILE)
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip("\"'"))


def secret(name):
    load_env()
    return os.environ.get(name, "").strip()


def hf_var():
    """The name of the variable the Hugging Face token comes from ('' if none)."""
    load_env()
    return next((n for n in HF_NAMES if os.environ.get(n, "").strip()), "")


def hf_token():
    return secret(hf_var()) if hf_var() else ""


def redact(text):
    for name in SECRETS:
        v = os.environ.get(name, "")
        if len(v) > 8:
            text = str(text).replace(v, "<%s>" % name)
    return str(text)


def log(stage, msg):
    print("[%s] %s" % (stage, redact(msg)), flush=True)


def _get_json(url, token=""):
    req = urllib.request.Request(url, headers={"User-Agent": "image2rig", **({"Authorization": "Bearer " + token} if token else {})})
    return json.loads(urllib.request.urlopen(req, timeout=30).read().decode("utf-8"))


# ---- the views (multiview.py's output) --------------------------------------------------------------------------------
def find_views(source, overrides=()):
    """{slot: path} from a multiview.py result (a name under build/views, or a folder with views/ or the PNGs themselves). The 3/4 views are
    not used: the services take four. `overrides`: 'slot=path' strings."""
    src = Path(source)
    folder = src if src.is_dir() else ROOT / "build/views" / str(source)
    folder = folder / "views" if (folder / "views").is_dir() else folder
    views = {s: folder / (s + ".png") for s in SLOTS if (folder / (s + ".png")).exists()}
    for item in overrides:
        slot, _, path = item.partition("=")
        if slot not in SLOTS or not Path(path).exists():
            raise Refused("bad --view %r (slots: %s)" % (item, ", ".join(SLOTS)))
        views[slot] = Path(path)
    if "front" not in views:
        raise Refused("no front view in %s: run tools/characters/multiview.py first" % folder)
    return views


def all_transparent(views):
    from PIL import Image
    for p in views.values():
        im = Image.open(p)
        if im.mode != "RGBA" or im.getchannel("A").getextrema()[0] == 255:
            return False
    return True


def sha(*paths_or_text):
    h = hashlib.sha256()
    for x in paths_or_text:
        h.update(Path(x).read_bytes() if isinstance(x, Path) else str(x).encode())
    return h.hexdigest()[:16]


# ---- budgets ----------------------------------------------------------------------------------------------------------
def zerogpu(token):
    """{'seconds': GPU seconds left, 'runs': runs left} or None without a token."""
    if not token:
        return None
    try:
        q = _get_json("https://huggingface.co/api/spaces/zero-gpu/quota", token)
        return {"seconds": float(q.get("current", 0)), "runs": int((q.get("runs") or {}).get("remaining", 0)), "raw": q}
    except Exception as e:
        return {"error": redact(e)[:120]}


def gpu_guard(token, min_seconds):
    q = zerogpu(token)
    if q is None:
        raise Refused("no Hugging Face token: an anonymous call gets about 2 GPU-minutes a day; put HUGGINGFACE_TOKEN in the environment or .env.local")
    if "error" in q:
        raise Refused("cannot read the ZeroGPU quota (%s)" % q["error"])
    if q["seconds"] < min_seconds or q["runs"] < 1:
        raise Refused("ZeroGPU quota too low: %.0f s and %d runs left (needs %.0f s). It resets 24 h after the first call of the window."
                      % (q["seconds"], q["runs"], min_seconds))
    return q


def tripo_guard(balance, max_credits):
    if balance < max_credits:
        raise Refused("Tripo balance is %g credits, below --max-credits %g: nothing was sent. Claim the signup credits or lower the cap." % (balance, max_credits))


# ---- Spaces (gradio_client) -------------------------------------------------------------------------------------------
def make_client(space, token):
    from gradio_client import Client
    return Client(space, token=token or None, verbose=False)


def call(client, api_name, **kw):
    try:
        return client.predict(api_name=api_name, **kw)
    except Exception as e:
        msg = redact(e)
        if re.search(r"quota|GPU duration|exceeded|ZeroGPU", msg, re.I):
            raise QuotaError("%s refused %s: %s. Lower --steps/--octree where the provider has them; a request above the account's per-call cap (SkinTokens asks for 450 s) "
                             "cannot run on this tier at all: that needs a bigger account or your own GPU." % (client.src, api_name, msg[:200]))
        hint = " (its own PyMeshLab step failed; the Hunyuan texture stage did this on the witch at 5 and 30 steps and at octree 192 and 256: use --shape-only and texture elsewhere)" if "PyMeshLab" in msg else ""
        raise SpaceError("%s failed in %s: %s%s" % (client.src, api_name, msg[:200], hint))


def _files(result):
    """Mesh paths in a Space's answer: plain paths, or the dicts Gradio uses for an updated component ({'value': path, '__type__': 'update'})."""
    found = []
    for r in result if isinstance(result, (list, tuple)) else [result]:
        if isinstance(r, dict):
            r = r.get("value") or r.get("path") or r.get("name")
            r = r.get("path") if isinstance(r, dict) else r
        if isinstance(r, str) and r.lower().endswith((".glb", ".obj", ".ply", ".fbx")):
            found.append(r)
    return found


def geo_hunyuan2mv(views, out, token, steps=5, octree=256, textured=True, target_faces=0, seed=1234, client=None):
    """Hunyuan3D-2mv from the four views (shape, then texture). `steps` 5 is the Space's Turbo mode: the quota is 300 s a day."""
    from gradio_client import handle_file
    c = client or make_client(SPACES["hunyuan2mv"], token)
    api = "/generation_all" if textured else "/shape_generation"
    args = dict(caption="", image=None, steps=steps, guidance_scale=5.0, seed=seed, octree_resolution=octree,
                check_box_rembg=not all_transparent(views), num_chunks=8000, randomize_seed=False)
    for slot in SLOTS:
        args["mv_image_" + slot] = handle_file(str(views[slot])) if slot in views else None
    result = call(c, api, **args)
    files = _files(result)
    if not files:
        raise SpaceError("hunyuan2mv returned no mesh file; it answered %s" % redact(repr(result))[:400])
    mesh = files[-1]                                   # generation_all: the white mesh, then the textured one
    if target_faces:
        exp = call(c, "/on_export_click", file_out=handle_file(mesh), file_out2=handle_file(mesh), file_type="glb", reduce_face=True,
                   export_texture=textured, target_face_num=target_faces)
        mesh = (_files(exp) or [mesh])[-1]
    dest = out / (("mesh_" if textured else "shape_") + "hunyuan2mv.glb")
    shutil.copyfile(mesh, dest)
    return dest


def rig_anigen(front, out, token, texture=1024, client=None):
    """AniGen: a skinned, textured mesh with a skeleton from the FRONT view alone (it invents the back; it does not use the other views).
    /extract_glb answers the skinned mesh first and a skeleton visualisation second (the draft had them the other way round)."""
    from gradio_client import handle_file
    c = client or make_client(SPACES["anigen"], token)
    call(c, "/prepare_input_for_generation", image=handle_file(str(front)))
    call(c, "/generate_preview")
    files = _files(call(c, "/extract_glb", texture_size=texture, simplify_ratio=0.95, fill_holes=True))
    if not files:
        raise SpaceError("anigen returned no mesh")
    dest = out / "rig_anigen.glb"
    shutil.copyfile(files[0], dest)
    if len(files) > 1:
        shutil.copyfile(files[1], out / "skeleton_anigen.glb")
    return dest


def rig_skintokens(mesh, out, token, faces=30000, client=None):
    """VAST-AI/SkinTokens: skeleton and skin weights for a MESH (any: it does not make its own), so the best geometry can be the one that is rigged.
    The mesh is decimated first (`faces`): a Space cannot take half a million triangles."""
    from gradio_client import handle_file
    src = Path(mesh)
    if glb_inspect(src).get("triangles", 0) > faces:
        src = decimate(src, out / "rig_input.glb", faces)
    c = client or make_client(SPACES["skintokens"], token)
    res = call(c, "/run_gradio", files=[handle_file(str(src))])
    files = _files(res)
    if not files:
        raise SpaceError("skintokens returned no rigged mesh; it answered %s" % redact(repr(res))[:500])
    dest = out / "rig_skintokens.glb"
    shutil.copyfile(files[-1], dest)
    return dest


def parts_hunyuan(mesh, out, token, client=None):
    from gradio_client import handle_file
    c = client or make_client(SPACES["parts"], token)
    got = []
    for i, f in enumerate(_files(call(c, "/generate", mesh_path=handle_file(str(mesh)), seed=42))):
        dest = out / ("parts_%d.glb" % i)
        shutil.copyfile(f, dest)
        got.append(dest)
    if not got:
        raise RuntimeError("hunyuan-part returned no mesh")
    return got


# ---- Tripo (the vendor SDK, v2 API) -----------------------------------------------------------------------------------
def tripo_balance(key):
    import asyncio
    from tripo3d import TripoClient

    async def go():
        async with TripoClient(api_key=key) as c:
            return float((await c.get_balance()).balance)
    return asyncio.run(go())


def tripo_job(views, out, key, max_credits, rig=False, spec="tripo", face_limit=0, version="v2.5-20250123"):
    """multiview_to_model, then (rig) animate_rig on that task. Returns ({'mesh': path, 'rig': path|None}, credits spent)."""
    import asyncio
    from tripo3d import RigSpec, TripoClient

    async def go():
        async with TripoClient(api_key=key) as c:
            before = float((await c.get_balance()).balance)
            tripo_guard(before, max_credits)
            tid = await c.multiview_to_model([str(views[s]) if s in views else None for s in SLOTS], model_version=version,
                                             face_limit=face_limit or None, texture=True, pbr=True)
            task = await c.wait_for_task(tid, verbose=True)
            files = await c.download_task_models(task, str(out))
            made = {"mesh": _pick_tripo(files, out / "mesh_tripo.glb"), "rig": None}
            if rig:
                rid = await c.rig_model(tid, out_format="glb", spec=RigSpec.MIXAMO if spec == "mixamo" else RigSpec.TRIPO)
                files = await c.download_task_models(await c.wait_for_task(rid, verbose=True), str(out))
                made["rig"] = _pick_tripo(files, out / "rig_tripo.glb")
            return made, before - float((await c.get_balance()).balance)
    return asyncio.run(go())


def _pick_tripo(files, dest):
    pick = files.get("pbr_model") or files.get("model") or next(iter(files.values()), None)
    if not pick:
        raise RuntimeError("tripo returned no model file")
    shutil.copyfile(pick, dest)
    return dest


# ---- inspecting a GLB (no dependencies) -------------------------------------------------------------------------------
def _image_size(b):
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", b[16:24])
    if b[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(b):
            if b[i] != 0xFF:
                break
            m, ln = b[i + 1], struct.unpack(">H", b[i + 2:i + 4])[0]
            if m in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", b[i + 5:i + 9])
                return w, h
            i += 2 + ln
    return None


def glb_inspect(path):
    """{'triangles','vertices','surfaces','joints','joint_names','animations','textures': [sizes], 'size': [x,y,z] m, 'bytes'} of a .glb."""
    raw = Path(path).read_bytes()
    st = {"bytes": len(raw), "ok": False}
    if raw[:4] != b"glTF":
        return st
    off, gltf, binary = 12, None, b""
    while off + 8 <= len(raw):
        ln, kind = struct.unpack("<II", raw[off:off + 8])
        chunk = raw[off + 8:off + 8 + ln]
        if kind == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = chunk
        off += 8 + ln + (-ln % 4)
    if gltf is None:
        return st
    acc = gltf.get("accessors") or []
    tris = verts = surfaces = 0
    lo, hi = [float("inf")] * 3, [float("-inf")] * 3
    for m in gltf.get("meshes") or []:
        for p in m.get("primitives") or []:
            surfaces += 1
            pos = (p.get("attributes") or {}).get("POSITION")
            if pos is None:
                continue
            verts += acc[pos].get("count", 0)
            n = acc[p["indices"]]["count"] if p.get("indices") is not None else acc[pos]["count"]
            tris += n // 3 if p.get("mode", 4) == 4 else 0
            if "min" in acc[pos] and "max" in acc[pos]:
                lo = [min(a, b) for a, b in zip(lo, acc[pos]["min"])]
                hi = [max(a, b) for a, b in zip(hi, acc[pos]["max"])]
    skins = gltf.get("skins") or []
    nodes = gltf.get("nodes") or []
    joints = max((len(s.get("joints") or []) for s in skins), default=0)
    names = [nodes[j].get("name", "") for j in (skins[0].get("joints") or [])] if skins else []
    sizes = []
    for im in gltf.get("images") or []:
        if "bufferView" in im:
            bv = gltf["bufferViews"][im["bufferView"]]
            sizes.append(_image_size(binary[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + 32 + bv["byteLength"]]))
        else:
            sizes.append(None)
    st.update(ok=True, triangles=tris, vertices=verts, surfaces=surfaces, joints=joints, joint_names=names, animations=len(gltf.get("animations") or []),
              textures=sizes, size=[round(h - l, 3) for l, h in zip(lo, hi)] if all(x != float("inf") for x in lo) else None)
    return st


def game_fit(st):
    """What stands between this mesh and the game's characters (tests/render/test_character_models.gd)."""
    notes = []
    if st.get("triangles", 0) > GAME["triangles"]:
        notes.append("%d triangles, the game allows %d: decimate" % (st["triangles"], GAME["triangles"]))
    if st.get("surfaces", 0) > GAME["surfaces"]:
        notes.append("%d surfaces, the game allows %d: merge materials into one atlas" % (st["surfaces"], GAME["surfaces"]))
    big = [s for s in st.get("textures", []) if s and max(s) > GAME["texture"]]
    if big:
        notes.append("texture %dx%d, the game's atlas is %d px: bake down and snap to the 5-bit palette" % (big[0][0], big[0][1], GAME["texture"]))
    if st.get("joints"):
        notes.append("%d joints named like %s: retarget onto the game's bones (root, hips, spine, ...)" % (st["joints"], ", ".join(st["joint_names"][:3])))
    else:
        notes.append("no skeleton: rig it before it can be animated")
    return notes


def score(st):
    """A tie-breaker between candidate meshes (--all): textured, mid-density, taller than wide."""
    if not st.get("ok") or not st.get("triangles"):
        return 0.0
    s = 1.0 + (1.2 if any(st["textures"]) else 0) + 0.5 * bool(st["joints"])
    if st["triangles"] < 25000:
        s *= 0.45 + 0.55 * st["triangles"] / 25000
    if st.get("size") and max(st["size"][0], st["size"][2]) > 0:
        s *= 0.75 + 0.25 * min(st["size"][1] / max(st["size"][0], st["size"][2]) / 1.6, 1.0)
    return s


_DTYPES = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load_glb(path):
    """(gltf json, binary chunk) of a .glb."""
    raw = Path(path).read_bytes()
    off, gltf, binary = 12, None, b""
    while off + 8 <= len(raw):
        ln, kind = struct.unpack("<II", raw[off:off + 8])
        if kind == 0x4E4F534A:
            gltf = json.loads(raw[off + 8:off + 8 + ln].decode("utf-8"))
        elif kind == 0x004E4942:
            binary = raw[off + 8:off + 8 + ln]
        off += 8 + ln + (-ln % 4)
    return gltf, binary


def accessor(gltf, binary, idx):
    import numpy as np
    a = gltf["accessors"][idx]
    bv = gltf["bufferViews"][a["bufferView"]]
    dt, w = np.dtype(_DTYPES[a["componentType"]]), _WIDTH[a["type"]]
    start, stride = bv.get("byteOffset", 0) + a.get("byteOffset", 0), bv.get("byteStride") or dt.itemsize * w
    buf = np.frombuffer(binary, np.uint8, count=stride * (a["count"] - 1) + dt.itemsize * w, offset=start)
    rows = np.lib.stride_tricks.as_strided(buf, (a["count"], dt.itemsize * w), (stride, 1))
    out = np.ascontiguousarray(rows).view(dt).reshape(a["count"], w)
    return out.astype(np.float64) if dt.kind == "f" else out.astype(np.int64)


def write_glb(path, positions, faces):
    """A bare triangle mesh as a .glb (positions, vertex normals, one grey material)."""
    import numpy as np
    P, F = np.asarray(positions, np.float32), np.asarray(faces, np.uint32)
    N = np.zeros_like(P)
    tri = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    for k in range(3):
        np.add.at(N, F[:, k], tri)
    N = (N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)).astype(np.float32)
    blob = P.tobytes() + N.tobytes() + F.tobytes()
    gltf = {"asset": {"version": "2.0", "generator": "image2rig"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "mesh"}],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 0}]}],
            "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.7, 0.7, 0.7, 1], "metallicFactor": 0, "roughnessFactor": 0.9}}],
            "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(P), "type": "VEC3", "min": P.min(0).tolist(), "max": P.max(0).tolist()},
                          {"bufferView": 1, "componentType": 5126, "count": len(N), "type": "VEC3"},
                          {"bufferView": 2, "componentType": 5125, "count": F.size, "type": "SCALAR"}],
            "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": P.nbytes}, {"buffer": 0, "byteOffset": P.nbytes, "byteLength": N.nbytes},
                            {"buffer": 0, "byteOffset": P.nbytes + N.nbytes, "byteLength": F.nbytes}],
            "buffers": [{"byteLength": len(blob)}]}
    js = json.dumps(gltf).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + blob
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)
    return Path(path)


def decimate(src, dest, faces):
    """Quadric decimation of every mesh in a .glb to about `faces` triangles (fast_simplification; the texture is dropped), vertices welded first."""
    import numpy as np
    import fast_simplification
    gltf, binary = load_glb(src)
    pts, tris, base = [], [], 0
    for m in gltf["meshes"]:
        for prim in m["primitives"]:
            pos = accessor(gltf, binary, prim["attributes"]["POSITION"])
            idx = accessor(gltf, binary, prim["indices"]).reshape(-1, 3) if "indices" in prim else np.arange(len(pos)).reshape(-1, 3)
            pts.append(pos)
            tris.append(idx + base)
            base += len(pos)
    P, F = np.concatenate(pts), np.concatenate(tris)
    keys = np.round(P * 1e5).astype(np.int64)
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    P, F = P[first], inverse.reshape(-1)[F]
    F = F[(F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])]
    if len(F) > faces:
        P, F = fast_simplification.simplify(P.astype(np.float32), F.astype(np.int32), target_reduction=1.0 - faces / len(F))
    return write_glb(dest, P, F)


def preview(path, dest, size=480):
    """Four orthographic views (0, 90, 180, 270 degrees round the up axis) of the first mesh, painter's algorithm, flat key light, the base colour
    texture sampled at each face's centre (grey without one). A judgement aid, not the game's renderer."""
    import numpy as np
    from PIL import Image, ImageDraw
    gltf, binary = load_glb(path)
    tris, uvs, colours = [], [], []
    for m in gltf["meshes"]:
        for prim in m["primitives"]:
            pos = accessor(gltf, binary, prim["attributes"]["POSITION"])
            idx = accessor(gltf, binary, prim["indices"]).reshape(-1, 3) if "indices" in prim else np.arange(len(pos)).reshape(-1, 3)
            tris.append(pos[idx])
            tc = prim["attributes"].get("TEXCOORD_0")
            uvs.append(accessor(gltf, binary, tc)[idx].mean(axis=1) if tc is not None else np.full((len(idx), 2), np.nan))
            mat = (gltf.get("materials") or [{}])[prim.get("material", 0)] if gltf.get("materials") else {}
            colours.append(np.tile(np.array(mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [0.7, 0.7, 0.7, 1])[:3]), (len(idx), 1)))
    T, UV, C = np.concatenate(tris), np.concatenate(uvs), np.concatenate(colours)
    tex = None
    try:
        t = (gltf["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"])
        bv = gltf["bufferViews"][gltf["images"][gltf["textures"][t]["source"]]["bufferView"]]
        tex = np.asarray(Image.open(__import__("io").BytesIO(binary[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])).convert("RGB"))
    except (KeyError, IndexError, TypeError):
        pass
    if tex is not None and not np.isnan(UV).all():
        u = (np.nan_to_num(UV[:, 0]) % 1.0 * (tex.shape[1] - 1)).astype(int)
        v = (np.nan_to_num(UV[:, 1]) % 1.0 * (tex.shape[0] - 1)).astype(int)
        C = tex[v, u] / 255.0
    lo, hi = T.reshape(-1, 3).min(0), T.reshape(-1, 3).max(0)
    centre, span = (lo + hi) / 2, float((hi - lo).max())
    sheet = Image.new("RGB", (size * 4, size), (30, 30, 34))
    for k, az in enumerate((0, 90, 180, 270)):
        c, s_ = np.cos(np.radians(az)), np.sin(np.radians(az))
        R = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
        P = (T - centre) @ R.T
        n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        facing = n[:, 2] > 0
        shade = 0.35 + 0.65 * np.clip(n @ np.array([-0.3, 0.5, 0.8]), 0, 1)
        order = np.argsort(P[:, :, 2].mean(axis=1))
        im = Image.new("RGB", (size, size), (30, 30, 34))
        d = ImageDraw.Draw(im)
        px = (P[..., :2] * np.array([1, -1]) / span * size * 0.92 + size / 2)
        for i in order:
            if facing[i]:
                d.polygon([tuple(q) for q in px[i]], fill=tuple((np.clip(C[i] * shade[i], 0, 1) * 255).astype(int)))
        sheet.paste(im, (k * size, 0))
    Path(dest).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest)
    return dest


def show(path):
    st = glb_inspect(path)
    if not st["ok"]:
        print("%-24s not a readable .glb" % Path(path).name)
        return st
    print("%-24s %7d tris  %d surfaces  %s joints  textures %s  size %s m" % (Path(path).name, st["triangles"], st["surfaces"], st["joints"] or "no",
          [("%dx%d" % t) if t else "?" for t in st["textures"]] or "none", st["size"]))
    for n in game_fit(st):
        print("    - " + n)
    return st


# ---- the run ----------------------------------------------------------------------------------------------------------
def run(a):
    views = find_views(a.source, a.view)
    out = Path(a.out or ROOT / "build/rigs" / Path(a.source).name)
    out.mkdir(parents=True, exist_ok=True)
    mf = out / "manifest.json"
    manifest = json.loads(mf.read_text(encoding="utf-8")) if mf.exists() else {"stages": {}}
    hf, tripo = hf_token(), secret("TRIPO_API_KEY")
    inputs = sha(*[views[s] for s in SLOTS if s in views])
    log("views", "%s (unused: the 3/4 views; the services take four)" % ", ".join(s for s in SLOTS if s in views))
    if len(views) < 4:
        log("views", "! only %d of 4 views: the geometry will be a guess where a view is missing" % len(views))
    manifest["views"] = {s: str(p) for s, p in views.items()}

    def stage(name, key, fn):
        """Runs `fn` unless this stage already ran with the same inputs and settings."""
        k = sha(inputs, key)
        old = manifest["stages"].get(name)
        if old and old.get("key") == k and not a.force and all(Path(f).exists() for f in old["files"]):
            log(name, "unchanged, kept (%s)" % ", ".join(Path(f).name for f in old["files"]))
            return [Path(f) for f in old["files"]]
        before = zerogpu(hf) if name.startswith("space") else None
        t0 = time.time()
        files, extra = fn()
        files = [Path(f) for f in files]
        entry = {"key": k, "files": [str(f) for f in files], "seconds": round(time.time() - t0), **extra}
        if before and "seconds" in before:
            after = zerogpu(hf)
            if after and "seconds" in after:
                entry["gpu_seconds_spent"] = round(before["seconds"] - after["seconds"])
        manifest["stages"][name] = entry
        mf.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        return files

    meshes, tripo_rig, errors = {}, None, []
    for g in [x for x in a.geometry.split(",") if x]:
        if g not in GEOMETRY:
            raise Refused("unknown geometry provider %r (%s)" % (g, ", ".join(GEOMETRY)))
        try:
            if g == "hunyuan2mv":
                gpu_guard(hf, a.min_gpu)
                meshes[g] = stage("space:hunyuan2mv" + (":shape" if a.shape_only else ""), [a.steps, a.octree, a.target_faces, a.shape_only], lambda: (
                    [geo_hunyuan2mv(views, out, hf, a.steps, a.octree, not a.shape_only, a.target_faces)], {}))[0]
            else:
                if not tripo:
                    raise Refused("no TRIPO_API_KEY")
                want_rig = "tripo" in a.rig.split(",")

                def tripo_stage():
                    res, spent = tripo_job(views, out, tripo, a.max_credits, want_rig, a.rig_spec, a.target_faces)
                    return [p for p in (res["mesh"], res["rig"]) if p], {"credits_spent": round(spent, 2)}
                files = stage("tripo", [a.target_faces, want_rig, a.rig_spec], tripo_stage)
                meshes[g], tripo_rig = files[0], (files[1] if len(files) > 1 else None)
        except (Refused, QuotaError, SpaceError) as e:
            errors.append("%s: %s" % (g, redact(e)))
            log("geometry", errors[-1])
            continue
        if not a.all:
            break
    if not meshes:
        raise Refused("no mesh was made (%s)" % "; ".join(errors))
    best = max(meshes, key=lambda g: score(glb_inspect(meshes[g])))
    master = meshes[best]
    log("geometry", "mesh: %s%s" % (master, " (best of %d)" % len(meshes) if len(meshes) > 1 else ""))

    rigged = None
    for r in [x for x in a.rig.split(",") if x]:
        if r not in RIGS:
            raise Refused("unknown rig provider %r (%s)" % (r, ", ".join(RIGS)))
        if r == "tripo":
            if tripo_rig is None:
                raise Refused("Tripo rigs only its own meshes: use --geometry tripo with --rig tripo")
            rigged = tripo_rig
        elif r == "skintokens":
            gpu_guard(hf, a.min_gpu)
            rigged = stage("space:skintokens", [sha(master), a.rig_faces], lambda: ([rig_skintokens(master, out, hf, a.rig_faces)], {}))[0]
        else:
            gpu_guard(hf, a.min_gpu)
            rigged = stage("space:anigen", [a.texture], lambda: ([rig_anigen(views["front"], out, hf, a.texture)], {}))[0]
        log("rig", str(rigged))
        break
    parts = []
    if a.parts:
        gpu_guard(hf, a.min_gpu)
        parts = stage("space:parts", [str(master)], lambda: (parts_hunyuan(master, out, hf), {}))

    print()
    for p in [master] + ([rigged] if rigged else []) + parts:
        show(p)
    manifest["master"] = str(rigged or master)
    mf.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("\nmanifest: %s" % mf)
    return 0


def doctor():
    print("image2rig doctor")
    hf, tripo = hf_token(), secret("TRIPO_API_KEY")
    print("  %-14s %s" % (hf_var() or "HUGGINGFACE_TOKEN", ("set, from the %s" % source(hf_var())) if hf else "MISSING (anonymous: about 2 GPU-minutes a day)"))
    if hf:
        try:
            who = _get_json("https://huggingface.co/api/whoami-v2", hf)
            print("  HF account     @%s  (pro: %s)" % (who.get("name"), who.get("isPro")))
        except Exception as e:
            print("  HF account     token rejected (%s)" % redact(e)[:80])
        q = zerogpu(hf)
        if q and "seconds" in q:
            print("  ZeroGPU        %.0f GPU-seconds and %d runs left (rolling 24 h from the first call)" % (q["seconds"], q["runs"]))
    print("  TRIPO_API_KEY  %s" % (("set, from the %s" % source("TRIPO_API_KEY")) if tripo else "MISSING"))
    if tripo:
        try:
            print("  Tripo credits  %g" % tripo_balance(tripo))
        except Exception as e:
            print("  Tripo credits  cannot read (%s)" % redact(e)[:80])
    for key, sp in SPACES.items():
        try:
            stage = _get_json("https://huggingface.co/api/spaces/" + sp, hf).get("runtime", {}).get("stage")
        except Exception as e:
            stage = "unreachable (%s)" % redact(e)[:50]
        print("  %-14s %-26s %s" % (key, sp, stage))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("doctor")
    i = sub.add_parser("inspect")
    i.add_argument("files", nargs="+")
    dc = sub.add_parser("decimate")
    dc.add_argument("file")
    dc.add_argument("out")
    dc.add_argument("--faces", type=int, default=30000)
    pv = sub.add_parser("preview")
    pv.add_argument("file")
    pv.add_argument("out")
    r = sub.add_parser("run")
    r.add_argument("source", help="a multiview.py result: its name under build/views, or a folder")
    r.add_argument("--view", action="append", default=[], metavar="SLOT=PATH", help="replace one view (front, left, back, right)")
    r.add_argument("--out")
    r.add_argument("--geometry", default="hunyuan2mv", help="comma list, tried in order: " + ", ".join(GEOMETRY))
    r.add_argument("--all", action="store_true", help="run every listed geometry provider and keep the best (uses all their budgets)")
    r.add_argument("--rig", default="", help="skintokens (rigs the mesh that won the geometry stage), anigen (its own mesh, front view only) or tripo (credits; needs --geometry tripo)")
    r.add_argument("--rig-faces", type=int, default=30000, help="skintokens: decimate the mesh to about this many triangles first")
    r.add_argument("--rig-spec", choices=("tripo", "mixamo"), default="tripo", help="Tripo's skeleton: its own, or Mixamo's names")
    r.add_argument("--parts", action="store_true", help="split the mesh into parts (Hunyuan3D-Part, one more GPU run)")
    r.add_argument("--steps", type=int, default=5, help="Hunyuan3D-2mv sampling steps (5 = the Space's Turbo mode)")
    r.add_argument("--shape-only", action="store_true", help="Hunyuan3D-2mv: the untextured shape (far less GPU time; texture it elsewhere)")
    r.add_argument("--octree", type=int, default=256, help="Hunyuan3D-2mv octree resolution (16..512)")
    r.add_argument("--texture", type=int, default=1024, help="AniGen texture size")
    r.add_argument("--target-faces", type=int, default=0, help="reduce to about this many faces (Hunyuan export, Tripo face_limit)")
    r.add_argument("--min-gpu", type=float, default=90.0, help="refuse a Space call when fewer GPU-seconds than this are left")
    r.add_argument("--max-credits", type=float, default=60.0, help="Tripo: the balance must cover this before anything is sent")
    r.add_argument("--force", action="store_true")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "doctor":
            return doctor()
        if a.cmd == "decimate":
            print(decimate(a.file, a.out, a.faces))
            show(a.out)
            return 0
        if a.cmd == "preview":
            print(preview(a.file, a.out))
            return 0
        if a.cmd == "inspect":
            for f in a.files:
                show(f)
            return 0
        return run(a)
    except (Refused, QuotaError, SpaceError) as e:
        print("STOPPED: " + redact(e))
        return 2


if __name__ == "__main__":
    sys.exit(main())
