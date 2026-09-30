class_name SimulationRunner
extends RefCounted

# Deterministic headless playthroughs. A script is a list of steps, each the same
# {action, target} an interactive choice would submit, resolved through the very same Mirror
# engine, so a sim is a faithful, repeatable regression of the real game logic.
#
#   godot --headless --path . -- --debug-sim data/sim/patient.json
#
# (See game_root.gd for the command-line hook.)

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
		var result := runtime.resolve_now(runtime.make_action(str(step.get("action", "")), str(step.get("target", "")), step.get("context", {})))
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

# expect: {"state": <condition matched against the world/npc snapshot>, "knows": [claim ids],
#          "model_status": {rule_id: "REVISED"}, "operators": [ids]}
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
