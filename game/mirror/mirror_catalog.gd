class_name MirrorCatalog
extends RefCounted

# Loads the authored game content in data/mirror/ into a MirrorEngine.
#
# Content is plain JSON so it diffs, reviews and validates like code. JSON has no enums, so
# fields that the engine stores as ints may be written by name ("LOOK", "SUPPORTED") and are
# normalised here. The catalog holds IDs and text KEYS only; prose lives in data/text/, so
# rewording never changes the catalog fingerprint (which every save is bound to).

const DEFAULT_DIR := "res://data/mirror"

# Builds a fresh engine with the full catalog registered (but NOT locked: locking happens on
# the first committed transaction). Returns {"engine", "report"}.
static func build_engine(dir: String = DEFAULT_DIR) -> Dictionary:
	var engine := MirrorEngine.new()
	var report := load_into(engine, dir)
	return {"engine": engine, "report": report}

static func load_into(engine: MirrorEngine, dir: String = DEFAULT_DIR) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []

	var world: Dictionary = _read_object(dir.path_join("world.json"), errors)
	for key in world.get("world", {}).keys():
		if not engine.set_world(str(key), world["world"][key]):
			errors.append("world: could not set '%s' (catalog locked or events exist)" % key)
	for npc_id in world.get("npc_state", {}).keys():
		if not engine.set_npc_state(str(npc_id), world["npc_state"][npc_id]):
			errors.append("world: could not set npc state '%s'" % npc_id)

	for file_name in _list_json(dir.path_join("actions")):
		for definition in _read_array(dir.path_join("actions").path_join(file_name), errors):
			if not definition is Dictionary:
				errors.append("%s: entry is not an object" % file_name)
				continue
			_normalize_action(definition, errors, warnings)
			if not engine.register_action(definition):
				errors.append("%s: could not register action '%s'" % [file_name, definition.get("id", "?")])

	for definition in _read_array(dir.path_join("operators.json"), errors):
		if not engine.register_operator(definition):
			errors.append("operators.json: could not register '%s'" % definition.get("id", "?"))
	for definition in _read_array(dir.path_join("storylets.json"), errors):
		_normalize_requirements(definition, errors, str(definition.get("id", "?")))
		if not engine.register_storylet(definition):
			errors.append("storylets.json: could not register '%s'" % definition.get("id", "?"))
	for definition in _read_array(dir.path_join("hypotheses.json"), errors):
		_normalize_requirements(definition, errors, str(definition.get("id", "?")))
		for requirement in definition.get("requires_evidence", []):
			_normalize_claim_requirement(requirement, errors, str(definition.get("id", "?")))
		if not engine.register_causal_hypothesis(definition):
			errors.append("hypotheses.json: could not register '%s'" % definition.get("id", "?"))

	var validation := engine.validate_catalog()
	errors.append_array(validation.get("errors", []))
	warnings.append_array(validation.get("warnings", []))
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}

# The "what the witch already believes" observation recorded as the first event of a new game.
static func load_prologue(dir: String = DEFAULT_DIR) -> Dictionary:
	var errors: Array = []
	var prologue := _read_object(dir.path_join("prologue.json"), errors)
	_normalize_effects(prologue, errors, "prologue")
	return prologue

# ---------------------------------------------------------------------------------------------

static func _normalize_action(definition: Dictionary, errors: Array, warnings: Array) -> void:
	var id := str(definition.get("id", "?"))
	if definition.has("action_type"):
		definition["action_type"] = _enum(MirrorDomain.ActionType, definition["action_type"], errors, id)
	_normalize_requirements(definition, errors, id)
	var repeatable := str(definition.get("once_key", "")).is_empty()
	for response in definition.get("response_contracts", []):
		var where := "%s/%s" % [id, response.get("id", "?")]
		_normalize_requirements(response, errors, where)
		_normalize_effects(response, errors, where)
		for evidence in response.get("evidence", []):
			# Evidence ids are immutable: re-recording the same id from a later transaction is an
			# evidence_conflict, so a fixed id can only ever fire once. Omit the id and the engine
			# derives a unique one per transaction.
			if evidence is Dictionary and evidence.has("id") and repeatable:
				errors.append("%s: fixed evidence id '%s' in a repeatable action would conflict on second use" % [where, evidence["id"]])
		if not response.has("presentation"):
			warnings.append("%s: response has no presentation" % where)

static func _normalize_requirements(holder: Dictionary, errors: Array, where: String) -> void:
	for field in ["requires_claims", "excludes_claims"]:
		for requirement in holder.get(field, []):
			_normalize_claim_requirement(requirement, errors, where)
	for requirement in holder.get("requires_models", []):
		if requirement is Dictionary and requirement.has("min_status"):
			requirement["min_status"] = _enum(MirrorDomain.ModelStatus, requirement["min_status"], errors, where)

static func _normalize_claim_requirement(requirement: Variant, errors: Array, where: String) -> void:
	if requirement is Dictionary and requirement.has("min_status"):
		requirement["min_status"] = _enum(MirrorDomain.EpistemicStatus, requirement["min_status"], errors, where)

static func _normalize_effects(holder: Dictionary, errors: Array, where: String) -> void:
	for effect in holder.get("knowledge_effects", []):
		if effect is Dictionary and effect.has("status"):
			effect["status"] = _enum(MirrorDomain.EpistemicStatus, effect["status"], errors, where)
	for effect in holder.get("model_effects", []):
		if effect is Dictionary and effect.has("status"):
			effect["status"] = _enum(MirrorDomain.ModelStatus, effect["status"], errors, where)
	for evidence in holder.get("evidence", []):
		if evidence is Dictionary and evidence.has("type"):
			evidence["type"] = _enum(MirrorDomain.EvidenceType, evidence["type"], errors, where)

static func _enum(table: Dictionary, value: Variant, errors: Array, where: String) -> int:
	if value is int or value is float:
		return int(value)
	var key := str(value)
	if table.has(key):
		return int(table[key])
	errors.append("%s: unknown enum name '%s'" % [where, key])
	return 0

static func _list_json(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".json"):
			out.append(file_name)
	out.sort()
	return out

static func _read_array(path: String, errors: Array) -> Array:
	var parsed: Variant = _read_json(path, errors)
	if parsed is Array:
		return parsed
	if parsed != null:
		errors.append("%s: expected a JSON array" % path)
	return []

static func _read_object(path: String, errors: Array) -> Dictionary:
	var parsed: Variant = _read_json(path, errors)
	if parsed is Dictionary:
		var cleaned := {}
		for key in parsed.keys():
			if not str(key).begins_with("_"):
				cleaned[key] = parsed[key]
		return cleaned
	if parsed != null:
		errors.append("%s: expected a JSON object" % path)
	return {}

static func _read_json(path: String, errors: Array) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
