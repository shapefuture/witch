extends TestCase

func test_the_same_target_offers_different_options_as_knowledge_changes() -> void:
	var r := GameFixtures.runtime()
	var before := GameFixtures.action_ids(r, "machine")
	in_array("look_machine", before, "plain look at first")
	not_in_array("look_machine_informed", before, "informed look is not yet meaningful")
	GameFixtures.do(r, "ask_tomas_what", "tomas")
	var after := GameFixtures.action_ids(r, "machine")
	not_in_array("look_machine", after, "the naive look is replaced")
	in_array("look_machine_informed", after, "same verb, new meaning: look at the gear he described")
	GameFixtures.do(r, "look_machine_informed", "machine")
	not_in_array("look_machine_informed", GameFixtures.action_ids(r, "machine"), "nothing more to learn from looking")

func test_options_unlock_from_revised_models_not_from_keys() -> void:
	var r := GameFixtures.runtime()
	not_in_array("ask_tomas_help", GameFixtures.action_ids(r, "tomas"), "hidden while the witch believes helping is simply welcome")
	GameFixtures.do(r, "cast_repair", "machine")
	in_array("ask_tomas_help", GameFixtures.action_ids(r, "tomas"), "appears once the model is revised")

func test_the_three_ways_help_can_be_offered() -> void:
	# "Help Tomas" is never a verb. After learning, the same world offers three different acts.
	var r := GameFixtures.runtime()
	GameFixtures.do(r, "ask_tomas_what", "tomas")
	GameFixtures.do(r, "look_machine_informed", "machine")
	var ids := GameFixtures.action_ids(r, "tomas")
	in_array("show_tomas_solution", ids, "show the solution without acting")
	in_array("wait_watch", ids, "wait to be asked")
	GameFixtures.do(r, "cast_repair", "machine")
	GameFixtures.do(r, "wait_watch", "tomas")
	in_array("ask_tomas_help", GameFixtures.action_ids(r, "tomas"), "ask whether he wants it")

func test_options_are_ordered_observe_social_wait_act_magic() -> void:
	var r := GameFixtures.runtime()
	var groups: Array[String] = []
	for option in r.options_for("tomas"):
		groups.append(option.group)
	var last := -1
	for group in groups:
		var index := InteractionResolver.GROUP_ORDER.find(group)
		ok(index >= last, "group order respected: %s" % str(groups))
		last = index

func test_hidden_system_actions_are_never_offered() -> void:
	var r := GameFixtures.runtime()
	for target in ["tomas", "machine", "bell", "path_out", "nothing"]:
		not_in_array("DIALOGUE_CHOICE", GameFixtures.action_ids(r, target), "system action hidden on %s" % target)

func test_unknown_target_offers_nothing() -> void:
	eq(GameFixtures.action_ids(GameFixtures.runtime(), "nothing"), [], "no options for something that is not there")

func test_explain_reports_available_and_latent_options_with_reasons() -> void:
	var r := GameFixtures.runtime()
	var rows := r.explain_for("tomas")
	var by_id := {}
	for row in rows:
		by_id[row["action_id"]] = row
	ok(by_id["ask_tomas_what"]["available"], "available")
	in_array("state:npc.tomas.stance", by_id["ask_tomas_what"]["available_because"], "says why it is available")
	ok(not by_id["ask_tomas_help"]["available"], "help is not available yet")
	ok(by_id["ask_tomas_help"]["latent"], "but it is latent: knowledge would reveal it")
	eq(by_id["ask_tomas_help"]["state"], "blocked_by_model", "the blocking reason is the unrevised model")
	eq(by_id["show_tomas_wand"]["source"], {"ontology": "SHOW", "target": "tomas"}, "developer view shows the ontology; the player never does")
	eq(by_id["show_tomas_wand"]["prediction"], "p.impressed", "the prediction the action carries")
	in_array("npc_expectation", by_id["show_tomas_wand"]["effect_contract"], "effect contract lists what can change")
	in_array("model_revision", by_id["show_tomas_wand"]["effect_contract"], "including the player's model")

func test_option_converts_to_the_same_mirror_action_the_catalog_expects() -> void:
	var r := GameFixtures.runtime()
	var option: InteractionOption = r.options_for("tomas").filter(func(o): return o.action_id == "look_tomas")[0]
	var action := option.to_action("player", "req-7")
	eq(action.id, "look_tomas", "id")
	eq(action.target_id, "tomas", "target")
	eq(action.action_type, MirrorDomain.ActionType.LOOK, "ontology travels with the action, hidden from the UI")
	eq(action.client_request_id, "req-7", "idempotency key")
	ok(r.resolve_now(action)["ok"], "and it resolves")

func test_labels_change_with_state_for_the_same_action_family() -> void:
	var r := GameFixtures.runtime()
	var before := GameFixtures.labels(r, "machine")
	GameFixtures.do(r, "cast_repair", "machine")
	var after := GameFixtures.labels(r, "machine")
	ok(before != after, "the machine offers something different once it runs")
