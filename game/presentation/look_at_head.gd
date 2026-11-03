class_name LookAtHead
extends SkeletonModifier3D

# A procedural head turn layered on whatever clip is playing: the head (and the neck, when the skeleton has one)
# turns toward a world point over a few frames, holds, and hands the pose back to the clip.
#
#   var gaze := LookAtHead.of(visual)        # CharacterModels adds one under every skeleton with a "head" bone
#   gaze.look_at_point(world_point, 1.6)     # turn in, hold 1.6 s, release (a negative hold keeps looking)
#
# The aim is measured in the frame of the bone above the chain (spine or chest, as the clip poses it), so the
# limits are a body's limits: yaw YAW_LIMIT_DEG either side, pitch PITCH_LIMIT_DEG up or down. A target behind the
# character is looked toward as far as the neck allows, never through the shoulder. The turn is a rotation applied
# on top of the clip's own head pose, scaled by an eased weight, so at weight 0 the clip's pose is untouched.
# Bones face +Z in the character kit (tools/characters): the head's forward is its local +Z.
#
# Not LookAtModifier3D: it turns one bone, has no hold-and-release, and splitting the turn between neck and head
# would take two of them fighting over one target.

signal released

const YAW_LIMIT_DEG := 70.0
const PITCH_LIMIT_DEG := 30.0
# The neck's share of the turn; the head takes the rest.
const NECK_SHARE := 0.4
const FORWARD := Vector3(0, 0, 1)

enum Phase { IDLE, TURNING, HOLDING, RELEASING }

@export var head_name := "head"
@export var neck_name := "neck"
var yaw_limit := deg_to_rad(YAW_LIMIT_DEG)
var pitch_limit := deg_to_rad(PITCH_LIMIT_DEG)
var turn_time := 0.25
var release_time := 0.45
# How fast the aim follows a target that moves while held (1/s).
var follow_rate := 12.0

var head_bone := -1
var neck_bone := -1
var phase := Phase.IDLE
var target := Vector3.INF
var hold_time := 1.6
var _weight := 0.0
var _held := 0.0
var _aim := Vector2.ZERO
var _aim_fresh := true

# Adds a LookAtHead under every skeleton below `visual` that has a head bone. Returns the first (null if none).
static func attach_to(visual: Node) -> LookAtHead:
	if visual == null:
		return null
	var first: LookAtHead = null
	for node in visual.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		if skeleton.find_bone("head") < 0:
			continue
		var gaze: LookAtHead = _child_of(skeleton)
		if gaze == null:
			gaze = LookAtHead.new()
			gaze.name = "LookAtHead"
			skeleton.add_child(gaze)
		if first == null:
			first = gaze
	return first

# The LookAtHead under `node` (a character's visual, or anything above it), or null.
static func of(node: Node) -> LookAtHead:
	if node == null:
		return null
	if node is LookAtHead:
		return node as LookAtHead
	for found in node.find_children("*", "Skeleton3D", true, false):
		var gaze := _child_of(found)
		if gaze != null:
			return gaze
	return null

static func _child_of(skeleton: Node) -> LookAtHead:
	for child in skeleton.get_children():
		if child is LookAtHead:
			return child as LookAtHead
	return null

# Turn toward `world_point`, hold for `hold` seconds (negative: until release()), then return to the clip.
func look_at_point(world_point: Vector3, hold: float = 1.6) -> void:
	if not world_point.is_finite():
		return
	target = world_point
	hold_time = hold
	_held = 0.0
	if phase == Phase.IDLE:
		_aim_fresh = true
	phase = Phase.HOLDING if _weight >= 1.0 else Phase.TURNING

func release() -> void:
	if phase != Phase.IDLE:
		phase = Phase.RELEASING

func is_looking() -> bool:
	return phase != Phase.IDLE

# The eased blend of the turn over the clip, 0..1.
func weight() -> float:
	return smoothstep(0.0, 1.0, _weight)

# Where the head is, in world space (the clip's head plus whatever this modifier did last).
func head_world_position() -> Vector3:
	var skeleton := get_skeleton()
	if skeleton == null or not _bones_ready(skeleton):
		return Vector3.INF
	return skeleton.global_transform * skeleton.get_bone_global_pose(head_bone).origin

func _bones_ready(skeleton: Skeleton3D) -> bool:
	if head_bone < 0:
		head_bone = skeleton.find_bone(head_name)
		var neck := skeleton.find_bone(neck_name)
		neck_bone = neck if neck >= 0 and skeleton.get_bone_parent(head_bone) == neck else -1
	return head_bone >= 0

func _advance(delta: float) -> void:
	match phase:
		Phase.TURNING:
			_weight = minf(1.0, _weight + delta / maxf(turn_time, 0.001))
			if _weight >= 1.0:
				phase = Phase.HOLDING
		Phase.HOLDING:
			_held += delta
			if hold_time >= 0.0 and _held >= hold_time:
				phase = Phase.RELEASING
		Phase.RELEASING:
			_weight = maxf(0.0, _weight - delta / maxf(release_time, 0.001))
			if _weight <= 0.0:
				phase = Phase.IDLE
				target = Vector3.INF
				released.emit()

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not _bones_ready(skeleton):
		return
	_advance(delta)
	if _weight <= 0.0 or not target.is_finite():
		return
	var top := neck_bone if neck_bone >= 0 else head_bone
	var above := skeleton.get_bone_parent(top)
	var body := skeleton.get_bone_global_pose(above).basis.orthonormalized() if above >= 0 else Basis.IDENTITY
	var head := skeleton.get_bone_global_pose(head_bone)
	var to_target := (skeleton.global_transform.affine_inverse() * target) - head.origin
	if to_target.length_squared() < 0.000001:
		return
	var goal := _clamped(_angles(body.transposed() * to_target))
	if _aim_fresh:
		_aim = goal
		_aim_fresh = false
	else:
		_aim = _aim.lerp(goal, 1.0 - exp(-follow_rate * delta))
	var facing := _angles(body.transposed() * (head.basis * FORWARD))
	var w := weight()
	var aimed := Vector2(lerp_angle(facing.x, _aim.x, w), lerpf(facing.y, _aim.y, w))
	var turn_in_body := _facing_basis(aimed) * _facing_basis(facing).inverse()
	var turn := body * turn_in_body * body.transposed()
	if neck_bone >= 0:
		var share := Basis(Quaternion.IDENTITY.slerp(turn_in_body.get_rotation_quaternion(), NECK_SHARE))
		_set_global_rotation(skeleton, neck_bone, body * share * body.transposed() * skeleton.get_bone_global_pose(neck_bone).basis)
	_set_global_rotation(skeleton, head_bone, turn * head.basis)

# (yaw, pitch) of a direction in the body frame: yaw about +Y from +Z toward +X, pitch up from the floor plane.
static func _angles(direction: Vector3) -> Vector2:
	return Vector2(atan2(direction.x, direction.z), atan2(direction.y, Vector2(direction.x, direction.z).length()))

func _clamped(angles: Vector2) -> Vector2:
	return Vector2(clampf(angles.x, -yaw_limit, yaw_limit), clampf(angles.y, -pitch_limit, pitch_limit))

# The rotation that takes +Z to the direction (yaw, pitch), with no roll.
static func _facing_basis(angles: Vector2) -> Basis:
	return Basis(Vector3.UP, angles.x) * Basis(Vector3.RIGHT, -angles.y)

func _set_global_rotation(skeleton: Skeleton3D, bone: int, global_basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := parent_basis.inverse() * global_basis
	skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
