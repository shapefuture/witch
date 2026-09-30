class_name InteractionResolver
extends RefCounted

# Turns the Mirror engine's affordances for a target into natural-language options.
#
#   knowledge / relationships / NPC expectation  ->  engine.explain_affordances()
#                                                 ->  available, player-facing options
#
# This is where "knowledge becomes ability": the same target offers different options as the
# player's claims and models change, and an option only ever appears once the engine says it is
# available. Options blocked only by knowledge (latent) are simply absent for the player and
# visible, with their reasons, to explain().

const GROUP_ORDER := ["observe", "social", "wait", "act", "magic"]

var engine: MirrorEngine

func _init(p_engine: MirrorEngine) -> void:
	engine = p_engine

func resolve(ctx: InteractionContext) -> Array[InteractionOption]:
	var options: Array[InteractionOption] = []
	for entry in engine.explain_affordances(ctx.target_id, ctx.action_context(), ctx.actor_id):
		var definition: Dictionary = entry["action"]
		if bool(definition.get("hidden", false)) or not entry["available"]:
			continue
		options.append(_build_option(definition, ctx))
	options.sort_custom(_compare)
	return options

# Developer-only: every action considered for the target, available or not, with why.
func explain(ctx: InteractionContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var world_context: Dictionary = engine.explain_action(MirrorAction.new("", ctx.actor_id, ctx.target_id)).get("context", {})
	for entry in engine.explain_affordances(ctx.target_id, ctx.action_context(), ctx.actor_id):
		var definition: Dictionary = entry["action"]
		if bool(definition.get("hidden", false)):
			continue
		var valid_targets: Array = definition.get("valid_targets", [])
		if not valid_targets.is_empty() and ctx.target_id not in valid_targets:
			continue
		var row := {
			"action_id": str(definition.get("id", "")),
			"label": _label(definition),
			"available": entry["available"],
			"latent": entry["latent"],
			"state": entry["affordance_state"],
			"reasons": entry["reasons"],
			"source": {"ontology": _ontology_name(int(definition.get("action_type", MirrorDomain.ActionType.CUSTOM))), "target": ctx.target_id},
			"available_because": _satisfied(definition) if entry["available"] else [],
			"prediction": _matching_prediction(definition, world_context, ctx),
			"effect_contract": _effect_contract(definition),
		}
		out.append(row)
	return out

func _build_option(definition: Dictionary, ctx: InteractionContext) -> InteractionOption:
	var option := InteractionOption.new()
	option.action_id = str(definition.get("id", ""))
	option.option_id = "%s@%s" % [option.action_id, ctx.target_id]
	option.target_id = ctx.target_id
	option.label_key = str(definition.get("label_key", ""))
	option.label = _label(definition)
	option.group = str(definition.get("affordance_group", ""))
	option.ontology = int(definition.get("action_type", MirrorDomain.ActionType.CUSTOM))
	option.context = ctx.action_context()
	return option

func _label(definition: Dictionary) -> String:
	var key := str(definition.get("label_key", ""))
	return TranslationServer.translate(key) if not key.is_empty() else str(definition.get("id", ""))

func _compare(a: InteractionOption, b: InteractionOption) -> bool:
	var ga := GROUP_ORDER.find(a.group)
	var gb := GROUP_ORDER.find(b.group)
	if ga != gb:
		return (GROUP_ORDER.size() if ga < 0 else ga) < (GROUP_ORDER.size() if gb < 0 else gb)
	return a.action_id < b.action_id

func _ontology_name(type: int) -> String:
	for key in MirrorDomain.ActionType.keys():
		if int(MirrorDomain.ActionType[key]) == type:
			return str(key)
	return "UNKNOWN"

func _satisfied(definition: Dictionary) -> Array:
	var out: Array = []
	for requirement in definition.get("requires_claims", []):
		out.append("knows:%s" % (requirement.get("id", "") if requirement is Dictionary else str(requirement)))
	for requirement in definition.get("requires_models", []):
		out.append("model:%s" % requirement.get("id", ""))
	for requirement in definition.get("requires_operators", []):
		out.append("operator:%s" % (requirement.get("id", "") if requirement is Dictionary else str(requirement)))
	for path in _condition_paths(definition.get("preconditions", {})):
		out.append("state:%s" % path)
	return out

# The state paths a condition reads, looking through $neq / $in / $all / $not wrappers.
func _condition_paths(node: Variant) -> Array[String]:
	var out: Array[String] = []
	if node is Dictionary:
		for key in node.keys():
			var name := str(key)
			if name in ["$all", "$any"] and node[key] is Array:
				for child in node[key]:
					out.append_array(_condition_paths(child))
			elif name == "$not":
				out.append_array(_condition_paths(node[key]))
			elif name.begins_with("$") and node[key] is Dictionary:
				for path in node[key].keys():
					out.append(str(path))
			else:
				out.append(name)
	return out

func _matching_prediction(definition: Dictionary, world_context: Dictionary, ctx: InteractionContext) -> String:
	var candidates: Array = definition.get("prediction_candidates", [])
	if candidates.is_empty():
		return ""
	var context := world_context.duplicate(true)
	context["actor_id"] = ctx.actor_id
	context["target_id"] = ctx.target_id
	var result := engine.prediction.predict(context, candidates)
	return str(result.get("prediction", {}).get("id", "")) if result.get("matched", false) else ""

func _effect_contract(definition: Dictionary) -> Array:
	var kinds := {}
	for response in definition.get("response_contracts", []):
		var effects: Dictionary = response.get("effects", {})
		if not effects.get("world", {}).is_empty(): kinds["world"] = true
		if not effects.get("npc_state", {}).is_empty(): kinds["npc_expectation"] = true
		if not response.get("knowledge_effects", []).is_empty(): kinds["knowledge"] = true
		if not response.get("model_effects", []).is_empty(): kinds["model_revision"] = true
		if not response.get("operator_effects", []).is_empty(): kinds["operator"] = true
		if not response.get("relationship_tags", []).is_empty(): kinds["relationship"] = true
		if not response.get("presentation", []).is_empty(): kinds["presentation"] = true
	var out: Array = kinds.keys()
	out.sort()
	return out
