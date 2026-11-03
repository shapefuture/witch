extends TestCase

# Act VII, the town and the exit: verdigris stabilises the chooser (Tomas sets the cams himself; the stallholder chooses
# the grey lantern, not the red one the witch would), violet still works, and the next morning needs both (GAME_SPEC act VII).

func _shop(extra_world: Dictionary = {}) -> MirrorRuntime:
	var world := {"story": {"act": "act7"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "returned"},
		"verdigris": {"known": true}, "wand": {"fate": "kept"}}
	world.merge(extra_world, true)
	return ActFixtures.runtime_at(world,
		{"raccoon": {"place": "shop", "stance": "busy"}, "miron": {"place": "fog"}}, [], [])

func _modes(result: Dictionary) -> Array:
	var modes: Array = []
	for entry in result.get("presentation", []):
		if str(entry.get("kind", "")) == "magic":
			modes.append(str(entry.get("mode", "")))
	return modes

func _dialogue_titles(result: Dictionary) -> Array:
	var titles: Array = []
	for entry in result.get("presentation", []):
		if str(entry.get("kind", "")) == "dialogue":
			titles.append(str(entry.get("title", "")))
	return titles

func test_the_frame_is_held_so_tomas_sets_the_cams_himself() -> void:
	var r := _shop({"witch": {"place": "clearing", "from": "street"}})
	var result: Dictionary = GameFixtures.do(r, "act7_hold_frame", "machine")
	ok(result.get("ok", false), "holding the frame commits: %s" % JSON.stringify(result.get("errors", [])))
	ok(r.engine.knowledge.has("act7_enabled_tomas", "player"), "she knows she enabled him")
	ok(_modes(result).has("verdigris"), "it is a verdigris cast, not a violet one")
	ok(_dialogue_titles(result).has("act7_frame_held"), "and Tomas answers in his own words")

func test_violet_still_works_and_he_looks_at_it_like_a_stranger() -> void:
	var r := _shop({"witch": {"place": "clearing", "from": "street"}})
	var result: Dictionary = GameFixtures.do(r, "act7_cast_violet", "machine")
	ok(result.get("ok", false), "the violet cast commits")
	ok(r.engine.knowledge.has("act7_violet_works", "player"), "the witch knows violet works")
	ok(_modes(result).has("violet"), "the cast is violet")

func test_the_lanterns_lay_out_three_colours_and_vera_chooses_not_the_witch() -> void:
	var r := _shop({"witch": {"place": "street", "from": "shop"}})
	var result: Dictionary = GameFixtures.do(r, "act7_lanterns", "act7_lanterns")
	ok(result.get("ok", false), "the lanterns commit")
	ok(r.engine.knowledge.has("act7_town_chose", "player"), "the town chose")
	ok(_modes(result).has("verdigris"), "the lanterns are verdigris: they open a choice and do not make it")
	eq(r.engine.get_world("magic", {}), {"state": "returned"}, "the lanterns leave magic as it was")

func test_the_lanterns_happen_once() -> void:
	var r := _shop({"witch": {"place": "street", "from": "shop"}})
	GameFixtures.do(r, "act7_lanterns", "act7_lanterns")
	ok(not GameFixtures.action_ids(r, "act7_lanterns").has("act7_lanterns"), "after the choice the lanterns offer nothing")

func test_the_attic_bench_records_the_lamp_gone_to_the_street() -> void:
	var r := _shop({"witch": {"place": "attic", "from": "shop"}})
	var result: Dictionary = GameFixtures.do(r, "act7_attic_bench", "act7_bench")
	ok(result.get("ok", false), "the bench is looked at")
	ok(r.engine.knowledge.has("act7_lamp_went_out", "player"), "and the half-lamp is seen to be gone")

func test_the_morning_needs_both_town_and_tomas_and_leads_to_act_eight() -> void:
	var r := _shop()
	ok(not GameFixtures.action_ids(r, "act7_lamp").has("act7_morning"), "no morning before the act's work")
	GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street")
	GameFixtures.do(r, "act7_lanterns", "act7_lanterns")
	GameFixtures.do(r, "core_go_door_street_archive", "door_street_archive")
	GameFixtures.do(r, "act7_hold_frame", "machine")
	GameFixtures.do(r, "act7_cast_violet", "machine")
	GameFixtures.do(r, "core_go_door_archive_street", "door_archive_street")
	GameFixtures.do(r, "core_go_door_street_shop", "door_street_shop")
	ok(GameFixtures.action_ids(r, "act7_lamp").has("act7_morning"), "with both claims the morning is offered at the lamp")
	var result: Dictionary = GameFixtures.do(r, "act7_morning", "act7_lamp")
	ok(result.get("ok", false), "the morning commits")
	eq(r.engine.get_world("story", {}).get("act", ""), "act8", "the story moves to act eight")
	eq(r.engine.get_npc_state("miron").get("place", ""), "fog", "Miron is still in the Fog after act seven (constitution C8)")

func test_the_morning_is_not_offered_without_the_town_choice() -> void:
	var r := _shop()
	GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street")
	GameFixtures.do(r, "core_go_door_street_archive", "door_street_archive")
	GameFixtures.do(r, "act7_hold_frame", "machine")
	GameFixtures.do(r, "core_go_door_archive_street", "door_archive_street")
	GameFixtures.do(r, "core_go_door_street_shop", "door_street_shop")
	ok(not GameFixtures.action_ids(r, "act7_lamp").has("act7_morning"), "Tomas alone is not enough: the town must choose too")
