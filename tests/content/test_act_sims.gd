extends TestCase

# The sims of acts VII to the postgame (data/sim_pending/*_main.json). Each replays its own steps from its act's entry
# state (ActFixtures), so it runs before the earlier acts' sims are chained in. The "after" chain is dropped here on
# purpose: at integration the integrator adds it, and the entry state must not then count the earlier steps twice.

func _npcs() -> Dictionary:
	return {"raccoon": {"place": "shop", "stance": "busy"}, "miron": {"place": "fog"}}

func _run(sim_name: String, r: MirrorRuntime) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim_pending/%s.json" % sim_name))
	if not parsed is Dictionary:
		return {"ok": false, "failed_step": -1, "expect_failures": ["%s is not a JSON object" % sim_name]}
	var script: Dictionary = parsed
	script.erase("after")
	return SimulationRunner.new().run(r, script)

func _report(sim_name: String, outcome: Dictionary) -> String:
	return "%s: failed_step=%d expect=%s" % [sim_name, int(outcome.get("failed_step", -1)), JSON.stringify(outcome.get("expect_failures", []))]

func test_act_seven_replays_from_its_entry_and_ends_in_act_eight() -> void:
	var r := ActFixtures.runtime_at({"story": {"act": "act7"}, "witch": {"place": "shop", "from": ""},
		"magic": {"state": "gone"}, "wand": {"fate": "kept"}}, _npcs(), ["act6_half_light"], [])
	var outcome := _run("act7_main", r)
	ok(outcome.get("ok", false), _report("act7_main", outcome))

func test_act_eight_replays_from_the_street_and_ends_in_act_nine() -> void:
	var r := ActFixtures.runtime_at({"story": {"act": "act8"}, "witch": {"place": "street", "from": "shop"},
		"magic": {"state": "returned"}, "verdigris": {"known": true}, "wand": {"fate": "kept"}}, _npcs(), [], [])
	var outcome := _run("act8_main", r)
	ok(outcome.get("ok", false), _report("act8_main", outcome))

func test_act_nine_replays_from_the_shop_and_ends_in_the_postgame() -> void:
	var r := ActFixtures.runtime_at({"story": {"act": "act9"}, "witch": {"place": "shop", "from": "street"},
		"magic": {"state": "returned"}, "verdigris": {"known": true}, "wand": {"fate": "kept"}}, _npcs(), [], [])
	var outcome := _run("act9_main", r)
	ok(outcome.get("ok", false), _report("act9_main", outcome))

func test_the_postgame_sim_replays_the_house_and_closes_the_notebook() -> void:
	var claims: Array = ["act1_key_on_hook", "prologue_knot", "act6_half_light", "act7_enabled_tomas"]
	claims.append({"id": "act9_what_happened", "proposition": {"event": "what_happened_at_dusk"},
		"status": "UNRESOLVED_BY_DESIGN", "scope": "global"})
	var r := ActFixtures.runtime_at({"story": {"act": "postgame"}, "witch": {"place": "shop", "from": ""},
		"magic": {"state": "returned"}, "verdigris": {"known": true}, "gold": {"known": true}, "wand": {"fate": "kept"},
		"act2_shadow_coin": {"left": true}, "act3_shadow_key": {"left": true}, "act6_shadow_flower": {"left": true},
		"garden_below": {"state": "dust"}}, _npcs(), claims, [])
	var outcome := _run("postgame_main", r)
	ok(outcome.get("ok", false), _report("postgame_main", outcome))
