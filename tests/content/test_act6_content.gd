extends TestCase

# Act VI's content package (docs/engine/CONTENT_PACKAGES.md): every key, dialogue title, claim, target and sidecar the act
# names exists and is well formed; no cast is offered; the voice rules that can be checked here hold.

const PUBLISHED_CLAIMS := [
	"act6_tomas_finished_it", "act6_elian_ty", "act6_vera_cart", "act6_vera_customer", "act6_ilya_together",
	"act6_half_light", "act6_shadow_flower",
]
const KINDS := ["seen", "heard", "shown", "inferred", "predicted", "altered", "untestable"]
const GHOSTS := ["flinch", "reach", "turn_away", "step_back", "hold_breath"]

func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _actions() -> Array:
	return _json("res://data/mirror/areas/act6/actions.json")

func _walk_presentation(entries: Array, out: Dictionary) -> void:
	for entry in entries:
		if entry.has("key"):
			out[str(entry["key"])] = true
		if entry.has("sensation"):
			out[str(entry["sensation"])] = true
		if entry.has("title"):
			out["title:" + str(entry["title"])] = true

func _used_keys_and_titles() -> Dictionary:
	var used := {}
	for definition in _actions():
		used[str(definition.get("label_key", ""))] = true
		for response in definition.get("response_contracts", []):
			_walk_presentation(response.get("presentation", []), used)
	for storylet in _json("res://data/mirror/areas/act6/storylets.json"):
		_walk_presentation(storylet.get("presentation", []), used)
	return used

func test_no_action_of_the_act_is_a_cast() -> void:
	for definition in _actions():
		ok(str(definition.get("action_type", "")) != "CAST", "%s is not a cast" % definition.get("id", "?"))

func test_every_text_key_the_act_names_is_in_the_table() -> void:
	var table := Localization.load_table()
	var used := _used_keys_and_titles()
	for note in _json("res://data/notebook/act6.json").values():
		used[str(note.get("text", ""))] = true
	for entry in _json("res://data/expectations/act6.json"):
		used[str(entry.get("note", ""))] = true
		used["speaker." + str(entry.get("npc", ""))] = true
	var missing: Array[String] = []
	for key in used.keys():
		if key.begins_with("title:") or key.is_empty():
			continue
		if not table.has(key):
			missing.append(key)
	eq(missing, [], "every key the act uses is defined in data/text/ru.json or its fragments")

func test_every_dialogue_the_act_presents_is_defined() -> void:
	var titles: Dictionary = DialogueBridge.title_index()["titles"]
	var used := _used_keys_and_titles()
	var missing: Array[String] = []
	for key in used.keys():
		if str(key).begins_with("title:") and not titles.has(str(key).substr(6)):
			missing.append(str(key).substr(6))
	eq(missing, [], "every dialogue title the act presents exists in data/conversations")
	eq(DialogueBridge.title_index()["duplicates"], [], "no dialogue title is defined twice")

func test_the_dialogue_speakers_have_names() -> void:
	var table := Localization.load_table()
	var speakers := RegEx.create_from_string("^([a-z_][a-z0-9_]*):\\s")
	var missing: Array[String] = []
	for raw in FileAccess.get_file_as_string("res://data/conversations/act6.dialogue").split("\n"):
		var found := speakers.search(raw.strip_edges())
		if found != null and not table.has("speaker." + found.get_string(1)):
			missing.append(found.get_string(1))
	eq(missing, [], "every speaker in the act's conversations has a speaker.<id> key")

func test_the_notebook_lists_every_claim_the_act_publishes() -> void:
	var notebook: Dictionary = _json("res://data/notebook/act6.json")
	for claim_id in PUBLISHED_CLAIMS:
		ok(notebook.has(claim_id), "%s is in the notebook" % claim_id)
	for claim_id in notebook.keys():
		ok(str(notebook[claim_id].get("kind", "")) in KINDS, "%s has a notebook kind" % claim_id)
		ok(str(notebook[claim_id].get("text", "")).begins_with("note.act6."), "%s names an act VI note" % claim_id)

func test_the_act_world_values_are_its_own() -> void:
	var world: Dictionary = _json("res://data/mirror/areas/act6/world.json")["world"]
	var core: Dictionary = _json("res://data/mirror/areas/core/world.json")
	for key in world.keys():
		ok(not core["world"].has(key), "%s is not an entity the core area already defines" % key)
		ok(str(key).begins_with("act6_"), "%s carries the act's prefix" % key)

func test_every_hotspot_points_at_an_action_target() -> void:
	var targets := {}
	for definition in _actions() + _json("res://data/mirror/areas/core/actions.json") + _json("res://data/mirror/areas/act2/actions.json"):
		for target in definition.get("valid_targets", []):
			targets[str(target)] = true
	var places := ["shop", "window", "garden", "street", "clearing", "observatory", "attic", "fog_edge", "basement",
		"hotel", "clocktower", "garden_below", "threshold"]
	for spot in _json("res://data/world/hotspots/act6.json"):
		ok(targets.has(str(spot.get("target", ""))), "%s is an act target" % spot.get("target", "?"))
		ok(str(spot.get("place", "")) in places, "%s is in a known place" % spot.get("target", "?"))
		ok(spot.get("at", []).size() == 2 and int(spot.get("radius", 0)) > 0, "%s has a position and a radius" % spot.get("target", "?"))

func test_the_expectations_are_well_formed() -> void:
	for entry in _json("res://data/expectations/act6.json"):
		ok(entry.has("id") and entry.has("npc") and entry.get("when", null) is Dictionary, "%s has an id, an npc and a condition" % entry.get("id", "?"))
		var ghost := str(entry.get("ghost", ""))
		ok(ghost in GHOSTS or ghost.begins_with("look_at:"), "%s has a known ghost" % entry.get("id", "?"))
		ok(str(entry.get("source", "")) in ["npc", "projection"], "%s says whose expectation it is" % entry.get("id", "?"))

func test_every_action_and_storylet_is_named_for_the_act() -> void:
	for definition in _actions():
		ok(str(definition.get("id", "")).begins_with("act6_"), "%s carries the act's prefix" % definition.get("id", "?"))
		ok(str(definition.get("label_key", "")).begins_with("opt.act6."), "%s has an act label" % definition.get("id", "?"))
	for storylet in _json("res://data/mirror/areas/act6/storylets.json"):
		ok(str(storylet.get("id", "")).begins_with("act6_"), "%s carries the act's prefix" % storylet.get("id", "?"))

func test_the_act_text_follows_the_form_rules() -> void:
	# VOICES.md Form: at most 90 characters in a bubble line, 40 on an option, at most one "!" per line.
	var table: Dictionary = _json("res://data/text/ru/act6.json")
	for key in table.keys():
		var text := str(table[key])
		if str(key).begins_with("_"):
			continue
		if str(key).begins_with("opt."):
			ok(text.length() <= 40, "%s fits an option (%d)" % [key, text.length()])
		elif str(key).begins_with("line.") or str(key).begins_with("dlg."):
			ok(text.length() <= 90, "%s fits a bubble (%d)" % [key, text.length()])
		ok(text.count("!") <= 1, "%s has at most one exclamation mark" % key)
