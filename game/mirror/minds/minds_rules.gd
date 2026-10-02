class_name MindsRules
extends RefCounted

# World rules (data/mirror/minds/world_rules.json): stable relations with unstable surfaces. A RULE names an
# invariant ("a poke is answered later with the same move"); each VARIANT is one surface manifestation of it
# (the globe answered by the statue, the raccoon repeating the poke) with a trigger, a transformation and the
# evidence the witch gets from seeing it. Conventions can patch a variant, so folklore can change what a rule
# does without a new rule.
#
# A variant:
#   trigger: {event_kind, subject, subject_not, subject_tags, actor, actor_not, witnessed_by, unwitnessed_by,
#             seen_by, unseen_by (witnessed by sight, or not),
#             requires_convention, convention_change: {id, change}, when, max_depth}
#   transformation: {reactions: [...], schedule: [...], effects: {world, npc_state}}
#   evidence: {holders, at: trigger|consequence, knowledge_effects, model_effects, ...}
#   conventions: {convention_id: {patch: {...}}}      (patch keys replace; keys ending in _add append)

var data: Dictionary
var _variants: Dictionary = {}

func _init(p_data: Dictionary) -> void:
	data = p_data
	for rule in data.get("rules", []):
		for variant in rule.get("variants", []):
			_variants[str(variant.get("id", ""))] = {"rule": str(rule.get("id", "")), "variant": variant}
		# An exception may carry a trigger of its own (the boundary of the rule announcing itself).
		for exception in rule.get("exceptions", []):
			if exception.has("trigger"):
				_variants[str(exception.get("id", ""))] = {"rule": str(rule.get("id", "")), "variant": exception}

func variant(id: String) -> Dictionary:
	var entry: Dictionary = _variants.get(id, {})
	var found: Dictionary = entry.get("variant", {})
	return found

func rule_of(variant_id: String) -> String:
	var entry: Dictionary = _variants.get(variant_id, {})
	return str(entry.get("rule", ""))

# The variants an event triggers, in variant-id order (never file order, so reordering the data cannot change
# what happens), each with its transformation already patched by the active conventions.
# Returns [{rule, variant_id, variant, holder}] where `holder` is the witness the trigger bound, if any.
func triggered(event: Dictionary, witness_ids: Array, tags: Array, active_conventions: Array, depth: int, context: Dictionary, default_depth: int) -> Array:
	var out: Array = []
	var ids: Array = _variants.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = _variants[id]
		var raw: Dictionary = entry["variant"]
		var trigger: Dictionary = raw.get("trigger", {})
		var bound := _match(trigger, event, witness_ids, tags, active_conventions, depth, context, default_depth)
		if bound.is_empty():
			continue
		out.append({"rule": entry["rule"], "variant_id": id, "variant": patched(raw, active_conventions), "holder": str(bound.get("holder", ""))})
	return out

# The variant with every active convention's patch applied (in convention-id order).
func patched(variant_data: Dictionary, active_conventions: Array) -> Dictionary:
	var patches: Dictionary = variant_data.get("conventions", {})
	if patches.is_empty():
		return variant_data
	var out: Dictionary = variant_data.duplicate(true)
	var transformation: Dictionary = out.get("transformation", {})
	var names: Array = patches.keys()
	names.sort()
	for convention_id in names:
		if convention_id not in active_conventions:
			continue
		var patch: Dictionary = patches[convention_id].get("patch", {})
		for key in patch.keys():
			var patch_key := str(key)
			if patch_key == "set":
				for path in patch[key].keys():
					_set_path(transformation, str(path).split("."), patch[key][path])
			elif patch_key.ends_with("_add"):
				var base := patch_key.trim_suffix("_add")
				var merged: Array = transformation.get(base, []).duplicate(true)
				merged.append_array(patch[key])
				transformation[base] = merged
			else:
				transformation[patch_key] = patch[key]
	out["transformation"] = transformation
	return out

# Sets one value inside a nested structure by a dotted path ("schedule.0.delay": array indexes are numbers).
static func _set_path(root: Variant, parts: PackedStringArray, value: Variant) -> bool:
	var current: Variant = root
	for i in range(parts.size() - 1):
		var step := parts[i]
		if current is Array and step.is_valid_int() and int(step) < (current as Array).size():
			current = current[int(step)]
		elif current is Dictionary and (current as Dictionary).has(step):
			current = current[step]
		else:
			return false
	var last := parts[parts.size() - 1]
	if current is Array and last.is_valid_int() and int(last) < (current as Array).size():
		current[int(last)] = value
		return true
	if current is Dictionary:
		current[last] = value
		return true
	return false

# Returns {} when the trigger does not match, else {"holder": <the witness it bound or "">}.
func _match(trigger: Dictionary, event: Dictionary, witness_ids: Array, tags: Array, active_conventions: Array, depth: int, context: Dictionary, default_depth: int) -> Dictionary:
	if depth > int(trigger.get("max_depth", default_depth)):
		return {}
	if not _listed(trigger.get("event_kind", "*"), str(event.get("kind", ""))):
		return {}
	if not _listed(trigger.get("subject", "*"), str(event.get("subject", ""))):
		return {}
	if trigger.has("subject_not") and _listed(trigger["subject_not"], str(event.get("subject", ""))):
		return {}
	if not _listed(trigger.get("actor", "*"), str(event.get("actor", ""))):
		return {}
	if trigger.has("actor_not") and _listed(trigger["actor_not"], str(event.get("actor", ""))):
		return {}
	if trigger.has("subject_tags"):
		var wanted: Array = trigger["subject_tags"]
		var any_tag := false
		for tag in wanted:
			if tag in tags:
				any_tag = true
		if not any_tag:
			return {}
	if trigger.has("requires_convention") and str(trigger["requires_convention"]) not in active_conventions:
		return {}
	if trigger.has("convention_change"):
		var wanted_change: Dictionary = trigger["convention_change"]
		var seen := false
		for change in context.get("convention_changes", []):
			if _listed(wanted_change.get("id", "*"), str(change.get("id", ""))) and str(change.get("change", "")) == str(wanted_change.get("change", "")):
				seen = true
		if not seen:
			return {}
	var bound := ""
	if trigger.has("witnessed_by"):
		bound = str(trigger["witnessed_by"])
		if bound not in witness_ids:
			return {}
	if trigger.has("unwitnessed_by"):
		bound = str(trigger["unwitnessed_by"])
		if bound in witness_ids or not data.get("holders", {}).has(bound):
			return {}
	# Seen means eyes on it (sight, or doing it): hearing something from the next room is not looking.
	if trigger.has("seen_by"):
		bound = str(trigger["seen_by"])
		if str(context.get("channels", {}).get(bound, "")) not in ["sight", "direct"]:
			return {}
	if trigger.has("unseen_by"):
		bound = str(trigger["unseen_by"])
		if str(context.get("channels", {}).get(bound, "")) in ["sight", "direct"] or not data.get("holders", {}).has(bound):
			return {}
	if trigger.has("when") and not MirrorConditions.matches(trigger["when"], context):
		return {}
	return {"holder": bound}

# "*" or an id or a list of ids.
static func _listed(spec: Variant, value: String) -> bool:
	if spec is Array:
		return value in spec or "*" in spec
	return str(spec) == "*" or str(spec) == value
