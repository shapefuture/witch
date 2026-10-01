class_name DioramaCamera
extends Camera3D

# A composed camera, not a free one. It is described by a look-at point, a distance, two angles
# and a roll (the Dutch tilt), and it never follows anyone: the CameraDirector asks for a pose and
# the camera either CUTS to it (the stage-play default) or eases to it (the spell's swing).
# The player never drives it (DESIGN_INVARIANTS: the camera is authored).

const EASE_RATE := 3.5

var look_at_point := Vector3.ZERO
var distance := 12.0
var pitch_deg := 32.0
var yaw_deg := 0.0
var roll_deg := 0.0
var _target: Dictionary = {}
# Capture aid: while true the camera ignores every pose request (see debug_place).
var locked := false

func set_pose(pose: Dictionary, instant: bool = false) -> void:
	if locked:
		return
	_target = pose.duplicate()
	if instant:
		look_at_point = pose["look_at"]
		distance = pose["distance"]
		pitch_deg = pose["pitch_deg"]
		yaw_deg = pose["yaw_deg"]
		roll_deg = float(pose.get("roll_deg", 0.0))
		fov = pose["fov"]
		_apply()

# Capture aid (--cam): puts the camera exactly somewhere, bypassing the pose easing.
func debug_place(from: Vector3, to: Vector3, field_of_view: float, roll: float = 0.0) -> void:
	locked = true
	_target = {}
	fov = field_of_view
	look_at_from_position(from, to, Vector3.UP)
	if absf(roll) > 0.001:
		rotate_object_local(Vector3.BACK, deg_to_rad(roll))

func current_pose() -> Dictionary:
	return {"look_at": look_at_point, "distance": distance, "pitch_deg": pitch_deg, "yaw_deg": yaw_deg, "roll_deg": roll_deg, "fov": fov}

func _process(delta: float) -> void:
	if _target.is_empty():
		return
	var t := 1.0 - exp(-EASE_RATE * delta)
	look_at_point = look_at_point.lerp(_target["look_at"], t)
	distance = lerpf(distance, _target["distance"], t)
	pitch_deg = lerpf(pitch_deg, _target["pitch_deg"], t)
	yaw_deg = lerp_angle(deg_to_rad(yaw_deg), deg_to_rad(_target["yaw_deg"]), t) * 180.0 / PI
	roll_deg = lerpf(roll_deg, float(_target.get("roll_deg", 0.0)), t)
	fov = lerpf(fov, _target["fov"], t)
	_apply()

func _apply() -> void:
	var at := CameraDirector.placement(look_at_point, distance, pitch_deg, yaw_deg)
	if not at.is_equal_approx(look_at_point):
		look_at_from_position(at, look_at_point, Vector3.UP)
		if absf(roll_deg) > 0.001:
			rotate_object_local(Vector3.BACK, deg_to_rad(roll_deg))
