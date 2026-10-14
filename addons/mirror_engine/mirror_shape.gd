class_name MirrorShape
extends RefCounted

# Shape checks for definitions at registration. The engine reads these fields as arrays and
# dictionaries without checking them on every path, so a definition with the wrong shape is
# refused here rather than failing deep inside a transaction. Returns "" when the shape is fine.

const ACTION_ARRAY_FIELDS := ["valid_targets", "prediction_signature", "prediction_candidates", "response_contracts", "requires_claims", "excludes_claims", "requires_operators", "requires_models", "relationship_preconditions"]
const ACTION_DICTIONARY_FIELDS := ["preconditions", "default_observed"]

static func action_error(definition: Dictionary) -> String:
	if definition.has("action_type") and not definition["action_type"] is int:
		return "action_type must be an enum value"
	for field in ACTION_ARRAY_FIELDS:
		if definition.has(field) and not definition[field] is Array:
			return "%s must be an array" % field
	for field in ACTION_DICTIONARY_FIELDS:
		if definition.has(field) and not definition[field] is Dictionary:
			return "%s must be an object" % field
	for field in ["response_contracts", "prediction_candidates"]:
		for entry in definition.get(field, []):
			if not entry is Dictionary:
				return "%s must hold objects" % field
	return ""
