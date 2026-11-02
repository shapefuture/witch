extends TestCase

# The witch's own actions (data/mirror/areas/systems/actions.json): she can open her notebook and listen to her
# Expectation-Sight (the chuika), both on the witch as a target. The chuika is not offered in the postgame, where looking
# is the only verb. Every action and response loads in the game scope with no errors and no warnings
# (test_game_scope_catalog.gd).

func test_the_witch_offers_her_notebook_and_her_sight_in_the_game() -> void:
	var r := GameFixtures.runtime(true)
	var ids := GameFixtures.action_ids(r, "witch")
	ok("systems_witch_open_notebook" in ids, "the notebook is one of her options")
	ok("systems_witch_listen_sight" in ids, "and listening to her Expectation-Sight is another")

func test_the_option_labels_are_her_words_in_the_text_table() -> void:
	var r := GameFixtures.runtime(true)
	for id in ["systems_witch_open_notebook", "systems_witch_listen_sight"]:
		var label_key := str(r.engine.action_definitions[id].get("label_key", ""))
		ok(label_key.begins_with("opt.systems."), "%s has a systems label key" % id)
		var text := tr(label_key)
		ok(text != label_key and not text.is_empty(), "%s resolves to words in the table" % label_key)
		ok(text.length() <= 40, "%s is at most 40 characters (%d)" % [label_key, text.length()])

func test_the_chuika_is_not_offered_in_the_postgame_but_the_notebook_is() -> void:
	var r := GameFixtures.runtime(true)
	var sight_gate: Dictionary = r.engine.action_definitions["systems_witch_listen_sight"].get("preconditions", {})
	ok(MirrorConditions.matches(sight_gate, {"story": {"act": "act3"}}), "open in the middle of the game")
	ok(not MirrorConditions.matches(sight_gate, {"story": {"act": "postgame"}}), "closed in the postgame")
	var notebook_gate: Dictionary = r.engine.action_definitions["systems_witch_open_notebook"].get("preconditions", {})
	ok(MirrorConditions.matches(notebook_gate, {"story": {"act": "postgame"}}), "the notebook stays open in the postgame: closing it returns to the menu")
