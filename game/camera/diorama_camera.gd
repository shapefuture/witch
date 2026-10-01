class_name DioramaCamera
extends Camera3D

# A composed camera, not a free one. It is described by a look-at point, a distance, two angles
# and a roll (the Dutch tilt), and it never follows anyone: the CameraDirector asks for a pose and
# the camera either CUTS to it (the stage-play default) or eases to it (the spell's swing).
# The player never drives it (DESIGN_INVARIANTS: the camera is authored).
#
# On a plate's pose (the pose carries "plate_aspect") the set is a pre-rendered picture with no roll in
# it; the roll is added here, and the lens closes just enough (roll_fit) that the rolled frame never
# leaves the plate. A pose may also ask for a slow push-in ("dolly", metres) after it arrives: the
# spell's shot moves for real, so the projected set shows real parallax.

const EASE_RATE := 3.5
const DOLLY_SECONDS := 3.0

var look_at_point := Vector3.ZERO
var distance := 12.0
var pitch_deg := 32.0
var yaw_deg := 0.0
var roll_deg := 0.0
# The pose's lens; `fov` (what is drawn) is this, closed down to fit a plate when there is one.
var lens_fov := 70.0
var plate_aspect := 0.0
var _target: Dictionary = {}
var _dolly := 0.0
var _dolly_time := 0.0
# Capture aid: while true the camera ignores every pose request (see debug_place).
var locked := false

func set_pose(pose: Dictionary, instant: bool = false) -> void:
	if locked:
		return
	_target = pose.duplicate()
	_dolly = float(pose.get("dolly", 0.0))
	_dolly_time = 0.0
	if instant:
		look_at_point = pose["look_at"]
		distance = pose["distance"]
		pitch_deg = pose["pitch_deg"]
		yaw_deg = pose["yaw_deg"]
		roll_deg = float(pose.get("roll_deg", 0.0))
		lens_fov = pose["fov"]
		plate_aspect = float(pose.get("plate_aspect", 0.0))
		_apply()
	else:
		# ease from what is on screen, not from the plate's wider lens
		lens_fov = fov
		plate_aspect = float(pose.get("plate_aspect", 0.0))

# Capture aid (--cam): puts the camera exactly somewhere, bypassing the pose easing.
func debug_place(from: Vector3, to: Vector3, field_of_view: float, roll: float = 0.0) -> void:
	locked = true
	_target = {}
	fov = field_of_view
	lens_fov = field_of_view
	plate_aspect = 0.0
	look_at_from_position(from, to, Vector3.UP)
	if absf(roll) > 0.001:
		rotate_object_local(Vector3.BACK, deg_to_rad(roll))

func current_pose() -> Dictionary:
	return {"look_at": look_at_point, "distance": distance, "pitch_deg": pitch_deg, "yaw_deg": yaw_deg, "roll_deg": roll_deg, "fov": lens_fov}

# The largest vertical half-tangent a screen of `aspect`, rolled by `roll`, can have and still lie
# inside a plate whose half-tangents are (tan_half_v * plate_aspect_, tan_half_v).
static func roll_fit(tan_half_v: float, plate_aspect_: float, roll: float, aspect: float) -> float:
	var c := absf(cos(deg_to_rad(roll)))
	var s := absf(sin(deg_to_rad(roll)))
	return minf(tan_half_v / (c + aspect * s), tan_half_v * plate_aspect_ / (aspect * c + s))

# The field of view actually drawn: the lens, closed down to stay inside the plate when on one.
func effective_fov() -> float:
	if plate_aspect <= 0.0:
		return lens_fov
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	var tv := tan(deg_to_rad(lens_fov) * 0.5)
	var fit := roll_fit(tv, plate_aspect, roll_deg, size.x / maxf(size.y, 1.0))
	return rad_to_deg(2.0 * atan(minf(tv, fit)))

func _process(delta: float) -> void:
	if _target.is_empty():
		return
	var t := 1.0 - exp(-EASE_RATE * delta)
	look_at_point = look_at_point.lerp(_target["look_at"], t)
	if _dolly == 0.0:
		distance = lerpf(distance, _target["distance"], t)
	pitch_deg = lerpf(pitch_deg, _target["pitch_deg"], t)
	yaw_deg = lerp_angle(deg_to_rad(yaw_deg), deg_to_rad(_target["yaw_deg"]), t) * 180.0 / PI
	roll_deg = lerpf(roll_deg, float(_target.get("roll_deg", 0.0)), t)
	lens_fov = lerpf(lens_fov, _target["fov"], t)
	if _dolly != 0.0:
		_dolly_time += delta
		var push := clampf(_dolly_time / DOLLY_SECONDS, 0.0, 1.0)
		distance = lerpf(distance, float(_target["distance"]) - _dolly * push * push * (3.0 - 2.0 * push), t)
	_apply()

# Re-derives the drawn lens (after the screen changed shape).
func refit() -> void:
	if not _target.is_empty() or plate_aspect > 0.0:
		_apply()

func _apply() -> void:
	fov = effective_fov()
	var at := CameraDirector.placement(look_at_point, distance, pitch_deg, yaw_deg)
	if not at.is_equal_approx(look_at_point):
		look_at_from_position(at, look_at_point, Vector3.UP)
		if absf(roll_deg) > 0.001:
			rotate_object_local(Vector3.BACK, deg_to_rad(roll_deg))
