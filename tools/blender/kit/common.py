"""Faceted-mesh construction kit for the diorama (runs inside Blender's Python, `bpy`).

Everything is authored in GODOT space (x right, y up, -z forward). A Part collects geometry in that
space and converts to Blender's Z-up only when the object is created, so the numbers in the scene
scripts are the same numbers the game code uses (MACHINE_AT, TREE_AT ...). The glTF exporter's
Y-up conversion then brings them back to exactly where they were authored.

All meshes are flat-shaded: chunky facets are the look. Lighting is baked into corner colours
(see bake.py); albedo comes from a small hand-painted texture per material (textures.py).
"""
import math
import random

import bmesh
import bpy
import mathutils.noise as mnoise
from mathutils import Matrix, Vector

TO_BL = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
TO_GD = TO_BL.inverted()

# UV tiles per metre for each material (box projection in world scale: constant texel density).
UV_DENSITY = {}
# Materials whose tile is placed ONCE per face (a carved glyph, the eye mural) instead of tiled:
# name -> number of glyph cells per axis in the tile (1 = whole tile, 2 = a 2x2 sheet of glyphs).
CENTERED = {}


def rot_matrix(rx=0.0, ry=0.0, rz=0.0):
    """Euler XYZ in degrees (Godot space)."""
    return Matrix.Rotation(math.radians(rz), 4, "Z") @ Matrix.Rotation(math.radians(ry), 4, "Y") @ Matrix.Rotation(math.radians(rx), 4, "X")


def xf(pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    s = Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    return Matrix.Translation(Vector(pos)) @ rot_matrix(*rot) @ s


def catmull(points, per_segment=6):
    """Catmull-Rom through points (list of Vector). Returns a denser polyline."""
    pts = [Vector(p) for p in points]
    if len(pts) < 3:
        return pts
    out = []
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(per_segment):
            t = s / per_segment
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def fbm(p, octaves=3, seed=0.0):
    v, a, f = 0.0, 1.0, 1.0
    tot = 0.0
    for _ in range(octaves):
        v += mnoise.noise(Vector((p[0] * f + seed * 13.1, p[1] * f + seed * 7.7, p[2] * f - seed * 3.3))) * a
        tot += a
        a *= 0.5
        f *= 2.0
    return v / tot


def Matrix_rotz(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def _h2(i, j, seed=0):
    v = math.sin(i * 127.1 + j * 311.7 + seed * 74.7) * 43758.5453
    return v - math.floor(v)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a))) if a != b else (1.0 if x >= a else 0.0)
    return t * t * (3.0 - 2.0 * t)


class Part:
    """One object being assembled. Geometry accumulates in a bmesh (Godot space)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        # Creation order lives ON the vertices (an int layer), not in a list of Python wrappers.
        # bmesh reuses freed slots (create_icosphere frees some) and the wrappers of older vertices
        # then go stale, so a list of them silently drops geometry from later transforms.
        self._seq_layer = self.bm.verts.layers.int.new("seq")
        self._seq = 0

    # ---- materials -------------------------------------------------------------------------
    def mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _tag(self, faces, mat):
        index = self.mi(mat)
        for f in faces:
            f.material_index = index

    def _reg(self, verts):
        verts = [v for v in verts if v.is_valid]
        for v in verts:
            v[self._seq_layer] = self._seq
            self._seq += 1
        return verts

    def _tag_new(self, verts, mat):
        """Give the faces that own these (new) vertices a material."""
        self._tag(list({f for v in verts for f in v.link_faces}), mat)

    def mark(self):
        return self._seq

    def verts_since(self, mark):
        layer = self._seq_layer
        return [v for v in self.bm.verts if v[layer] >= mark]

    def deform(self, mark, fn):
        """fn(Vector)->Vector applied to every vertex created since `mark`."""
        for v in self.verts_since(mark):
            v.co = Vector(fn(v.co.copy()))

    def transform_since(self, mark, matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=self.verts_since(mark))

    def _vert(self, co):
        v = self.bm.verts.new(co)
        v[self._seq_layer] = self._seq
        self._seq += 1
        return v

    # ---- primitives --------------------------------------------------------------------------
    def blob(self, center=(0, 0, 0), radii=(1, 1, 1), mat="leaf_a", subdiv=2, amp=0.12, seed=0, rot=(0, 0, 0), flat_bottom=None, sway=None):
        """A lumpy faceted ellipsoid: the basis of canopies, rocks, bushes, belly shapes."""
        m = self.mark()
        verts = self._reg(bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=1.0)["verts"])
        for v in verts:
            n = v.co.normalized()
            d = 1.0 + amp * fbm(n * 1.8, 2, seed + 0.37)
            v.co = n * d
            if flat_bottom is not None and v.co.y < flat_bottom:
                v.co.y = flat_bottom
        bmesh.ops.transform(self.bm, matrix=xf(center, rot, radii), verts=verts)
        self._tag_new(verts, mat)
        return m

    def box(self, center=(0, 0, 0), size=(1, 1, 1), mat="wood", rot=(0, 0, 0), bevel=0.0, taper=None):
        """Axis box. `taper` = (top_scale_x, top_scale_z) shrinks the +Y face.

        `bevel` is accepted and ignored on purpose: bmesh's bevel deletes vertices, and bmesh reuses
        freed slots for later vertices, which breaks the "vertices added since the mark" bookkeeping
        every other primitive relies on. Sharp edges suit the faceted look anyway."""
        m = self.mark()
        verts = self._reg(bmesh.ops.create_cube(self.bm, size=1.0)["verts"])
        if taper is not None:
            for v in verts:
                if v.co.y > 0:
                    v.co.x *= taper[0]
                    v.co.z *= taper[1]
        bmesh.ops.transform(self.bm, matrix=xf(center, rot, size), verts=verts)
        self._tag_new(verts, mat)
        return m

    def cyl(self, base=(0, 0, 0), top=(0, 1, 0), r0=0.5, r1=0.5, mat="wood", segs=8, caps=True, spin=0.0):
        """Cylinder/cone between two points (any axis)."""
        base, top = Vector(base), Vector(top)
        axis = top - base
        length = axis.length
        if length < 1e-6:
            return self.mark()
        m = self.mark()
        verts = self._reg(bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=length)["verts"])
        for v in verts:
            c, s = math.cos(math.radians(spin)), math.sin(math.radians(spin))
            v.co.x, v.co.y = v.co.x * c - v.co.y * s, v.co.x * s + v.co.y * c
        quat = Vector((0, 0, 1)).rotation_difference(axis.normalized())
        mat4 = Matrix.Translation((base + top) * 0.5) @ quat.to_matrix().to_4x4()
        bmesh.ops.transform(self.bm, matrix=mat4, verts=verts)
        self._tag_new(verts, mat)
        return m

    def lathe(self, profile, segs=8, mat="wood", center=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), closed_top=True, closed_bottom=True, jitter=0.0, seed=0, spin=0.0):
        """Revolve [(radius, y), ...] around Y. First point is the bottom."""
        m = self.mark()
        rings = []
        for (r, y) in profile:
            ring = []
            for k in range(segs):
                a = math.tau * k / segs + math.radians(spin)
                rr = r * (1.0 + jitter * mnoise.noise(Vector((math.cos(a) * 2 + seed, y * 2, math.sin(a) * 2))))
                ring.append(self._vert((math.cos(a) * rr, y, math.sin(a) * rr)))
            rings.append(ring)
        faces = []
        for i in range(len(rings) - 1):
            for k in range(segs):
                a, b = rings[i][k], rings[i][(k + 1) % segs]
                c, d = rings[i + 1][(k + 1) % segs], rings[i + 1][k]
                try:
                    faces.append(self.bm.faces.new((a, d, c, b)))
                except ValueError:
                    pass
        # Profiles run bottom->top; (a, d, c, b) winds the side faces outward.
        if closed_bottom and profile[0][0] > 1e-5:
            faces.append(self.bm.faces.new(rings[0]))
        if closed_top and profile[-1][0] > 1e-5:
            faces.append(self.bm.faces.new(list(reversed(rings[-1]))))
        self.transform_since(m, xf(center, rot, scale))
        self._tag(faces, mat)
        return m

    def tube(self, points, radii, mat="bark", segs=6, caps=True, per_segment=5, jitter=0.0, seed=0, twist=0.0):
        """Sweep a circle along a smooth path with varying radius (trunks, roots, vines, handles)."""
        path = catmull(points, per_segment)
        n = len(path)
        if isinstance(radii, (int, float)):
            radii = [radii, radii]
        m = self.mark()
        rings = []
        prev_up = Vector((0, 0, 1))
        for i, p in enumerate(path):
            t = i / max(1, n - 1)
            tangent = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
            up = prev_up - tangent * prev_up.dot(tangent)
            if up.length < 1e-4:
                up = Vector((1, 0, 0)) - tangent * tangent.x
            up.normalize()
            prev_up = up
            side = tangent.cross(up).normalized()
            seg = t * (len(radii) - 1)
            i0 = min(int(seg), len(radii) - 2)
            r = radii[i0] + (radii[i0 + 1] - radii[i0]) * (seg - i0)
            ring = []
            for k in range(segs):
                a = math.tau * k / segs + twist * t
                rr = r * (1.0 + jitter * mnoise.noise(Vector((p.x * 3 + seed, p.y * 3, p.z * 3 + k * 0.7))))
                ring.append(self._vert(p + (up * math.cos(a) + side * math.sin(a)) * rr))
            rings.append(ring)
        faces = []
        for i in range(n - 1):
            for k in range(segs):
                faces.append(self.bm.faces.new((rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k])))
        if caps:
            faces.append(self.bm.faces.new(list(reversed(rings[0]))))
            faces.append(self.bm.faces.new(rings[-1]))
        self._tag(faces, mat)
        return m

    def tri_toward(self, a, b, c, mat, toward):
        """Triangle wound so its normal faces `toward` (a Vector): for room shells seen from inside."""
        a, b, c = Vector(a), Vector(b), Vector(c)
        n = (b - a).cross(c - a)
        centre = (a + b + c) / 3.0
        if n.dot(Vector(toward) - centre) < 0:
            b, c = c, b
        f = self.bm.faces.new([self._vert(p) for p in (a, b, c)])
        self._tag([f], mat)
        return f

    def quad_out(self, a, b, c, d, mat, centre):
        """Quad wound so its normal points away from `centre` (for the faces of an open box)."""
        pts = [Vector(a), Vector(b), Vector(c), Vector(d)]
        n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        mid = sum(pts, Vector()) / 4.0
        if n.dot(mid - Vector(centre)) < 0:
            pts.reverse()
        f = self.bm.faces.new([self._vert(p) for p in pts])
        self._tag([f], mat)
        return f

    def book(self, centre, size, mat, rot_z=0.0, mat_top=None):
        """A box with no bottom and no back: ten triangles. Spines, crates, boxes on shelves.
        Local +z is the front. `rot_z` leans it (degrees)."""
        cx, cy, cz = centre
        w, h, d = size[0] / 2, size[1] / 2, size[2] / 2
        m = Matrix_rotz(rot_z)
        corners = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    p = Vector((sx * w, sy * h, sz * d))
                    p = m @ p
                    corners[(sx, sy, sz)] = Vector((cx, cy, cz)) + p
        c = Vector(centre)
        self.quad_out(corners[(-1, -1, 1)], corners[(1, -1, 1)], corners[(1, 1, 1)], corners[(-1, 1, 1)], mat, c)            # front
        self.quad_out(corners[(-1, 1, -1)], corners[(1, 1, -1)], corners[(1, 1, 1)], corners[(-1, 1, 1)], mat_top or mat, c)   # top
        self.quad_out(corners[(-1, -1, -1)], corners[(-1, 1, -1)], corners[(-1, 1, 1)], corners[(-1, -1, 1)], mat, c)          # left
        self.quad_out(corners[(1, -1, -1)], corners[(1, 1, -1)], corners[(1, 1, 1)], corners[(1, -1, 1)], mat, c)            # right

    def quad(self, a, b, c, d, mat):
        f = self.bm.faces.new([self._vert(p) for p in (a, b, c, d)])
        self._tag([f], mat)
        return f

    def tri(self, a, b, c, mat):
        f = self.bm.faces.new([self._vert(p) for p in (a, b, c)])
        self._tag([f], mat)
        return f

    def grid(self, x0, x1, z0, z1, step, height_fn, mat_fn, jitter=0.0, seed=1):
        """Heightfield from a function. Two triangles per cell, split along the diagonal that suits the slope."""
        nx = int(round((x1 - x0) / step))
        nz = int(round((z1 - z0) / step))
        verts = {}
        for i in range(nx + 1):
            for j in range(nz + 1):
                x, z = x0 + i * step, z0 + j * step
                if jitter > 0.0 and 0 < i < nx and 0 < j < nz:
                    x += (_h2(i, j, seed) - 0.5) * 2.0 * jitter * step
                    z += (_h2(j, i, seed + 7) - 0.5) * 2.0 * jitter * step
                verts[(i, j)] = self._vert((x, height_fn(x, z), z))
        m = 0
        for i in range(nx):
            for j in range(nz):
                a, b, c, d = verts[(i, j)], verts[(i + 1, j)], verts[(i + 1, j + 1)], verts[(i, j + 1)]
                # counter-clockwise seen from +Y: a(x0,z0) -> d(x0,z1) -> c -> b
                flip = ((i + j) % 2 == 0)
                tris = ((a, d, c), (a, c, b)) if flip else ((a, d, b), (b, d, c))
                for tri in tris:
                    f = self.bm.faces.new(tri)
                    cx = sum(v.co.x for v in tri) / 3
                    cz = sum(v.co.z for v in tri) / 3
                    f.material_index = self.mi(mat_fn(cx, cz))
                m += 1
        return m

    # ---- finishing ---------------------------------------------------------------------------
    def split_long_edges(self, max_len, passes=4):
        """Subdivide so baked vertex lighting has resolution on big flat faces (shadows need vertices)."""
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces[:])
        for _ in range(passes):
            long_edges = [e for e in self.bm.edges if e.calc_length() > max_len]
            if not long_edges:
                break
            bmesh.ops.subdivide_edges(self.bm, edges=long_edges, cuts=1, use_grid_fill=False)
            bmesh.ops.triangulate(self.bm, faces=self.bm.faces[:])

    def uv_project(self):
        uv = self.bm.loops.layers.uv.verify()
        self.bm.normal_update()
        for f in self.bm.faces:
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            name = self.mats[f.material_index] if f.material_index < len(self.mats) else ""
            dens = UV_DENSITY.get(name, 0.3)
            pts = []
            for loop in f.loops:
                p = loop.vert.co
                if ay >= ax and ay >= az:
                    pts.append((p.x, p.z))
                elif ax >= az:
                    pts.append((p.z, p.y))
                else:
                    pts.append((p.x, p.y))
            if name in CENTERED:
                cells = CENTERED[name]
                us, vs = [q[0] for q in pts], [q[1] for q in pts]
                u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
                cx, cy = (0, 0)
                if cells > 1:
                    h = int(abs(f.calc_center_median().x * 7.3 + f.calc_center_median().y * 3.1 + f.calc_center_median().z * 5.7) * 10) % (cells * cells)
                    cx, cy = h % cells, h // cells
                for loop, (u, v) in zip(f.loops, pts):
                    uu = (u - u0) / max(u1 - u0, 1e-6)
                    vv = 1.0 - (v - v0) / max(v1 - v0, 1e-6)
                    loop[uv].uv = ((cx + uu) / cells, (cy + vv) / cells)
                continue
            for loop, (u, v) in zip(f.loops, pts):
                loop[uv].uv = (u * dens, -v * dens)

    def build(self, collection, materials, max_edge=None, parent=None, location=(0, 0, 0), rotation=(0, 0, 0), flat=True):
        """Create the Blender object. `location`/`rotation` become the object's own transform (Godot space,
        converted), so animated parts keep a pivot; the mesh data stays in local space."""
        if max_edge:
            self.split_long_edges(max_edge)
        # Winding is authored per primitive (and per triangle for room shells); recalc_face_normals
        # would re-guess it from loose, unwelded triangles and flip about half of them.
        self.uv_project()
        for v in self.bm.verts:
            v.co = TO_BL @ v.co
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for mname in self.mats:
            me.materials.append(materials[mname])
        for poly in me.polygons:
            poly.use_smooth = not flat
        me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        obj = bpy.data.objects.new(self.name, me)
        collection.objects.link(obj)
        local = xf(location, rotation)
        obj.matrix_basis = TO_BL @ local @ TO_GD
        if parent is not None:
            obj.parent = parent
        return obj


def empty(name, collection, location=(0, 0, 0), rotation=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.matrix_basis = TO_BL @ xf(location, rotation) @ TO_GD
    if parent is not None:
        obj.parent = parent
    return obj
