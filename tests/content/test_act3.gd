extends TestCase

# Act III: the basement, the hotel, the clock loop and the garden below (docs/design/GAME_SPEC.md section 6).
# Each test starts from ActFixtures's entry state; the prologue's claims are given as known.

const PROLOGUE := ["prologue_bench_crooked", "prologue_sunflowers", "prologue_knot", "prologue_garden_two_tastes",
		"prologue_father_drawing", "prologue_fog_mentioned"]
const OPERATOR := "op.act3_revise_before_repeating"


func _at(place: String, knows: Array = PROLOGUE, operators: Array = [], world_extra: Dictionary = {}) -> MirrorRuntime:
	var world: Dictionary = {"story": {"act": "act3"}, "witch": {"place": place, "from": "shop"}, "magic": {"state": "below"}}
	world.merge(world_extra, true)
	return ActFixtures.runtime_at(world, {"raccoon": {"place": "with_witch"}}, knows, operators)


func _can(r: MirrorRuntime, action_id: String, target_id: String) -> bool:
	return bool(r.engine.explain_action(r.make_action(action_id, target_id)).get("available", false))


func _do(r: MirrorRuntime, action_id: String, target_id: String) -> bool:
	return bool(GameFixtures.do(r, action_id, target_id).get("ok", false))


func _status(r: MirrorRuntime, claim_id: String) -> int:
	var claim: Dictionary = r.engine.knowledge.get_claim(claim_id, "player")
	return int(claim.get("status", -1))


func _face(r: MirrorRuntime) -> String:
	var clock: Dictionary = r.engine.get_world("act3_clock", {})
	return str(clock.get("face", ""))


func _stillness(r: MirrorRuntime) -> int:
	var garden: Dictionary = r.engine.get_world("act3_garden", {})
	return int(garden.get("stillness", -1))


func _place(r: MirrorRuntime) -> String:
	var witch: Dictionary = r.engine.get_world("witch", {})
	return str(witch.get("place", ""))


func test_the_act_starts_in_the_basement_with_the_raccoon_and_magic_below() -> void:
	var r: MirrorRuntime = _at("basement")
	eq(_place(r), "basement", "she starts in the basement")
	eq(r.engine.get_world("story", {}).get("act", ""), "act3", "at act three")
	eq(r.engine.get_world("magic", {}).get("state", ""), "below", "magic works underground only")
	eq(r.engine.get_npc_state("raccoon").get("place", ""), "with_witch", "he goes with her")


func test_the_toolbox_is_seen_and_the_crooked_door_leads_up_to_the_hotel() -> void:
	var r: MirrorRuntime = _at("basement")
	ok(_do(r, "act3_look_toolbox", "act3_toolbox"), "she opens the box")
	eq(_status(r, "act3_father_toolbox"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the child-size hammer is seen")
	ok(_do(r, "act3_go_basement_hotel", "act3_door_basement_hotel"), "she goes through the crooked door")
	eq(_place(r), "hotel", "she is in the hotel")
	eq(r.engine.get_npc_state("shadow").get("place", ""), "hotel", "Тень is sitting in the lobby")


func test_the_concierge_offers_only_the_rooms_she_remembers() -> void:
	var bare: MirrorRuntime = _at("hotel", [])
	ok(_do(bare, "act3_ask_rooms", "concierge"), "she asks for a room")
	ok(not _can(bare, "act3_room_garden", "concierge"), "no garden room without the garden claims")
	var r: MirrorRuntime = _at("hotel")
	ok(_can(r, "act3_room_garden", "concierge"), "the garden room is offered from her notebook")
	ok(_do(r, "act3_room_garden", "concierge"), "she takes it")
	eq(_status(r, "act3_key_garden_number"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the key has the garden's number")


func test_the_shadow_leaves_her_key_on_the_counter_when_she_waits() -> void:
	var r: MirrorRuntime = _at("basement")
	ok(_do(r, "act3_go_basement_hotel", "act3_door_basement_hotel"), "into the hotel")
	ok(_do(r, "act3_ask_shadow", "shadow"), "she asks Тень")
	ok(_do(r, "act3_wait_shadow", "shadow"), "she waits and Тень gets up")
	eq(r.engine.get_world("act3_shadow_key", {}).get("left", false), true, "the key is left (postgame evidence)")
	eq(r.engine.get_npc_state("shadow").get("place", "x"), "", "Тень is gone from the lobby")
	eq(_status(r, "act3_shadow_key"), MirrorDomain.EpistemicStatus.ESTABLISHED, "she saw the key on the counter")


func test_the_clock_loops_until_it_yawns_and_runs_backwards_and_reading_it_ends_the_loop() -> void:
	var r: MirrorRuntime = _at("clocktower")
	ok(_do(r, "act3_climb", "act3_stairs_up"), "first climb")
	eq(_face(r), "bored", "the face grows bored")
	ok(_do(r, "act3_climb", "act3_stairs_up"), "second climb")
	eq(_face(r), "asleep", "then asleep")
	ok(_do(r, "act3_climb", "act3_stairs_up"), "third climb")
	eq(_face(r), "backwards", "it yawns and runs backwards")
	eq(_place(r), "clocktower", "the landing is the same")
	ok(_do(r, "act3_read_clock_backwards", "act3_clock"), "she reads it backwards")
	eq(_face(r), "counted", "the loop is ended")
	ok(r.engine.operators.has(OPERATOR, "player"), "the operator is granted")
	ok(not _can(r, "act3_climb", "act3_stairs_up"), "climbing no longer loops")


func test_going_down_and_up_again_also_ends_the_loop_and_grants_the_operator() -> void:
	var r: MirrorRuntime = _at("clocktower")
	ok(_do(r, "act3_climb", "act3_stairs_up"), "one climb")
	ok(_do(r, "act3_go_clocktower_hotel", "act3_stairs_clocktower_hotel"), "down to the hotel")
	ok(_do(r, "act3_go_hotel_clocktower", "act3_stairs_hotel_clocktower"), "and up again")
	eq(_face(r), "counted", "the stairs were revised")
	ok(r.engine.operators.has(OPERATOR, "player"), "the operator is granted")


func test_with_ilyas_backwards_clock_she_reads_it_at_once() -> void:
	var r: MirrorRuntime = _at("clocktower", PROLOGUE + ["act2_ilya_backwards"])
	ok(_can(r, "act3_read_clock_known", "act3_clock"), "read it straight away, from Илья's clock")
	ok(_do(r, "act3_read_clock_known", "act3_clock"), "she reads it")
	ok(r.engine.operators.has(OPERATOR, "player"), "the operator is granted")
	eq(_status(r, "act3_tower_counts_down"), MirrorDomain.EpistemicStatus.SUPPORTED, "the tower counting down is inferred")


func test_the_garden_differences_register_only_with_the_prologue_claims() -> void:
	var r: MirrorRuntime = _at("garden_below", PROLOGUE)
	ok(_do(r, "act3_look_bench", "act3_bench"), "she looks at the bench")
	eq(_status(r, "act3_bench_straight"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the bench is straight")
	var bare: MirrorRuntime = _at("garden_below", [])
	ok(_do(bare, "act3_look_bench", "act3_bench"), "the same look without the claim")
	ok(not bare.engine.knowledge.has("act3_bench_straight", "player"), "no difference is registered without it")


func test_two_differences_infer_that_the_garden_is_only_hers_and_never_establish_it() -> void:
	var r: MirrorRuntime = _at("garden_below", PROLOGUE)
	ok(_do(r, "act3_look_bench", "act3_bench"), "bench")
	ok(_do(r, "act3_look_bed", "act3_sunflower_bed"), "bed")
	ok(_do(r, "act3_look_garden", "act3_garden_whole"), "the whole garden")
	eq(_status(r, "act3_only_mine"), MirrorDomain.EpistemicStatus.SUPPORTED, "inferred, at most supported")
	ok(_status(r, "act3_only_mine") != MirrorDomain.EpistemicStatus.ESTABLISHED, "never established")


func test_perfecting_casts_make_the_garden_stiller_and_the_bees_stop_after_two() -> void:
	var r: MirrorRuntime = _at("garden_below")
	eq(_stillness(r), 0, "the garden starts with no stillness")
	ok(_do(r, "act3_cast_lilies", "act3_lilies"), "first cast")
	ok(_do(r, "act3_cast_bench", "act3_bench"), "second cast")
	eq(_stillness(r), 2, "two casts")
	eq(_status(r, "act3_bees_stopped"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the bees have stopped")
	ok(_do(r, "act3_cast_swing", "act3_swing"), "third cast")
	ok(_do(r, "act3_cast_lilies", "act3_lilies"), "fourth cast")
	ok(_do(r, "act3_cast_lilies", "act3_lilies"), "a fifth, past the limit")
	eq(_stillness(r), 4, "it stops at stone")


func test_three_casts_are_a_way_to_see_the_garden_as_only_hers_when_the_claims_are_missing() -> void:
	var r: MirrorRuntime = _at("garden_below", [])
	ok(_do(r, "act3_cast_lilies", "act3_lilies"), "cast")
	ok(_do(r, "act3_cast_bench", "act3_bench"), "cast")
	ok(_do(r, "act3_cast_swing", "act3_swing"), "cast")
	ok(_do(r, "act3_look_garden", "act3_garden_whole"), "look at the whole garden")
	eq(_status(r, "act3_only_mine"), MirrorDomain.EpistemicStatus.SUPPORTED, "the fallback infers it too, so the exit is never closed")


func test_the_exit_needs_both_the_inference_and_the_operator() -> void:
	var no_operator: MirrorRuntime = _at("garden_below", PROLOGUE)
	ok(_do(no_operator, "act3_look_bench", "act3_bench"), "bench")
	ok(_do(no_operator, "act3_look_bed", "act3_sunflower_bed"), "bed")
	ok(_do(no_operator, "act3_look_garden", "act3_garden_whole"), "garden")
	ok(not _can(no_operator, "act3_sit_bench", "act3_bench"), "sitting is refused without the operator")
	var no_inference: MirrorRuntime = _at("garden_below", [], [OPERATOR])
	ok(not _can(no_inference, "act3_sit_bench", "act3_bench"), "and without the inference")
	var both: MirrorRuntime = _at("garden_below", PROLOGUE, [OPERATOR])
	ok(_do(both, "act3_look_bench", "act3_bench"), "bench")
	ok(_do(both, "act3_look_bed", "act3_sunflower_bed"), "bed")
	ok(_do(both, "act3_look_garden", "act3_garden_whole"), "garden")
	ok(_do(both, "act3_sit_bench", "act3_bench"), "she sits on the straight bench")
	eq(both.engine.get_world("story", {}).get("act", ""), "act4", "and act four begins")


func test_the_arrival_beats_play_once_in_their_place() -> void:
	var r: MirrorRuntime = _at("basement")
	var ids: Array = []
	for storylet in r.engine.select_storylets(r.context_snapshot(), "player"):
		ids.append(str(storylet.get("id", "")))
	ok("act3_arrive_basement" in ids, "the basement's arrival is eligible in the basement")
	ok(not ("act3_arrive_hotel" in ids), "and the hotel's is not")


func test_the_act_three_simulation_walks_the_whole_act() -> void:
	var script: Dictionary = SimulationRunner.load_script("res://data/sim_pending/act3_main.json")
	var outcome: Dictionary = SimulationRunner.new().run(_at("basement"), script)
	ok(outcome.get("ok", false), "act3_main passes: failed step %d, expectations %s"
			% [int(outcome.get("failed_step", -1)), str(outcome.get("expect_failures", []))])
