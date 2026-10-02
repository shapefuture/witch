"""Skinning, animation clips and the glTF 2.0 binary writer for the witches.

Rest pose is the authored T-pose (bones carry translations only, world-aligned). Every clip
keys *every* bone, so switching clips in Godot never leaves a bone in a previous clip's pose
and no bone falls back to the T-pose rest.

The writer emits one mesh with one primitive and one material (the atlas, sampled NEAREST,
clamped), flat normals (corners duplicated per triangle), a skin, and the clips.
"""
import io
import json
import math
import struct
import numpy as np

A = np.array


# ---- rotations -----------------------------------------------------------------------------------
def rot(axis, deg):
    a = A(axis, float)
    a = a / np.linalg.norm(a)
    t = math.radians(deg)
    K = A([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + math.sin(t) * K + (1 - math.cos(t)) * K @ K


def euler(x=0., y=0., z=0.):
    """Degrees about X, then Y, then Z (applied in that order)."""
    return rot((0, 0, 1), z) @ rot((0, 1, 0), y) @ rot((1, 0, 0), x)


def quat(M):
    """3x3 rotation -> glTF quaternion (x, y, z, w)."""
    m = M
    tr = m[0, 0] + m[1, 1] + m[2, 2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w = .25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = .25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = .25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = .25 * s
    q = A([x, y, z, w])
    return q / np.linalg.norm(q)


class Clip:
    """A named animation: `fn(t)` -> (rotations {bone: 3x3}, translations {bone: offset})."""

    def __init__(s, name, duration, fn, fps=15, loop=True):
        s.name, s.duration, s.fn, s.fps, s.loop = name, duration, fn, fps, loop

    def times(s):
        n = max(2, int(round(s.duration * s.fps)) + 1)
        return np.linspace(0, s.duration, n)


# ---- skinning (previews and sanity checks) ---------------------------------------------------------
def global_mats(model, rots, trans=None):
    trans = trans or {}
    G = {}
    for n in model.names:
        par, h = model.B[n]
        off = A(h, float) - (A(model.B[par][1], float) if par else 0)
        L = np.eye(4)
        L[:3, 3] = off + A(trans.get(n, (0, 0, 0)), float)
        if n in rots:
            L[:3, :3] = rots[n]
        G[n] = (G[par] if par else np.eye(4)) @ L
    S = {}
    for n in model.names:
        T = np.eye(4)
        T[:3, 3] = -A(model.B[n][1], float)
        S[n] = G[n] @ T
    return G, S


def pose_arrays(model, arr, rots, trans=None):
    """Linear blend skinning of the exported arrays; normals recomputed per triangle."""
    _, S = global_mats(model, rots, trans)
    Sm = np.stack([S[n] for n in model.names])           # (B,4,4)
    P = arr['P']
    Ph = np.hstack([P, np.ones((len(P), 1))])
    J = arr['J'].astype(int)
    W = arr['W']
    Q = np.zeros((len(P), 3))
    for k in range(4):
        M = Sm[J[:, k]]                                    # (n,4,4)
        Q += W[:, k, None] * np.einsum('nij,nj->ni', M, Ph)[:, :3]
    T = Q.reshape(-1, 3, 3)
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    n = np.where(ln > 1e-12, n / np.maximum(ln, 1e-12), A([0, 1., 0]))
    out = dict(arr)
    out['P'] = Q
    out['N'] = np.repeat(n, 3, axis=0)
    return out


# ---- writer -------------------------------------------------------------------------------------------
def export(path, model, arr, atlas_img, clips, scale, mesh_name='Witch', generator='witch.py', extras=None):
    blob = bytearray()
    views, accs = [], []

    def view(b, target=None):
        while len(blob) % 4:
            blob.append(0)
        v = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(b)}
        if target:
            v['target'] = target
        views.append(v)
        blob.extend(b)
        return len(views) - 1

    def acc(a, ct, typ, minmax=False, target=None):
        a = np.ascontiguousarray(a)
        a_ = {'bufferView': view(a.tobytes(), target), 'componentType': ct, 'count': len(a), 'type': typ}
        if minmax:
            a_['min'] = np.atleast_1d(a.min(0)).astype(float).tolist()
            a_['max'] = np.atleast_1d(a.max(0)).astype(float).tolist()
        accs.append(a_)
        return len(accs) - 1

    B, names, ix = model.B, model.names, model.ix
    nodes = []
    for n in names:
        par, h = B[n]
        off = (A(h, float) - (A(B[par][1], float) if par else 0)) * scale
        nodes.append({'name': n, 'translation': [float(x) for x in off]})
    for n in names:
        par = B[n][0]
        if par:
            nodes[ix[par]].setdefault('children', []).append(ix[n])
    nb = len(names)
    nodes.append({'name': mesh_name, 'mesh': 0, 'skin': 0})

    ibm = np.zeros((nb, 16), np.float32)
    for i, n in enumerate(names):
        m = np.eye(4)
        m[:3, 3] = -A(B[n][1], float) * scale
        ibm[i] = m.flatten('F')
    skin = {'joints': list(range(nb)), 'skeleton': 0, 'inverseBindMatrices': acc(ibm, 5126, 'MAT4'), 'name': mesh_name + 'Skin'}

    P = (arr['P'] * scale).astype(np.float32)
    attrs = {'POSITION': acc(P, 5126, 'VEC3', True, 34962),
             'NORMAL': acc(arr['N'].astype(np.float32), 5126, 'VEC3', False, 34962),
             'TEXCOORD_0': acc(arr['UV'].astype(np.float32), 5126, 'VEC2', False, 34962),
             'JOINTS_0': acc(arr['J'].astype(np.uint8), 5121, 'VEC4', False, 34962),
             'WEIGHTS_0': acc(arr['W'].astype(np.float32), 5126, 'VEC4', False, 34962)}
    if 'C' in arr:
        attrs['COLOR_0'] = acc(arr['C'].astype(np.float32), 5126, 'VEC4', False, 34962)
    prim = {'attributes': attrs, 'material': 0, 'mode': 4}

    png = io.BytesIO()
    atlas_img.save(png, 'PNG', optimize=True)
    img_view = view(png.getvalue())

    anims = []
    for clip in clips:
        T = clip.times()
        ti = acc(T.astype(np.float32), 5126, 'SCALAR', True)
        samplers, channels = [], []
        poses = [clip.fn(float(t)) for t in T]
        tr_bones = sorted({b for _, tr in poses for b in tr})
        for n in names:
            q = np.stack([quat(r.get(n, np.eye(3))) for r, _ in poses])
            # keep quaternions in one hemisphere so LINEAR interpolation takes the short way
            for k in range(1, len(q)):
                if q[k] @ q[k - 1] < 0:
                    q[k] = -q[k]
            samplers.append({'input': ti, 'output': acc(q.astype(np.float32), 5126, 'VEC4'), 'interpolation': 'LINEAR'})
            channels.append({'sampler': len(samplers) - 1, 'target': {'node': ix[n], 'path': 'rotation'}})
        for n in tr_bones:
            par, h = B[n]
            base = A(h, float) - (A(B[par][1], float) if par else 0)
            t = np.stack([(base + A(tr.get(n, (0, 0, 0)), float)) * scale for _, tr in poses])
            samplers.append({'input': ti, 'output': acc(t.astype(np.float32), 5126, 'VEC3'), 'interpolation': 'LINEAR'})
            channels.append({'sampler': len(samplers) - 1, 'target': {'node': ix[n], 'path': 'translation'}})
        anims.append({'name': clip.name, 'samplers': samplers, 'channels': channels})

    g = {'asset': {'version': '2.0', 'generator': generator, 'extras': extras or {}},
         'scene': 0, 'scenes': [{'name': mesh_name, 'nodes': [0, nb]}],
         'nodes': nodes, 'skins': [skin],
         'meshes': [{'name': mesh_name, 'primitives': [prim]}],
         'materials': [{'name': mesh_name.lower() + '_atlas',
                        'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'baseColorFactor': [1, 1, 1, 1],
                                                 'metallicFactor': 0, 'roughnessFactor': 1}}],
         'textures': [{'sampler': 0, 'source': 0}],
         'samplers': [{'magFilter': 9728, 'minFilter': 9728, 'wrapS': 33071, 'wrapT': 33071}],
         'images': [{'bufferView': img_view, 'mimeType': 'image/png', 'name': mesh_name.lower() + '_atlas'}],
         'animations': anims,
         'buffers': [{'byteLength': 0}], 'bufferViews': views, 'accessors': accs}
    while len(blob) % 4:
        blob.append(0)
    g['buffers'][0]['byteLength'] = len(blob)
    js = json.dumps(g, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        f.write(struct.pack('<II', len(blob), 0x004E4942) + bytes(blob))
    return len(P) // 3


def read_glb(path):
    """(gltf json, embedded atlas as a PIL image) of a previously exported GLB, or (None, None)."""
    from PIL import Image
    try:
        data = open(path, 'rb').read()
    except OSError:
        return None, None
    jl, = struct.unpack('<I', data[12:16])
    g = json.loads(data[20:20 + jl])
    bin_ = data[20 + jl + 8:]
    for im in g.get('images', []):
        v = g['bufferViews'][im['bufferView']]
        o = v.get('byteOffset', 0)
        return g, Image.open(io.BytesIO(bin_[o:o + v['byteLength']])).convert('RGB')
    return g, None
