extends TestCase

# The chains that end in act five, run from a new game at game scope: each "after" is followed into data/sim, or into
# data/sim_pending while the chain is still pending, and every segment runs on one runtime with its own expectations
# checked at its end. The transcript has the same shape as the gate's golden transcripts (tests/sim/
# test_golden_transcripts.gd). Goldens live beside them as tests/golden/<name>.json; UPDATE_GOLDEN=1 writes the goldens
# of these four chains only, which is this file's own update.

const CHAINS := ["act3_main", "act4_main", "act5_main", "act5_wait"]
const GOLDEN_DIR := "res://tests/golden"
const TARGETS := ["tomas", "machine", "bell", "path_out"]

var _runs: Dictionary = {}


func _load(name: String) -> Dictionary:
	var path := "res://data/sim/%s.json" % name
	if not FileAccess.file_exists(path):
		path = "res://data/sim_pending/%s.json" % name
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


func _segments(name: String, depth: int = 0) -> Array:
	var out: Array = []
	var script := _load(name)
	if depth > 16 or script.is_empty():
		return out
	var after: Variant = script.get("after", [])
	var priors: Array = [after] if after is String else (after as Array if after is Array else [])
	for prior in priors:
		out.append_array(_segments(str(prior).get_file().get_basename(), depth + 1))
	out.append(script)
	return out


func _name(table: Dictionary, value: int) -> String:
	for key in table.keys():
		if int(table[key]) == value:
			return str(key)
	return str(value)


# Runs the chain and returns {"transcript": {...}, "failures": [...]}. Cached per suite, since the chains are long.
func _run(name: String) -> Dictionary:
	if _runs.has(name):
		return _runs[name]
	var r: MirrorRuntime = GameFixtures.runtime(true)
	r.next_story()
	var steps: Array = []
	var failures: Array = []
	var uses_minds := false
	var final_name := ""
	for segment in _segments(name):
		final_name = str(segment.get("name", ""))
		for step in segment.get("steps", []):
			if SimulationRunner.is_minds_step(step):
				uses_minds = true
				steps.append(SimulationRunner.summarize_minds(step, SimulationRunner.run_step(r, step)))
				continue
			var result := r.resolve_now(r.make_action(str(step["action"]), str(step["target"])))
			var entry := {"action": step["action"], "target": step["target"], "ok": result.get("ok", false)}
			if result.get("ok", false):
				entry["response"] = result["response"].get("id", "")
				entry["observed"] = result["observed"]
				var missed: Array = []
				for kind in result["discrepancy"]["kinds"]:
					missed.append(_name(MirrorDomain.DiscrepancyKind, int(kind)))
				entry["prediction_missed"] = missed
				entry["camera"] = result["presentation"].filter(func(p): return p.get("kind") == "camera").map(func(p): return p.get("mode"))
				var options := {}
				for target in TARGETS:
					options[target] = GameFixtures.action_ids(r, target)
				entry["options_after"] = options
			steps.append(entry)
		for failure in SimulationRunner.new().check_expectations(r, segment.get("expect", {})):
			failures.append("%s: %s" % [str(segment.get("name", "")), failure])
	var e := r.engine
	var knowledge := {}
	for claim in e.knowledge.all("player"):
		knowledge[claim["id"]] = _name(MirrorDomain.EpistemicStatus, int(claim["status"]))
	var models := {}
	for rule in e.models.query_rules("", "", "player"):
		models[rule["id"]] = _name(MirrorDomain.ModelStatus, int(rule["status"]))
	var final := {
		"world": e.world_state, "npc_state": e.npc_state, "knowledge": knowledge, "models": models,
		"operators": e.operators.all("player").map(func(o): return o["id"]),
		"event_count": e.event_store.size(), "head_hash": e.event_store.head_hash(),
	}
	if uses_minds:
		final["minds"] = _minds_state(r)
	var run := {"transcript": {"name": final_name, "steps": steps, "final": final}, "failures": failures}
	_runs[name] = run
	return run


# The minds layer's end state, as the gate's transcript records it, for chains that use it.
func _minds_state(r: MirrorRuntime) -> Dictionary:
	var minds := r.minds
	var conventions := {}
	for id in minds.state.conventions.ids():
		var state := minds.convention_state(str(id))
		conventions[id] = {"tally": int(state["tally"]), "adopted": bool(state["adopted"]), "stalled": bool(state["stalled"]), "holders": state["holders"].keys(), "origin_events": state["origin_events"].size()}
	var holders := {}
	for holder in ["raccoon", "tomas"]:
		var held := {}
		for claim in r.engine.knowledge.all(holder):
			held[claim["id"]] = _name(MirrorDomain.EpistemicStatus, int(claim["status"]))
		var beliefs := {}
		for rule in r.engine.models.query_rules("", "", holder):
			beliefs[rule["id"]] = "%s %.2f" % [_name(MirrorDomain.ModelStatus, int(rule["status"])), float(rule["confidence"])]
		holders[holder] = {"knowledge": held, "models": beliefs}
	return {
		"pending": minds.pending().map(func(c: Dictionary) -> String: return "%s due %d: %s on %s" % [c["id"], int(c["due"]), c["event"]["kind"], c["event"]["subject"]]),
		"conventions": conventions, "holders": holders,
	}


func test_each_chain_runs_to_its_end_with_every_step_accepted_and_every_segment_met() -> void:
	for name in CHAINS:
		var run: Dictionary = _run(name)
		eq(run["failures"], [], "%s: every segment's expectations hold" % name)
		var refused := 0
		for step in run["transcript"]["steps"]:
			if not bool(step.get("ok", false)):
				refused += 1
		eq(refused, 0, "%s: every step is accepted" % name)


# The aliveness ratchet (game/mirror/aliveness_lint.gd measure_sim), at game scope for this workcell's own taps: a tap must
# change something the witch can see (a claim, an option or the world), or it is a dead tap, and the ratchet allows none.
func _view(r: MirrorRuntime) -> Dictionary:
	var claims := {}
	for claim in r.engine.knowledge.all():
		claims["%s::%s" % [claim.get("holder_id", "player"), claim.get("id", "")]] = int(claim.get("status", 0))
	var options := {}
	for target in ["tomas", "machine", "bell"]:
		options[target] = GameFixtures.action_ids(r, target)
	return {"claims": claims, "options": options, "world": r.engine.world_state.duplicate(true)}


func _is_ours(action_id: String) -> bool:
	return action_id.begins_with("act3_") or action_id.begins_with("act4_") or action_id.begins_with("act5_")


func _dead_taps(name: String) -> Array:
	var r: MirrorRuntime = GameFixtures.runtime(true)
	r.next_story()
	var dead: Array = []
	for segment in _segments(name):
		for step in segment.get("steps", []):
			if SimulationRunner.is_minds_step(step):
				SimulationRunner.run_step(r, step)
				continue
			var action_id := str(step["action"])
			var ours := _is_ours(action_id)
			var before: Dictionary = _view(r) if ours else {}
			r.resolve_now(r.make_action(action_id, str(step["target"])))
			if not ours:
				continue
			if MirrorHash.canonical_json(before) == MirrorHash.canonical_json(_view(r)):
				dead.append("%s@%s" % [action_id, str(step["target"])])
	return dead


func test_every_tap_of_acts_three_to_five_changes_something_the_witch_can_see() -> void:
	for name in ["act5_main", "act5_wait"]:
		eq(_dead_taps(name), [], "%s: no dead taps in acts three to five" % name)


func test_the_chain_transcripts_match_their_goldens() -> void:
	var update := OS.get_environment("UPDATE_GOLDEN") == "1"
	for name in CHAINS:
		var actual: Dictionary = _run(name)["transcript"]
		var golden_path := "%s/%s.json" % [GOLDEN_DIR, name]
		if update:
			var file := FileAccess.open(golden_path, FileAccess.WRITE)
			file.store_string(JSON.stringify(actual, "\t", true) + "\n")
			file.close()
			ok(true, "updated %s" % golden_path)
			continue
		ok(FileAccess.file_exists(golden_path), "%s has a golden transcript (UPDATE_GOLDEN=1 writes it)" % name)
		if not FileAccess.file_exists(golden_path):
			continue
		var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string(golden_path))
		ok(MirrorHash.canonical_json(actual) == MirrorHash.canonical_json(golden), "%s matches its golden transcript" % name)
