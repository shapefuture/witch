extends TestCase

# Act VIII, the ordinary flower (GAME_SPEC act VIII; constitution C20): the flower is met, never used. Its options are
# look, touch and leave it be. No cast, no take, at most two short lines, and the only record is having seen it.

func _street() -> MirrorRuntime:
	return ActFixtures.runtime_at({"story": {"act": "act8"}, "witch": {"place": "street", "from": "shop"},
		"magic": {"state": "returned"}, "verdigris": {"known": true}, "wand": {"fate": "kept"}},
		{"raccoon": {"place": "shop", "stance": "busy"}, "miron": {"place": "fog"}}, [], [])

func _flower_actions() -> Array:
	var out: Array = []
	var engine: MirrorEngine = MirrorCatalog.build_engine(MirrorCatalog.DEFAULT_DIR, true)["engine"]
	for id in engine.action_definitions.keys():
		var definition: Dictionary = engine.action_definitions[id]
		if "act8_flower" in definition.get("valid_targets", []):
			out.append(definition)
	return out

func test_the_flower_offers_look_touch_and_leave_only() -> void:
	var r := _street()
	var ids := GameFixtures.action_ids(r, "act8_flower")
	ok(ids.has("act8_look_flower") and ids.has("act8_touch_flower") and ids.has("act8_leave_flower"), "look, touch and leave it be")
	eq(_flower_actions().size(), 3, "exactly three actions target the flower")

func test_the_flower_has_no_cast_and_no_take_constitution_c20() -> void:
	for definition in _flower_actions():
		eq(definition.get("action_type", -1), MirrorDomain.ActionType.LOOK if str(definition["id"]) != "act8_leave_flower" else MirrorDomain.ActionType.WAIT,
			"%s is a look or a wait, never a cast or a take" % definition["id"])
		ok(str(definition.get("affordance_group", "")) != "magic", "%s is not in the magic group" % definition["id"])

func test_every_option_records_only_having_seen_the_flower() -> void:
	for definition in _flower_actions():
		for response in definition.get("response_contracts", []):
			for effect in response.get("knowledge_effects", []):
				eq(str(effect.get("id", "")), "act8_flower", "%s writes only act8_flower" % response["id"])
			for effect in response.get("model_effects", []):
				ok(false, "%s has no model effects" % response["id"])
			var world: Dictionary = response.get("effects", {}).get("world", {})
			for key in world.keys():
				eq(str(key), "gold", "%s changes only the gold flag in the world" % response["id"])
			ok(response.get("effects", {}).get("npc_state", {}).is_empty(), "%s moves nobody" % response["id"])

func test_each_option_meets_the_flower_and_makes_gold_known() -> void:
	for action_id in ["act8_look_flower", "act8_touch_flower", "act8_leave_flower"]:
		var r := _street()
		var result: Dictionary = GameFixtures.do(r, action_id, "act8_flower")
		ok(result.get("ok", false), "%s commits: %s" % [action_id, JSON.stringify(result.get("errors", []))])
		ok(r.engine.knowledge.has("act8_flower", "player"), "%s: she has met it" % action_id)
		eq(r.engine.get_world("gold", {}), {"known": true}, "%s: gold is known" % action_id)

func test_the_touch_is_the_gentle_gold_light_and_at_most_two_lines() -> void:
	for definition in _flower_actions():
		for response in definition.get("response_contracts", []):
			var lines := 0
			for entry in response.get("presentation", []):
				if str(entry.get("kind", "")) == "line":
					lines += 1
				if str(entry.get("kind", "")) == "magic":
					eq(str(entry.get("mode", "")), "gold", "%s: a magic step is gold only" % response["id"])
			ok(lines <= 2, "%s: at most two short lines (%d)" % [response["id"], lines])

func test_the_way_on_is_to_meet_it_and_then_go_home_to_the_evening() -> void:
	var r := _street()
	ok(not GameFixtures.action_ids(r, "door_street_shop").has("act8_go_evening"), "before she has met it, going home is not the evening")
	var met: Dictionary = GameFixtures.do(r, "act8_look_flower", "act8_flower")
	ok(met.get("ok", false), "she meets the flower")
	var home: Dictionary = GameFixtures.do(r, "act8_go_evening", "door_street_shop")
	ok(home.get("ok", false), "going home after meeting it is the evening")
	eq(r.engine.get_world("story", {}).get("act", ""), "act9", "the story moves to act nine")
	eq(r.engine.get_world("witch", {}).get("place", ""), "shop", "she is home")

func test_leaving_the_flower_be_takes_time_and_changes_nothing_else() -> void:
	var r := _street()
	var before: Dictionary = r.engine.get_world("magic", {})
	var result: Dictionary = GameFixtures.do(r, "act8_leave_flower", "act8_flower")
	ok(result.get("ok", false), "leaving it be commits")
	eq(r.engine.get_world("magic", {}), before, "magic is untouched")
	eq(r.engine.get_npc_state("miron").get("place", ""), "fog", "Miron is still in the Fog (constitution C8)")

func test_the_flower_storylet_introduces_it_once() -> void:
	var r := _street()
	var story: Dictionary = r.next_story()
	ok(story.get("ok", false), "the flower storylet is eligible in the street")
	eq(str(story.get("storylet", {}).get("id", "")), "act8_flower_met", "and it introduces the flower")
	var again: Dictionary = r.next_story()
	ok(str(again.get("storylet", {}).get("id", "")) != "act8_flower_met", "and it does not play a second time")
