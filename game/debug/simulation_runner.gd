class_name SimulationRunner
extends RefCounted

# Deterministic headless playthroughs. A script is a list of steps, each the same
# {action, target} an interactive choice would submit, resolved through the very same Mirror
# engine, so a sim is a faithful, repeatable regression of the real game logic.
#
#   godot --headless --path . -- --debug-sim data/sim/patient.json
#
# (See game_root.gd for the command-line hook.)
#
# A step is an authored action {action, target, context?}, or a happening in the minds layer:
#   {"event": {kind, actor, subject, data?, hints?}}   MirrorMinds.perceive (who sees it, what they make of it)
#   {"poke": "globe", "reaction": "hop", "hints"?}     shorthand for a PROP_POKED by the witch
#   {"advance": 3}                                     time passes: whatever fell due happens
#   {"presence": {"holder": "tomas", "place": "back_hall"}}

const SIM_DIR := "res://data/sim"

var lines: Array[String] = []

# Returns {"ok", "name", "results", "failed_step", "head_hash", "event_count", "expect_failures"}.
func run(runtime: MirrorRuntime, script: Dictionary, stop_after: int = -1) -> Dictionary:
	var results: Array[Dictionary] = []
	var failed_step := -1
	var steps: Array = script.get("steps", [])
	var limit := steps.size() if stop_after < 0 else mini(stop_after, steps.size())
	for i in range(limit):
		var step: Dictionary = steps[i]
		var result := run_step(runtime, step)
		results.append(result)
		if not result.get("ok", false):
			failed_step = i
			break
	var expect_failures: Array[String] = []
	if failed_step < 0 and limit == steps.size():
		expect_failures = check_expectations(runtime, script.get("expect", {}))
	return {
		"ok": failed_step < 0 and expect_failures.is_empty(),
		"name": str(script.get("name", "")),
		"results": results,
		"failed_step": failed_step,
		"head_hash": runtime.engine.event_store.head_hash(),
		"event_count": runtime.engine.event_store.size(),
		"expect_failures": expect_failures,
	}

static func is_minds_step(step: Dictionary) -> bool:
	return step.has("event") or step.has("poke") or step.has("advance") or step.has("presence")

# Runs one step through the very same Mirror engine an interactive choice would use.
static func run_step(runtime: MirrorRuntime, step: Dictionary) -> Dictionary:
	if step.has("event"):
		return runtime.minds.perceive(step["event"])
	if step.has("poke"):
		return runtime.minds.perceive({"kind": "PROP_POKED", "actor": "player", "subject": str(step["poke"]), "data": {"reaction": str(step.get("reaction", "wobble"))}, "hints": step.get("hints", {})})
	if step.has("advance"):
		return runtime.minds.advance_time(int(step["advance"]), "sim")
	if step.has("presence"):
		return runtime.minds.set_presence(str(step["presence"].get("holder", "")), str(step["presence"].get("place", "")))
	return runtime.resolve_now(runtime.make_action(str(step.get("action", "")), str(step.get("target", "")), step.get("context", {})))

# A compact, stable summary of a minds step's result, for transcripts and goldens.
static func summarize_minds(step: Dictionary, result: Dictionary) -> Dictionary:
	var kind := "advance" if step.has("advance") else ("presence" if step.has("presence") else "event")
	var entry: Dictionary = {"minds": kind, "ok": result.get("ok", false)}
	if not result.get("ok", false):
		return entry
	if kind == "advance":
		entry["time"] = int(result.get("time", 0))
		var fired: Array = []
		for item in result.get("fired", []):
			fired.append(_summarize_event(item))
		entry["fired"] = fired
	elif kind == "event":
		entry.merge(_summarize_event(result), true)
	return entry

static func _summarize_event(result: Dictionary) -> Dictionary:
	var reads: Dictionary = {}
	var misread: Array = []
	for reading in result.get("interpretations", []):
		reads[reading["holder"]] = reading["reads"]
		if reading["misread"]:
			misread.append(reading["holder"])
	var reactions: Array = []
	for reaction in result.get("reactions", []):
		reactions.append("%s %s>%s" % [reaction.get("op", ""), reaction.get("actor", reaction.get("reaction", "")), reaction.get("target", reaction.get("key", ""))])
	var changes: Array = []
	for change in result.get("convention_changes", []):
		changes.append("%s %s" % [change["id"], change["change"]])
	return {
		"kind": result.get("kind", ""), "subject": result.get("subject", ""), "time": int(result.get("time", 0)),
		"witnesses": result.get("witnesses", []), "unaware": result.get("unaware", []), "reads": reads, "misread": misread,
		"reactions": reactions, "scheduled": result.get("scheduled", []), "cancelled": result.get("cancelled", []),
		"dropped": result.get("dropped", []), "conventions": changes, "recorded": result.get("recorded", true),
	}

# expect: {"state": <condition matched against the world/npc snapshot>, "knows": [claim ids],
#          "model_status": {rule_id: "REVISED"}, "operators": [ids],
#          minds: "pending": n, "conventions": [active ids], "not_conventions": [ids],
#                 "holders_know": {holder: [claim ids]}, "holders_not_know": {holder: [claim ids]},
#                 "holder_models": {holder: {rule_id: "SUPPORTED"}}}
func check_expectations(runtime: MirrorRuntime, expect: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	if expect.has("state") and not MirrorConditions.matches(expect["state"], runtime.context_snapshot()):
		failures.append("state expectation not met: %s" % JSON.stringify(MirrorConditions.explain_failures(expect["state"], runtime.context_snapshot())))
	for claim_id in expect.get("knows", []):
		if not runtime.engine.knowledge.has(str(claim_id)):
			failures.append("expected the witch to know '%s'" % claim_id)
	for rule_id in expect.get("model_status", {}).keys():
		var wanted := int(MirrorDomain.ModelStatus.get(str(expect["model_status"][rule_id]), -1))
		var found := false
		for rule in runtime.engine.models.query_rules("", "", "player"):
			if str(rule["id"]) == str(rule_id) and int(rule["status"]) == wanted:
				found = true
		if not found:
			failures.append("expected model %s to be %s" % [rule_id, expect["model_status"][rule_id]])
	for operator_id in expect.get("operators", []):
		if not runtime.engine.operators.has(str(operator_id)):
			failures.append("expected operator '%s'" % operator_id)
	if expect.has("pending") and runtime.minds.pending().size() != int(expect["pending"]):
		failures.append("expected %d pending consequence(s), found %d" % [int(expect["pending"]), runtime.minds.pending().size()])
	for convention_id in expect.get("conventions", []):
		if not runtime.minds.is_convention_active(str(convention_id)):
			failures.append("expected convention '%s' to be in force" % convention_id)
	for convention_id in expect.get("not_conventions", []):
		if runtime.minds.is_convention_active(str(convention_id)):
			failures.append("expected convention '%s' NOT to be in force" % convention_id)
	for holder in expect.get("holders_know", {}).keys():
		for claim_id in expect["holders_know"][holder]:
			if not runtime.engine.knowledge.has(str(claim_id), str(holder)):
				failures.append("expected %s to know '%s'" % [holder, claim_id])
	for holder in expect.get("holders_not_know", {}).keys():
		for claim_id in expect["holders_not_know"][holder]:
			if runtime.engine.knowledge.has(str(claim_id), str(holder)):
				failures.append("expected %s NOT to know '%s'" % [holder, claim_id])
	for holder in expect.get("holder_models", {}).keys():
		for rule_id in expect["holder_models"][holder].keys():
			var wanted := int(MirrorDomain.ModelStatus.get(str(expect["holder_models"][holder][rule_id]), -1))
			var found := false
			for rule in runtime.engine.models.query_rules("", "", str(holder)):
				if str(rule["id"]) == str(rule_id) and int(rule["status"]) == wanted:
					found = true
			if not found:
				failures.append("expected %s's model %s to be %s" % [holder, rule_id, expect["holder_models"][holder][rule_id]])
	return failures

# The human-readable transcript: EVENT lines then the resulting Mirror state.
func report(runtime: MirrorRuntime) -> Array[String]:
	var out: Array[String] = []
	var events := runtime.engine.event_store.get_all()
	for event in events:
		out.append("EVENT " + EventLogView.describe(event).strip_edges())
	out.append("")
	out.append("Mirror State:")
	var e := runtime.engine
	out.append("  time: %d" % e.get_time())
	out.append("  world: %s" % JSON.stringify(e.world_state))
	out.append("  npc_state: %s" % JSON.stringify(e.npc_state))
	out.append("  knowledge:")
	for claim in e.knowledge.all("player"):
		out.append("    %s = %s" % [claim["id"], _enum_name(MirrorDomain.EpistemicStatus, int(claim["status"]))])
	out.append("  models:")
	for rule in e.models.query_rules("", "", "player"):
		out.append("    %s = %s (%.2f)" % [rule["id"], _enum_name(MirrorDomain.ModelStatus, int(rule["status"])), float(rule["confidence"])])
	out.append("  relationships:")
	for target in ["tomas"]:
		var relation := e.relationships.get_relation("player", target)
		if not relation.is_empty():
			out.append("    player->%s: %d events, boundaries=%s, invitations=%d" % [target, relation["events"].size(), JSON.stringify(relation["boundaries"]), relation["invitations"].size()])
	out.append("  predictions: %s" % JSON.stringify(e.prediction.to_dict()))
	out.append("  operators: %s" % JSON.stringify(e.operators.all("player").map(func(o): return o["id"])))
	if runtime.minds != null and (runtime.minds.state.seeded or runtime.minds.pending().size() > 0 or runtime.minds.state.conventions.ids().size() > 0):
		out.append("  minds:")
		out.append("    pending: %s" % JSON.stringify(runtime.minds.pending().map(func(c): return "%s due %d: %s on %s" % [c["id"], int(c["due"]), c["event"]["kind"], c["event"]["subject"]])))
		out.append("    conventions: %s" % JSON.stringify(runtime.minds.state.conventions.ids().map(func(id): return "%s tally %d%s" % [id, runtime.minds.convention_state(id)["tally"], " (in force)" if runtime.minds.is_convention_active(id) else ""])))
		for holder in ["raccoon", "tomas"]:
			out.append("    %s knows: %s" % [holder, JSON.stringify(e.knowledge.all(holder).map(func(c): return c["id"]))])
	out.append("  head: %s (%d events)" % [e.event_store.head_hash(), events.size()])
	return out

static func load_script(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data

static func list_scripts() -> Array[String]:
	var out: Array[String] = []
	for file_name in DirAccess.get_files_at(SIM_DIR):
		if file_name.ends_with(".json"):
			out.append(SIM_DIR.path_join(file_name))
	out.sort()
	return out

static func _enum_name(table: Dictionary, value: int) -> String:
	for key in table.keys():
		if int(table[key]) == value:
			return str(key)
	return str(value)
