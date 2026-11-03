extends TestCase

# Act I, run through Mirror (docs/design/GAME_SPEC.md section 6, Act I). Each test starts at the day it needs
# (ActFixtures), so one day's rules are checked without playing the days before it. The whole-act routes are the sims
# in data/sim/act1_*.json.

func _status(r: MirrorRuntime, claim_id: String) -> int:
	var claim: Dictionary = r.engine.knowledge.get_claim(claim_id, "player")
	return int(claim.get("status", -1)) if not claim.is_empty() else -1

func _day(n: int, place: String) -> MirrorRuntime:
	return ActFixtures.runtime_at({"story": {"act": "act1"}, "act1_day": {"n": n}, "witch": {"place": place, "from": ""}})

func _miron(r: MirrorRuntime) -> String:
	return str(r.engine.get_npc_state("miron").get("place", ""))

func test_ending_a_day_advances_the_count_and_the_fifth_ending_is_the_exit() -> void:
	var r := _day(1, "shop")
	for n in [2, 3, 4, 5]:
		ok(GameFixtures.do(r, "act1_end_day", "act1_bed").get("ok", false), "the day ends into day %d" % n)
		eq(int(r.engine.get_world("act1_day", {}).get("n", 0)), n, "the count is %d" % n)
	eq(r.engine.get_world("story", {}).get("act", ""), "act1", "still act I after four endings")
	ok(GameFixtures.do(r, "act1_end_day", "act1_bed").get("ok", false), "the fifth ending")
	eq(r.engine.get_world("story", {}).get("act", ""), "act2", "the story moves to act II")
	eq(r.engine.get_world("magic", {}).get("state", ""), "failing", "and her magic is failing")

func test_the_window_shows_miron_only_on_the_third_day() -> void:
	var early := _day(1, "shop")
	GameFixtures.do(early, "act1_window_sit", "window_seat")
	eq(early.engine.get_world("witch", {}).get("place", ""), "window", "she sits at the window")
	eq(_miron(early), "garden", "on day one nobody passes the shop")
	ok(not GameFixtures.do(early, "act1_window_look", "miron").get("ok", false), "so there is nothing to look at")
	var third := _day(3, "shop")
	GameFixtures.do(third, "act1_window_sit", "window_seat")
	eq(_miron(third), "window", "on day three he stops in the street, facing the window")
	ok(GameFixtures.do(third, "act1_window_look", "miron").get("ok", false), "she can watch him")
	eq(_status(third, "act1_he_lingers"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen: he lingers")
	eq(_status(third, "act1_predicts_he_goes"), MirrorDomain.EpistemicStatus.POSSIBLE, "she predicts he goes when she turns away")

func test_turning_away_from_the_window_is_when_he_goes() -> void:
	var r := _day(3, "shop")
	GameFixtures.do(r, "act1_window_sit", "window_seat")
	GameFixtures.do(r, "act1_window_look", "miron")
	ok(GameFixtures.do(r, "act1_window_turn_away", "miron").get("ok", false), "she turns away")
	eq(_miron(r), "fog", "and he goes to the marsh")
	eq(_status(r, "act1_miron_left"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen: he left")
	eq(_status(r, "act1_visits_unwatched"), MirrorDomain.EpistemicStatus.SUPPORTED, "the prediction came true (SUPPORTED)")

func test_the_fog_edge_path_opens_on_the_fourth_day() -> void:
	var third := _day(3, "street")
	ok(not GameFixtures.do(third, "act1_marsh_road", "act1_marsh_road").get("ok", false), "no path to the marsh on day three")
	var fourth := _day(4, "street")
	ok(GameFixtures.do(fourth, "act1_marsh_road", "act1_marsh_road").get("ok", false), "the path opens on day four")
	eq(fourth.engine.get_world("witch", {}).get("place", ""), "fog_edge", "and she is at the Fog's edge")

func test_the_call_from_the_fog_is_heard_but_not_established() -> void:
	var r := _day(4, "fog_edge")
	ok(GameFixtures.do(r, "act1_fog_call", "act1_fog").get("ok", false), "she calls him")
	eq(_status(r, "act1_fog_is_quiet"), MirrorDomain.EpistemicStatus.SUPPORTED, "the Fog's quiet is SUPPORTED, never ESTABLISHED (C3)")
	eq(_status(r, "act1_why_quiet"), MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "why it is quiet stays unresolved")
	ok(not GameFixtures.do(r, "act1_fog_call", "act1_fog").get("ok", false), "she calls once")

func test_the_scarf_is_seen_and_the_way_back_is_always_open() -> void:
	var r := _day(4, "fog_edge")
	ok(GameFixtures.do(r, "act1_scarf_look", "act1_scarf").get("ok", false), "she looks at the scarf")
	eq(_status(r, "act1_scarf_on_branch"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen")
	ok(GameFixtures.do(r, "act1_marsh_back", "act1_marsh_back").get("ok", false), "and walks back")
	eq(r.engine.get_world("witch", {}).get("place", ""), "street", "to the street")

func test_the_mill_is_only_doubted_once_the_moss_is_seen() -> void:
	var heard_only := _day(2, "garden")
	GameFixtures.do(heard_only, "act1_ask_mill", "miron")
	eq(_status(heard_only, "act1_said_mill"), MirrorDomain.EpistemicStatus.ESTABLISHED, "he said the mill: heard")
	eq(_status(heard_only, "act1_not_at_mill"), -1, "without the moss there is nothing to infer")
	var seen := _day(2, "garden")
	GameFixtures.do(seen, "act1_look_miron", "miron")
	eq(_status(seen, "act1_silver_moss"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen: silver moss on the boots")
	GameFixtures.do(seen, "act1_ask_mill", "miron")
	eq(_status(seen, "act1_not_at_mill"), MirrorDomain.EpistemicStatus.SUPPORTED, "so she infers he was not at the mill (SUPPORTED, may be wrong)")

func test_the_three_modes_each_leave_their_own_record_and_change_how_he_stands() -> void:
	var hound := _day(1, "garden")
	GameFixtures.do(hound, "act1_hound_where", "miron")
	eq(hound.engine.get_npc_state("miron").get("stance", ""), "guarded", "HOUND makes him guarded")
	eq(_status(hound, "act1_asked_where"), MirrorDomain.EpistemicStatus.ESTABLISHED, "and leaves a heard entry")
	var proving := _day(1, "garden")
	ok(GameFixtures.do(proving, "act1_prove_bloom", "prologue_lilies").get("ok", false), "PROVING blooms the garden at night")
	eq(_status(proving, "act1_bloom_admired"), MirrorDomain.EpistemicStatus.ESTABLISHED, "he admired it: altered")
	eq(proving.engine.get_npc_state("miron").get("stance", ""), "warm", "and he is still warm")
	var fine := _day(2, "garden")
	GameFixtures.do(fine, "act1_fine_chore", "miron")
	eq(fine.engine.get_npc_state("miron").get("stance", ""), "braced", "FINE makes him brace for a question that does not come")
	eq(_status(fine, "act1_chore_turned"), MirrorDomain.EpistemicStatus.ESTABLISHED, "and leaves a seen entry")

func test_the_bloom_happens_once() -> void:
	var r := _day(1, "garden")
	ok(GameFixtures.do(r, "act1_prove_bloom", "prologue_lilies").get("ok", false), "the first bloom")
	ok(not GameFixtures.do(r, "act1_prove_bloom", "prologue_lilies").get("ok", false), "not a second one")

func test_the_key_is_on_the_hook_only_after_the_fourth_day() -> void:
	var fourth := _day(4, "shop")
	ok(not GameFixtures.do(fourth, "act1_look_hook", "act1_hook").get("ok", false), "no key on day four")
	var fifth := _day(5, "shop")
	ok(not GameFixtures.do(fifth, "act1_look_hook", "act1_hook").get("ok", false), "the key is still not there until the morning after the fourth ending")
	var key_there := ActFixtures.runtime_at({"story": {"act": "act1"}, "act1_day": {"n": 5}, "act1_key": {"on": "hook"}, "witch": {"place": "shop", "from": ""}})
	ok(GameFixtures.do(key_there, "act1_look_hook", "act1_hook").get("ok", false), "with the key on the hook, she can look")
	eq(_status(key_there, "act1_key_on_hook"), MirrorDomain.EpistemicStatus.ESTABLISHED, "seen")

func test_the_reading_of_the_loss_needs_the_fog_and_the_departure_and_is_only_inferred() -> void:
	var nothing_yet := _day(5, "shop")
	ok(not GameFixtures.do(nothing_yet, "act1_think_replaced", "witch").get("ok", false), "not before she has heard the Fog and seen him go")
	var r := ActFixtures.runtime_at({"story": {"act": "act1"}, "act1_day": {"n": 5}, "witch": {"place": "shop", "from": ""}},
		{}, [
			{"id": "act1_fog_is_quiet", "proposition": {"fog": "quiet"}, "status": "SUPPORTED", "scope": "fixture"},
			{"id": "act1_miron_left", "proposition": {"miron": "left"}, "status": "ESTABLISHED", "scope": "fixture"}
		])
	ok(GameFixtures.do(r, "act1_think_replaced", "witch").get("ok", false), "with both, she reads it")
	eq(_status(r, "act1_replaced"), MirrorDomain.EpistemicStatus.SUPPORTED, "the Fog replaced me is hers: SUPPORTED at most")

func test_the_morning_flash_of_the_fog_is_eligible_on_the_fourth_day_only() -> void:
	var ids_on_four: Array = []
	var fourth := _day(4, "shop")
	for definition in fourth.engine.select_storylets(fourth.context_snapshot(), "player"):
		ids_on_four.append(str(definition.get("id", "")))
	ok("act1_flash_coat" in ids_on_four, "the flash is eligible on day four in the shop")
	var ids_on_three: Array = []
	var third := _day(3, "shop")
	for definition in third.engine.select_storylets(third.context_snapshot(), "player"):
		ids_on_three.append(str(definition.get("id", "")))
	ok("act1_flash_coat" not in ids_on_three, "and not before")

func test_the_day_ending_is_available_in_the_shop_only() -> void:
	var r := _day(2, "garden")
	ok(not GameFixtures.do(r, "act1_end_day", "act1_bed").get("ok", false), "she cannot go to bed in the garden")
	GameFixtures.do(r, "core_go_door_garden_shop", "door_garden_shop")
	ok(GameFixtures.do(r, "act1_end_day", "act1_bed").get("ok", false), "from the shop she can")
