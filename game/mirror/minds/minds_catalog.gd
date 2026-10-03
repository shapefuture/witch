class_name MindsCatalog
extends RefCounted

# The authored half of the Minds layer, plain JSON in data/mirror/minds/ (ids and text KEYS only, never
# prose; the text table owns every word):
#
#   minds.json            limits, perception tuning, event kinds, places and their subjects, holders,
#                         communities, the starting beliefs
#   interpretations.json  how each holder reads each event
#   world_rules.json      the world's rules: invariants, surface variants, exceptions, revision paths
#   conventions.json      the folklore that can form
#
# It is kept apart from the engine's catalog on purpose. Everything a rule decides is written into the event
# log when it happens (who saw, what they made of it, what was scheduled, what was adopted), so retuning this
# data never invalidates a save; and a deferred consequence or a convention in the middle of a save can never
# disagree with the catalog fingerprint, because neither is part of it.

const DEFAULT_DIR := "res://data/mirror/minds"

const DEFAULTS := {
	"limits": {"max_pending": 32, "max_fired_per_pump": 16, "max_chain_depth": 3, "max_active_conventions": 12, "max_origin_events": 5},
	"attention": WitnessSelector.DEFAULT_ATTENTION,
	"perception": {"overheard_clarity": 35, "min_clarity": 10},
	"reaction_ops": [],
	"event_kinds": {},
	"places": {},
	"holders": {},
	"communities": {},
	"initial_beliefs": [],
}

# Returns {"data": Dictionary, "errors": Array, "warnings": Array}.
static func load_dir(dir: String = DEFAULT_DIR) -> Dictionary:
	var errors: Array = []
	var raw: Dictionary = {}
	var minds: Dictionary = _read_object(dir.path_join("minds.json"), errors)
	for key in minds.keys():
		raw[key] = minds[key]
	raw["interpretations"] = _read_array(dir.path_join("interpretations.json"), errors)
	raw["rules"] = _read_array(dir.path_join("world_rules.json"), errors)
	raw["conventions"] = _read_array(dir.path_join("conventions.json"), errors)
	return build(raw, errors)

# Normalises raw authored data (defaults, enum names) and checks the structure the runtime relies on.
static func build(raw: Dictionary, errors: Array = []) -> Dictionary:
	var warnings: Array = []
	var data: Dictionary = DEFAULTS.duplicate(true)
	for key in raw.keys():
		if key == "limits" or key == "perception":
			var merged: Dictionary = data[key]
			merged.merge(raw[key], true)
			data[key] = merged
		else:
			data[key] = raw[key].duplicate(true) if raw[key] is Array or raw[key] is Dictionary else raw[key]
	for key in ["interpretations", "rules", "conventions"]:
		if not data.has(key):
			data[key] = []
	_normalize(data, errors, "minds")
	_check_ids(data["interpretations"], "interpretation", errors)
	_check_ids(data["rules"], "world rule", errors)
	_check_ids(data["conventions"], "convention", errors)
	var variant_ids: Dictionary = {}
	for rule in data["rules"]:
		for variant in rule.get("variants", []):
			var variant_id := str(variant.get("id", ""))
			if variant_id.is_empty():
				errors.append("world rule %s has a variant without an id" % rule.get("id", "?"))
			elif variant_ids.has(variant_id):
				errors.append("duplicate variant id %s" % variant_id)
			variant_ids[variant_id] = true
	return {"data": data, "errors": errors, "warnings": warnings}

static func empty() -> Dictionary:
	return build({})["data"]

# Enum names ("SUPPORTED", "DIRECT") become the engine's ints, wherever effects appear in the data.
static func _normalize(node: Variant, errors: Array, where: String) -> void:
	if node is Array:
		for item in node:
			_normalize(item, errors, where)
	elif node is Dictionary:
		if node.has("knowledge_effects") or node.has("model_effects") or node.has("evidence"):
			MirrorCatalog._normalize_effects(node, errors, where)
		if node.has("requires_claims") or node.has("excludes_claims") or node.has("requires_models"):
			MirrorCatalog._normalize_requirements(node, errors, where)
		for key in node.keys():
			_normalize(node[key], errors, where)

static func _check_ids(items: Array, label: String, errors: Array) -> void:
	var seen: Dictionary = {}
	for item in items:
		if not item is Dictionary:
			errors.append("%s entry is not an object" % label)
			continue
		var id := str(item.get("id", ""))
		if id.is_empty():
			errors.append("%s without an id" % label)
		elif seen.has(id):
			errors.append("duplicate %s id %s" % [label, id])
		seen[id] = true

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
		var cleaned: Dictionary = {}
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
