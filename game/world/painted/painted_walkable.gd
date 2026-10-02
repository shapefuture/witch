class_name PaintedWalkable
extends RefCounted

# Where a character may stand in a painted room: the "walkable" block of room.json, derived from the room's
# depth by tools/painted/walkable.py (see docs/art/painted_room.md). A coarse grid in world x/z: '#' the
# character's centre may be there, '+' floor that is too near an edge for her body, '.' not floor; and the
# floor's height per cell (the dais is a step the depth model smooths into a ramp). Paths are planned by
# GridNavigator, the same A* the archive hall walks on.

# How far above the floor a pixel's surface may be and still count as the floor (a tap just above a wall's foot).
const FLOOR_TOLERANCE := 0.10
# A tap on floor too near an edge walks to the nearest place the body fits, if it is this close (metres).
const SNAP_REACH := 1.0

var cell := 0.25
var origin := Vector2.ZERO
var size := Vector2i.ZERO
var obstacles: Array = []
var navigator: GridNavigator
var _rows: Array[String] = []
var _heights := PackedFloat32Array()

static func from_room(data: Dictionary) -> PaintedWalkable:
	var block: Variant = data.get("walkable")
	if not block is Dictionary:
		return null
	var walkable := PaintedWalkable.new()
	walkable._load(block)
	return walkable

func _load(block: Dictionary) -> void:
	cell = float(block["cell"])
	origin = Vector2(float(block["origin"][0]), float(block["origin"][1]))
	size = Vector2i(int(block["size"][0]), int(block["size"][1]))
	for row in block["rows"]:
		_rows.append(str(row))
	for centimetres in block["heights_cm"]:
		_heights.append(float(centimetres) * 0.01)
	obstacles = block.get("obstacles", [])
	navigator = GridNavigator.new(Rect2(origin, Vector2(size) * cell), cell)
	navigator.block_where(func(p: Vector2) -> bool: return not is_standable(p.x, p.y))

func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - origin.x) / cell), floori((z - origin.y) / cell))

func center_of(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell

func _char_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return "."
	return _rows[c.y][c.x]

# The character's centre may be here.
func is_standable(x: float, z: float) -> bool:
	return _char_at(cell_of(x, z)) == "#"

# Floor, whether or not a body fits.
func is_floor(x: float, z: float) -> bool:
	return _char_at(cell_of(x, z)) != "."

func cell_height(c: Vector2i) -> float:
	return _heights[c.y * size.x + c.x] if _char_at(c) != "." else 0.0

# The floor's height (metres) under a point, bilinear over the floor cells around it.
func height_at(x: float, z: float) -> float:
	var gx := (x - origin.x) / cell - 0.5
	var gz := (z - origin.y) / cell - 0.5
	var x0 := floori(gx)
	var z0 := floori(gz)
	var fx := gx - x0
	var fz := gz - z0
	var total := 0.0
	var weight := 0.0
	for dz in 2:
		for dx in 2:
			var c := Vector2i(x0 + dx, z0 + dz)
			if _char_at(c) == ".":
				continue
			var w := (fx if dx == 1 else 1.0 - fx) * (fz if dz == 1 else 1.0 - fz)
			total += w * _heights[c.y * size.x + c.x]
			weight += w
	if weight > 0.0001:
		return total / weight
	var nearest := nearest_standable(x, z, 2.0)
	return height_at(nearest.x, nearest.y) if nearest != Vector2.INF and (nearest.x != x or nearest.y != z) else 0.0

# The nearest standable cell's centre within `reach` metres of (x, z), or Vector2.INF.
func nearest_standable(x: float, z: float, reach: float = SNAP_REACH) -> Vector2:
	var here := cell_of(x, z)
	var best := Vector2.INF
	var best_distance := reach
	var rings := ceili(reach / cell) + 1
	for dz in range(-rings, rings + 1):
		for dx in range(-rings, rings + 1):
			var c := here + Vector2i(dx, dz)
			if _char_at(c) != "#":
				continue
			var p := center_of(c)
			var d := p.distance_to(Vector2(x, z))
			if d < best_distance:
				best_distance = d
				best = p
	return best

# Where a tap on a painting surface point (the room mesh under the pixel) sends the character, or Vector3.INF
# when the tap is not on the floor: on a wall, on an object, on floor she cannot reach, behind the frame.
# A tap that fits keeps the surface point's own height, so her feet land exactly on the painted pixel; one that
# does not (floor too near an edge) goes to the nearest place that does, at that place's floor height.
func floor_target(surface_point: Vector3) -> Vector3:
	var x := surface_point.x
	var z := surface_point.z
	if not is_floor(x, z) or absf(surface_point.y - height_at(x, z)) > FLOOR_TOLERANCE:
		return Vector3.INF
	if is_standable(x, z):
		return surface_point
	var snapped := nearest_standable(x, z)
	if snapped == Vector2.INF:
		return Vector3.INF
	return Vector3(snapped.x, height_at(snapped.x, snapped.y), snapped.y)

# Waypoints (world, y = the floor's height; the last keeps `to`'s own height when she can stand exactly there)
# from one point to another, around whatever is not floor. Empty when there is nowhere to go.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var flat := navigator.find_path(from, to)
	var out := PackedVector3Array()
	for p in flat:
		out.append(Vector3(p.x, height_at(p.x, p.z), p.z))
	if not out.is_empty() and Vector2(out[out.size() - 1].x, out[out.size() - 1].z).distance_to(Vector2(to.x, to.z)) < 0.001:
		out[out.size() - 1].y = to.y
	return out

func standable_count() -> int:
	var n := 0
	for row in _rows:
		n += row.count("#")
	return n
