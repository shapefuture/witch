class_name CameraDirector
extends Node

# Chooses the composition for the current dramatic beat. Presentation entries from a committed
# result ({"kind":"camera","mode":...,"focus":[ids]}) are the ONLY thing that moves the camera,
# so framing is authored alongside the content it serves.
#
# Modes: wide (the room), inspect (close on a thing), conversation (two-shot),
# magic_reveal (low, wide and tipped 45 degrees while the lens swings to a fisheye; the cut back
# to the wide shot is the snap), consequence (hold on the result),
# stay (freeze: the camera does not follow; the ending contract).
#
# Stage-play grammar: the camera is bolted, so changing shot is a CUT, not a move. Only the
# magic reveal eases (the lens swinging out is the point). Each shot carries a small Dutch roll so
# the frame feels staged rather than level.

const MODES := ["wide", "inspect", "conversation", "magic_reveal", "consequence", "stay"]
const EASED_MODES := ["magic_reveal"]

signal cut(mode: String)

var camera: DioramaCamera
# func() -> Dictionary                 the room's default framing (Room.framing())
var framing_provider: Callable
# func(id: String) -> Variant          a world position for a focus id, or null
var focus_resolver: Callable
var mode := "wide"
var frozen := false

# Pure: which pose does `mode` want, given where its focus targets are? Returns {} for "stay".
static func compute_pose(pose_mode: String, focus_points: Array, room_framing: Dictionary) -> Dictionary:
	if pose_mode == "stay":
		return {}
	var room_focus: Vector3 = room_framing["focus"]
	var center := room_focus
	if not focus_points.is_empty():
		center = Vector3.ZERO
		for point in focus_points:
			center += point
		center /= focus_points.size()
	var base_distance: float = room_framing["distance"]
	var base_pitch: float = room_framing["pitch_deg"]
	var base_yaw: float = room_framing["yaw_deg"]
	var base_fov: float = room_framing["fov"]
	var base_roll: float = room_framing.get("roll_deg", 0.0)
	match pose_mode:
		"inspect":
			return {"look_at": center + Vector3(0, 0.6, 0), "distance": base_distance * 0.5, "pitch_deg": base_pitch - 3.0, "yaw_deg": base_yaw, "roll_deg": base_roll - 1.5, "fov": base_fov - 8.0}
		"conversation":
			return {"look_at": center + Vector3(0, 1.0, 0), "distance": base_distance * 0.46, "pitch_deg": base_pitch - 3.0, "yaw_deg": base_yaw + 16.0, "roll_deg": base_roll + 2.2, "fov": base_fov - 10.0}
		"magic_reveal":
			return {"look_at": center + Vector3(0, 1.2, 0), "distance": base_distance * 0.8, "pitch_deg": base_pitch - 11.0, "yaw_deg": base_yaw, "roll_deg": base_roll - 45.0, "fov": base_fov + 8.0}
		"consequence":
			return {"look_at": center + Vector3(0, 0.9, 0), "distance": base_distance * 0.55, "pitch_deg": base_pitch - 2.0, "yaw_deg": base_yaw - 10.0, "roll_deg": base_roll - 1.2, "fov": base_fov - 6.0}
	return {"look_at": room_focus, "distance": base_distance, "pitch_deg": base_pitch, "yaw_deg": base_yaw, "roll_deg": base_roll, "fov": base_fov}

# Camera position for a look-at point, distance and angles. yaw 0 puts the camera on the +Z
# side looking toward -Z; pitch is the downward angle.
static func placement(look_at: Vector3, distance: float, pitch_deg: float, yaw_deg: float) -> Vector3:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	return look_at + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance

func frame(new_mode: String, focus_ids: Array = [], instant: bool = false) -> void:
	if new_mode not in MODES:
		push_warning("CameraDirector: unknown mode '%s'" % new_mode)
		return
	mode = new_mode
	if new_mode == "stay":
		# The ending contract: from here the camera does not follow anyone. It also stops
		# where it is: without re-targeting it would keep easing toward its previous pose.
		frozen = true
		if camera != null:
			camera.set_pose(camera.current_pose())
		return
	frozen = false
	var points: Array = []
	for id in focus_ids:
		var resolved: Variant = focus_resolver.call(str(id)) if focus_resolver.is_valid() else null
		if resolved is Vector3:
			points.append(resolved)
	var pose := compute_pose(new_mode, points, framing_provider.call())
	if camera != null:
		camera.set_pose(pose, instant or new_mode not in EASED_MODES)
	cut.emit(new_mode)

func return_to_wide(instant: bool = false) -> void:
	if not frozen:
		frame("wide", [], instant)
