extends TestCase

# The Witch GAUNTLET's behavioural layer. Every simulation script is replayed and reduced to a
# canonical transcript: per step, which response Tomas chose, what was observed, how the
# witch's prediction missed, which camera beats were authored, and which options each target
# offered AFTERWARDS; plus the final world, expectations, knowledge, models and chain head.
# The transcript is diffed against tests/golden/<name>.json, so any unintended change to
# content behaviour - a response that stopped matching, an option that vanished, a belief that
# no longer revises - fails here with the first differing path.
#
# Changed content on purpose?  UPDATE_GOLDEN=1 ./tests/run_tests.sh golden   (then review the diff).

const GOLDEN_DIR := "res://tests/golden"
const TARGETS := ["tomas", "machine", "bell", "path_out"]

func _transcript(script: Dictionary) -> Dictionary:
	var r := GameFixtures.runtime()
	r.next_story()
	var steps: Array = []
	var uses_minds := false
	for step in script["steps"]:
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
	return {"name": script.get("name", ""), "steps": steps, "final": final}

# The minds layer's end state, for scripts that use it: what is pending, which customs formed, and what each
# non-player mind came to believe.
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

func test_every_sim_matches_its_golden_transcript() -> void:
	var update := OS.get_environment("UPDATE_GOLDEN") == "1"
	for path in SimulationRunner.list_scripts():
		var name := path.get_file().get_basename()
		var actual := _transcript(SimulationRunner.load_script(path))
		var golden_path := "%s/%s.json" % [GOLDEN_DIR, name]
		if update:
			var file := FileAccess.open(golden_path, FileAccess.WRITE)
			file.store_string(JSON.stringify(actual, "\t", true) + "\n")
			file.close()
			ok(true, "updated %s" % golden_path)
			continue
		ok(FileAccess.file_exists(golden_path), "%s has a golden transcript (run with UPDATE_GOLDEN=1 to create it)" % name)
		if not FileAccess.file_exists(golden_path):
			continue
		var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string(golden_path))
		var same := MirrorHash.canonical_json(actual) == MirrorHash.canonical_json(golden)
		var first := "" if same else _first_difference(golden, actual, "")
		ok(same, "%s drifted from its golden transcript. First difference: %s" % [name, first])

func _first_difference(expected: Variant, actual: Variant, path: String) -> String:
	if expected is Dictionary and actual is Dictionary:
		var keys: Array = expected.keys()
		for key in actual.keys():
			if key not in keys:
				keys.append(key)
		keys.sort()
		# Report behaviour before the chain hash: the hash changes on ANY catalog edit, so it is
		# the least informative place to start.
		for last in ["head_hash", "event_count"]:
			if last in keys:
				keys.erase(last)
				keys.append(last)
		for key in keys:
			if not expected.has(key):
				return "%s.%s added: %s" % [path, key, JSON.stringify(actual[key]).left(120)]
			if not actual.has(key):
				return "%s.%s removed (was %s)" % [path, key, JSON.stringify(expected[key]).left(120)]
			var deeper := _first_difference(expected[key], actual[key], "%s.%s" % [path, key])
			if deeper != "":
				return deeper
		return ""
	if expected is Array and actual is Array:
		for i in range(maxi(expected.size(), actual.size())):
			if i >= expected.size():
				return "%s[%d] added: %s" % [path, i, JSON.stringify(actual[i]).left(120)]
			if i >= actual.size():
				return "%s[%d] removed (was %s)" % [path, i, JSON.stringify(expected[i]).left(120)]
			var deeper := _first_difference(expected[i], actual[i], "%s[%d]" % [path, i])
			if deeper != "":
				return deeper
		return ""
	if MirrorHash.canonical_json(expected) != MirrorHash.canonical_json(actual):
		return "%s: expected %s, got %s" % [path, JSON.stringify(expected), JSON.stringify(actual)]
	return ""

func _name(table: Dictionary, value: int) -> String:
	for key in table.keys():
		if int(table[key]) == value:
			return str(key)
	return str(value)
