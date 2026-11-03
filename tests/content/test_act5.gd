extends TestCase

# Act V: the unsrescuable rescue (docs/design/GAME_SPEC.md section 6, decision X35). The rescue works and holds: Miron
# stands in the threshold while the witch holds the pull, and steps back into the Fog the moment she lets go (C4). The
# garden below fades and dust is where it ends (C5). The questions the game leaves open are never established (C3, C9).

const OPERATOR := "op.act3_revise_before_repeating"


func _at(place: String = "garden_below", knows: Array = [], operators: Array = [OPERATOR], garden: String = "lush",
		magic: String = "below") -> MirrorRuntime:
	return ActFixtures.runtime_at({"story": {"act": "act5"}, "witch": {"place": place, "from": "clocktower"},
			"magic": {"state": magic}, "wand": {"fate": "kept"}, "garden_below": {"state": garden}},
			{"raccoon": {"place": "with_witch"}, "miron": {"place": "fog"}}, knows, operators)


func _can(r: MirrorRuntime, action_id: String, target_id: String) -> bool:
	return bool(r.engine.explain_action(r.make_action(action_id, target_id)).get("available", false))


func _do(r: MirrorRuntime, action_id: String, target_id: String) -> bool:
	return bool(GameFixtures.do(r, action_id, target_id).get("ok", false))


func _held(r: MirrorRuntime) -> bool:
	var hold: Dictionary = r.engine.get_world("act5_hold", {})
	return bool(hold.get("held", false))


func _miron(r: MirrorRuntime) -> String:
	return str(r.engine.get_npc_state("miron").get("place", ""))


func _magic(r: MirrorRuntime) -> String:
	var magic: Dictionary = r.engine.get_world("magic", {})
	return str(magic.get("state", ""))


func _garden(r: MirrorRuntime) -> String:
	var garden: Dictionary = r.engine.get_world("garden_below", {})
	return str(garden.get("state", ""))


func _status(r: MirrorRuntime, claim_id: String) -> int:
	var claim: Dictionary = r.engine.knowledge.get_claim(claim_id, "player")
	return int(claim.get("status", -1))


# Walks from the garden below to the threshold: the clock tower, the hotel, the deepest key, the stairs down.
func _to_threshold(r: MirrorRuntime) -> bool:
	var through := _do(r, "act3_go_garden_clocktower", "act3_stairs_garden_clocktower")
	through = _do(r, "act3_go_clocktower_hotel", "act3_stairs_clocktower_hotel") and through
	through = _do(r, "act5_ask_key", "concierge") and through
	return _do(r, "act5_go_hotel_threshold", "act5_door_hotel_threshold") and through


# From the threshold, with the phase ended, back to the basement and up the stairs home.
func _home(r: MirrorRuntime) -> bool:
	var through := _do(r, "act5_go_threshold_hotel", "act5_door_threshold_hotel")
	through = _do(r, "act3_go_hotel_basement", "act3_door_hotel_basement") and through
	return _do(r, "act5_stairs_home", "act5_stairs_home") and through


func test_the_pull_brings_him_through_and_he_stands_in_the_room_while_she_holds_it() -> void:
	var r: MirrorRuntime = _at()
	ok(_to_threshold(r), "she reaches the threshold")
	ok(_do(r, "act5_pull_miron", "act5_glass"), "she pulls")
	ok(_held(r), "the hold is on")
	eq(_miron(r), "threshold", "he stands in the room")
	eq(_status(r, "act5_he_stood_here"), MirrorDomain.EpistemicStatus.ESTABLISHED, "altered: he stood here")
	ok(_do(r, "act5_ask_hello", "miron"), "she asks, and he answers")
	ok(_held(r), "asking does not let go")
	ok(_do(r, "act5_ask_tired", "miron"), "a second question")
	ok(_held(r), "still held")
	eq(_miron(r), "threshold", "he is still in the room")


func test_letting_go_sends_him_back_into_the_fog_and_ends_the_magic() -> void:
	var r: MirrorRuntime = _at()
	ok(_to_threshold(r), "to the threshold")
	ok(_do(r, "act5_pull_miron", "act5_glass"), "the pull")
	ok(_do(r, "act5_let_go", "act5_glass"), "she lets go")
	ok(not _held(r), "the hold is off")
	eq(_miron(r), "fog", "he steps back through the glass")
	eq(_status(r, "act5_he_went_back"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen: he went back")
	eq(_status(r, "act5_would_he_come"), MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "untestable: would he come")
	eq(_magic(r), "gone", "her magic goes out")
	eq(_garden(r), "fading", "and the garden below begins to fade")


func test_any_other_action_releases_the_hold() -> void:
	var asking: MirrorRuntime = _at()
	ok(_to_threshold(asking), "to the threshold")
	ok(_do(asking, "act5_pull_miron", "act5_glass"), "the pull")
	ok(_do(asking, "act5_ask_raccoon", "raccoon"), "she asks the raccoon instead")
	ok(not _held(asking), "that other action lets him go")
	eq(_miron(asking), "fog", "he is back in the Fog")
	var leaving: MirrorRuntime = _at()
	ok(_to_threshold(leaving), "to the threshold again")
	ok(_do(leaving, "act5_pull_miron", "act5_glass"), "the pull")
	ok(_do(leaving, "act5_go_threshold_hotel", "act5_door_threshold_hotel"), "she goes up the stairs")
	ok(not _held(leaving), "leaving releases him too")
	eq(_miron(leaving), "fog", "he steps back through the glass as she goes")


func test_the_pull_is_gone_once_the_magic_has_gone() -> void:
	var r: MirrorRuntime = _at()
	ok(_to_threshold(r), "to the threshold")
	ok(_do(r, "act5_pull_miron", "act5_glass"), "the pull")
	ok(_do(r, "act5_let_go", "act5_glass"), "let go")
	ok(not _can(r, "act5_pull_miron", "act5_glass"), "there is no second pull")


func test_the_pull_needs_the_operator_that_the_loop_grants() -> void:
	var r: MirrorRuntime = _at("garden_below", [], [])
	ok(_to_threshold(r), "to the threshold without the operator")
	ok(not _can(r, "act5_pull_miron", "act5_glass"), "the pull is refused without it")


func test_the_bell_comes_back_cold_and_the_spell_moves_things() -> void:
	var r: MirrorRuntime = _at()
	ok(_to_threshold(r), "to the threshold")
	ok(_do(r, "act5_bell", "act5_desk_bell"), "she sends the bell beyond the glass")
	eq(_status(r, "act5_spell_moves_things"), MirrorDomain.EpistemicStatus.ESTABLISHED, "altered: the spell works on things")
	eq(_magic(r), "below", "and her magic is still there")


func test_the_raccoon_volunteers_and_his_return_proves_nothing() -> void:
	var r: MirrorRuntime = _at()
	ok(_to_threshold(r), "to the threshold")
	ok(not _can(r, "act5_pull_raccoon", "act5_glass"), "she cannot pull him back before he volunteers")
	ok(_do(r, "act5_ask_raccoon", "raccoon"), "she asks him")
	eq(_status(r, "act5_raccoon_volunteered"), MirrorDomain.EpistemicStatus.ESTABLISHED, "heard: he will go")
	ok(_do(r, "act5_pull_raccoon", "act5_glass"), "she pulls him back")
	eq(_status(r, "act5_pull_proves_nothing"), MirrorDomain.EpistemicStatus.SUPPORTED, "inferred, at most supported")
	ok(_status(r, "act5_pull_proves_nothing") != MirrorDomain.EpistemicStatus.ESTABLISHED, "never established")


func test_waiting_at_the_glass_lifts_his_hand_and_ends_the_magic_without_a_pull() -> void:
	var r: MirrorRuntime = _at()
	ok(_to_threshold(r), "to the threshold")
	ok(_do(r, "act5_wait_glass", "act5_glass"), "she waits at the glass")
	eq(_status(r, "act5_hand_lifted"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen: the hand lifted")
	eq(_status(r, "act5_what_the_wave_meant"), MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "untestable: what it meant")
	eq(_miron(r), "fog", "he stays in the Fog")
	eq(_magic(r), "gone", "the magic goes out")
	eq(_garden(r), "fading", "the garden fades")


func test_showing_the_seed_touches_the_glass_and_ends_the_magic() -> void:
	var r: MirrorRuntime = _at("garden_below", ["prologue_sunflowers"])
	ok(_to_threshold(r), "to the threshold")
	ok(_do(r, "act5_show_seed", "act5_glass"), "she shows the seed")
	eq(_status(r, "act5_show_touched_glass"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen: he touched the glass")
	eq(_miron(r), "fog", "he stays in the Fog")
	eq(_magic(r), "gone", "the magic goes out")


func test_the_garden_fades_then_dust_and_no_action_brings_it_back() -> void:
	var r: MirrorRuntime = _at("garden_below", [], [OPERATOR], "fading", "gone")
	ok(_do(r, "act5_water_garden", "act3_lilies"), "she waters the lilies")
	eq(_garden(r), "dust", "the water turns to dust")
	for target in ["act3_lilies", "act3_garden_whole", "act3_stairs_garden_clocktower", "act3_bench", "act3_swing"]:
		for option in GameFixtures.action_ids(r, str(target)):
			GameFixtures.do(r, str(option), str(target))
			ok(_garden(r) != "lush", "after %s on %s the garden is not lush (it is %s)" % [str(option), str(target), _garden(r)])
			ok(_garden(r) == "dust", "and it stays dust after %s" % str(option))


func test_no_action_sets_the_garden_back_to_lush() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	for id in r.engine.action_definitions.keys():
		if not str(id).begins_with("act5_") and not str(id).begins_with("act3_") and not str(id).begins_with("act4_"):
			continue
		for response in r.engine.action_definitions[id].get("response_contracts", []):
			var garden: Dictionary = response.get("effects", {}).get("world", {}).get("garden_below", {})
			ok(str(garden.get("state", "")) != "lush", "%s never restores the garden" % str(response.get("id", "")))


func test_the_untestable_questions_are_never_established() -> void:
	var script: Dictionary = SimulationRunner.load_script("res://data/sim_pending/act5_main.json")
	var r: MirrorRuntime = _at()
	SimulationRunner.new().run(r, script)
	eq(_status(r, "act5_would_he_come"), MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "would he come stays open")
	var wave: MirrorRuntime = _at()
	ok(_to_threshold(wave) and _do(wave, "act5_wait_glass", "act5_glass"), "the other route")
	eq(_status(wave, "act5_what_the_wave_meant"), MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "what the wave meant stays open")


func test_the_stairs_home_wait_for_the_magic_to_go_and_the_exit_stays_reachable() -> void:
	var early: MirrorRuntime = _at("basement")
	ok(not _can(early, "act5_stairs_home", "act5_stairs_home"), "no way home while the magic is below")
	# Every way of dealing with the glass, then the way home: none may close the exit.
	var prefixes := [[], ["bell"], ["ask_raccoon"], ["ask_raccoon", "pull_raccoon"], ["pull_miron"],
			["pull_miron", "ask_hello"], ["show_seed"], ["wait"]]
	for prefix in prefixes:
		var knows: Array = ["prologue_sunflowers"]
		var r: MirrorRuntime = _at("garden_below", knows)
		ok(_to_threshold(r), "to the threshold (%s)" % str(prefix))
		for step in prefix:
			match str(step):
				"bell":
					_do(r, "act5_bell", "act5_desk_bell")
				"ask_raccoon":
					_do(r, "act5_ask_raccoon", "raccoon")
				"pull_raccoon":
					_do(r, "act5_pull_raccoon", "act5_glass")
				"pull_miron":
					_do(r, "act5_pull_miron", "act5_glass")
				"ask_hello":
					_do(r, "act5_ask_hello", "miron")
				"show_seed":
					_do(r, "act5_show_seed", "act5_glass")
				"wait":
					_do(r, "act5_wait_glass", "act5_glass")
		if _magic(r) == "below":
			if _held(r):
				ok(_do(r, "act5_let_go", "act5_glass"), "let go, then home (%s)" % str(prefix))
			else:
				ok(_do(r, "act5_wait_glass", "act5_glass"), "wait at the glass, then home (%s)" % str(prefix))
		ok(_home(r), "the way home opens (%s)" % str(prefix))
		eq(r.engine.get_world("story", {}).get("act", ""), "act6", "and act five ends (%s)" % str(prefix))
		eq(r.engine.get_npc_state("raccoon").get("place", ""), "shop", "the raccoon goes home with her (%s)" % str(prefix))


func test_the_act_five_rescue_simulation_passes() -> void:
	var script: Dictionary = SimulationRunner.load_script("res://data/sim_pending/act5_main.json")
	var outcome: Dictionary = SimulationRunner.new().run(_at(), script)
	ok(outcome.get("ok", false), "act5_main passes: failed step %d, expectations %s"
			% [int(outcome.get("failed_step", -1)), str(outcome.get("expect_failures", []))])


func test_the_act_five_wait_simulation_passes() -> void:
	var script: Dictionary = SimulationRunner.load_script("res://data/sim_pending/act5_wait.json")
	var outcome: Dictionary = SimulationRunner.new().run(_at(), script)
	ok(outcome.get("ok", false), "act5_wait passes: failed step %d, expectations %s"
			% [int(outcome.get("failed_step", -1)), str(outcome.get("expect_failures", []))])
