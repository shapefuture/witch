extends TestCase

# The authoring rules of docs/design/GAME_SPEC.md section 5, checked over act I's own files (the same rules as
# test_prologue_structure.gd): every action is bound to the act and, when it is about an object or a person, to the place;
# every response has a presentation; every cast presents its magic (C1); every key the files name exists in the table.

const ACTIONS := "res://data/mirror/areas/act1/actions.json"
const CORE_ACTIONS := "res://data/mirror/areas/core/actions.json"
const PROLOGUE_ACTIONS := "res://data/mirror/areas/prologue/actions.json"
const NOTEBOOK := "res://data/notebook/act1.json"
const EXPECTATIONS := "res://data/expectations/act1.json"
const HOTSPOTS := "res://data/world/hotspots/act1.json"
const STORYLETS := "res://data/mirror/areas/act1/storylets.json"
const NOT_PLACE_BOUND := ["witch"]

func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _actions() -> Array:
	return _read(ACTIONS)

func test_every_act1_action_is_bound_to_the_act() -> void:
	for action in _actions():
		var pre: Dictionary = action.get("preconditions", {})
		ok(pre.has("story.act"), "%s is bound to story.act" % action["id"])

func test_every_action_about_a_place_is_bound_to_the_witch_place() -> void:
	for action in _actions():
		var targets: Array = action.get("valid_targets", [])
		if targets.size() == 1 and str(targets[0]) in NOT_PLACE_BOUND:
			continue
		var pre: Dictionary = action.get("preconditions", {})
		ok(pre.has("witch.place"), "%s is bound to witch.place" % action["id"])

func test_every_response_has_a_presentation() -> void:
	for action in _actions():
		for response in action.get("response_contracts", []):
			ok(not (response.get("presentation", []) as Array).is_empty(), "%s has a presentation" % response["id"])

func test_every_cast_presents_its_magic() -> void:
	for action in _actions():
		if str(action.get("action_type", "")) != "CAST":
			continue
		for response in action.get("response_contracts", []):
			var kinds: Array = []
			for entry in response.get("presentation", []):
				kinds.append(str(entry.get("kind", "")))
			ok("magic" in kinds, "the cast %s shows the magic (C1)" % response["id"])

func test_every_key_the_area_names_is_in_the_text_table() -> void:
	var table: Dictionary = Localization.load_table()
	for action in _actions():
		if action.has("label_key"):
			ok(table.has(str(action["label_key"])), "label %s exists" % action["label_key"])
		for response in action.get("response_contracts", []):
			for entry in response.get("presentation", []):
				if entry.has("key"):
					ok(table.has(str(entry["key"])), "line %s exists" % entry["key"])
	for storylet in _read(STORYLETS):
		for entry in storylet.get("presentation", []):
			if entry.has("key"):
				ok(table.has(str(entry["key"])), "storylet line %s exists" % entry["key"])
			if entry.has("sensation"):
				ok(table.has(str(entry["sensation"])), "sensation %s exists" % entry["sensation"])

func test_every_notebook_claim_is_one_the_area_publishes_and_has_a_valid_kind() -> void:
	var published: Dictionary = {}
	for action in _actions():
		for response in action.get("response_contracts", []):
			for effect in response.get("knowledge_effects", []):
				published[str(effect["id"])] = true
	var kinds := ["seen", "heard", "shown", "inferred", "predicted", "altered", "untestable"]
	var table: Dictionary = Localization.load_table()
	var notebook: Dictionary = _read(NOTEBOOK)
	for claim_id in notebook.keys():
		if str(claim_id).begins_with("_"):
			continue
		ok(published.has(claim_id), "notebook claim %s is published by an action" % claim_id)
		ok(str(notebook[claim_id]["kind"]) in kinds, "%s has a notebook kind" % claim_id)
		ok(table.has(str(notebook[claim_id]["text"])), "%s has its note in the table" % claim_id)

func test_every_untestable_note_ends_with_a_question_mark() -> void:
	var table: Dictionary = Localization.load_table()
	var notebook: Dictionary = _read(NOTEBOOK)
	for claim_id in notebook.keys():
		if str(claim_id).begins_with("_") or str(notebook[claim_id]["kind"]) != "untestable":
			continue
		ok(str(table[str(notebook[claim_id]["text"])]).ends_with("?"), "%s is a question, as an untestable note must be" % claim_id)

func test_the_chuyka_entries_name_known_npcs_and_their_notes_exist() -> void:
	var table: Dictionary = Localization.load_table()
	for entry in _read(EXPECTATIONS):
		ok(str(entry["npc"]) in ["raccoon", "miron", "vera", "tomas"], "%s is about a known person" % entry["id"])
		ok(str(entry["source"]) in ["npc", "projection"], "%s says whose ghost it is" % entry["id"])
		ok(table.has(str(entry["note"])), "%s has its note in the table" % entry["id"])

func test_every_hotspot_names_a_known_place_and_a_target_some_action_offers() -> void:
	var offered: Dictionary = {}
	for source in [_actions(), _read(CORE_ACTIONS), _read(PROLOGUE_ACTIONS)]:
		for action in source:
			for target in action.get("valid_targets", []):
				offered[str(target)] = true
	var places := ["shop", "window", "garden", "street", "clearing", "observatory", "attic", "fog_edge", "basement",
		"hotel", "clocktower", "garden_below", "threshold"]
	for spot in _read(HOTSPOTS):
		ok(str(spot["place"]) in places, "%s is a known place" % spot["place"])
		ok(offered.has(str(spot["target"])), "the hotspot %s is offered by an action" % spot["target"])

func test_the_fog_is_only_entered_on_the_day_it_opens() -> void:
	for action in _actions():
		if str(action.get("id", "")) != "act1_marsh_road":
			continue
		var pre: Dictionary = action["preconditions"]
		ok(pre.has("$gte") and int((pre["$gte"] as Dictionary).get("act1_day.n", 0)) == 4, "the marsh road opens on day four")
