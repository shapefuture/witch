class_name PaintedWalker
extends Node

# Walks a character (the holder PaintedRoom spawned) along a path over the painted floor: the same pace, arrival
# distance and turn rate as the archive hall's Witch, but on the floor's own height so her feet stay on the
# painted pixels, with the character's own walk and idle clips. She is a real 3D model at a world position, so
# perspective scale is automatic and the room mesh and the prop cards hide her where they are nearer.

# Emitted when a walk finishes (reached = true) or is cancelled by a newer order (false), as Witch.walk_ended.
signal walk_ended(reached: bool)

# The feet float this far above the painted floor so the soles never fight the room mesh for the pixel.
const FOOT_LIFT := 0.012

var body: Node3D
var visual: Node3D
var walkable: PaintedWalkable
var speed := Witch.SPEED
var walk_clip := "walk"
var idle_clip := "idle"
var _path := PackedVector3Array()
var _index := 0
var _end_bias := 0.0
var _facing_target := Vector3.ZERO
var _has_facing := false

func setup(p_body: Node3D, p_visual: Node3D, p_walkable: PaintedWalkable) -> void:
	body = p_body
	visual = p_visual
	walkable = p_walkable

func is_walking() -> bool:
	return _index < _path.size()

func destination() -> Vector3:
	return _path[_path.size() - 1] if not _path.is_empty() else body.position

# Starts walking along `path` (world points, as PaintedWalkable.find_path gives them). A newer order cancels the
# one before it. Returns false for an empty path.
func walk_path(path: PackedVector3Array) -> bool:
	if is_walking():
		_end(false)
	if path.is_empty():
		return false
	_path = path
	_index = 0
	_has_facing = false
	var last := path[path.size() - 1]
	_end_bias = last.y - walkable.height_at(last.x, last.z)
	_set_walking(true)
	return true

func stop() -> void:
	if is_walking():
		_end(false)

func face_toward(point: Vector3) -> void:
	_facing_target = point
	_has_facing = true

func advance(delta: float) -> void:
	if body == null:
		return
	if is_walking():
		var waypoint := _path[_index]
		var to_waypoint := Vector3(waypoint.x - body.position.x, 0.0, waypoint.z - body.position.z)
		var last := _index == _path.size() - 1
		# A corner is cut within the archive hall's arrival distance; the last point is reached exactly, so her
		# feet land on the painted pixel that was tapped.
		if to_waypoint.length() <= (0.0005 if last else Witch.ARRIVE_DISTANCE):
			_index += 1
			if last:
				body.position = Vector3(waypoint.x, waypoint.y + FOOT_LIFT, waypoint.z)
				_end(true)
			return
		var moved := to_waypoint.normalized() * minf(speed * delta, to_waypoint.length())
		body.position.x += moved.x
		body.position.z += moved.z
		# The floor's height, eased onto the tapped pixel's own height over the last stretch.
		var to_end := Vector2(_path[_path.size() - 1].x - body.position.x, _path[_path.size() - 1].z - body.position.z).length()
		var bias := _end_bias * (1.0 - smoothstep(0.0, 0.8, to_end))
		body.position.y = walkable.height_at(body.position.x, body.position.z) + bias + FOOT_LIFT
		_turn_toward(body.position + to_waypoint, delta)
	elif _has_facing:
		_turn_toward(_facing_target, delta)

func _end(reached: bool) -> void:
	_path = PackedVector3Array()
	_index = 0
	_set_walking(false)
	walk_ended.emit(reached)

func _set_walking(on: bool) -> void:
	CharacterModels.play(visual, walk_clip if on else idle_clip)

func _turn_toward(point: Vector3, delta: float) -> void:
	var direction := Vector3(point.x - body.position.x, 0.0, point.z - body.position.z)
	if direction.length() < 0.01:
		return
	body.rotation.y = lerp_angle(body.rotation.y, atan2(direction.x, direction.z), clampf(Witch.TURN_RATE * delta, 0.0, 1.0))
