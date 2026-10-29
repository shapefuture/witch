class_name AlivenessLint
extends RefCounted

# The aliveness rules (docs/design/ALIVENESS.md section 4) checked over the authored catalog, and the section 5
# metrics measured by replaying the deterministic sims. Same shape as FourLawsLinter: findings carry
# {severity, rule, object, code, message}; errors fail tests/mirror/test_aliveness.gd.
#
# It reads the raw JSON of data/mirror (never writes it) plus a sidecar, data/aliveness/, that sits outside the
# catalog fingerprint: rules.json (which objects are important, the ratchet of known gaps) and classes.json (the
# discovery class of each authored hypothesis and reveal). A rule an object does not meet yet is a warning only
# while rules.json lists it as a known gap; every other failure is an error, and so is a gap that has closed.
#
# Rules (codes):
#   answers         every tappable object answers: a visible action with a response, or a poke a mind reads
#   action_answers  every visible action has at least one response contract
#   linked          every entity has an authored edge to another (rule role, hypothesis evidence, prerequisite)
#   gated_option    an important object offers an option gated on what the witch knows
#   gated_rewrite   an important object's option is rewritten by knowledge (one option gives way to another)
#   class_*         the discovery-class sidecar names real entries and real classes; hypotheses are classed

const MIRROR_DIR := "res://data/mirror"
const SIDECAR_DIR := "res://data/aliveness"
const PLAYER := "player"

# ---- loading ------------------------------------------------------------------------------------------------

static func load_catalog(mirror_dir: String = MIRROR_DIR, areas: bool = false) -> Dictionary:
	var actions: Array = []
	var actions_dir := mirror_dir.path_join("actions")
	var files := Array(DirAccess.get_files_at(actions_dir))
	files.sort()
	for file_name: String in files:
		if file_name.ends_with(".json"):
			actions.append_array(_read(actions_dir.path_join(file_name), []))
	# The area packages (docs/engine/CONTENT_PACKAGES.md), merged the way the loaders merge them; a duplicate is the
	# loaders' error to report, so it is ignored here.
	var areas_dir := mirror_dir.path_join(ContentFiles.AREAS) if areas else ""
	for path in ContentFiles.area_paths(areas_dir, "actions"):
		actions.append_array(_read(path, []))
	var hypotheses: Array = _read(mirror_dir.path_join("hypotheses.json"), [])
	for path in ContentFiles.area_paths(areas_dir, "hypotheses"):
		hypotheses.append_array(_read(path, []))
	var minds_dir := mirror_dir.path_join("minds")
	var raw: Dictionary = (_read(minds_dir.path_join("minds.json"), {}) as Dictionary).duplicate(true)
	raw["rules"] = _read(minds_dir.path_join("world_rules.json"), [])
	raw["interpretations"] = _read(minds_dir.path_join("interpretations.json"), [])
	raw["conventions"] = _read(minds_dir.path_join("conventions.json"), [])
	MindsCatalog.merge_areas(raw, areas_dir, [])
	var lists := {}
	for key in ["rules", "interpretations", "conventions"]:
		lists[key] = raw[key]
		raw.erase(key)
	return {
		"actions": actions,
		"hypotheses": hypotheses,
		"minds": {
			"world": raw,
			"rules": lists["rules"],
			"interpretations": lists["interpretations"],
			"conventions": lists["conventions"],
		},
	}

static func load_sidecar(dir: String = SIDECAR_DIR) -> Dictionary:
	return {"rules": _read(dir.path_join("rules.json"), {}), "classes": _read(dir.path_join("classes.json"), {})}

static func _read(path: String, fallback: Variant) -> Variant:
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("AlivenessLint: cannot read %s" % path)
		return fallback
	if typeof(json.data) != typeof(fallback):
		push_error("AlivenessLint: %s has the wrong shape" % path)
		return fallback
	return json.data

# ---- entities -----------------------------------------------------------------------------------------------

static func visible_actions(catalog: Dictionary) -> Array:
	return catalog.get("actions", []).filter(func(a: Dictionary) -> bool: return not bool(a.get("hidden", false)))

# The things the witch can tap: targets of visible actions, and the props of every minds place.
static func tappables(catalog: Dictionary) -> Array:
	var out: Array = []
	for action: Dictionary in visible_actions(catalog):
		for target in action.get("valid_targets", []):
			if str(target) not in out:
				out.append(str(target))
	for subject in prop_subjects(catalog):
		if subject not in out:
			out.append(subject)
	out.sort()
	return out

static func prop_subjects(catalog: Dictionary) -> Array:
	var out: Array = []
	var places: Dictionary = catalog.get("minds", {}).get("world", {}).get("places", {})
	for place in places.keys():
		for subject in places[place].get("subjects", {}).keys():
			if str(subject) not in out:
				out.append(str(subject))
	out.sort()
	return out

# Tappables plus every mind but the witch's own, plus whatever a hypothesis is about.
static func entities(catalog: Dictionary) -> Array:
	var out := tappables(catalog)
	for holder in catalog.get("minds", {}).get("world", {}).get("holders", {}).keys():
		if str(holder) != PLAYER and str(holder) not in out:
			out.append(str(holder))
	for hypothesis: Dictionary in catalog.get("hypotheses", []):
		var about := str(hypothesis.get("rule", {}).get("about", ""))
		if not about.is_empty() and about not in out:
			out.append(about)
	out.sort()
	return out

static func default_room(catalog: Dictionary) -> String:
	return str(catalog.get("minds", {}).get("world", {}).get("default_place", "clearing"))

# ---- links --------------------------------------------------------------------------------------------------

# Authored edges between entities, undirected and deduplicated: [{a, b, kind, via}] with a < b.
static func links(catalog: Dictionary) -> Array:
	var known := entities(catalog)
	var props := prop_subjects(catalog)
	var edges: Dictionary = {}
	var producers := _producers(catalog)
	# Option prerequisites: a gate (claim, model or state) on one object that another object's options settle.
	for action: Dictionary in visible_actions(catalog):
		var targets: Array = action.get("valid_targets", [])
		var gated: Array = []
		var keys: Array = []
		_collect_gate(action, gated)
		_state_keys(action.get("preconditions", {}), keys)
		for response: Dictionary in action.get("response_contracts", []):
			_collect_gate(response, gated)
			_state_keys(response.get("when", {}), keys)
			for section in ["world", "npc_state"]:
				for key in response.get("effects", {}).get(section, {}).keys():
					keys.append(str(key))
		for target in targets:
			for id in gated:
				for source in producers.get(id, []):
					_edge(edges, known, str(target), str(source), "prerequisite", "%s needs %s" % [action["id"], id])
			for key in keys:
				_edge(edges, known, str(target), str(key), "prerequisite", "%s reads or writes %s" % [action["id"], key])
	# Hypothesis evidence: what each piece of evidence comes from is linked to what the hypothesis is about.
	for hypothesis: Dictionary in catalog.get("hypotheses", []):
		var about := str(hypothesis.get("rule", {}).get("about", ""))
		var ends: Array = []
		for requirement in hypothesis.get("requires_evidence", []) + hypothesis.get("requires_models", []):
			ends.append_array(producers.get(str(requirement.get("id", "")), []))
		for experiment: Dictionary in hypothesis.get("experiments", []):
			ends.append(str(experiment.get("target_id", "")))
		for end in ends:
			_edge(edges, known, about, str(end), "hypothesis", str(hypothesis.get("id", "")))
	# Rule roles: everything a world-rule variant binds or names; a "$subject" role stands for every prop.
	for rule: Dictionary in catalog.get("minds", {}).get("rules", []):
		for variant: Dictionary in rule.get("variants", []) + rule.get("exceptions", []):
			var concrete: Array = []
			var wildcard := false
			var trigger: Dictionary = variant.get("trigger", {})
			var named: Array = [variant.get("source", "")]
			named.append_array(variant.get("relation", {}).get("bindings", {}).values())
			for field in ["subject", "actor", "seen_by", "witnessed_by", "unseen_by"]:
				named.append(trigger.get(field, ""))
			for value in named:
				var text := str(value)
				if text.begins_with("$"):
					wildcard = true
				elif text in known and text not in concrete:
					concrete.append(text)
			if not trigger.has("subject") and trigger.has("event_kind"):
				wildcard = true
			if wildcard:
				for prop in props:
					if prop not in trigger.get("subject_not", []):
						concrete.append(prop)
			for i in concrete.size():
				for j in range(i + 1, concrete.size()):
					_edge(edges, known, concrete[i], concrete[j], "rule_role", str(variant.get("id", "")))
	for convention: Dictionary in catalog.get("minds", {}).get("conventions", []):
		var members: Array = catalog.get("minds", {}).get("world", {}).get("communities", {}).get(str(convention.get("community", "")), {}).get("members", [])
		for subject in convention.get("subjects", []):
			for member in members:
				_edge(edges, known, str(subject), str(member), "rule_role", str(convention.get("id", "")))
	for reading: Dictionary in catalog.get("minds", {}).get("interpretations", []):
		if reading.has("subject"):
			_edge(edges, known, str(reading["subject"]), str(reading.get("holder", "")), "rule_role", str(reading.get("id", "")))
	var out: Array = edges.values()
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return "%s|%s" % [x["a"], x["b"]] < "%s|%s" % [y["a"], y["b"]])
	return out

static func degree(edges: Array) -> Dictionary:
	var out: Dictionary = {}
	for edge: Dictionary in edges:
		out[edge["a"]] = int(out.get(edge["a"], 0)) + 1
		out[edge["b"]] = int(out.get(edge["b"], 0)) + 1
	return out

static func _edge(edges: Dictionary, known: Array, a: String, b: String, kind: String, via: String) -> void:
	if a == b or a not in known or b not in known:
		return
	var lo := a if a < b else b
	var hi := b if a < b else a
	var key := "%s|%s" % [lo, hi]
	if not edges.has(key):
		edges[key] = {"a": lo, "b": hi, "kind": kind, "via": via}

# claim or model id -> the objects whose actions settle it.
static func _producers(catalog: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for action: Dictionary in visible_actions(catalog):
		for response: Dictionary in action.get("response_contracts", []):
			var ids: Array = []
			for effect in response.get("knowledge_effects", []):
				ids.append(str(effect.get("id", "")))
			for effect in response.get("model_effects", []):
				ids.append(str(effect.get("new_rule_id", effect.get("rule_id", ""))))
			for id in ids:
				if not out.has(id):
					out[id] = []
				for target in action.get("valid_targets", []):
					if str(target) not in out[id]:
						out[id].append(str(target))
	return out

static func _collect_gate(holder: Dictionary, out: Array) -> void:
	for field in ["requires_claims", "requires_models"]:
		for requirement in holder.get(field, []):
			out.append(str(requirement.get("id", "")) if requirement is Dictionary else str(requirement))

# The entity a state path is about: "machine.state" -> machine, "npc.tomas.stance" -> tomas.
static func _state_keys(condition: Variant, out: Array) -> void:
	if condition is Array:
		for item in condition:
			_state_keys(item, out)
		return
	if not condition is Dictionary:
		return
	for key in condition.keys():
		var text := str(key)
		if text.begins_with("$"):
			_state_keys(condition[key], out)
			continue
		var parts := text.split(".")
		out.append(parts[1] if parts[0] == "npc" and parts.size() > 1 else parts[0])

# ---- the rules ----------------------------------------------------------------------------------------------

# Every failure as {rule, object, message}, before the ratchet decides its severity.
static func violations(catalog: Dictionary, sidecar: Dictionary) -> Array:
	var out: Array = []
	var actions := visible_actions(catalog)
	for target in tappables(catalog):
		if not _answers(catalog, actions, target):
			out.append(_v("answers", target, "nothing answers a tap on '%s': give it an action with a response, or a poke a mind reads" % target))
	for action: Dictionary in actions:
		if (action.get("response_contracts", []) as Array).is_empty() and not bool(action.get("allow_no_response", false)):
			out.append(_v("action_answers", str(action.get("id", "")), "action '%s' has no response contract" % action.get("id", "")))
	var deg := degree(links(catalog))
	for entity in entities(catalog):
		if int(deg.get(entity, 0)) == 0:
			out.append(_v("linked", entity, "'%s' is linked to nothing: tie it to another entity (a rule role, hypothesis evidence, an option prerequisite)" % entity))
	for important in sidecar.get("rules", {}).get("important", []):
		var mine := actions.filter(func(a: Dictionary) -> bool: return str(important) in a.get("valid_targets", []))
		if mine.is_empty() and str(important) not in prop_subjects(catalog):
			out.append(_v("important_exists", str(important), "rules.json names '%s' important, but nothing targets it" % important))
			continue
		if not _has_gated_option(mine):
			out.append(_v("gated_option", str(important), "'%s' is important but no option on it depends on what the witch knows" % important))
		if rewrites(mine).is_empty():
			out.append(_v("gated_rewrite", str(important), "'%s' is important but no option on it gives way to a knowledge-gated one" % important))
	out.append_array(_class_violations(catalog, sidecar))
	return out

static func _v(rule: String, object: String, message: String) -> Dictionary:
	return {"rule": rule, "object": object, "message": message}

static func _answers(catalog: Dictionary, actions: Array, target: String) -> bool:
	for action: Dictionary in actions:
		if target in action.get("valid_targets", []) and not (action.get("response_contracts", []) as Array).is_empty():
			return true
	if target not in prop_subjects(catalog):
		return false
	for reading: Dictionary in catalog.get("minds", {}).get("interpretations", []):
		var kinds: Variant = reading.get("event_kind", "")
		var pokes: bool = ("PROP_POKED" in kinds) if kinds is Array else str(kinds) == "PROP_POKED"
		if pokes and (not reading.has("subject") or str(reading["subject"]) == target):
			return true
	return false

static func _has_gated_option(actions: Array) -> bool:
	for action: Dictionary in actions:
		var gate: Array = []
		_collect_gate(action, gate)
		if not gate.is_empty():
			return true
	return false

# Pairs on one object where knowledge swaps one option for another of the same kind: [[from_id, to_id, claim]].
static func rewrites(actions: Array) -> Array:
	var out: Array = []
	for to: Dictionary in actions:
		var gate: Array = []
		_collect_gate(to, gate)
		for from: Dictionary in actions:
			if from == to or str(from.get("action_type", "")) != str(to.get("action_type", "")) or from.get("label_key") == to.get("label_key"):
				continue
			for requirement in from.get("excludes_claims", []):
				var id := str(requirement.get("id", "")) if requirement is Dictionary else str(requirement)
				if id in gate:
					out.append([str(from["id"]), str(to["id"]), id])
	return out

# The ratchet: listed gaps are warnings, everything else (and a gap that has closed) is an error.
static func lint(catalog: Dictionary, sidecar: Dictionary) -> Array:
	var gaps: Array = sidecar.get("rules", {}).get("known_gaps", [])
	var seen: Array = []
	var findings: Array = []
	for violation: Dictionary in violations(catalog, sidecar):
		var key := "%s:%s" % [violation["rule"], violation["object"]]
		var waived := key in gaps
		if waived:
			seen.append(key)
		findings.append({"severity": "warning" if waived else "error", "rule": violation["rule"], "object": violation["object"],
			"code": violation["rule"], "message": violation["message"]})
	for gap in gaps:
		if str(gap) not in seen:
			findings.append({"severity": "error", "rule": "known_gaps", "object": str(gap), "code": "gap_closed",
				"message": "'%s' now holds: delete it from data/aliveness/rules.json known_gaps so it cannot regress" % gap})
	return findings

static func errors(findings: Array) -> Array:
	return findings.filter(func(f: Dictionary) -> bool: return f["severity"] == "error")

static func warnings(findings: Array) -> Array:
	return findings.filter(func(f: Dictionary) -> bool: return f["severity"] == "warning")

static func format(findings: Array) -> String:
	var lines: Array[String] = []
	for finding: Dictionary in findings:
		lines.append("[%s] %s %s: %s" % [finding["severity"], finding["code"], finding["object"], finding["message"]])
	return "\n".join(lines)

# ---- discovery classes --------------------------------------------------------------------------------------

# Every authored hypothesis and reveal: {id: kind}. Reveals are the claims responses and world-rule evidence give
# the witch, the models a revision leads to, and the customs.
static func discoveries(catalog: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for hypothesis: Dictionary in catalog.get("hypotheses", []):
		out[str(hypothesis.get("id", ""))] = "hypothesis"
	var claims: Array = []
	for action: Dictionary in visible_actions(catalog):
		_knowledge_ids(action.get("response_contracts", []), claims)
	_knowledge_ids(catalog.get("minds", {}).get("rules", []), claims)
	for id in claims:
		out[id] = "claim"
	for action: Dictionary in visible_actions(catalog):
		for response: Dictionary in action.get("response_contracts", []):
			for effect in response.get("model_effects", []):
				if str(effect.get("type", "")) == "revise":
					out[str(effect.get("new_rule_id", ""))] = "model"
	for rule: Dictionary in catalog.get("minds", {}).get("rules", []):
		var deeper := str(rule.get("revision", {}).get("deeper_model", ""))
		if not deeper.is_empty():
			out[deeper] = "model"
	for convention: Dictionary in catalog.get("minds", {}).get("conventions", []):
		out[str(convention.get("id", ""))] = "custom"
	return out

static func _knowledge_ids(node: Variant, out: Array) -> void:
	if node is Array:
		for item in node:
			_knowledge_ids(item, out)
	elif node is Dictionary:
		for key in node.keys():
			if str(key) == "knowledge_effects" and node[key] is Array:
				for effect in node[key]:
					if effect is Dictionary and str(effect.get("holder_id", PLAYER)) == PLAYER and str(effect.get("id", "")) not in out:
						out.append(str(effect.get("id", "")))
			else:
				_knowledge_ids(node[key], out)

static func _class_violations(catalog: Dictionary, sidecar: Dictionary) -> Array:
	var out: Array = []
	var classes: Dictionary = sidecar.get("classes", {})
	var vocabulary: Array = classes.get("classes", [])
	var entries: Dictionary = classes.get("entries", {})
	var found := discoveries(catalog)
	for id in entries.keys():
		var klass := str(entries[id].get("class", "")) if entries[id] is Dictionary else ""
		if klass not in vocabulary:
			out.append(_v("class_known", str(id), "'%s' has class '%s', which is not one of %s" % [id, klass, JSON.stringify(vocabulary)]))
		if not found.has(str(id)):
			out.append(_v("class_target", str(id), "classes.json classes '%s', which no hypothesis or reveal in the catalog has" % id))
	for id in found.keys():
		if entries.has(id):
			continue
		var rule := "class_hypothesis" if found[id] == "hypothesis" else "class_reveal"
		out.append(_v(rule, str(id), "%s '%s' has no discovery class: add it to data/aliveness/classes.json" % [found[id], id]))
	return out

# room -> class -> [ids], every class of the vocabulary present (empty when the room has none).
static func classes_by_room(catalog: Dictionary, sidecar: Dictionary) -> Dictionary:
	var classes: Dictionary = sidecar.get("classes", {})
	var out: Dictionary = {}
	var found := discoveries(catalog)
	var ids: Array = classes.get("entries", {}).keys()
	ids.sort()
	for id in ids:
		if not found.has(id):
			continue
		var entry: Dictionary = classes["entries"][id]
		var room := str(entry.get("room", default_room(catalog)))
		if not out.has(room):
			out[room] = {}
			for klass in classes.get("classes", []):
				out[room][str(klass)] = []
		var klass := str(entry.get("class", ""))
		if out[room].has(klass):
			out[room][klass].append(id)
	return out

# ---- metrics (section 5) ------------------------------------------------------------------------------------

# Static measures of a room's catalog: possibility density over the authored responses, and link density.
static func catalog_metrics(catalog: Dictionary) -> Dictionary:
	var actions := visible_actions(catalog)
	var taps := tappables(catalog)
	var rich: Array = []
	for target in taps:
		var count := 0
		for action: Dictionary in actions:
			if target in action.get("valid_targets", []):
				count += (action.get("response_contracts", []) as Array).size()
		if count >= 2:
			rich.append(target)
	var edges := links(catalog)
	var known := entities(catalog)
	return {
		"tappables": taps.size(), "with_two_responses": rich, "possibility_density": rich.size(),
		"possibility_share": float(rich.size()) / maxf(1.0, taps.size()),
		"entities": known.size(), "links": edges.size(), "link_density": float(edges.size()) / maxf(1.0, known.size()),
	}

# Replays one sim script exactly as tests/sim does and measures every tap (an action or a poke; time passing and
# presence are not taps). A tap returns attention when it changes a claim (any holder), an option or its wording,
# a mind's reading (a model or a custom's tally) or the world (state, or a consequence scheduled or cancelled).
static func measure_sim(script: Dictionary, targets: Array) -> Dictionary:
	var runtime := MirrorRuntime.new()
	runtime.new_game()
	runtime.next_story()
	var taps := 0
	var returned := 0
	var dead: Array = []
	var retro: Array = []
	var tapped: Array = []
	var responses: Dictionary = {}
	var steps: Array = script.get("steps", [])
	for i in steps.size():
		var step: Dictionary = steps[i]
		var before := _snapshot(runtime, targets)
		var result: Dictionary = SimulationRunner.run_step(runtime, step)
		if step.has("advance") or step.has("presence"):
			continue
		var after := _snapshot(runtime, targets)
		var target := str(step.get("poke", step.get("target", step.get("event", {}).get("subject", ""))))
		taps += 1
		var changed: Array = []
		for part in ["claims", "options", "minds", "world"]:
			if JSON.stringify(before[part]) != JSON.stringify(after[part]):
				changed.append(part)
		if changed.is_empty():
			dead.append("%d:%s" % [i, target])
		else:
			returned += 1
		for other in targets:
			if other != target and other in tapped and JSON.stringify(before["options"].get(other, [])) != JSON.stringify(after["options"].get(other, [])):
				retro.append("%s->%s" % [target, other])
		if target not in tapped:
			tapped.append(target)
		if not responses.has(target):
			responses[target] = []
		var signature := _signature(step, result)
		if signature not in responses[target]:
			responses[target].append(signature)
	runtime.free()
	var rich: Array = responses.keys().filter(func(t: String) -> bool: return (responses[t] as Array).size() >= 2)
	rich.sort()
	return {
		"name": str(script.get("name", "")), "taps": taps, "returned": returned,
		"attention_return": float(returned) / maxf(1.0, taps), "dead_taps": dead, "retroactive": retro,
		"tapped": tapped.size(), "with_two_responses": rich,
	}

# Every sim in data/sim, plus the sums. Deterministic: same catalog, same numbers.
static func sim_metrics(paths: Array, targets: Array) -> Dictionary:
	var per: Dictionary = {}
	var taps := 0
	var returned := 0
	var dead := 0
	var retro := 0
	for path in paths:
		var measured := measure_sim(SimulationRunner.load_script(str(path)), targets)
		per[str(path).get_file().get_basename()] = measured
		taps += int(measured["taps"])
		returned += int(measured["returned"])
		dead += (measured["dead_taps"] as Array).size()
		retro += (measured["retroactive"] as Array).size()
	return {"sims": per, "taps": taps, "returned": returned, "attention_return": float(returned) / maxf(1.0, taps),
		"dead_taps": dead, "retroactive": retro}

static func _snapshot(runtime: MirrorRuntime, targets: Array) -> Dictionary:
	var claims: Dictionary = {}
	for claim: Dictionary in runtime.engine.knowledge.all():
		claims["%s::%s" % [claim.get("holder_id", PLAYER), claim.get("id", "")]] = int(claim.get("status", 0))
	var minds: Dictionary = {}
	for rule: Dictionary in runtime.engine.models.query_rules():
		minds["%s::%s" % [rule.get("observer_id", PLAYER), rule.get("id", "")]] = "%d %.2f" % [int(rule.get("status", 0)), float(rule.get("confidence", 0.0))]
	minds["conventions"] = runtime.minds.state.conventions.snapshot()
	var options: Dictionary = {}
	for target in targets:
		var listed: Array = []
		for option: InteractionOption in runtime.options_for(str(target)):
			listed.append("%s|%s" % [option.action_id, option.label_key])
		listed.sort()
		options[target] = listed
	var world: Dictionary = runtime.engine.world_state.duplicate(true)
	world.erase("__mirror_time")
	var pending: Array = runtime.minds.pending().map(func(c: Dictionary) -> String: return "%s@%d" % [c.get("id", ""), int(c.get("due", 0))])
	return {"claims": claims, "options": options, "minds": minds,
		"world": {"world": world, "npc": runtime.engine.npc_state.duplicate(true), "pending": pending}}

static func _signature(step: Dictionary, result: Dictionary) -> String:
	if SimulationRunner.is_minds_step(step):
		var summary := SimulationRunner.summarize_minds(step, result)
		return JSON.stringify({"reactions": summary.get("reactions", []), "reads": summary.get("reads", {})}, "", true)
	if not result.get("ok", false):
		return "refused"
	return str(result.get("response", {}).get("id", ""))
