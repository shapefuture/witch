class_name DioramaCamera
extends Camera3D

# A composed camera, not a free one. It is described by a look-at point, a distance and two
# angles, and eases toward whatever pose the CameraDirector asks for. The player never drives
# it (DESIGN_INVARIANTS: the camera should feel authored).

const EASE_RATE := 3.5

var look_at_point := Vector3.ZERO
var distance := 12.0
var pitch_deg := 32.0
var yaw_deg := 0.0
var _target: Dictionary = {}

func set_pose(pose: Dictionary, instant: bool = false) -> void:
	_target = pose.duplicate()
	if instant:
		look_at_point = pose["look_at"]
		distance = pose["distance"]
		pitch_deg = pose["pitch_deg"]
		yaw_deg = pose["yaw_deg"]
		fov = pose["fov"]
		_apply()

func current_pose() -> Dictionary:
	return {"look_at": look_at_point, "distance": distance, "pitch_deg": pitch_deg, "yaw_deg": yaw_deg, "fov": fov}

func _process(delta: float) -> void:
	if _target.is_empty():
		return
	var t := 1.0 - exp(-EASE_RATE * delta)
	look_at_point = look_at_point.lerp(_target["look_at"], t)
	distance = lerpf(distance, _target["distance"], t)
	pitch_deg = lerpf(pitch_deg, _target["pitch_deg"], t)
	yaw_deg = lerp_angle(deg_to_rad(yaw_deg), deg_to_rad(_target["yaw_deg"]), t) * 180.0 / PI
	fov = lerpf(fov, _target["fov"], t)
	_apply()

func _apply() -> void:
	var at := CameraDirector.placement(look_at_point, distance, pitch_deg, yaw_deg)
	if not at.is_equal_approx(look_at_point):
		look_at_from_position(at, look_at_point, Vector3.UP)
