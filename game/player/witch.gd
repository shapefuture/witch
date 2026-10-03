class_name Witch
extends CharacterBody3D

# The visible protagonist. She walks to where she is told (click/tap-to-move); everything she
# DOES when she gets there is an action submitted to Mirror, not something this script decides.

# Emitted when a walk finishes (reached = true) or is cancelled by a newer order (false).
signal walk_ended(reached: bool)

const SPEED := 2.8
const ARRIVE_DISTANCE := 0.12
const TURN_RATE := 10.0
# "witch" (purple star hood, orange curls) or "witch_antler" (felt hood, branch antlers).
const MODEL_ID := "witch"

var navigator: GridNavigator
var animation := WitchAnimation.new()
var visual: Node3D
var _path := PackedVector3Array()
var _index := 0
var _facing_target := Vector3.ZERO
var _has_facing := false

func _ready() -> void:
	collision_layer = PhysicsLayers.ACTOR
	collision_mask = PhysicsLayers.WORLD
	add_to_group("camera_target")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0, 0.8, 0)
	add_child(shape)
	var model := CharacterModels.instantiate(MODEL_ID)
	set_visual(model if model != null else Placeholders.witch())
	add_child(animation)
	BlobShadow.attach(self, 0.42, 1.05)

func set_visual(new_visual: Node3D) -> void:
	if visual != null:
		visual.queue_free()
	visual = new_visual
	add_child(visual)
	animation.visual = visual

func is_walking() -> bool:
	return _index < _path.size()

# Plans a walk to `point` (world XZ). Returns false if there is nowhere to go.
func move_to(point: Vector3) -> bool:
	if navigator == null:
		return false
	_path = navigator.find_path(global_position, point)
	_index = 0
	_has_facing = false
	animation.walking = not _path.is_empty()
	return not _path.is_empty()

# Walks there and returns true if she arrived, false if the walk was cancelled or impossible.
func walk_to(point: Vector3) -> bool:
	if global_position.distance_to(Vector3(point.x, global_position.y, point.z)) <= ARRIVE_DISTANCE:
		return true
	if not move_to(point):
		return false
	return await walk_ended

func stop() -> void:
	var was_walking := is_walking()
	_path = PackedVector3Array()
	_index = 0
	animation.walking = false
	if was_walking:
		walk_ended.emit(false)

# Leaves the scene in a straight line, ignoring the walkable grid (the ending's exit).
func walk_off(to: Vector3) -> void:
	collision_mask = 0
	_path = PackedVector3Array([Vector3(to.x, 0.0, to.z)])
	_index = 0
	_has_facing = false
	animation.walking = true
	await walk_ended

func face_toward(point: Vector3) -> void:
	_facing_target = point
	_has_facing = true

func _physics_process(delta: float) -> void:
	if _index < _path.size():
		var waypoint := _path[_index]
		var to_waypoint := Vector3(waypoint.x - global_position.x, 0.0, waypoint.z - global_position.z)
		if to_waypoint.length() <= ARRIVE_DISTANCE:
			_index += 1
			if _index >= _path.size():
				_path = PackedVector3Array()
				_index = 0
				animation.walking = false
				walk_ended.emit(true)
			return
		velocity = to_waypoint.normalized() * SPEED
		_turn_toward(global_position + to_waypoint, delta)
		move_and_slide()
	else:
		velocity = Vector3.ZERO
		if _has_facing:
			_turn_toward(_facing_target, delta)

func _turn_toward(point: Vector3, delta: float) -> void:
	var direction := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if direction.length() < 0.01:
		return
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_RATE * delta, 0.0, 1.0))
