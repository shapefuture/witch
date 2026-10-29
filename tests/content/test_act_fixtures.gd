extends TestCase

# ActFixtures puts a game-scope runtime at a chosen point of the story (for unit tests of one act).

func test_a_runtime_can_start_mid_story_with_state_knowledge_and_operators() -> void:
	var r := ActFixtures.runtime_at({"story": {"act": "act3"}, "witch": {"place": "street", "from": "shop"}},
		{"raccoon": {"place": "with_witch"}}, ["fixture_claim"], ["op.ask_before_acting"])
	eq(r.engine.get_world("story", {}), {"act": "act3"}, "the act is set")
	eq(r.engine.get_npc_state("raccoon").get("place", ""), "with_witch", "the raccoon's place is patched")
	eq(r.engine.get_npc_state("raccoon").get("stance", ""), "busy", "and his other fields kept")
	ok(not r.engine.knowledge.get_claim("fixture_claim", "player").is_empty(), "the witch knows the given claim")
	ok(r.engine.operators.has("op.ask_before_acting", "player"), "and has the given operator")
	var moved := GameFixtures.do(r, "core_go_door_street_shop", "door_street_shop")
	ok(moved.get("ok", false), "and the runtime plays on from there")
