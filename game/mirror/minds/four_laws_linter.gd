class_name FourLawsLinter
extends RefCounted

# The four laws of comic causal worldmaking, as concrete rules over the authored Minds catalog
# (data/mirror/minds). Run as a test (tests/mirror/test_four_laws.gd); a failing law names the rule, the code
# and what to add.
#
#   LAW 1  INVARIANT RELATIONS   Absurdity may change the surface; it must not arbitrarily change the
#                                relationship. A rule declares an invariant (a relation, its polarity, its
#                                roles, constraints). Every variant must instantiate exactly that relation,
#                                bind every role, keep the polarity, and satisfy the constraints in what it
#                                actually DOES (its transformation, also as altered by each convention).
#   LAW 2  EVIDENCE              If the player is to learn a rule, the world holds enough independent evidence
#                                to reconstruct it: at least N manifestations (3 for a major rule) with
#                                different sources, in at least two domains, each one delivering something
#                                the witch can learn.
#   LAW 3  MODEL REVISION        When the player is wrong, reveal a deeper rule instead of declaring her
#                                reasoning invalid. A learnable rule names the model the witch forms, an
#                                exception that breaks it, and a `revise` (never a bare `contradict`) from
#                                that model to a deeper one, with text that says what it teaches.
#   LAW 4  CULTURAL PERSISTENCE  Repeated interpretations become conventions, and conventions become causal
#                                forces. Every convention declares its origin (the event kinds and the
#                                readings that feed it), is reachable, is bounded (threshold, cap, decay),
#                                and does something (bias, an operator, a variant that depends on it).
#   (0)    STRUCTURE             References resolve: event kinds, subjects, holders, operators, text keys.
#
# A finding is {law, severity, subject, code, message}. Errors fail the test; warnings are advice.

const DOMAINS := ["physical", "affordance", "social", "relational", "semantic", "cultural", "temporal", "epistemic", "representational", "magic"]
const FORMS := ["direct", "social", "historical", "counter", "predictive"]
const MODEL_EFFECTS := ["upsert", "support", "contradict", "revise", "transfer", "ensure"]
const CONSTRAINTS := ["delay_min", "delay_max", "same_reaction", "needs_convention", "different_subject"]
const DEFAULTS := {"min_manifestations": 2, "major_manifestations": 3, "min_domains": 2}

# options: {"table": text table (keys must exist), "engine": MirrorEngine (operators must exist),
#           "min_manifestations", "major_manifestations", "min_domains"}
static func lint(data: Dictionary, options: Dictionary = {}) -> Array:
	var findings: Array = []
	var settings: Dictionary = DEFAULTS.duplicate()
	settings.merge(options, true)
	var index := _index(data)
	_structure(data, index, options, findings)
	for rule in data.get("rules", []):
		_law_one(rule, data, index, findings)
		if bool(rule.get("learnable", false)):
			_law_two(rule, settings, findings)
			_law_three(rule, data, options, findings)
	for convention in data.get("conventions", []):
		_law_four(convention, data, index, options, findings)
	var meets := recombinations(data)
	for rule in data.get("rules", []):
		if bool(rule.get("learnable", false)) and (meets.get(str(rule.get("id", "")), []) as Array).is_empty():
			findings.append(_finding(0, "warning", str(rule.get("id", "")), "no_recombination", "this rule never meets another: no consequence of it triggers another rule, and no convention is shared. Rules should recombine."))
	return findings

# Law 4 at runtime: whatever the world has actually adopted must be traceable to where it began.
static func lint_state(minds: MirrorMinds) -> Array:
	var findings: Array = []
	for id in minds.state.conventions.ids():
		var state: Dictionary = minds.state.conventions.get_state(str(id))
		if bool(state["adopted"]) and (state["origin_events"] as Array).is_empty():
			findings.append(_finding(4, "error", str(id), "adopted_without_origin", "convention %s is in force but no event is recorded as its origin" % id))
		for event_id in state["origin_events"]:
			if minds.engine.event_store.get_by_id(str(event_id)) == null:
				findings.append(_finding(4, "error", str(id), "origin_not_in_log", "convention %s names origin event %s, which is not in the log" % [id, event_id]))
	return findings

static func errors(findings: Array) -> Array:
	return findings.filter(func(f: Dictionary) -> bool: return f["severity"] == "error")

static func format(findings: Array) -> String:
	var lines: Array[String] = []
	for finding in findings:
		var law := "structure" if int(finding["law"]) == 0 else "law %d" % int(finding["law"])
		lines.append("[%s %s] %s (%s): %s" % [law, finding["severity"], finding["subject"], finding["code"], finding["message"]])
	return "\n".join(lines)

# What each learnable rule recombines with: another rule whose variants are triggered by an event kind this
# rule schedules, or that shares a convention with it. {rule_id: [{with, via}]}
static func recombinations(data: Dictionary) -> Dictionary:
	var scheduled: Dictionary = {}
	var triggers: Dictionary = {}
	var conventions: Dictionary = {}
	for rule in data.get("rules", []):
		var id := str(rule.get("id", ""))
		scheduled[id] = []
		triggers[id] = []
		conventions[id] = []
		for variant in _triggerables(rule):
			for spec in _schedules(variant):
				var kind := str(spec.get("event", {}).get("kind", ""))
				if kind not in scheduled[id]:
					scheduled[id].append(kind)
			var trigger: Dictionary = variant.get("trigger", {})
			for kind in _as_list(trigger.get("event_kind", [])):
				if kind not in triggers[id]:
					triggers[id].append(kind)
			for convention_id in _convention_refs(variant):
				if convention_id not in conventions[id]:
					conventions[id].append(convention_id)
	var out: Dictionary = {}
	for rule in data.get("rules", []):
		var id := str(rule.get("id", ""))
		var found: Array = []
		for other in data.get("rules", []):
			var other_id := str(other.get("id", ""))
			if other_id == id:
				continue
			for kind in scheduled[id]:
				if kind in triggers[other_id] and {"with": other_id, "via": "event:%s" % kind} not in found:
					found.append({"with": other_id, "via": "event:%s" % kind})
			for kind in scheduled[other_id]:
				if kind in triggers[id] and {"with": other_id, "via": "event:%s" % kind} not in found:
					found.append({"with": other_id, "via": "event:%s" % kind})
			for convention_id in conventions[id]:
				if convention_id in conventions[other_id] and {"with": other_id, "via": convention_id} not in found:
					found.append({"with": other_id, "via": convention_id})
		out[id] = found
	return out

# The five tests every world rule should pass (LXXXVI), as booleans, for the docs and for debugging.
static func five_tests(data: Dictionary, table: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	var meets := recombinations(data)
	for rule in data.get("rules", []):
		var id := str(rule.get("id", ""))
		var statement_key := str(rule.get("statement", {}).get("key", ""))
		var shown: Array = manifestations(rule)
		out[id] = {
			"can_state_it": not statement_key.is_empty() and (table.is_empty() or table.has(statement_key)),
			"can_demonstrate_it": shown.size() >= 2,
			"can_infer_it": shown.all(func(v: Dictionary) -> bool: return not _player_evidence(v).is_empty()),
			"can_recombine": not (meets.get(id, []) as Array).is_empty(),
			"can_surprise": not (rule.get("exceptions", []) as Array).is_empty(),
		}
	return out

# ---- structure ---------------------------------------------------------------------------------------------

static func _index(data: Dictionary) -> Dictionary:
	var subjects: Array = []
	for place in data.get("places", {}).values():
		for subject in place.get("subjects", {}).keys():
			if subject not in subjects:
				subjects.append(subject)
	var interpretations: Dictionary = {}
	for rule in data.get("interpretations", []):
		interpretations[str(rule.get("id", ""))] = rule
	var conventions: Dictionary = {}
	for convention in data.get("conventions", []):
		conventions[str(convention.get("id", ""))] = convention
	return {"subjects": subjects, "interpretations": interpretations, "conventions": conventions, "kinds": data.get("event_kinds", {}).keys(), "holders": data.get("holders", {}).keys()}

static func _structure(data: Dictionary, index: Dictionary, options: Dictionary, findings: Array) -> void:
	var table: Dictionary = options.get("table", {})
	var allowed_tokens: Array = MindsTemplate.VARIABLES + ["convention"]
	var ops: Array = data.get("reaction_ops", [])
	for rule in data.get("interpretations", []):
		var id := str(rule.get("id", ""))
		for kind in _as_list(rule.get("event_kind", "*")):
			if kind != "*" and kind not in index["kinds"]:
				findings.append(_finding(0, "error", id, "unknown_event_kind", "interpretation reads event kind %s, which minds.json does not define" % kind))
		for holder in _as_list(rule.get("holder", "*")):
			if holder != "*" and holder not in index["holders"]:
				findings.append(_finding(0, "error", id, "unknown_holder", "interpretation is for holder %s, who is not in minds.json" % holder))
		_check_tokens(rule, id, allowed_tokens, findings)
		_check_model_effects(rule, id, findings)
		_check_reaction_ops(rule, id, ops, findings)
		_check_text(rule, id, table, findings)
	for rule in data.get("rules", []):
		var rule_id := str(rule.get("id", ""))
		if str(rule.get("label_key", "")).is_empty():
			findings.append(_finding(0, "error", rule_id, "missing_label", "a world rule needs a label_key"))
		_check_text(rule, rule_id, table, findings)
		for variant in _triggerables(rule):
			var id := str(variant.get("id", ""))
			var trigger: Dictionary = variant.get("trigger", {})
			for kind in _as_list(trigger.get("event_kind", [])):
				if kind != "*" and kind not in index["kinds"]:
					findings.append(_finding(0, "error", id, "unknown_event_kind", "trigger waits for event kind %s, which minds.json does not define" % kind))
			for subject in _as_list(trigger.get("subject", [])) + _as_list(trigger.get("subject_not", [])):
				if subject != "*" and subject not in index["subjects"]:
					findings.append(_finding(0, "error", id, "unknown_subject", "trigger names subject %s, which no place in minds.json has" % subject))
			for field in ["witnessed_by", "unwitnessed_by", "seen_by", "unseen_by"]:
				if trigger.has(field) and str(trigger[field]) not in index["holders"]:
					findings.append(_finding(0, "error", id, "unknown_holder", "trigger %s names %s, who is not in minds.json" % [field, trigger[field]]))
			for holder in variant.get("evidence", {}).get("holders", []):
				if str(holder) not in index["holders"]:
					findings.append(_finding(0, "error", id, "unknown_holder", "evidence is for %s, who is not in minds.json" % holder))
			for convention_id in _convention_refs(variant):
				if not index["conventions"].has(convention_id):
					findings.append(_finding(0, "error", id, "unknown_convention", "refers to convention %s, which conventions.json does not define" % convention_id))
			for spec in _schedules(variant):
				var kind := str(spec.get("event", {}).get("kind", ""))
				if kind not in index["kinds"]:
					findings.append(_finding(0, "error", id, "unknown_event_kind", "schedules event kind %s, which minds.json does not define" % kind))
				var subject := str(spec.get("event", {}).get("subject", ""))
				if not subject.is_empty() and not subject.begins_with("$") and subject not in index["subjects"]:
					findings.append(_finding(0, "error", id, "unknown_subject", "schedules an event on %s, which no place in minds.json has" % subject))
			_check_tokens(variant, id, allowed_tokens, findings)
			_check_model_effects(variant, id, findings)
			_check_reaction_ops(variant, id, ops, findings)
	for community_id in data.get("communities", {}).keys():
		for member in data["communities"][community_id].get("members", []):
			if member not in index["holders"]:
				findings.append(_finding(0, "error", str(community_id), "unknown_holder", "community member %s is not in minds.json" % member))

static func _check_tokens(node: Variant, id: String, allowed: Array, findings: Array) -> void:
	for token in MindsTemplate.tokens(node):
		if token not in allowed and not str(token).begins_with("data_"):
			findings.append(_finding(0, "error", id, "unknown_template_token", "$%s is not a variable a template can use (%s, data_<key>)" % [token, ", ".join(allowed)]))

static func _check_model_effects(node: Variant, id: String, findings: Array) -> void:
	for effect in _model_effects(node):
		if str(effect.get("type", "")) not in MODEL_EFFECTS:
			findings.append(_finding(0, "error", id, "unknown_model_effect", "model effect type '%s' is not one of %s" % [effect.get("type", ""), ", ".join(MODEL_EFFECTS)]))

static func _check_reaction_ops(node: Variant, id: String, ops: Array, findings: Array) -> void:
	if ops.is_empty():
		return
	for reaction in _collect(node, "reactions"):
		for entry in reaction:
			if str(entry.get("op", "")) not in ops:
				findings.append(_finding(0, "error", id, "unknown_reaction_op", "reaction op %s is not in reaction_ops" % entry.get("op", "")))

static func _check_text(node: Variant, id: String, table: Dictionary, findings: Array) -> void:
	if table.is_empty():
		return
	for key in text_keys(node):
		if not table.has(key):
			findings.append(_finding(0, "error", id, "missing_text", "text key %s is not in data/text/ru.json" % key))

# ---- law 1 ---------------------------------------------------------------------------------------------------

static func _law_one(rule: Dictionary, data: Dictionary, index: Dictionary, findings: Array) -> void:
	var id := str(rule.get("id", ""))
	var invariant: Dictionary = rule.get("invariant", {})
	if invariant.is_empty() or str(invariant.get("relation", "")).is_empty() or (invariant.get("roles", []) as Array).is_empty():
		findings.append(_finding(1, "error", id, "no_invariant", "a world rule must declare its invariant: {relation, polarity, roles, constraints}. Without one there is nothing for the surface variants to stay faithful to."))
		return
	var polarity := str(invariant.get("polarity", ""))
	if polarity not in ["+", "-"]:
		findings.append(_finding(1, "error", id, "bad_polarity", "invariant polarity must be '+' or '-', not '%s'" % polarity))
	var constraints: Dictionary = invariant.get("constraints", {})
	for name in constraints.keys():
		if str(name) not in CONSTRAINTS:
			findings.append(_finding(1, "error", id, "unknown_constraint", "invariant constraint '%s' is not one of %s" % [name, ", ".join(CONSTRAINTS)]))
	for variant in rule.get("variants", []):
		var variant_id := str(variant.get("id", ""))
		var relation: Dictionary = variant.get("relation", {})
		if str(relation.get("id", "")) != str(invariant["relation"]):
			findings.append(_finding(1, "error", variant_id, "variant_relation_mismatch", "this variant instantiates relation '%s' but rule %s is about '%s'. A surface may change; the relationship may not." % [relation.get("id", ""), id, invariant["relation"]]))
		if str(relation.get("polarity", "")) != polarity:
			findings.append(_finding(1, "error", variant_id, "polarity_flip", "this variant has polarity '%s' where the invariant of %s has '%s': it reverses the relationship instead of re-skinning it" % [relation.get("polarity", ""), id, polarity]))
		for role in invariant.get("roles", []):
			if not relation.get("bindings", {}).has(role):
				findings.append(_finding(1, "error", variant_id, "unbound_role", "role '%s' of %s is not bound by this variant" % [role, id]))
		for problem in _constraint_problems(variant, constraints):
			findings.append(_finding(1, "error", variant_id, "constraint_violation", "violates the invariant of %s: %s" % [id, problem]))
		for convention_id in variant.get("conventions", {}).keys():
			var altered := MindsRules.new(data).patched(variant, [convention_id])
			for problem in _constraint_problems(altered, constraints):
				findings.append(_finding(1, "error", variant_id, "convention_patch_breaks_invariant", "when convention %s is in force this variant %s. Folklore may alter what a rule does, not what it is." % [convention_id, problem]))
	for exception in rule.get("exceptions", []):
		var exception_id := str(exception.get("id", ""))
		if str(exception.get("polarity", "")) != polarity:
			findings.append(_finding(1, "error", exception_id, "exception_flips_polarity", "an exception may narrow the scope of %s, not reverse it (polarity '%s' vs '%s')" % [id, exception.get("polarity", ""), polarity]))
		if str(exception.get("scope", "")).is_empty():
			findings.append(_finding(1, "error", exception_id, "exception_without_scope", "an exception must say what it narrows: give it a `scope`"))

static func _constraint_problems(variant: Dictionary, constraints: Dictionary) -> Array:
	var problems: Array = []
	var trigger: Dictionary = variant.get("trigger", {})
	for spec in _schedules(variant):
		var delay := int(spec.get("delay", 0))
		if constraints.has("delay_min") and delay < int(constraints["delay_min"]):
			problems.append("schedules a consequence after %d tick(s), under delay_min %d" % [delay, int(constraints["delay_min"])])
		if constraints.has("delay_max") and delay > int(constraints["delay_max"]):
			problems.append("schedules a consequence after %d tick(s), over delay_max %d" % [delay, int(constraints["delay_max"])])
		if bool(constraints.get("same_reaction", false)):
			var copied := str(spec.get("event", {}).get("data", {}).get("reaction", ""))
			if copied != "$reaction":
				problems.append("answers with reaction '%s' instead of copying the move that was made ($reaction): not 'in kind'" % copied)
		if bool(constraints.get("different_subject", false)) and str(spec.get("event", {}).get("subject", "")) == str(trigger.get("subject", "")):
			problems.append("answers on the very thing that was touched")
	if bool(constraints.get("needs_convention", false)) and _convention_refs(variant, true).is_empty():
		problems.append("does not depend on any convention (requires_convention / convention_change), though the invariant says it needs one")
	return problems

# ---- law 2 ---------------------------------------------------------------------------------------------------

static func _law_two(rule: Dictionary, settings: Dictionary, findings: Array) -> void:
	var id := str(rule.get("id", ""))
	var shown: Array = manifestations(rule)
	var needed := int(settings["major_manifestations"]) if bool(rule.get("major", false)) else int(settings["min_manifestations"])
	var sources: Array = []
	var domains: Array = []
	var forms: Array = []
	var seen_keys: Array = []
	for variant in shown:
		var variant_id := str(variant.get("id", ""))
		if str(variant.get("domain", "")) not in DOMAINS:
			findings.append(_finding(2, "error", variant_id, "unknown_domain", "domain '%s' is not one of %s" % [variant.get("domain", ""), ", ".join(DOMAINS)]))
		if str(variant.get("form", "")) not in FORMS:
			findings.append(_finding(2, "error", variant_id, "unknown_form", "evidence form '%s' is not one of %s" % [variant.get("form", ""), ", ".join(FORMS)]))
		var key := "%s|%s|%s" % [variant.get("domain", ""), variant.get("source", ""), JSON.stringify(variant.get("trigger", {}).get("subject", ""))]
		if key in seen_keys:
			findings.append(_finding(2, "warning", variant_id, "duplicate_manifestation", "same domain, source and subject as another variant of %s: not an independent manifestation" % id))
		seen_keys.append(key)
		if variant.get("source", "") not in sources:
			sources.append(variant.get("source", ""))
		if variant.get("domain", "") not in domains:
			domains.append(variant.get("domain", ""))
		if variant.get("form", "") not in forms:
			forms.append(variant.get("form", ""))
		if _player_evidence(variant).is_empty():
			findings.append(_finding(2, "error", variant_id, "no_player_evidence", "seeing this manifestation teaches the witch nothing: give `evidence` at least one knowledge or model effect for 'player'. A rule she cannot observe is a rule she cannot learn."))
	if sources.size() < needed:
		findings.append(_finding(2, "error", id, "too_few_manifestations", "%d independent manifestation(s) (distinct sources: %s); %s needs %d. Add another prop, character or situation that shows the same relation." % [sources.size(), ", ".join(sources), "a major rule" if bool(rule.get("major", false)) else "a rule", needed]))
	if domains.size() < int(settings["min_domains"]):
		findings.append(_finding(2, "error", id, "too_few_domains", "all manifestations are in domain %s; show the rule in at least %d different domains (physical, social, epistemic...) so it cannot be mistaken for one puzzle's trick" % [", ".join(domains), int(settings["min_domains"])]))
	if forms.size() < 2 and shown.size() >= 2:
		findings.append(_finding(2, "warning", id, "single_form_of_evidence", "every manifestation is '%s' evidence; mix direct, social, historical, counter and predictive evidence" % ", ".join(forms)))

# ---- law 3 ---------------------------------------------------------------------------------------------------

static func _law_three(rule: Dictionary, data: Dictionary, options: Dictionary, findings: Array) -> void:
	var id := str(rule.get("id", ""))
	var revision: Dictionary = rule.get("revision", {})
	if revision.is_empty():
		findings.append(_finding(3, "error", id, "no_revision_path", "a learnable rule needs a `revision`: {model, deeper_model, exception, teaches}. When the witch is wrong the world must show her a deeper rule, not just fail her."))
		return
	var model := str(revision.get("model", ""))
	var deeper := str(revision.get("deeper_model", ""))
	if model.is_empty() or deeper.is_empty() or model == deeper:
		findings.append(_finding(3, "error", id, "bad_revision", "revision must name the model the witch forms and a different, deeper one"))
		return
	var exception_id := str(revision.get("exception", ""))
	var exception: Dictionary = {}
	for candidate in rule.get("exceptions", []):
		if str(candidate.get("id", "")) == exception_id:
			exception = candidate
	if exception.is_empty():
		findings.append(_finding(3, "error", id, "unknown_exception", "revision.exception '%s' is not one of this rule's exceptions" % exception_id))
	elif str(exception.get("teaches", {}).get("key", "")).is_empty():
		findings.append(_finding(3, "error", exception_id, "exception_teaches_nothing", "every exception should teach something (`teaches.key`): 'I thought X, actually Y', never 'this one just works differently'"))
	if str(revision.get("teaches", {}).get("key", "")).is_empty():
		findings.append(_finding(3, "error", id, "revision_not_explained", "revision.teaches.key is the sentence that says what the deeper rule is"))
	var formed := false
	var revised := false
	var contradicted := false
	for effect in _model_effects(rule):
		var type := str(effect.get("type", ""))
		if str(effect.get("rule_id", "")) == model and type in ["ensure", "upsert", "support"]:
			formed = true
		if type == "revise" and str(effect.get("old_rule_id", "")) == model and str(effect.get("new_rule_id", "")) == deeper:
			revised = true
		if type == "contradict" and str(effect.get("rule_id", "")) == model:
			contradicted = true
	for interpretation in data.get("interpretations", []):
		for effect in _model_effects(interpretation):
			if str(effect.get("rule_id", "")) == model and str(effect.get("type", "")) in ["ensure", "upsert", "support"]:
				formed = true
	if not formed:
		findings.append(_finding(3, "error", id, "model_never_formed", "nothing in the data ever gives the witch model %s, so there is nothing to revise" % model))
	if not revised:
		findings.append(_finding(3, "error", id, "revision_unreachable", "no effect revises %s into %s. The exception must carry a `revise` model effect." % [model, deeper]))
	if contradicted and not revised:
		findings.append(_finding(3, "error", id, "punishing_contradiction", "model %s is contradicted without being revised: it punishes the witch's reasoning instead of refining it" % model))

# ---- law 4 ---------------------------------------------------------------------------------------------------

static func _law_four(convention: Dictionary, data: Dictionary, index: Dictionary, options: Dictionary, findings: Array) -> void:
	var id := str(convention.get("id", ""))
	var origin: Dictionary = convention.get("origin", {})
	var kinds: Array = origin.get("event_kinds", [])
	var fed_by: Array = origin.get("fed_by", [])
	if kinds.is_empty() or fed_by.is_empty():
		findings.append(_finding(4, "error", id, "no_origin", "a convention must declare where it comes from: origin.event_kinds (what happens) and origin.fed_by (the interpretation rules that read it so). A custom with no origin is a gimmick."))
	for kind in kinds:
		if kind not in index["kinds"]:
			findings.append(_finding(4, "error", id, "origin_event_kind_unknown", "origin names event kind %s, which minds.json does not define" % kind))
	var community: Dictionary = data.get("communities", {}).get(str(convention.get("community", "")), {})
	if community.is_empty():
		findings.append(_finding(4, "error", id, "unknown_community", "community '%s' is not in minds.json" % convention.get("community", "")))
	var members: Array = community.get("members", [])
	var reads := str(convention.get("reads", ""))
	var feeders: Array = []
	for fed_id in fed_by:
		var interpretation: Dictionary = index["interpretations"].get(str(fed_id), {})
		if interpretation.is_empty():
			findings.append(_finding(4, "error", id, "fed_by_unknown", "origin.fed_by names interpretation %s, which does not exist" % fed_id))
		elif str(interpretation.get("reads", "")) != reads:
			findings.append(_finding(4, "error", id, "fed_by_mismatch", "interpretation %s reads '%s', not '%s': it cannot feed this convention" % [fed_id, interpretation.get("reads", ""), reads]))
		else:
			feeders.append(interpretation)
	var feeding_holders: Array = []
	for interpretation in feeders:
		for holder in _as_list(interpretation.get("holder", "*")):
			if holder in members and holder not in feeding_holders:
				feeding_holders.append(holder)
	var adopt: Dictionary = convention.get("adopt", {})
	var threshold := int(adopt.get("threshold", 0))
	var min_holders := int(adopt.get("min_holders", 0))
	if threshold < 1 or min_holders < 1:
		findings.append(_finding(4, "error", id, "unbounded_adoption", "adopt.threshold and adopt.min_holders must both be at least 1"))
	if min_holders > members.size():
		findings.append(_finding(4, "error", id, "unreachable_adoption", "needs %d holders but its community has %d" % [min_holders, members.size()]))
	if not bool(convention.get("counterexample", false)) and not feeders.is_empty() and min_holders > feeding_holders.size() and not feeding_holders.is_empty():
		findings.append(_finding(4, "warning", id, "feeders_cover_fewer_holders", "origin.fed_by interpretations name %d holder(s) but min_holders is %d: it can only form if other rules also read '%s'" % [feeding_holders.size(), min_holders, reads]))
	if int(convention.get("cap", 0)) < threshold:
		findings.append(_finding(4, "error", id, "unbounded_tally", "`cap` must be set and at least the adoption threshold, so the tally is bounded and adoption is reachable"))
	var decay: Dictionary = convention.get("decay", {})
	if int(decay.get("every", 0)) <= 0 and not bool(convention.get("permanent", false)):
		findings.append(_finding(4, "error", id, "never_decays", "a convention nobody feeds must fade: give `decay` {every, amount}, or mark it `permanent` on purpose"))
	for operator_id in convention.get("force", {}).get("enables_operators", []):
		var engine: MirrorEngine = options.get("engine", null)
		if engine != null and not engine.operator_definitions.has(str(operator_id)):
			findings.append(_finding(4, "error", id, "unknown_operator", "force.enables_operators names %s, which the engine catalog does not define" % operator_id))
	if not _has_force(convention, data):
		findings.append(_finding(4, "error", id, "no_causal_force", "this convention does nothing: give it force.bias, force.enables_operators, or let a world-rule variant depend on it (requires_convention, convention_change, or a patch). A convention is meant to be a causal force."))
	var table: Dictionary = options.get("table", {})
	if str(convention.get("label_key", "")).is_empty():
		findings.append(_finding(4, "error", id, "missing_label", "a convention needs a label_key"))
	_check_text(convention, id, table, findings)

static func _has_force(convention: Dictionary, data: Dictionary) -> bool:
	var force: Dictionary = convention.get("force", {})
	if int(force.get("bias", 0)) > 0 or not (force.get("enables_operators", []) as Array).is_empty():
		return true
	var id := str(convention.get("id", ""))
	for rule in data.get("rules", []):
		for variant in _triggerables(rule):
			if id in _convention_refs(variant):
				return true
	return false

# ---- helpers -------------------------------------------------------------------------------------------------

static func _finding(law: int, severity: String, subject: String, code: String, message: String) -> Dictionary:
	return {"law": law, "severity": severity, "subject": subject, "code": code, "message": message}

static func _as_list(value: Variant) -> Array:
	if value is Array:
		return value
	return [value]

# Variants plus the exceptions that fire on their own: everything a trigger can start.
static func _triggerables(rule: Dictionary) -> Array:
	var out: Array = []
	out.append_array(rule.get("variants", []))
	for exception in rule.get("exceptions", []):
		if exception.has("trigger"):
			out.append(exception)
	return out

# What the player can be shown: a rule's variants, plus its exceptions that fire in the world.
static func manifestations(rule: Dictionary) -> Array:
	return _triggerables(rule).filter(func(v: Dictionary) -> bool: return not bool(v.get("flavor", false)))

static func _schedules(variant: Dictionary) -> Array:
	return variant.get("transformation", {}).get("schedule", [])

# Convention ids a variant depends on. `strict` looks only at its trigger and keeps the wildcard "*"
# ("whenever any convention changes"); otherwise patches count too and the wildcard does not.
static func _convention_refs(variant: Dictionary, strict: bool = false) -> Array:
	var out: Array = []
	var trigger: Dictionary = variant.get("trigger", {})
	if trigger.has("requires_convention"):
		out.append(str(trigger["requires_convention"]))
	if trigger.has("convention_change"):
		for convention_id in _as_list(trigger["convention_change"].get("id", "*")):
			if strict or str(convention_id) != "*":
				out.append(str(convention_id))
	if not strict:
		out.append_array(variant.get("conventions", {}).keys())
	return out

# Evidence a variant gives the witch: effects for a holder list that includes the player.
static func _player_evidence(variant: Dictionary) -> Array:
	var evidence: Dictionary = variant.get("evidence", {})
	if "player" not in evidence.get("holders", ["player"]):
		return []
	var out: Array = []
	out.append_array(evidence.get("knowledge_effects", []))
	out.append_array(evidence.get("model_effects", []))
	return out

# Every model effect anywhere inside a structure (evidence, on_replace, interpretation effects).
static func _model_effects(node: Variant) -> Array:
	var out: Array = []
	for list in _collect(node, "model_effects"):
		for effect in list:
			out.append(effect)
	return out

# Every value stored under `field` anywhere inside a structure.
static func _collect(node: Variant, field: String) -> Array:
	var out: Array = []
	if node is Dictionary:
		for key in node.keys():
			if str(key) == field and node[key] is Array:
				out.append(node[key])
			out.append_array(_collect(node[key], field))
	elif node is Array:
		for item in node:
			out.append_array(_collect(item, field))
	return out

# Every text key a structure refers to (`label_key` and `key` fields).
static func text_keys(node: Variant) -> Array:
	var out: Array = []
	if node is Dictionary:
		for key in node.keys():
			if (str(key) == "label_key" or str(key) == "key") and node[key] is String and not (node[key] as String).is_empty():
				out.append(node[key])
			else:
				out.append_array(text_keys(node[key]))
	elif node is Array:
		for item in node:
			out.append_array(text_keys(item))
	return out
