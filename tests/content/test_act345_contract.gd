extends TestCase

# The house rules for acts III to V (docs/design/GAME_SPEC.md section 5), checked over the whole game scope: every
# action is gated to its place and act, every response is presented with a known kind, the default response comes last,
# the notebook kinds carry the statuses they name, the text keys exist, no act moves the story backwards, magic does not
# come back in these acts, and the garden below is never restored.

const PREFIXES := ["act3_", "act4_", "act5_"]
const KINDS := ["line", "dialogue", "camera", "anim", "npc", "magic", "leave_frame", "wait", "room_variant", "flash",
		"sight", "notebook", "ending"]
const NOTEBOOK_FILES := ["act3", "act4", "act5"]
const PUBLISHED_CLAIMS := ["act3_father_toolbox", "act3_shadow_key", "act3_bench_straight", "act3_no_sunflowers",
		"act3_no_knot", "act3_only_mine", "act5_spell_moves_things", "act5_pull_proves_nothing", "act5_he_stood_here",
		"act5_he_went_back", "act5_would_he_come", "act5_hand_lifted", "act5_what_the_wave_meant", "act5_stain",
		"act5_cannot_be_restored"]


func _mine(id: String) -> bool:
	for prefix in PREFIXES:
		if id.begins_with(prefix):
			return true
	return false


func _definitions(r: MirrorRuntime) -> Array:
	var out: Array = []
	for id in r.engine.action_definitions.keys():
		if _mine(str(id)):
			out.append(r.engine.action_definitions[id])
	return out


func _statuses(definitions: Array) -> Dictionary:
	var found: Dictionary = {}
	for definition in definitions:
		for response in definition.get("response_contracts", []):
			for effect in response.get("knowledge_effects", []):
				var claim_id := str(effect.get("id", ""))
				if not found.has(claim_id):
					found[claim_id] = []
				found[claim_id].append(int(effect.get("status", -1)))
	return found


func _expected(kind: String) -> int:
	match kind:
		"untestable":
			return MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN
		"inferred":
			return MirrorDomain.EpistemicStatus.SUPPORTED
		"predicted":
			return MirrorDomain.EpistemicStatus.POSSIBLE
	return MirrorDomain.EpistemicStatus.ESTABLISHED


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


func _acts_allowed(pre: Dictionary) -> Array:
	if pre.has("story.act"):
		return [str(pre["story.act"])]
	var inner: Dictionary = pre.get("$in", {})
	return inner.get("story.act", [])


func _rank(act: String) -> int:
	var digits := act.trim_prefix("act")
	if digits.is_valid_int():
		return int(digits)
	return -1


func test_every_action_is_gated_to_the_witchs_place_and_to_its_act() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	for definition in _definitions(r):
		var id := str(definition.get("id", ""))
		var pre: Dictionary = definition.get("preconditions", {})
		ok(pre.has("witch.place"), "%s is gated to the witch's place" % id)
		ok(not _acts_allowed(pre).is_empty(), "%s is gated to an act" % id)


func test_every_response_is_presented_with_a_known_kind() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	for definition in _definitions(r):
		for response in definition.get("response_contracts", []):
			var rid := str(response.get("id", ""))
			var presentation: Array = response.get("presentation", [])
			ok(not presentation.is_empty(), "%s has a presentation" % rid)
			for entry in presentation:
				ok(str(entry.get("kind", "")) in KINDS, "%s presents a known kind (%s)" % [rid, str(entry.get("kind", ""))])


func _conditional(response: Dictionary) -> bool:
	for key in ["when", "requires_claims", "requires_operators", "requires_models", "npc_preconditions", "excludes_claims"]:
		if response.has(key):
			return true
	return false


func test_the_default_response_comes_last() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	for definition in _definitions(r):
		var responses: Array = definition.get("response_contracts", [])
		if responses.size() < 2:
			continue
		var lowest_conditional := 1000000
		var defaults: Array = []
		for response in responses:
			if _conditional(response):
				lowest_conditional = mini(lowest_conditional, int(response.get("priority", 0)))
			else:
				defaults.append(response)
		ok(defaults.size() <= 1, "%s has at most one default response" % str(definition.get("id", "")))
		for response in defaults:
			ok(int(response.get("priority", 0)) < lowest_conditional, "%s comes after the conditional ones" % str(response.get("id", "")))


func test_every_text_key_the_content_names_exists() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	var table: Dictionary = Localization.load_table()
	for definition in _definitions(r):
		var label := str(definition.get("label_key", ""))
		ok(table.has(label), "%s has its label text" % label)
		for response in definition.get("response_contracts", []):
			for entry in response.get("presentation", []):
				if entry.has("key"):
					ok(table.has(str(entry["key"])), "the line %s exists" % str(entry["key"]))
				if entry.has("sensation"):
					ok(table.has(str(entry["sensation"])), "the sensation %s exists" % str(entry["sensation"]))
	for file_name in NOTEBOOK_FILES:
		var notes := _read("res://data/notebook/%s.json" % file_name)
		for claim_id in notes.keys():
			ok(table.has(str(notes[claim_id].get("text", ""))), "the notebook text of %s exists" % str(claim_id))


func test_the_notebook_kinds_carry_the_statuses_they_name() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	var statuses := _statuses(_definitions(r))
	var table: Dictionary = Localization.load_table()
	for file_name in NOTEBOOK_FILES:
		var notes := _read("res://data/notebook/%s.json" % file_name)
		for claim_id in notes.keys():
			var entry: Dictionary = notes[claim_id]
			var kind := str(entry.get("kind", ""))
			ok(statuses.has(str(claim_id)), "%s is set by an action" % str(claim_id))
			for status in statuses.get(str(claim_id), []):
				eq(int(status), _expected(kind), "%s carries its %s status" % [str(claim_id), kind])
			if kind == "untestable":
				ok(str(table.get(str(entry.get("text", "")), "")).ends_with("?"), "%s is worded as an open question" % str(claim_id))


func test_the_published_interfaces_exist() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	var statuses := _statuses(_definitions(r))
	for claim_id in PUBLISHED_CLAIMS:
		ok(statuses.has(claim_id), "%s is published by an action" % claim_id)
	ok(r.engine.operator_definitions.has("op.act3_revise_before_repeating"), "the operator is registered")
	for world_key in ["act3_shadow_key", "act3_loop", "act3_clock", "act3_garden", "garden_below", "act5_hold"]:
		ok(r.engine.world_state.has(world_key), "the world entity %s exists" % world_key)


func test_no_act_moves_the_story_backwards() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	for definition in _definitions(r):
		var newest_allowed := -1
		for act in _acts_allowed(definition.get("preconditions", {})):
			newest_allowed = maxi(newest_allowed, _rank(str(act)))
		for response in definition.get("response_contracts", []):
			var world: Dictionary = response.get("effects", {}).get("world", {})
			if world.has("story"):
				var moved: Dictionary = world["story"]
				ok(_rank(str(moved.get("act", ""))) > newest_allowed, "%s moves the story forward" % str(response.get("id", "")))


func test_magic_does_not_come_back_in_these_acts() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	for definition in _definitions(r):
		for response in definition.get("response_contracts", []):
			var world: Dictionary = response.get("effects", {}).get("world", {})
			if world.has("magic"):
				var magic: Dictionary = world["magic"]
				ok(not (str(magic.get("state", "")) in ["below", "full", "returned"]), "%s does not give magic back" % str(response.get("id", "")))


func test_the_garden_below_is_never_restored_and_fades_only_as_the_magic_goes() -> void:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	for definition in _definitions(r):
		for response in definition.get("response_contracts", []):
			var world: Dictionary = response.get("effects", {}).get("world", {})
			if not world.has("garden_below"):
				continue
			var garden: Dictionary = world["garden_below"]
			var state := str(garden.get("state", ""))
			ok(state != "lush", "%s never restores the garden" % str(response.get("id", "")))
			if state == "fading":
				var magic: Dictionary = world.get("magic", {})
				eq(str(magic.get("state", "")), "gone", "%s fades the garden only as the magic goes" % str(response.get("id", "")))
