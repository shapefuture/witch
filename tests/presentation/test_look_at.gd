extends TestCase

# Gaze: Mirror's regard rule ("whatever moves is looked at") presented as a head turn on the real skinned
# characters. The skeleton and the clip are stepped by hand (manual callback modes), and the head bone's pose is
# read from the skeleton right after the modifiers ran, so the angles asserted are the ones the skin is drawn with.

const DT := 1.0 / 60.0

class Rig extends RefCounted:
	var visual: Node3D
	var skeleton: Skeleton3D
	var player: AnimationPlayer
	var gaze: LookAtHead
	var head := -1
	var body := -1
	# Skeleton-space poses as the skin saw them on the last step.
	var head_pose := Transform3D.IDENTITY
	var body_pose := Transform3D.IDENTITY

	func _init(id: String, at: Vector3, yaw_deg: float) -> void:
		visual = CharacterModels.instantiate(id)
		visual.position = at
		visual.rotation_degrees.y = yaw_deg
		(Engine.get_main_loop() as SceneTree).root.add_child(visual)
		skeleton = visual.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		player = CharacterModels.player_of(visual)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		gaze = CharacterModels.gaze_of(visual)
		head = skeleton.find_bone("head")
		var top := skeleton.find_bone("neck")
		body = skeleton.get_bone_parent(top if top >= 0 else head)
		gaze.modification_processed.connect(_capture)

	func _capture() -> void:
		head_pose = skeleton.get_bone_global_pose(head)
		body_pose = skeleton.get_bone_global_pose(body)

	func step(frames: int = 1) -> void:
		for i in frames:
			player.advance(DT)
			skeleton.advance(DT)
			# advance() only queues the update; run it now so the modifiers see this frame's clip pose.
			skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)

	func head_origin() -> Vector3:
		return skeleton.global_transform * head_pose.origin

	func forward() -> Vector3:
		return (skeleton.global_basis * head_pose.basis * LookAtHead.FORWARD).normalized()

	# Degrees between where the head faces and `point`.
	func off_by(point: Vector3) -> float:
		return rad_to_deg(forward().angle_to(point - head_origin()))

	# (yaw, pitch) in degrees of the head's facing in the frame of the bone above the neck.
	func facing_in_body() -> Vector2:
		var local := body_pose.basis.orthonormalized().transposed() * (head_pose.basis * LookAtHead.FORWARD)
		return Vector2(rad_to_deg(atan2(local.x, local.z)), rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length())))

	# A point `metres` from the head in the character's own frame (+Z is where it faces).
	func point_toward(local_direction: Vector3, metres: float = 3.0) -> Vector3:
		return head_origin() + (visual.global_basis.orthonormalized() * local_direction.normalized()) * metres

	func free_all() -> void:
		visual.queue_free()

func _rig(id: String, at: Vector3 = Vector3.ZERO, yaw_deg: float = 0.0) -> Rig:
	var rig := Rig.new(id, at, yaw_deg)
	track(rig.visual)
	rig.step()
	return rig

func test_every_character_gets_a_look_at_on_its_head_bone_and_the_neck_when_it_has_one() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	for id in ["witch", "tomas", "raccoon"]:
		var rig := _rig(id)
		ok(rig.gaze != null, "%s has a LookAtHead under its skeleton" % id)
		if rig.gaze == null:
			continue
		eq(rig.skeleton.get_bone_name(rig.gaze.head_bone), "head", "%s turns its 'head' bone" % id)
		var expected_neck := "" if id == "raccoon" else "neck"
		eq(rig.skeleton.get_bone_name(rig.gaze.neck_bone) if rig.gaze.neck_bone >= 0 else "", expected_neck, "%s's neck shares the turn when the skeleton has one" % id)
		rig.free_all()

func test_the_head_turns_toward_a_target_over_a_few_frames() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	for id in ["witch", "tomas", "raccoon"]:
		var rig := _rig(id, Vector3(2.0, 0.0, 1.0), 30.0)
		var target := rig.point_toward(Vector3(sin(deg_to_rad(40.0)), tan(deg_to_rad(12.0)), cos(deg_to_rad(40.0))))
		var before := rig.off_by(target)
		ok(before > 30.0, "%s faces away from the target to begin with (%.1f deg off)" % [id, before])
		rig.gaze.look_at_point(target, -1.0)
		rig.step(2)
		var early := rig.off_by(target)
		ok(early > 8.0 and early < before, "%s is turning, not snapped: %.1f deg off after two frames" % [id, early])
		rig.step(20)
		var after := rig.off_by(target)
		ok(after < 4.0, "%s's head bone faces the target after the turn (%.2f deg off)" % [id, after])
		rig.step(30)
		ok(rig.off_by(target) < 4.0, "%s keeps facing it while the clip plays on (%.2f deg off)" % [id, rig.off_by(target)])
		rig.free_all()

func test_a_target_behind_the_character_is_looked_toward_only_as_far_as_the_neck_allows() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	for id in ["witch", "tomas", "raccoon"]:
		var rig := _rig(id, Vector3(-1.0, 0.0, 0.5), -50.0)
		rig.gaze.look_at_point(rig.point_toward(Vector3(0.3, 0.0, -1.0)), -1.0)
		rig.step(40)
		var facing := rig.facing_in_body()
		ok(facing.x <= LookAtHead.YAW_LIMIT_DEG + 1.0, "%s's yaw stays inside %d deg for a target behind it (%.1f)" % [id, int(LookAtHead.YAW_LIMIT_DEG), facing.x])
		ok(facing.x >= LookAtHead.YAW_LIMIT_DEG - 3.0, "and it turns all the way to the limit on the target's side (%.1f)" % facing.x)
		ok(absf(facing.y) <= LookAtHead.PITCH_LIMIT_DEG + 1.0, "with its pitch in range (%.1f)" % facing.y)
		rig.gaze.look_at_point(rig.point_toward(Vector3(0.0, 1.0, 0.15), 6.0), -1.0)
		rig.step(40)
		facing = rig.facing_in_body()
		ok(facing.y <= LookAtHead.PITCH_LIMIT_DEG + 1.0 and facing.y >= LookAtHead.PITCH_LIMIT_DEG - 3.0, "%s looks up no further than %d deg at a target overhead (%.1f)" % [id, int(LookAtHead.PITCH_LIMIT_DEG), facing.y])
		rig.free_all()

func test_after_the_hold_the_head_is_handed_back_to_the_playing_clip() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	for id in ["witch", "tomas", "raccoon"]:
		var looking := _rig(id)
		var still := _rig(id)
		var target := looking.point_toward(Vector3(-0.8, 0.1, 1.0))
		var done := [false]
		looking.gaze.released.connect(func() -> void: done[0] = true)
		looking.gaze.look_at_point(target, 0.3)
		var apart := 0.0
		for i in 120:
			looking.step()
			still.step()
			apart = maxf(apart, rad_to_deg(looking.forward().angle_to(still.forward())))
			if done[0]:
				break
		ok(apart > 25.0, "%s's head left the clip's pose while it looked (%.1f deg apart at most)" % [id, apart])
		ok(done[0] and not looking.gaze.is_looking(), "%s released the look after its hold" % id)
		looking.step(3)
		still.step(3)
		var drift := 0.0
		for axis in 3:
			drift = maxf(drift, (looking.head_pose.basis[axis] - still.head_pose.basis[axis]).length())
		ok(drift < 0.001, "%s's head is exactly the clip's pose again (basis differs by %.5f)" % [id, drift])
		eq(looking.player.current_animation, still.player.current_animation, "%s's clip never stopped" % id)
		looking.free_all()
		still.free_all()

# ---- driven by Mirror ------------------------------------------------------------------------------------

class StubRoom extends Node:
	signal prop_pressed(prop_id: String, reaction: String, world_position: Vector3)
	signal walked(pixel: Vector2, world: Vector3)
	var actors: Dictionary = {}
	var things: Dictionary = {}
	func anchor(id: String) -> Variant:
		return things.get(id)

func _stage() -> Dictionary:
	var room: StubRoom = track(StubRoom.new()) as StubRoom
	var rigs := {
		"raccoon": _rig("raccoon", Vector3(0.0, 0.0, -2.0)),
		"tomas": _rig("tomas", Vector3(3.0, 0.0, -1.0), -60.0),
		"witch": _rig("witch", Vector3(0.75, 0.0, 2.0), 180.0),
	}
	for scene_id: String in rigs:
		room.actors[scene_id] = (rigs[scene_id] as Rig).visual
	room.things = {"globe": Vector3(0.9, 0.4, 0.0), "statue": Vector3(-2.0, 1.0, -3.0), "lamp": Vector3(-1.2, 1.4, -0.5)}
	return {"room": room, "rigs": rigs}

func _step_all(rigs: Dictionary, frames: int) -> void:
	for i in frames:
		for rig: Rig in rigs.values():
			rig.step()

func _reactions(result: Dictionary) -> Array:
	var out: Array = result.get("reactions", []).duplicate()
	for fired: Dictionary in result.get("fired", []):
		out.append_array(fired.get("reactions", []))
	return out

func test_the_regard_reaction_of_the_hall_rules_sim_turns_the_raccoons_head_and_no_one_elses() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var made := _stage()
	var rigs: Dictionary = made["rigs"]
	var raccoon: Rig = rigs["raccoon"]
	var gaze := LookAtPresenter.new()
	track(gaze)
	gaze.room = made["room"]
	var r := GameFixtures.runtime()
	var steps: Array = SimulationRunner.load_script("res://data/sim/hall_rules.json")["steps"]
	var first := SimulationRunner.run_step(r, steps[0])
	var looks: Array = _reactions(first).filter(func(x: Dictionary) -> bool: return x["op"] == "LOOK_AT")
	eq(looks.map(func(x: Dictionary) -> Array: return [x["actor"], x["target"]]), [["raccoon", "globe"]], "the sim's first poke of the globe: regard asks the raccoon to look at it")
	for reaction: Dictionary in _reactions(first):
		gaze.present(reaction)
	_step_all(rigs, 24)
	var globe: Vector3 = made["room"].anchor("globe")
	ok(raccoon.off_by(globe) < 4.0, "the raccoon's head faces the globe (%.2f deg off)" % raccoon.off_by(globe))
	ok(not (rigs["tomas"] as Rig).gaze.is_looking() and not (rigs["witch"] as Rig).gaze.is_looking(), "Tomas and the witch were not asked to look, and do not")
	_step_all(rigs, int(ceil((gaze.hold_time + 1.0) / DT)))
	ok(not raccoon.gaze.is_looking(), "and after the hold the raccoon goes back to its clip")
	# The rest of the sim, up to the lamp poked while the raccoon was looking away: nothing for it to look at.
	var lamp_looks: Array = []
	for i in range(1, steps.size()):
		var result := SimulationRunner.run_step(r, steps[i])
		if str(steps[i].get("poke", "")) == "lamp" and steps[i].has("hints"):
			for reaction: Dictionary in _reactions(result):
				if gaze.present(reaction):
					lamp_looks.append(reaction)
			break
	eq(lamp_looks, [], "the lamp the raccoon did not see moving is looked at by nobody (regard's exception)")
	_step_all(rigs, 24)
	ok(not raccoon.gaze.is_looking(), "so its head stays with its clip")

func test_a_poke_through_the_room_bridge_turns_the_raccoon_toward_the_poked_thing() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	var made := _stage()
	var rigs: Dictionary = made["rigs"]
	var raccoon: Rig = rigs["raccoon"]
	var room: StubRoom = made["room"]
	var bridge := PropEvents.attach(room, GameFixtures.runtime(), {"run_clock": false})
	track(bridge)
	var gaze := LookAtPresenter.attach(bridge)
	track(gaze)
	var shown: Array = []
	gaze.gaze_presented.connect(func(reaction: Dictionary, presented: bool) -> void: shown.append([reaction["actor"], reaction["target"], presented]))
	room.prop_pressed.emit("globe", "hop", room.anchor("globe"))
	eq(shown, [["raccoon", "globe", true]], "the raccoon's LOOK_AT reached the presenter and was shown")
	_step_all(rigs, 24)
	ok(raccoon.off_by(room.anchor("globe")) < 4.0, "its head faces the globe (%.2f deg off)" % raccoon.off_by(room.anchor("globe")))
	eq(gaze.present({"op": "LOOK_AT", "actor": "raccoon", "target": "nowhere"}), false, "a thing the room cannot place is not looked at")
	eq(gaze.present({"op": "PROP_REACT", "target": "statue", "reaction": "shiver"}), false, "a prop's move is not this presenter's")
	gaze.detach()
	ok(not bridge.reaction_requested.is_connected(gaze.present), "detached, it hears nothing more")

func test_the_live_hall_coordinator_presents_gaze_on_the_hall_it_attaches() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame
	GameFixtures.ensure_localization()
	var hall: ArchiveHall = track(ArchiveHall.new()) as ArchiveHall
	(Engine.get_main_loop() as SceneTree).root.add_child(hall)
	var live: LiveHallCoordinator = track(LiveHallCoordinator.new()) as LiveHallCoordinator
	live.runtime = GameFixtures.runtime()
	live.run_clock = false
	var bridge := live.attach(hall)
	ok(live.gaze != null and bridge.reaction_requested.is_connected(live.gaze.present), "the coordinator connects the gaze presenter to the bridge")
	var hall_raccoon := LookAtHead.of(hall.raccoon)
	ok(hall_raccoon != null, "the hall's raccoon has a head to turn")
	ok(live.gaze.present({"op": "LOOK_AT", "actor": "raccoon", "target": "bell"}), "a LOOK_AT at the bell turns the hall's raccoon")
	ok(hall_raccoon != null and hall_raccoon.is_looking(), "it is looking")
	live.detach()
	eq(live.gaze, null, "detaching drops the presenter")
