extends TestCase

const ROOM := {"focus": Vector3(0, 0.8, -1.2), "distance": 12.0, "pitch_deg": 32.0, "yaw_deg": 0.0, "fov": 40.0}

func test_every_mode_but_stay_yields_a_distinct_complete_pose() -> void:
	var seen := {}
	for mode in ["wide", "inspect", "conversation", "magic_reveal", "consequence"]:
		var pose := CameraDirector.compute_pose(mode, [Vector3(1, 0, 0)], ROOM)
		for key in ["look_at", "distance", "pitch_deg", "yaw_deg", "fov"]:
			ok(pose.has(key), "%s has %s" % [mode, key])
		seen[JSON.stringify([pose["distance"], pose["pitch_deg"], pose["yaw_deg"], pose["fov"]])] = true
	eq(seen.size(), 5, "five dramatic beats, five different compositions")

func test_stay_is_the_do_not_follow_contract() -> void:
	eq(CameraDirector.compute_pose("stay", [Vector3.ONE], ROOM), {}, "no pose: nothing to move toward")
	var director := CameraDirector.new()
	director.framing_provider = func() -> Dictionary: return ROOM
	director.frame("stay")
	ok(director.frozen, "frozen")
	director.return_to_wide()
	eq(director.mode, "stay", "later calls do not pull the camera back: it does not follow")
	director.frame("wide")
	ok(not director.frozen, "an authored composition unfreezes it")
	director.free()

func test_a_two_shot_is_centred_between_its_subjects_and_closer_than_the_room() -> void:
	var pose := CameraDirector.compute_pose("conversation", [Vector3(0, 0, 4), Vector3(0, 0, -2)], ROOM)
	eq(pose["look_at"].x, 0.0, "x")
	ok(is_equal_approx(pose["look_at"].z, 1.0), "centred on the midpoint")
	ok(pose["distance"] < ROOM["distance"], "closer than the wide shot")
	ok(pose["fov"] < ROOM["fov"], "longer lens")

func test_magic_reveal_is_lower_and_wider_than_the_room() -> void:
	var pose := CameraDirector.compute_pose("magic_reveal", [Vector3.ZERO], ROOM)
	ok(pose["pitch_deg"] < ROOM["pitch_deg"], "lower angle: heroic")
	ok(pose["fov"] > ROOM["fov"], "wider: reality opening")

func test_no_focus_falls_back_to_the_rooms_own_focus() -> void:
	eq(CameraDirector.compute_pose("wide", [], ROOM)["look_at"], ROOM["focus"], "room focus")

func test_placement_puts_the_camera_behind_and_above_looking_at_the_focus() -> void:
	var at := CameraDirector.placement(Vector3.ZERO, 10.0, 30.0, 0.0)
	ok(is_equal_approx(at.y, 5.0), "height = distance * sin(pitch)")
	ok(is_equal_approx(at.z, 8.660254), "depth = distance * cos(pitch), on the +Z side")
	ok(is_equal_approx(at.x, 0.0), "no sideways offset at yaw 0")
	var turned := CameraDirector.placement(Vector3.ZERO, 10.0, 0.0, 90.0)
	ok(turned.x > 9.9, "yaw swings the camera around the subject")

func test_focus_ids_are_resolved_through_the_provider() -> void:
	var director := CameraDirector.new()
	director.framing_provider = func() -> Dictionary: return ROOM
	director.focus_resolver = func(id: String) -> Variant: return Vector3(2, 0, 0) if id == "tomas" else null
	director.camera = track(DioramaCamera.new())
	director.frame("inspect", ["tomas", "ghost"], true)
	ok(is_equal_approx(director.camera.look_at_point.x, 2.0), "only resolvable ids count; unknown ones are ignored")
	director.free()
