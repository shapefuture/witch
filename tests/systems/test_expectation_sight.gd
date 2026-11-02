extends TestCase

# Expectation-Sight, the chuika (BIBLE section 9; GAME_SPEC section 4): the sidecars load and are checked; an NPC's ghost
# shows when the NPC is in the room and the entry's Mirror condition matches; a projection looks exactly like an NPC's
# ghost; the ghost moves its way and ends at rest; seeing a ghost writes nothing to Mirror; the copies are removed after.

const FIXTURES := "res://tests/systems/fixtures"
const StubRoom := preload("res://tests/systems/stub_room.gd")

func test_the_ghost_names_are_the_contract() -> void:
	for ghost in ["flinch", "reach", "turn_away", "step_back", "hold_breath", "look_at:witch"]:
		ok(ExpectationSight.is_ghost(ghost), "%s is a ghost" % ghost)
	for ghost in ["wave", "look_at:", "look_at", "Flinch", ""]:
		ok(not ExpectationSight.is_ghost(ghost), "'%s' is not a ghost" % ghost)
	eq(ExpectationSight.look_target("look_at:witch"), "witch", "a look names its target")

func test_the_loader_accepts_good_entries_and_reports_the_bad_ones() -> void:
	var good := ExpectationSight.load_entries(FIXTURES + "/expectations_good")
	eq(good["errors"], [], "the good fixture loads with no errors")
	eq(good["entries"].size(), 4, "four entries")
	var bad := ExpectationSight.load_entries(FIXTURES + "/expectations_bad")
	eq(bad["errors"].size(), 4, "an unknown ghost, an entry with no npc, a bad source, and a repeated id")
	eq(bad["entries"].size(), 1, "only the first definition of the repeated id survives")
	eq(bad["entries"][0]["ghost"], "look_at:witch", "and it is the first one")

func test_the_real_expectations_directory_loads_clean_when_it_is_absent_or_empty() -> void:
	eq(ExpectationSight.load_entries()["errors"], [], "data/expectations has no errors (no sidecars yet is fine)")

func test_the_npcs_in_the_room_are_the_ones_whose_state_puts_them_there() -> void:
	var context := {"witch": {"place": "shop"}, "npc": {"raccoon": {"place": "shop"}, "miron": {"place": "garden"}, "tomas": {}, "elian": {"place": "with_witch"}}}
	eq(ExpectationSight.present_npcs(context, ["raccoon", "miron", "tomas", "elian"]), ["raccoon", "tomas", "elian"], "the raccoon is here, Miron is in the garden, Tomas has no place and is on stage, and one with the witch is here")

func test_an_entry_is_shown_when_its_npc_is_here_and_its_condition_matches() -> void:
	var context := {"witch": {"place": "shop"}, "npc": {"raccoon": {"place": "shop"}}}
	var entries := [
		{"id": "x", "npc": "raccoon", "when": {"witch.place": "shop"}, "ghost": "flinch", "source": "npc", "note": "note.test.x"},
		{"id": "y", "npc": "miron", "when": {"witch.place": "shop"}, "ghost": "flinch", "source": "npc", "note": "note.test.y"},
		{"id": "z", "npc": "raccoon", "when": {"witch.place": "street"}, "ghost": "flinch", "source": "npc", "note": "note.test.z"},
	]
	var shown := ExpectationSight.selected(entries, context, ["raccoon"])
	eq(shown.size(), 1, "one ghost: the raccoon is here and the shop is the place")
	eq(shown[0]["id"], "x", "the raccoon's, whose condition holds")

func test_an_npc_ghost_and_a_projection_are_shown_and_look_exactly_the_same() -> void:
	var npc_entry := {"id": "a", "npc": "raccoon", "when": {}, "ghost": "flinch", "source": "npc", "note": "note.test.a"}
	var projection := {"id": "b", "npc": "raccoon", "when": {}, "ghost": "flinch", "source": "projection", "note": "note.test.b"}
	eq(ExpectationSight.selected([npc_entry, projection], {}, ["raccoon"]).size(), 2, "both are shown")
	eq(ExpectationSight.descriptor(projection), ExpectationSight.descriptor(npc_entry), "the same ghost, the same npc: the player cannot tell them apart")
	for t in [0.0, 0.3, 0.7, 1.0]:
		eq(ExpectationSight.pose_at(str(projection["ghost"]), t), ExpectationSight.pose_at(str(npc_entry["ghost"]), t), "and they move the same at %.1f" % t)

func test_the_ghosts_move_their_way_and_come_to_rest() -> void:
	eq(float(ExpectationSight.pose_at("flinch", 0.0)["alpha"]), 0.0, "a ghost starts unseen")
	ok(absf(float(ExpectationSight.pose_at("flinch", 1.0)["step"].z)) < 0.0001, "a flinch comes back to rest")
	ok(float(ExpectationSight.pose_at("step_back", 0.8)["step"].z) < -0.3, "a step back takes the copy back")
	ok(float(ExpectationSight.pose_at("look_at:witch", 1.0)["look_weight"]) > 0.99, "a look turns the copy to its target")
	ok(ExpectationSight.pose_at("hold_breath", 1.0)["step"].length() < 0.0001, "holding a breath does not move the copy")
	ok(absf(ExpectationSight.yaw_towards(Vector3.ZERO, Vector3(1.0, 0.0, 0.0)) - PI * 0.5) < 0.0001, "a target to the east is a quarter turn")

func test_seeing_ghosts_writes_nothing_to_mirror() -> void:
	var r := GameFixtures.runtime(true)
	var stub := _room_with_raccoon()
	var presenter := _presenter(r, stub)
	var events := r.engine.event_store.size()
	var world: Dictionary = r.engine.world_state.duplicate(true)
	var npcs: Dictionary = r.engine.npc_state.duplicate(true)
	presenter.play_entry({"kind": "sight"})
	await _settle(0.5)
	eq(r.engine.event_store.size(), events, "no event is committed by seeing a ghost")
	eq(r.engine.world_state, world, "the world is as it was")
	eq(r.engine.npc_state, npcs, "and so are the npcs")

func test_the_sight_step_copies_the_npcs_in_the_room_for_a_few_seconds_and_removes_the_copies() -> void:
	var r := GameFixtures.runtime(true)
	var stub := _room_with_raccoon()
	var presenter := _presenter(r, stub)
	presenter.play_entry({"kind": "sight"})
	# two ghosts: the raccoon's flinch and the projection, each a copy of his one mesh; Miron is not here, and the street
	# entry's condition does not hold. The copies are made before the step first waits.
	eq(_ghost_count(stub), 2, "two ghost copies while the step plays")
	await Engine.get_main_loop().process_frame
	await _settle(0.5)
	eq(_ghost_count(stub), 0, "and none once it has played")

func test_a_look_at_ghost_is_handed_its_target_by_the_room() -> void:
	var r := GameFixtures.runtime(true)
	var stub := _room_with_raccoon()
	stub.anchors["witch"] = Vector3(4.0, 0.0, 0.0)
	var presenter := _presenter(r, stub)
	presenter.sidecar_dir = FIXTURES + "/expectations_look"
	presenter.play_entry({"kind": "sight"})
	await Engine.get_main_loop().process_frame
	eq(_ghost_count(stub), 1, "the look ghost is shown")
	await _settle(0.5)
	eq(_ghost_count(stub), 0, "and removed")

func _room_with_raccoon() -> StubRoom:
	var stub := StubRoom.new()
	var raccoon := Node3D.new()
	raccoon.name = "Raccoon"
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	raccoon.add_child(mesh)
	stub.add_child(raccoon)
	stub.actors["raccoon"] = raccoon
	Engine.get_main_loop().root.add_child(stub)
	track(stub)
	return stub

func _presenter(r: MirrorRuntime, stub: StubRoom) -> SightPresenter:
	var presenter := SightPresenter.new()
	presenter.name = "Sight"
	presenter.sidecar_dir = FIXTURES + "/expectations_good"
	presenter.time_scale = 0.05
	presenter.runtime_provider = func() -> MirrorRuntime: return r
	presenter.room_provider = func() -> Object: return stub
	stub.add_child(presenter)
	return presenter

# The copies the presenter made, found by the marker it puts on them.
func _ghost_count(stub: StubRoom) -> int:
	var copies: Array = stub.find_children("*", "MeshInstance3D", true, false).filter(func(node: Node) -> bool: return SightPresenter.is_ghost_copy(node))
	return copies.size()

# Waits `seconds` of real time, so a step scaled to 5% of its length has finished and the copies are gone.
func _settle(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(seconds).timeout
	await tree.process_frame
