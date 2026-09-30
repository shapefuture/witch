class_name GridNavigator
extends RefCounted

# Deterministic walk-planning for a small diorama: an A* grid over the floor with solid cells
# for obstacles. Chosen over NavigationServer3D because a room this size needs no baked mesh,
# runs identically headless, and is fully reproducible (a requirement for the simulation and
# render regression modes).

const CELL := 0.5

var _grid := AStarGrid2D.new()
var _origin := Vector2.ZERO
var _size := Vector2i.ZERO

# `bounds` is the walkable rectangle in world XZ.
func _init(bounds: Rect2) -> void:
	_origin = bounds.position
	_size = Vector2i(ceili(bounds.size.x / CELL), ceili(bounds.size.y / CELL))
	_grid.region = Rect2i(Vector2i.ZERO, _size)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()

func block_disc(center: Vector3, radius: float) -> void:
	var c := _to_cell(Vector2(center.x, center.z))
	var reach := ceili(radius / CELL) + 1
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var cell := c + Vector2i(dx, dy)
			if _in_grid(cell) and _cell_center(cell).distance_to(Vector2(center.x, center.z)) <= radius:
				_grid.set_point_solid(cell, true)

# Blocks everything farther than `radius` from the origin except a gap around `gap_center`.
func block_outside(radius: float, gap_center: Vector3, gap_half_width: float) -> void:
	for x in range(_size.x):
		for y in range(_size.y):
			var p := _cell_center(Vector2i(x, y))
			if p.length() > radius and p.distance_to(Vector2(gap_center.x, gap_center.z)) > gap_half_width:
				_grid.set_point_solid(Vector2i(x, y), true)

func is_blocked(point: Vector3) -> bool:
	var cell := _to_cell(Vector2(point.x, point.z))
	return not _in_grid(cell) or _grid.is_point_solid(cell)

func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := _nearest_free(_to_cell(Vector2(from.x, from.z)))
	var goal := _nearest_free(_to_cell(Vector2(to.x, to.z)))
	var out := PackedVector3Array()
	if not _in_grid(start) or not _in_grid(goal):
		return out
	var cells: Array[Vector2i] = []
	for cell in _grid.get_id_path(start, goal):
		cells.append(cell)
	cells = _smooth(cells)
	for cell in cells:
		var p := _cell_center(cell)
		out.append(Vector3(p.x, 0.0, p.y))
	# Walk exactly to a reachable requested destination, not just to its cell centre.
	if not out.is_empty() and not is_blocked(to):
		out[out.size() - 1] = Vector3(to.x, 0.0, to.z)
	return out

func _smooth(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 2:
		return cells
	var out: Array[Vector2i] = [cells[0]]
	var anchor := 0
	var probe := 2
	while probe < cells.size():
		if not _line_clear(cells[anchor], cells[probe]):
			out.append(cells[probe - 1])
			anchor = probe - 1
		probe += 1
	out.append(cells[cells.size() - 1])
	return out

func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	if steps == 0:
		return true
	for i in range(steps + 1):
		var t := float(i) / steps
		var cell := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if _grid.is_point_solid(cell):
			return false
	return true

func _nearest_free(cell: Vector2i) -> Vector2i:
	if _in_grid(cell) and not _grid.is_point_solid(cell):
		return cell
	for ring in range(1, 12):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var candidate := cell + Vector2i(dx, dy)
				if _in_grid(candidate) and not _grid.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)

func _to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - _origin.x) / CELL), floori((p.y - _origin.y) / CELL))

func _cell_center(cell: Vector2i) -> Vector2:
	return _origin + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL

func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y
