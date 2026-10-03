extends TestCase

# The painted-room adapter, against a stub emitter with the same signals as PaintedRoom (the room itself is
# not edited or loaded): a tap becomes a happening in Mirror, so the raccoon or Tomas can notice a poked globe.

class StubRoom extends Node:
	signal prop_pressed(prop_id: String, reaction: String, world_position: Vector3)
	signal walked(pixel: Vector2, world: Vector3)
	var actors: Dictionary = {}
	var props: Array = []

class TwoArgRoom extends Node:
	signal prop_pressed(prop_id: String, reaction: String)

class StubProp extends RefCounted:
	var prop_id := ""
	var played: Array[String] = []
	func play(reaction: String) -> void:
		played.append(reaction)

func _stage(with_tomas: bool = false, raccoon_distance_from_globe: float = 2.0) -> StubRoom:
	var room: StubRoom = track(StubRoom.new())
	var witch: Node3D = track(Node3D.new())
	witch.position = Vector3(0.75, 0.0, -5.76)
	var raccoon: Node3D = track(Node3D.new())
	raccoon.position = Vector3(raccoon_distance_from_globe, 0.0, 0.0)
	room.actors = {"witch": witch, "raccoon": raccoon}
	if with_tomas:
		var tomas: Node3D = track(Node3D.new())
		tomas.position = Vector3(3.0, 0.0, 0.0)
		room.actors["tomas"] = tomas
	return room

func _bridge(room: Object, r: MirrorRuntime, options: Dictionary = {}) -> PropEvents:
	var bridge := PropEvents.attach(room, r, options)
	track(bridge)
	return bridge

func test_a_tap_on_a_prop_becomes_a_poke_the_raccoon_notices() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var bridge := _bridge(room, r)
	var got: Array = []
	bridge.happened.connect(func(result: Dictionary) -> void: got.append(result))
	room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	eq(got.size(), 1, "one happening")
	eq(got[0]["kind"], "PROP_POKED", "a poke")
	eq(got[0]["subject"], "globe", "of the globe")
	eq(got[0]["actor"], "player", "by the witch (the scene's 'witch' is Mirror's 'player')")
	in_array("raccoon", got[0]["witnesses"], "the raccoon saw it")
	ok(r.engine.knowledge.has("saw_witch_play.globe", "raccoon"), "and made something of it: it believes the witch was playing")
	ok(r.engine.knowledge.has("poked.globe", "player"), "the witch's own record of it")

func test_the_scene_decides_who_is_on_stage_and_how_far_they_are() -> void:
	var r := _runtime_with_tomas_off_stage()
	var room := _stage(false, 2.0)
	var bridge := _bridge(room, r)
	var result := bridge.poke("globe", "hop", Vector3.ZERO)
	not_in_array("tomas", result["witnesses"], "Tomas is in the clearing in Mirror's truth but not on this stage: he did not see it")
	ok("tomas" in result["unaware"], "and the event says so")
	ok(not r.engine.knowledge.has("tomas_saw_tampering", "tomas"), "he learned nothing")
	var far := _stage(false, 40.0)
	var far_bridge := _bridge(far, GameFixtures.runtime())
	var seen := far_bridge.poke("globe", "hop", Vector3.ZERO)
	not_in_array("raccoon", seen["witnesses"], "a raccoon forty metres off, beyond sight and sound, did not notice")

func _runtime_with_tomas_off_stage() -> MirrorRuntime:
	return GameFixtures.runtime()

func test_tomas_notices_too_when_he_is_on_stage_and_his_remark_is_a_presentation_line() -> void:
	var r := GameFixtures.runtime()
	var room := _stage(true)
	var bridge := _bridge(room, r)
	var lines: Array = []
	bridge.presentation_ready.connect(func(entries: Array, _result: Dictionary) -> void: lines.append_array(entries))
	room.prop_pressed.emit("globe", "wobble", Vector3.ZERO)
	eq(lines.size(), 1, "Tomas says something")
	eq([lines[0]["kind"], lines[0]["speaker"]], ["line", "tomas"], "an existing presentation kind, spoken by him")
	ok(Localization.load_table().has(lines[0]["key"]), "and the line is a key in the text table")

func test_reactions_come_back_one_by_one_in_order() -> void:
	var r := GameFixtures.runtime()
	var room := _stage(true)
	var bridge := _bridge(room, r)
	var ops: Array = []
	bridge.reaction_requested.connect(func(reaction: Dictionary) -> void: ops.append(reaction["op"]))
	room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	eq(ops, ["LOOK_AT", "PROP_REACT", "COMMENT"], "the raccoon turns, the statue leans, Tomas speaks")

func test_it_connects_to_a_room_whose_signal_has_two_arguments_too() -> void:
	var r := GameFixtures.runtime()
	var room: TwoArgRoom = track(TwoArgRoom.new())
	var bridge := _bridge(room, r)
	var got: Array = []
	bridge.happened.connect(func(result: Dictionary) -> void: got.append(result["subject"]))
	room.prop_pressed.emit("statue", "shiver")
	eq(got, ["statue"], "the signal as the task describes it, without a position, works as well")

func test_attention_the_scene_reports_travels_with_the_poke() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var bridge := _bridge(room, r)
	bridge.set_attention("raccoon", "away")
	var result := bridge.poke("lamp", "wobble", Vector3.ZERO)
	var channel := ""
	for reading in result["interpretations"]:
		if reading["holder"] == "raccoon":
			channel = reading["channel"]
	eq(channel, "sound", "the raccoon, looking away, only hears it")
	eq(result["reactions"].filter(func(x: Dictionary) -> bool: return x["op"] == "LOOK_AT").size(), 0, "and does not look")

func test_walking_is_throttled_and_recorded_only_when_someone_reacts() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var bridge := _bridge(room, r)
	var before := r.engine.event_store.size()
	room.walked.emit(Vector2.ZERO, Vector3(0, 0, 0))
	var first := r.engine.event_store.size()
	ok(first > before, "the raccoon reacts to the witch crossing the floor: recorded")
	room.walked.emit(Vector2.ZERO, Vector3(0.5, 0, 0))
	eq(r.engine.event_store.size(), first, "half a metre later is not worth another entry")
	room.walked.emit(Vector2.ZERO, Vector3(4, 0, 0))
	ok(r.engine.event_store.size() > first, "four metres is")
	var data_empty: Dictionary = r.minds.data
	ok(data_empty["event_kinds"]["WALKED"]["quiet"], "WALKED is a quiet kind in the data")

func test_a_walk_nobody_reacts_to_writes_nothing() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	room.actors.erase("raccoon")
	var bridge := _bridge(room, r)
	bridge.poke("lamp", "wobble", Vector3.ZERO)
	var before := r.engine.event_store.size()
	bridge.walked(Vector2.ZERO, Vector3(9, 0, 0))
	eq(r.engine.event_store.size(), before, "with nobody there to notice, the log is untouched")

func test_deferred_consequences_reach_the_same_outputs_when_time_passes() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var bridge := _bridge(room, r)
	var ops: Array = []
	bridge.reaction_requested.connect(func(reaction: Dictionary) -> void: ops.append("%s:%s" % [reaction["op"], reaction.get("target", "")]))
	room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	ops.clear()
	var fired := bridge.pass_time(3)
	eq(fired.size(), 1, "the hall's answer fell due")
	eq(ops, ["LOOK_AT:statue"], "and the raccoon looked where it landed: the same output path as a poke")

func test_the_clock_runs_in_real_time_when_the_node_is_in_the_tree() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var bridge := _bridge(room, r, {"seconds_per_tick": 1.0})
	room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	bridge._process(0.9)
	eq(r.minds.pending().size(), 2, "not yet: 0.9 s")
	bridge._process(2.2)
	eq(r.engine.get_time(), 3, "three ticks passed")
	eq(r.minds.pending().filter(func(c: Dictionary) -> bool: return c["event"]["kind"] == "PROP_ECHOED").size(), 0, "and the answer happened")

func test_detached_it_hears_nothing() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var bridge := _bridge(room, r)
	bridge.detach()
	var before := r.engine.event_store.size()
	room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	eq(r.engine.event_store.size(), before, "nothing reaches Mirror")

func test_the_adapter_can_play_prop_reactions_on_a_rooms_props() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var statue := StubProp.new()
	statue.prop_id = "statue"
	room.props = [statue]
	var bridge := _bridge(room, r)
	bridge.play_prop_reactions_on_room()
	room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	eq(statue.played, ["shiver"], "the statue leans in: a world rule's reaction played on the room's own prop")

func test_the_adapter_holds_no_game_truth() -> void:
	var r := GameFixtures.runtime()
	var room := _stage()
	var bridge := _bridge(room, r)
	room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	var twin := GameFixtures.runtime()
	var twin_room := _stage()
	var twin_bridge := _bridge(twin_room, twin)
	twin_room.prop_pressed.emit("globe", "hop", Vector3.ZERO)
	eq(r.engine.event_store.head_hash(), twin.engine.event_store.head_hash(), "the same tap on the same stage is the same history: all of it is in Mirror")
	ok(bridge != twin_bridge, "(two bridges, one truth)")

func test_without_a_runtime_it_does_nothing_rather_than_fail() -> void:
	var bridge: PropEvents = track(PropEvents.new())
	eq(bridge.poke("globe", "hop"), {}, "no runtime, no result")
	eq(bridge.pass_time(3), [], "and time does not pass")
