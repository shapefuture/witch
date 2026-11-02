extends TestCase

# Act VI (workcell B, docs/design/GAME_SPEC.md section 6): no magic; the operators unlock the better options; Vera's two
# new contexts invert act II's lesson; Gavrila's half-light; the exit needs the half-light and two other items.
# Each test starts at the act's state (ActFixtures) and drives the authored actions through Mirror, as the game does.

func _at(place: String, npc_state: Dictionary = {}, world_extra: Dictionary = {}, operators: Array = []) -> MirrorRuntime:
	var world := {"story": {"act": "act6"}, "witch": {"place": place, "from": ""}, "magic": {"state": "gone"}}
	for key in world_extra.keys():
		world[key] = world_extra[key]
	return ActFixtures.runtime_at(world, npc_state, [], operators)

func _offered(r: MirrorRuntime, action_id: String, target_id: String) -> bool:
	return bool(r.engine.explain_action(r.make_action(action_id, target_id)).get("available", false))

func _dialogue_titles(result: Dictionary) -> Array:
	var out: Array = []
	for entry in result.get("presentation", []):
		if str(entry.get("kind", "")) == "dialogue":
			out.append(str(entry.get("title", "")))
	return out

func test_act_six_offers_no_magic_at_all() -> void:
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/mirror/areas/act6/actions.json"))
	ok(data.size() > 15, "the act has actions")
	for definition in data:
		eq(str(definition.get("action_type", "")) in ["CAST"], false, "%s is not a cast" % definition.get("id", "?"))
	var r := _at("shop")
	ok(not _offered(r, "act2_cast_hearth", "act2_hearth"), "the act II hearth cast is not offered in act VI")

func test_elian_wants_the_tap_looked_at_and_says_ty_when_nothing_is_broken() -> void:
	var r := _at("shop")
	ok(GameFixtures.do(r, "act6_wait_counter", "act2_counter").get("ok", false), "waiting at the counter brings him in")
	eq(r.engine.get_npc_state("elian").get("place", ""), "shop", "he stands in the shop")
	var looked := GameFixtures.do(r, "act6_look_tap", "act6_tap")
	ok(looked.get("ok", false), "she looks at the tap")
	eq(r.engine.get_npc_state("elian").get("address", ""), "ty", "nothing is broken, and he now speaks informally")
	eq(r.engine.get_world("act6_done_elian", {}), {"done": true}, "the act's Elian item is done")
	ok(r.engine.knowledge.has("act6_elian_ty", "player"), "she has heard it")

func test_a_companion_who_already_says_ty_gets_the_same_visit() -> void:
	var r := _at("shop", {"elian": {"address": "ty"}})
	GameFixtures.do(r, "act6_wait_counter", "act2_counter")
	ok(GameFixtures.do(r, "act6_look_tap_ty", "act6_tap").get("ok", false), "the visit still happens when he already says ty")
	eq(r.engine.get_world("act6_done_elian", {}), {"done": true}, "and the item is done")

func test_the_raccoon_moves_up_for_act_six() -> void:
	var r := _at("shop")
	ok(GameFixtures.do(r, "act6_look_ladder", "ladder_shop_attic").get("ok", false), "she calls up the ladder")
	eq(r.engine.get_npc_state("raccoon").get("place", ""), "attic", "Gavrila is up in the attic")
	ok(GameFixtures.do(r, "core_go_ladder_shop_attic", "ladder_shop_attic").get("ok", false), "she climbs")
	ok(_offered(r, "act6_look_lamp", "act6_lamp"), "and the lamp is there to look at")

func test_the_lamp_is_looked_at_and_sat_in_for_the_half_light() -> void:
	var r := _at("attic", {"raccoon": {"place": "attic"}})
	ok(GameFixtures.do(r, "act6_look_lamp", "act6_lamp").get("ok", false), "she looks at the lamp")
	eq(r.engine.get_world("act6_lamp", {}).get("state", ""), "shown", "it is shown to her")
	ok(GameFixtures.do(r, "act6_wait_lamp", "act6_lamp").get("ok", false), "she sits with him in the half-light")
	eq(r.engine.get_world("act6_lamp", {}).get("state", ""), "sat", "the half-light has happened")
	ok(r.engine.knowledge.has("act6_half_light", "player"), "and it is in her notebook")

func test_suggesting_covers_the_lamp_and_waiting_has_him_uncover_it() -> void:
	# The softlock fix: an unasked suggestion covers the lamp. The half-light must stay reachable from there.
	var r := _at("attic", {"raccoon": {"place": "attic"}})
	GameFixtures.do(r, "act6_look_lamp", "act6_lamp")
	ok(GameFixtures.do(r, "act6_suggest_lamp", "act6_lamp").get("ok", false), "she suggests improvements without asking")
	eq(r.engine.get_world("act6_lamp", {}).get("state", ""), "covered", "and he covers the lamp")
	ok(not _offered(r, "act6_wait_lamp", "act6_lamp"), "the half-light is not offered under the cloth")
	ok(GameFixtures.do(r, "act6_uncover_lamp", "act6_lamp").get("ok", false), "waiting, she lets him take the cloth off")
	eq(r.engine.get_world("act6_lamp", {}).get("state", ""), "shown", "the lamp is lit again")
	ok(GameFixtures.do(r, "act6_wait_lamp", "act6_lamp").get("ok", false), "and the half-light is still there to sit in")
	eq(r.engine.get_world("act6_lamp", {}).get("state", ""), "sat", "it has happened after all")

func test_asking_first_needs_the_operator_and_lets_it_be() -> void:
	var without := _at("attic", {"raccoon": {"place": "attic"}})
	GameFixtures.do(without, "act6_look_lamp", "act6_lamp")
	ok(not _offered(without, "act6_ask_lamp", "raccoon"), "without the operator, asking first is not offered")
	var asked := _at("attic", {"raccoon": {"place": "attic"}}, {}, ["op.ask_before_acting"])
	GameFixtures.do(asked, "act6_look_lamp", "act6_lamp")
	ok(GameFixtures.do(asked, "act6_ask_lamp", "raccoon").get("ok", false), "with it, she asks whether she may say something")
	eq(asked.engine.get_world("act6_lamp", {}).get("state", ""), "asked", "he says not now")
	ok(GameFixtures.do(asked, "act6_wait_lamp", "act6_lamp").get("ok", false), "and she sits in the half-light all the same")

func test_vera_acting_at_once_is_right_for_the_cart_and_waiting_is_not() -> void:
	var acted := _at("street")
	ok(GameFixtures.do(acted, "act6_cart_stop", "act6_cart").get("ok", false), "she catches the cart at once")
	eq(acted.engine.get_world("act6_cart", {}).get("state", ""), "held", "and it stops")
	ok(acted.engine.knowledge.has("act6_vera_cart", "player"), "Vera thanks her, and the witch has seen it help")
	var waited := _at("street")
	ok(GameFixtures.do(waited, "act6_cart_wait", "act6_cart").get("ok", false), "she waits")
	eq(waited.engine.get_world("act6_cart", {}).get("state", ""), "crashed", "and the cart goes over")
	ok(not waited.engine.knowledge.has("act6_vera_cart", "player"), "that is no help to anyone")

func test_vera_waiting_out_the_sharp_customer_is_right_and_intervening_is_not() -> void:
	var waited := _at("street")
	ok(GameFixtures.do(waited, "act6_customer_wait", "act6_customer").get("ok", false), "she stays out of it")
	eq(waited.engine.get_world("act6_customer", {}).get("state", ""), "settled", "and the customer leaves on her own")
	ok(waited.engine.knowledge.has("act6_vera_customer", "player"), "Vera manages by herself, and the witch has seen it")
	var helped := _at("street")
	ok(GameFixtures.do(helped, "act6_customer_help", "act6_customer").get("ok", false), "she steps in")
	eq(helped.engine.get_world("act6_customer", {}).get("state", ""), "spoiled", "and the deal is spoiled")
	ok(not helped.engine.knowledge.has("act6_vera_customer", "player"), "that is not a success")

func test_tomas_finishes_his_second_machine_when_asked_first() -> void:
	var r := _at("clearing", {}, {}, ["op.ask_before_acting"])
	ok(GameFixtures.do(r, "act6_look_second", "tomas").get("ok", false), "she looks at his second machine")
	ok(GameFixtures.do(r, "act6_ask_second", "tomas").get("ok", false), "she asks whether he wants her sketch")
	ok(GameFixtures.do(r, "act6_show_second", "tomas").get("ok", false), "she shows it, without taking over")
	eq(r.engine.get_world("act6_second_machine", {}).get("state", ""), "finished_by_tomas", "he finishes it himself")
	ok(r.engine.knowledge.has("act6_tomas_finished_it", "player"), "she has seen it")

func test_taking_the_work_leaves_it_to_the_witch() -> void:
	var r := _at("clearing")
	ok(not _offered(r, "act6_ask_second", "tomas"), "without the operator, asking first is not offered")
	ok(GameFixtures.do(r, "act6_take_second", "tomas").get("ok", false), "she takes the tools and finishes it herself")
	eq(r.engine.get_world("act6_second_machine", {}).get("state", ""), "finished_by_witch", "the machine is hers now")
	ok(not r.engine.knowledge.has("act6_tomas_finished_it", "player"), "nothing in her notebook for that")

func test_the_flower_is_found_in_the_ledger_after_shadow_leaves() -> void:
	var r := _at("street")
	ok(GameFixtures.do(r, "act6_wait_step", "act6_step").get("ok", false), "she waits on the step")
	eq(r.engine.get_npc_state("shadow").get("place", ""), "street", "Shadow sits on the step")
	ok(GameFixtures.do(r, "act6_wait_step_leave", "act6_step").get("ok", false), "and goes")
	eq(r.engine.get_world("act6_shadow_flower", {}), {"left": true}, "leaving a pressed petal behind")
	ok(GameFixtures.do(r, "core_go_door_street_shop", "door_street_shop").get("ok", false), "she goes in")
	ok(GameFixtures.do(r, "act6_look_ledger", "act6_ledger").get("ok", false), "and finds it in the ledger")
	ok(r.engine.knowledge.has("act6_shadow_flower", "player"), "she has seen it")

func test_ilya_watches_the_clock_and_does_not_fix_it() -> void:
	var r := _at("observatory")
	ok(GameFixtures.do(r, "act6_wait_clock", "act2_clock").get("ok", false), "she sits with him by the clock")
	eq(r.engine.get_world("act2_clock", {}).get("state", ""), "backwards", "and the clock still runs backwards")
	ok(r.engine.knowledge.has("act6_ilya_together", "player"), "she has seen him show it, for no reason")
	eq(r.engine.get_world("act6_done_ilya", {}), {"done": true}, "the act's Ilya item is done")

func test_ilya_turns_the_clock_back_himself_after_it_was_fixed() -> void:
	var r := _at("observatory", {}, {"act2_clock": {"state": "fixed"}})
	var result := GameFixtures.do(r, "act6_wait_clock", "act2_clock")
	ok(result.get("ok", false), "she sits with him again")
	eq(r.engine.get_world("act2_clock", {}).get("state", ""), "shown", "he has set it back, on his own")
	ok(_dialogue_titles(result).has("act6_ilya_turned_back"), "and says so")

func test_the_exit_needs_the_half_light_and_two_other_items() -> void:
	var one := _at("shop", {}, {"act6_lamp": {"state": "sat"}, "act6_done_elian": {"done": true}})
	ok(not GameFixtures.do(one, "act6_look_jars", "act6_jars").get("ok", false), "one item is not enough")
	var two := _at("shop", {}, {"act6_lamp": {"state": "sat"}, "act6_done_elian": {"done": true}, "act6_done_ilya": {"done": true}})
	ok(GameFixtures.do(two, "act6_look_jars", "act6_jars").get("ok", false), "two items and the half-light open the exit")
	eq(two.engine.get_world("story", {}).get("act", ""), "act7", "the act ends")

func test_the_exit_stays_reachable_after_the_worst_choices() -> void:
	# Covers the lamp, lets the cart go over, turns the customer away, and then plays the rest of the act.
	var r := _at("shop")
	var steps := [
		["act6_look_ladder", "ladder_shop_attic"], ["core_go_ladder_shop_attic", "ladder_shop_attic"],
		["act6_look_lamp", "act6_lamp"], ["act6_suggest_lamp", "act6_lamp"], ["act6_uncover_lamp", "act6_lamp"],
		["act6_wait_lamp", "act6_lamp"], ["core_go_ladder_attic_shop", "ladder_attic_shop"],
		["act6_wait_counter", "act2_counter"], ["act6_look_tap", "act6_tap"],
		["core_go_door_shop_street", "door_shop_street"], ["act6_customer_help", "act6_customer"],
		["act6_cart_wait", "act6_cart"], ["act6_wait_step", "act6_step"], ["act6_wait_step_leave", "act6_step"],
		["core_go_door_street_observatory", "door_street_observatory"], ["act6_wait_clock", "act2_clock"],
		["core_go_door_observatory_street", "door_observatory_street"], ["core_go_door_street_shop", "door_street_shop"],
		["act6_look_jars", "act6_jars"],
	]
	var results := GameFixtures.play(r, steps)
	eq(results.size(), steps.size(), "every step of the rest of the act is available")
	eq(r.engine.get_world("story", {}).get("act", ""), "act7", "and the exit opens")

func test_every_act_six_action_names_its_place_and_its_act() -> void:
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/mirror/areas/act6/actions.json"))
	for definition in data:
		var pre: Dictionary = definition.get("preconditions", {})
		ok(pre.has("witch.place"), "%s has a witch.place precondition" % definition.get("id", "?"))
		ok(pre.has("story.act"), "%s has a story.act precondition" % definition.get("id", "?"))
