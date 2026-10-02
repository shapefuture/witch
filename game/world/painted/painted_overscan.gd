class_name PaintedOverscan
extends RefCounted

# The margin of a painted room (docs/art/painted_room.md, "Margins"): tools/painted/extend_plate.py paints a few
# percent more picture around the plate and tools/painted/extend_room.py gives it depth. The plate's own pixel
# coordinates never change (props, actors, taps keep their meaning); the margin is coordinates below zero and
# past the plate's size. This file holds the arithmetic, so painted_room.gd only wires it in.

# room.json may carry the block inline ("overscan": {...}) or beside it as overscan.json (so a room whose depth
# was built earlier gains a margin without rewriting its room.json).
static func load_for(room: Dictionary, room_dir: String) -> Dictionary:
	var inline: Variant = room.get("overscan", null)
	if inline is Dictionary:
		return inline
	var path := room_dir.path_join("overscan.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func margin_of(overscan: Dictionary) -> Vector2:
	if overscan.is_empty():
		return Vector2.ZERO
	var m: Array = overscan["margin"]
	return Vector2(float(m[0]), float(m[1]))

# The vertical field of view (degrees) that keeps a view of shape `aspect` (width / height), rolled by `roll`
# (radians), inside a painting of `size` pixels with `margin` extra pixels on each side: the painting's own
# `base_fov` when it fits, narrower (a zoom) by exactly as much as it takes when it does not.
static func fov_for(base_fov: float, size: Vector2, margin: Vector2, aspect: float, roll: float) -> float:
	var c := absf(cos(roll))
	var s := absf(sin(roll))
	var half := size * 0.5
	# The rolled view's bounding box, in units of its own half-height h: (aspect * c + s) h wide, (aspect * s + c) h tall.
	var fit_x := (half.x + margin.x) / (half.y * (aspect * c + s))
	var fit_y := (half.y + margin.y) / (half.y * (aspect * s + c))
	var zoom := minf(1.0, minf(fit_x, fit_y))
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) * zoom))

# Where painting pixel `px` lands in the extended plate texture, 0..1.
static func plate_uv(px: Vector2, size: Vector2, margin: Vector2) -> Vector2:
	return (px + margin) / (size + margin * 2.0)

# The painting pixel of grid vertex (i, j): the grid keeps the plate's sample positions (multiples of `step`
# from `origin`), and its outermost vertices are clamped to the plate's edge.
static func vertex_pixel(i: int, j: int, origin: Vector2, step: float, size: Vector2, margin: Vector2) -> Vector2:
	return Vector2(
		clampf(origin.x + i * step, -margin.x, size.x + margin.x),
		clampf(origin.y + j * step, -margin.y, size.y + margin.y))
