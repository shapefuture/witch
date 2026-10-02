class_name MindsInterpreter
extends RefCounted

# What does THIS witness make of what it perceived? The same event is read differently by different holders,
# depending on what each already believes (claims, models, operators), how each stands with the actor
# (relationship), each one's stance (npc state), how clearly it perceived the event, and which conventions
# its community holds. The reading is data (data/mirror/minds/interpretations.json), chosen like a response
# contract: every rule that matches competes, the highest score wins, ties go to the lowest id.
#
# A reading is not necessarily true. Each rule says what the holder takes to have happened (`perceived`:
# outcome, actor_id, motive, ...). Anything the event's `truth` also states is compared with the engine's own
# discrepancy service, so a witness who blames the wrong person, or reads a motive into an accident, is
# recorded as having misread, with the discrepancy kinds the engine already defines.
#
# A rule:
#   event_kind  holder / holder_tags  actor  subject / subject_tags  channels  min_clarity / max_clarity
#   when (the condition DSL)  requires_claims / excludes_claims / requires_models / requires_operators
#   priority  reads  perceived  expects
#   knowledge_effects  model_effects  operator_effects  relationship_effects  reactions
# Effects are templated ($holder, $actor, $subject, ...) and default to the witness as their holder.

const EVIDENCE_BY_CHANNEL := {
	"direct": MirrorDomain.EvidenceType.DIRECT,
	"sight": MirrorDomain.EvidenceType.DIRECT,
	"sound": MirrorDomain.EvidenceType.INDIRECT,
	"overheard": MirrorDomain.EvidenceType.AMBIGUOUS,
}

var engine: MirrorEngine
var data: Dictionary

func _init(p_engine: MirrorEngine, p_data: Dictionary) -> void:
	engine = p_engine
	data = p_data

func interpret(event: Dictionary, witness: Dictionary, context: Dictionary, active_conventions: Array, truth: Dictionary) -> Dictionary:
	var holder := str(witness["holder"])
	var holder_tags: Array = data.get("holders", {}).get(holder, {}).get("tags", [])
	var vars := variables(event, witness)
	var witness_context: Dictionary = context.duplicate()
	witness_context["holder"] = holder
	witness_context["witness"] = {"holder": holder, "channel": str(witness["channel"]), "clarity": int(witness["clarity"]), "attention": str(witness.get("attention", "idle"))}
	witness_context["relation"] = _relation_summary(holder, str(event.get("actor", "")))
	var candidates: Array = []
	for rule in data.get("interpretations", []):
		var score := _score(rule, event, witness, holder_tags, witness_context, active_conventions)
		if score >= 0:
			candidates.append({"rule": rule, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) == int(b["score"]):
			return str(a["rule"].get("id", "")) < str(b["rule"].get("id", ""))
		return int(a["score"]) > int(b["score"]))
	var rule: Dictionary = {} if candidates.is_empty() else candidates[0]["rule"]
	var reads := str(rule.get("reads", "")) if not rule.is_empty() else "noticed"
	if reads.is_empty():
		reads = "noticed"
	var perceived: Dictionary = MindsTemplate.apply(rule.get("perceived", {}), vars)
	var out := {
		"holder": holder,
		"rule_id": str(rule.get("id", "")),
		"reads": reads,
		"perceived": perceived,
		"misread": false,
		"kinds": [],
		"surprise": [],
		"knowledge_effects": with_holder(MindsTemplate.apply(rule.get("knowledge_effects", []), vars), "holder_id", holder, "scope", str(event.get("place", ""))),
		"model_effects": with_holder(MindsTemplate.apply(rule.get("model_effects", []), vars), "observer_id", holder),
		"operator_effects": with_holder(MindsTemplate.apply(rule.get("operator_effects", []), vars), "observer_id", holder),
		"relationship_effects": with_holder(MindsTemplate.apply(rule.get("relationship_effects", []), vars), "a", holder),
		"reactions": MindsTemplate.apply(rule.get("reactions", []), vars),
		"evidence": [{"type": int(EVIDENCE_BY_CHANNEL.get(str(witness["channel"]), MirrorDomain.EvidenceType.DIRECT)), "payload": {
			"event": str(event.get("kind", "")), "subject": str(event.get("subject", "")), "channel": str(witness["channel"]),
			"clarity": int(witness["clarity"]), "reads": reads}}],
	}
	var common: Dictionary = shared(perceived, truth)
	if not common.is_empty():
		var comparison := engine.discrepancy.compare({"expected": common}, truth)
		out["misread"] = bool(comparison.get("has_discrepancy", false))
		out["kinds"] = comparison.get("kinds", [])
	if rule.has("expects"):
		var expected: Dictionary = MindsTemplate.apply(rule["expects"], vars)
		var surprise := engine.discrepancy.compare({"expected": shared(expected, truth)}, truth)
		out["surprise"] = surprise.get("kinds", [])
	return out

# The variables an authored template may use for one witness of one event.
static func variables(event: Dictionary, witness: Dictionary = {}) -> Dictionary:
	var data_block: Dictionary = event.get("data", {})
	var out: Dictionary = {
		"holder": str(witness.get("holder", "")),
		"actor": str(event.get("actor", "")),
		"subject": str(event.get("subject", "")),
		"place": str(event.get("place", "")),
		"kind": str(event.get("kind", "")),
		"channel": str(witness.get("channel", "")),
		"time": str(event.get("time", 0)),
		"reaction": str(data_block.get("reaction", "")),
	}
	# Anything else the event carries is `$data_<key>` ($data_answers for {"answers": "globe"}).
	for key in data_block.keys():
		out["data_" + str(key)] = str(data_block[key])
	return out

# -1 when the rule does not apply to this witness of this event, else its score.
func _score(rule: Dictionary, event: Dictionary, witness: Dictionary, holder_tags: Array, context: Dictionary, active_conventions: Array) -> int:
	var holder := str(witness["holder"])
	if not MindsRules._listed(rule.get("event_kind", "*"), str(event.get("kind", ""))):
		return -1
	var specificity := 1
	var holder_spec: Variant = rule.get("holder", "*")
	if not (holder_spec is String and holder_spec == "*"):
		if not MindsRules._listed(holder_spec, holder):
			return -1
		specificity = 3
	if rule.has("holder_tags"):
		var tag_hit := false
		for tag in rule["holder_tags"]:
			if tag in holder_tags:
				tag_hit = true
		if not tag_hit:
			return -1
		specificity = maxi(specificity, 2)
	if not MindsRules._listed(rule.get("actor", "*"), str(event.get("actor", ""))):
		return -1
	if not MindsRules._listed(rule.get("subject", "*"), str(event.get("subject", ""))):
		return -1
	if rule.has("subject_tags"):
		var subject_hit := false
		for tag in rule["subject_tags"]:
			if tag in context.get("event", {}).get("subject_tags", []):
				subject_hit = true
		if not subject_hit:
			return -1
	if rule.has("channels") and str(witness["channel"]) not in rule["channels"]:
		return -1
	var clarity := int(witness["clarity"])
	if clarity < int(rule.get("min_clarity", 0)) or clarity > int(rule.get("max_clarity", 100)):
		return -1
	if rule.has("when") and not MirrorConditions.matches(rule["when"], context):
		return -1
	if not engine.check_requirements(rule, holder, context).get("ok", false):
		return -1
	return (int(rule.get("priority", 0)) + _bias(rule, event, holder, active_conventions)) * 10 + specificity

# A convention held by the holder's community makes the reading it is about easier to reach.
func _bias(rule: Dictionary, event: Dictionary, holder: String, active_conventions: Array) -> int:
	var reads := str(rule.get("reads", ""))
	if reads.is_empty():
		return 0
	var bonus := 0
	for definition in data.get("conventions", []):
		if str(definition.get("id", "")) not in active_conventions or str(definition.get("reads", "")) != reads:
			continue
		var members: Array = data.get("communities", {}).get(str(definition.get("community", "")), {}).get("members", [])
		if holder not in members:
			continue
		var subjects: Array = definition.get("subjects", [])
		if not subjects.is_empty() and str(event.get("subject", "")) not in subjects:
			continue
		bonus += int(definition.get("force", {}).get("bias", 0))
	return bonus

func _relation_summary(holder: String, actor: String) -> Dictionary:
	var relation := engine.relationships.get_relation(holder, actor)
	var tags: Array = []
	for item in relation.get("events", []):
		for tag in item.get("tags", []):
			if tag not in tags:
				tags.append(tag)
	tags.sort()
	var readings: Array = []
	for item in relation.get("interpretations", []):
		readings.append(item.get("value", ""))
	return {"count": relation.get("events", []).size(), "tags": tags, "interpretations": readings}

# What a perceived account and the truth both speak about (so only comparable dimensions are compared).
static func shared(account: Dictionary, truth: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in account.keys():
		if truth.has(key):
			out[key] = account[key]
	return out

# Fills the default holder field of each effect that does not name one.
static func with_holder(effects: Variant, field: String, holder: String, second_field: String = "", second_value: String = "") -> Array:
	var out: Array = []
	for effect in effects:
		var copy: Dictionary = (effect as Dictionary).duplicate(true)
		if not copy.has(field):
			copy[field] = holder
		if not second_field.is_empty() and not copy.has(second_field):
			copy[second_field] = second_value
		out.append(copy)
	return out
