class_name SlabMesh
extends RefCounted

# Meshes for diegetic UI, built in "pixel units": x right, y UP, the rectangle's top-left corner
# at the origin so it spans x in [0, w] and y in [-h, 0]. The owner scales one unit to one render
# pixel and places the origin where the slab should appear.

const CHAMFER := 4.0

# A rectangle with chamfered corners; the corners are cut, not rounded: this is a faceted world.
static func chamfered(w: float, h: float, cut: float = CHAMFER) -> PackedVector2Array:
	var c := minf(cut, minf(w, h) * 0.5)
	return PackedVector2Array([
		Vector2(c, 0), Vector2(w - c, 0), Vector2(w, -c), Vector2(w, -(h - c)),
		Vector2(w - c, -h), Vector2(c, -h), Vector2(0, -(h - c)), Vector2(0, -c),
	])

# The same rectangle with a pointed tail reaching `tip` (in the same local coordinates). The tail
# leaves the nearest edge; its base is clamped away from the corners.
static func with_tail(w: float, h: float, tip: Vector2, cut: float = CHAMFER) -> PackedVector2Array:
	var body := chamfered(w, h, cut)
	var base_half := 5.0
	var margin := cut + base_half + 2.0
	var out := PackedVector2Array()
	var edge := "bottom"
	if tip.y > 0.0:
		edge = "top"
	elif tip.y >= -h:
		edge = "left" if tip.x < w * 0.5 else "right"
	var bx := clampf(tip.x, margin, maxf(margin, w - margin))
	var by := clampf(tip.y, -(h - margin), -margin) if h > margin * 2.0 else -h * 0.5
	for i in range(body.size()):
		out.append(body[i])
		# insert the tail after the vertex that ends the chosen edge (vertex order: top edge is 0-1)
		if edge == "top" and i == 0:
			out.append(Vector2(bx - base_half, 0)); out.append(tip); out.append(Vector2(bx + base_half, 0))
		elif edge == "right" and i == 2:
			out.append(Vector2(w, by + base_half)); out.append(tip); out.append(Vector2(w, by - base_half))
		elif edge == "bottom" and i == 4:
			out.append(Vector2(bx + base_half, -h)); out.append(tip); out.append(Vector2(bx - base_half, -h))
		elif edge == "left" and i == 6:
			out.append(Vector2(0, by - base_half)); out.append(tip); out.append(Vector2(0, by + base_half))
	return out

# A scalloped cloud for thoughts and narration.
static func cloud(w: float, h: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := 3.0
	var nx := maxi(3, int(w / 20.0))
	var ny := maxi(2, int(h / 20.0))
	var steps_x := nx * 4
	var steps_y := ny * 4
	for i in range(steps_x + 1):
		var t := float(i) / steps_x
		out.append(Vector2(lerpf(0.0, w, t), r * absf(sin(t * PI * nx))))
	for j in range(1, steps_y + 1):
		var t := float(j) / steps_y
		out.append(Vector2(w + r * absf(sin(t * PI * ny)), -lerpf(0.0, h, t)))
	for i in range(1, steps_x + 1):
		var t := 1.0 - float(i) / steps_x
		out.append(Vector2(lerpf(0.0, w, t), -h - r * absf(sin(t * PI * nx))))
	for j in range(1, steps_y):
		var t := 1.0 - float(j) / steps_y
		out.append(Vector2(-r * absf(sin(t * PI * ny)), -lerpf(0.0, h, t)))
	return out

# A small octagon: the trail of dots that leads a thought bubble to its thinker.
static func dot(centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(8):
		var a := TAU * k / 8.0 + PI / 8.0
		out.append(centre + Vector2(cos(a), sin(a)) * radius)
	return out

static func offset(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p + by)
	return out

# `inset` pixels inward, or the original if the shrink collapses it.
static func inset(points: PackedVector2Array, pixels: float) -> PackedVector2Array:
	var shrunk := Geometry2D.offset_polygon(points, -pixels, Geometry2D.JOIN_MITER)
	if shrunk.is_empty():
		return points
	return shrunk[0]

# Flat mesh of a (possibly concave) polygon at depth z.
static func fill(points: PackedVector2Array, z: float = 0.0) -> ArrayMesh:
	var indices := Geometry2D.triangulate_polygon(points)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for p in points:
		vertices.append(Vector3(p.x, p.y, z))
		normals.append(Vector3(0, 0, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	var mesh := ArrayMesh.new()
	if indices.size() >= 3:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
