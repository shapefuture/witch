extends TestCase

# Act II (workcell B, docs/design/GAME_SPEC.md section 6): the failing magic, the town's substitutes and the exit.
# Each test starts at the act's state (ActFixtures) and drives the authored actions through Mirror, as the game does.

func _at(place: String, npc_state: Dictionary = {}, world_extra: Dictionary = {}, knows: Array = [], operators: Array = []) -> MirrorRuntime:
	var world := {"story": {"act": "act2"}, "witch": {"place": place, "from": ""}, "magic": {"state": "failing"}}
	for key in world_extra.keys():
		world[key] = world_extra[key]
	return ActFixtures.runtime_at(world, npc_state, knows, operators)

func _offered(r: MirrorRuntime, action_id: String, target_id: String) -> bool:
	return bool(r.engine.explain_action(r.make_action(action_id, target_id)).get("available", false))

func _kinds(result: Dictionary, kind: String) -> Array:
	var out: Array = []
	for entry in result.get("presentation", []):
		if str(entry.get("kind", "")) == kind:
			out.append(entry)
	return out

func test_every_violet_cast_misfires_in_act_two() -> void:
	var r := _at("shop")
	var result := GameFixtures.do(r, "act2_cast_hearth", "act2_hearth")
	ok(result.get("ok", false), "the hearth can be cast at: %s" % JSON.stringify(result.get("errors", [])))
	var fizzles := _kinds(result, "magic")
	eq(fizzles.size(), 1, "the cast presents exactly one magic step")
	eq(str(fizzles[0].get("effect", "")), "fizzle", "and it fizzles")
	ok(r.engine.knowledge.has("act2_magic_failing", "player"), "the witch has seen that her magic does not hold")

func test_the_violet_casts_are_gone_once_magic_is_not_failing() -> void:
	var r := _at("shop", {}, {"magic": {"state": "gone"}})
	ok(not _offered(r, "act2_cast_hearth", "act2_hearth"), "no cast is offered once her magic is gone")

func test_the_janitor_lights_the_lamp_and_the_witch_sees_it() -> void:
	var r := _at("street")
	var result := GameFixtures.do(r, "act2_look_lamp", "act2_street_lamp")
	ok(result.get("ok", false), "she can look at the lamp")
	eq(r.engine.get_world("act2_lamp", {}).get("state", ""), "lit_by_janitor", "the janitor has lit it")
	eq(r.engine.get_npc_state("janitor").get("place", ""), "street", "and he stands in the street")
	ok(r.engine.knowledge.has("act2_lamps_without_me", "player"), "she has seen the town light its own lamps")

func test_elian_comes_in_asks_then_takes_tea_and_then_says_ty() -> void:
	var r := _at("shop")
	ok(GameFixtures.do(r, "act2_wait_counter", "act2_counter").get("ok", false), "waiting at the counter brings him in")
	eq(r.engine.get_npc_state("elian").get("place", ""), "shop", "he stands in the shop")
	ok(GameFixtures.do(r, "act2_ask_elian", "elian").get("ok", false), "she can ask what he needs")
	ok(GameFixtures.do(r, "act2_show_elian_tea", "elian").get("ok", false), "she can offer tea")
	eq(r.engine.get_npc_state("elian").get("stance", ""), "sitting", "he sits")
	ok(GameFixtures.do(r, "act2_wait_elian", "elian").get("ok", false), "she lets him stay")
	eq(r.engine.get_npc_state("elian").get("address", ""), "ty", "and he now speaks to her informally (ty)")
	ok(r.engine.knowledge.has("act2_elian_company", "player"), "she heard that he likes it here")

func test_elian_says_vy_until_she_offers_tea() -> void:
	var r := _at("shop")
	GameFixtures.do(r, "act2_wait_counter", "act2_counter")
	ok(not _offered(r, "act2_wait_elian", "elian"), "waiting with him is not offered before the tea")
	eq(r.engine.get_npc_state("elian").get("address", ""), "vy", "he keeps the formal address (vy) while he needs her")

func test_waiting_helps_the_oven_and_intervening_does_not() -> void:
	var r := _at("street")
	var refused := GameFixtures.do(r, "act2_help_oven", "act2_oven")
	ok(refused.get("ok", false), "she can offer to help with the oven")
	eq(r.engine.get_world("act2_vera_oven", {}).get("state", ""), "arguing", "and Vera still has the oven to herself")
	ok(r.engine.knowledge.has("act2_vera_not_now", "player"), "Vera says not now")
	var waited := GameFixtures.do(r, "act2_wait_oven", "act2_oven")
	ok(waited.get("ok", false), "waiting is offered too")
	eq(r.engine.get_world("act2_vera_oven", {}).get("state", ""), "solved", "waiting, she solves it")
	ok(r.engine.knowledge.has("act2_vera_wait_helped", "player"), "the witch has seen waiting help")

func test_waiting_loses_the_sign_and_catching_it_keeps_it() -> void:
	# Same verbs as the oven (C7): waiting helped there and drops the sign here.
	var waited := _at("street")
	ok(GameFixtures.do(waited, "act2_wait_sign", "act2_sign").get("ok", false), "she can wait with the sign")
	eq(waited.engine.get_world("act2_vera_sign", {}).get("state", ""), "fell", "and it falls")
	ok(waited.engine.knowledge.has("act2_vera_sign_fell", "player"), "Vera is upset, and the witch has seen it")
	var caught := _at("street")
	ok(GameFixtures.do(caught, "act2_catch_sign", "act2_sign").get("ok", false), "she can catch it")
	eq(caught.engine.get_world("act2_vera_sign", {}).get("state", ""), "caught", "and it is caught")
	ok(caught.engine.knowledge.has("act2_vera_direct_helped", "player"), "Vera thanks her")

func test_ilya_shows_the_backwards_clock_and_it_can_then_be_fixed() -> void:
	var r := _at("observatory")
	ok(not _offered(r, "act2_fix_clock", "act2_clock"), "the clock cannot be fixed before she has looked with him")
	ok(GameFixtures.do(r, "act2_look_clock", "act2_clock").get("ok", false), "she looks at the clock with him")
	eq(r.engine.get_world("act2_clock", {}).get("state", ""), "shown", "he has shown her what it counts")
	ok(r.engine.knowledge.has("act2_ilya_backwards", "player"), "the claim is in her notebook")
	ok(GameFixtures.do(r, "act2_fix_clock", "act2_clock").get("ok", false), "she can set it right")
	eq(r.engine.get_npc_state("ilya").get("stance", ""), "disappointed", "and Ilya is disappointed")
	ok(r.engine.knowledge.has("act2_clock_fixed", "player"), "that is her change, altered")

func test_the_raccoon_moves_up_and_refuses_the_commission() -> void:
	var r := _at("shop")
	ok(not GameFixtures.do(r, "act2_ask_commission", "raccoon").get("ok", false), "no commission from the shop floor")
	ok(GameFixtures.do(r, "act2_look_ladder", "ladder_shop_attic").get("ok", false), "she listens at the ladder")
	eq(r.engine.get_npc_state("raccoon").get("place", ""), "attic", "Gavrila is up in the attic")
	ok(GameFixtures.do(r, "core_go_ladder_shop_attic", "ladder_shop_attic").get("ok", false), "she climbs")
	ok(GameFixtures.do(r, "act2_ask_commission", "raccoon").get("ok", false), "she asks for the lamp that lights itself")
	eq(r.engine.get_world("act2_raccoon_commission", {}).get("state", ""), "refused", "and he says no")
	ok(r.engine.knowledge.has("act2_raccoon_refused", "player"), "she has heard it")

func test_the_hidden_spoon_gives_a_telesomatic_flash_and_a_guess() -> void:
	var r := _at("attic", {"raccoon": {"place": "attic"}})
	var result := GameFixtures.do(r, "act2_look_cloth", "act2_cloth")
	ok(result.get("ok", false), "she lifts the cloth")
	var flashes := _kinds(result, "flash")
	eq(flashes.size(), 1, "one flash shows his senses")
	eq(str(flashes[0].get("image", "")), "attic", "in the attic")
	ok(r.engine.knowledge.has("act2_raccoon_hid_it", "player"), "she guesses he hid it, and marks it as a guess")
	ok(not GameFixtures.do(r, "act2_look_cloth", "act2_cloth").get("ok", false), "the flash happens once")

func test_the_shadow_buys_a_candle_and_leaves_her_coin() -> void:
	var r := _at("shop")
	ok(GameFixtures.do(r, "act2_take_candle", "act2_candle_box").get("ok", false), "she takes a candle")
	ok(GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street").get("ok", false), "she goes out")
	ok(GameFixtures.do(r, "act2_wait_corner", "act2_corner").get("ok", false), "she waits on the corner")
	eq(r.engine.get_npc_state("shadow").get("place", ""), "street", "Shadow passes")
	ok(GameFixtures.do(r, "act2_sell_candle", "shadow").get("ok", false), "she sells the candle")
	eq(r.engine.get_world("act2_shadow_coin", {}), {"left": true}, "the knotted coin stays with the witch")
	eq(r.engine.get_npc_state("shadow").get("place", ""), "", "and Shadow goes")
	ok(r.engine.knowledge.has("act2_shadow_coin", "player"), "the witch has seen it")

func test_the_trapdoor_needs_tomas_resolved_and_three_of_five_items() -> void:
	var none := _at("shop", {}, {}, [], ["op.ask_before_acting"])
	ok(not GameFixtures.do(none, "act2_trapdoor_op", "trapdoor").get("ok", false), "the trapdoor stays shut with no items")
	var two := _at("shop", {"elian": {"address": "ty"}}, {"act2_lamp": {"state": "lit_by_janitor"}}, [], ["op.ask_before_acting"])
	ok(not GameFixtures.do(two, "act2_trapdoor_op", "trapdoor").get("ok", false), "two items are not enough")
	var three := _at("shop", {"elian": {"address": "ty"}, "raccoon": {"place": "attic"}},
		{"act2_lamp": {"state": "lit_by_janitor"}, "act2_raccoon_commission": {"state": "refused"}},
		[], ["op.ask_before_acting"])
	var went := GameFixtures.do(three, "act2_trapdoor_op", "trapdoor")
	ok(went.get("ok", false), "three items and Tomas's way (the operator) open it: %s" % JSON.stringify(went.get("errors", [])))
	eq(three.engine.get_world("story", {}).get("act", ""), "act3", "the act ends")
	eq(three.engine.get_world("witch", {}), {"place": "basement", "from": "shop"}, "she goes down, from the shop")
	eq(three.engine.get_world("magic", {}).get("state", ""), "below", "her magic now works only below")
	eq(three.engine.get_npc_state("raccoon").get("place", ""), "with_witch", "Gavrila goes with her")

func test_the_quiet_stance_also_opens_the_trapdoor() -> void:
	var r := _at("shop", {"tomas": {"stance": "quiet"}, "elian": {"address": "ty"}},
		{"act2_vera_oven": {"state": "solved"}, "act2_vera_sign": {"state": "caught"}, "act2_raccoon_commission": {"state": "refused"}})
	ok(GameFixtures.do(r, "act2_trapdoor_quiet", "trapdoor").get("ok", false), "Tomas quiet and three items open it (Vera counts as one)")

func test_every_act_two_action_names_its_place_and_its_act() -> void:
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/mirror/areas/act2/actions.json"))
	ok(data.size() > 20, "the act has actions")
	for definition in data:
		var pre: Dictionary = definition.get("preconditions", {})
		ok(pre.has("witch.place"), "%s has a witch.place precondition" % definition.get("id", "?"))
		ok(pre.has("story.act"), "%s has a story.act precondition" % definition.get("id", "?"))
