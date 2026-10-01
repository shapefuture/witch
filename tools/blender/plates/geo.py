"""Mesh building for the plates, authored in Godot space (x right, y up, -z forward).

The surface look is made by DECIMATING smooth forms: a dense, gently displaced surface is collapsed
(Decimate, collapse) and triangulated, which leaves large irregular triangles of different sizes and
orientations. Each triangle then gets a random `facet` value (a face attribute) that the materials
turn into a small value/hue shift: the crystalline mosaic of the reference.
"""
import math
import random

import bmesh
import bpy
import mathutils.noise as mnoise
import numpy as np
from mathutils import Matrix, Vector

TO_BL = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
TO_GD = TO_BL.inverted()


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Euler XYZ in degrees, Godot space (applied X, then Y, then Z, like Godot's default order YXZ? no:
    this is the kit's own convention: R = Rz @ Ry @ Rx)."""
    return (Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(ry), 4, "Y")
            @ Matrix.Rotation(math.radians(rx), 4, "X"))


def xf(pos=(0, 0, 0), r=(0, 0, 0), scale=(1, 1, 1)):
    if isinstance(scale, (int, float)):
        scale = (scale, scale, scale)
    return Matrix.Translation(Vector(pos)) @ rot(*r) @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))


def fbm(p, octaves=3, seed=0.0, lacunarity=2.0, gain=0.5):
    v, a, f, tot = 0.0, 1.0, 1.0, 0.0
    for _ in range(octaves):
        v += mnoise.noise(Vector((p[0] * f + seed * 13.1, p[1] * f + seed * 7.7, p[2] * f - seed * 3.3))) * a
        tot += a
        a *= gain
        f *= lacunarity
    return v / tot


class Builder:
    """Collects geometry for one object in Godot space; faces carry material names."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.uv = self.bm.loops.layers.uv.verify()

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _new_faces(self, n0):
        self.bm.faces.ensure_lookup_table()
        return self.bm.faces[n0:]

    def _finish(self, n0, mat, uv_mode="box", uv_scale=1.0):
        faces = list(self._new_faces(n0))
        mi = self._mi(mat)
        for f in faces:
            f.material_index = mi
        if uv_mode == "box":
            self.box_uv(faces, uv_scale)
        return faces

    def count(self):
        return len(self.bm.faces)

    # ---- primitives ----------------------------------------------------------------------------------
    def box(self, center, size, mat, r=(0, 0, 0), taper=None, uv_mode="box", uv_scale=1.0, skip=()):
        n0 = len(self.bm.faces)
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        if taper is not None:
            for v in verts:
                if v.co.y > 0:
                    v.co.x *= taper[0]
                    v.co.z *= taper[1]
        bmesh.ops.transform(self.bm, matrix=xf(center, r, size), verts=verts)
        faces = self._finish(n0, mat, uv_mode, uv_scale)
        if skip:
            m = xf((0, 0, 0), r).to_3x3()
            dirs = {"-y": Vector((0, -1, 0)), "+y": Vector((0, 1, 0)), "-z": Vector((0, 0, -1)), "+z": Vector((0, 0, 1)), "-x": Vector((-1, 0, 0)), "+x": Vector((1, 0, 0))}
            kill = []
            for f in faces:
                f.normal_update()
                for s in skip:
                    if f.normal.dot(m @ dirs[s]) > 0.9:
                        kill.append(f)
            bmesh.ops.delete(self.bm, geom=kill, context="FACES_ONLY")
            faces = [f for f in faces if f.is_valid]
        return faces

    def cyl(self, base, top, r0, r1, mat, segs=8, caps=True, spin=0.0, uv_mode="box", uv_scale=1.0):
        base, top = Vector(base), Vector(top)
        axis = top - base
        length = axis.length
        if length < 1e-6:
            return []
        n0 = len(self.bm.faces)
        verts = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=length)["verts"]
        if spin:
            bmesh.ops.transform(self.bm, matrix=Matrix.Rotation(math.radians(spin), 4, "Z"), verts=verts)
        quat = Vector((0, 0, 1)).rotation_difference(axis.normalized())
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation((base + top) * 0.5) @ quat.to_matrix().to_4x4(), verts=verts)
        return self._finish(n0, mat, uv_mode, uv_scale)

    def sphere(self, center, radii, mat, subdiv=2, amp=0.0, seed=0, r=(0, 0, 0), freq=1.6, flat_bottom=None):
        n0 = len(self.bm.faces)
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=1.0)["verts"]
        for v in verts:
            n = v.co.normalized()
            d = 1.0 + amp * fbm(n * freq, 2, seed + 0.37)
            v.co = n * d
            if flat_bottom is not None and v.co.y < flat_bottom:
                v.co.y = flat_bottom
        if isinstance(radii, (int, float)):
            radii = (radii, radii, radii)
        bmesh.ops.transform(self.bm, matrix=xf(center, r, radii), verts=verts)
        return self._finish(n0, mat)

    def lathe(self, profile, mat, segs=8, matrix=None, jitter=0.0, seed=0, closed_top=True, closed_bottom=True, spin=0.0):
        """Revolve [(radius, y), ...] (bottom first) about local Y."""
        n0 = len(self.bm.faces)
        rings = []
        for (rad, y) in profile:
            ring = []
            for k in range(segs):
                a = math.tau * k / segs + math.radians(spin)
                rr = rad * (1.0 + jitter * mnoise.noise(Vector((math.cos(a) * 2 + seed, y * 2, math.sin(a) * 2))))
                ring.append(self.bm.verts.new((math.cos(a) * rr, y, math.sin(a) * rr)))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for k in range(segs):
                a, b = rings[i][k], rings[i][(k + 1) % segs]
                c, d = rings[i + 1][(k + 1) % segs], rings[i + 1][k]
                try:
                    self.bm.faces.new((a, d, c, b))
                except ValueError:
                    pass
        if closed_bottom and profile[0][0] > 1e-5:
            self.bm.faces.new(rings[0])
        if closed_top and profile[-1][0] > 1e-5:
            self.bm.faces.new(list(reversed(rings[-1])))
        if matrix is not None:
            bmesh.ops.transform(self.bm, matrix=matrix, verts=[v for ring in rings for v in ring])
        return self._finish(n0, mat)

    def surface(self, fn, nu, nv, mat, closed_u=False, uv_mode="box", uv_scale=1.0, keep=None):
        """A parametric sheet: fn(u, v) -> (x, y, z) with u, v in [0, 1], nu x nv cells. Normals follow
        (dP/du x dP/dv). `keep(u, v)` drops cells (an opening in a wall)."""
        n0 = len(self.bm.faces)
        cols = nu if closed_u else nu + 1
        grid = [[self.bm.verts.new(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(cols)]
        for i in range(nu):
            for j in range(nv):
                if keep is not None and not keep((i + 0.5) / nu, (j + 0.5) / nv):
                    continue
                a, b = grid[i][j], grid[(i + 1) % cols][j]
                c, d = grid[(i + 1) % cols][j + 1], grid[i][j + 1]
                self.bm.faces.new((a, b, c, d))
        loose = [v for row in grid for v in row if not v.link_faces]
        if loose:
            bmesh.ops.delete(self.bm, geom=loose, context="VERTS")
        return self._finish(n0, mat, uv_mode, uv_scale)

    def quad(self, a, b, c, d, mat, uv=None):
        n0 = len(self.bm.faces)
        f = self.bm.faces.new([self.bm.verts.new(p) for p in (a, b, c, d)])
        faces = self._finish(n0, mat, "none" if uv else "box")
        if uv:
            for loop, t in zip(f.loops, uv):
                loop[self.uv].uv = t
        return faces

    def tri(self, a, b, c, mat):
        n0 = len(self.bm.faces)
        self.bm.faces.new([self.bm.verts.new(p) for p in (a, b, c)])
        return self._finish(n0, mat)

    def transform(self, faces_or_n0, matrix):
        if isinstance(faces_or_n0, int):
            self.bm.faces.ensure_lookup_table()
            faces = self.bm.faces[faces_or_n0:]
        else:
            faces = faces_or_n0
        verts = list({v for f in faces for v in f.verts})
        bmesh.ops.transform(self.bm, matrix=matrix, verts=verts)

    def displace(self, n0, fn):
        """fn(Vector) -> Vector for every vertex of faces created since n0."""
        self.bm.faces.ensure_lookup_table()
        verts = list({v for f in self.bm.faces[n0:] for v in f.verts})
        for v in verts:
            v.co = Vector(fn(v.co.copy()))

    # ---- UVs -----------------------------------------------------------------------------------------
    def box_uv(self, faces, scale=1.0):
        for f in faces:
            f.normal_update()
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for loop in f.loops:
                p = loop.vert.co
                if ay >= ax and ay >= az:
                    uv = (p.x, -p.z)
                elif ax >= az:
                    uv = (p.z if n.x < 0 else -p.z, p.y)
                else:
                    uv = (p.x if n.z > 0 else -p.x, p.y)
                loop[self.uv].uv = (uv[0] * scale, uv[1] * scale)

    def face_uv(self, faces, cell=(0, 0), cells=1, inset=0.0):
        """Map each face's bounding box (in its own plane) onto one cell of an atlas."""
        for f in faces:
            f.normal_update()
            n = f.normal
            t = (Vector((0, 1, 0)).cross(n) if abs(n.y) < 0.9 else Vector((1, 0, 0)))
            t.normalize()
            b = n.cross(t)
            pts = [(loop.vert.co.dot(t), loop.vert.co.dot(b)) for loop in f.loops]
            us, vs = [p[0] for p in pts], [p[1] for p in pts]
            u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
            for loop, (u, v) in zip(f.loops, pts):
                uu = inset + (1 - 2 * inset) * (u - u0) / max(u1 - u0, 1e-6)
                vv = inset + (1 - 2 * inset) * (v - v0) / max(v1 - v0, 1e-6)
                loop[self.uv].uv = ((cell[0] + uu) / cells, (cell[1] + vv) / cells)

    # ---- object --------------------------------------------------------------------------------------
    def build(self, collection, materials, location=(0, 0, 0), rotation=(0, 0, 0), parent=None):
        for v in self.bm.verts:
            v.co = TO_BL @ v.co
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(materials[m])
        obj = bpy.data.objects.new(self.name, me)
        collection.objects.link(obj)
        obj.matrix_basis = TO_BL @ xf(location, rotation) @ TO_GD
        if parent is not None:
            obj.parent = parent
        return obj


def facet(obj, ratio=None, target_edge=None, seed=0, planar=False, keep_boundary=True):
    """Collapse a smooth form into large irregular triangles, then give every triangle a random tone.

    `ratio` is the Decimate collapse ratio; `target_edge` (metres) picks it from the current mean
    edge length instead."""
    me = obj.data
    if target_edge is not None and len(me.edges):
        co = np.zeros(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        ev = np.zeros(len(me.edges) * 2, np.int32)
        me.edges.foreach_get("vertices", ev)
        ev = ev.reshape(-1, 2)
        mean = float(np.linalg.norm(co[ev[:, 0]] - co[ev[:, 1]], axis=1).mean())
        ratio = min(1.0, (mean / target_edge) ** 2)
    if ratio is not None and ratio < 0.999:
        mod = obj.modifiers.new("decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        if planar:
            mod.decimate_type = "DISSOLVE"
            mod.angle_limit = math.radians(4)
    tri = obj.modifiers.new("triangulate", "TRIANGULATE")
    tri.quad_method = "BEAUTY"
    apply_modifiers(obj)
    flat(obj)
    facet_attr(obj, seed)
    return obj


def apply_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    me.name = old.name
    bpy.data.meshes.remove(old)


def flat(obj):
    me = obj.data
    me.polygons.foreach_set("use_smooth", [False] * len(me.polygons))


def facet_attr(obj, seed=0):
    me = obj.data
    rng = np.random.default_rng(abs(hash((obj.name, seed))) % (2 ** 32))
    if "facet" in me.attributes:
        me.attributes.remove(me.attributes["facet"])
    attr = me.attributes.new("facet", "FLOAT", "FACE")
    attr.data.foreach_set("value", rng.random(len(me.polygons)).astype(np.float32))


def tri_count(obj):
    me = obj.data
    n = np.zeros(len(me.polygons), np.int32)
    me.polygons.foreach_get("loop_total", n)
    return int((n - 2).sum())


def join(objs, name):
    """Join objects into the first one (keeps materials and the facet attribute)."""
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]
