extends TestCase

# C18 (architecture/constitution.json, test_every_act_exit_stays_reachable): from every reachable state of an act, the
# act's exit stays reachable, so no authored route soft-locks the story. The search (progress_explorer.gd) runs over the
# whole game, act by act, from the new game. Each act starts in the state its predecessor's exit reached (a real path,
# replayed), so no entry is copied by hand. An act whose area is not in data/mirror/areas yet is SKIPped, and so is every
# act after it, because its entry state is unknown.

const WORK := "user://progress_fixture"
const MAX_DEPTH := 40
const MAX_EXPANSIONS := 400
const ACTS := ["prologue", "act1", "act2", "act3", "act4", "act5", "act6", "act7", "act8", "act9"]
const EXITS := ["act1", "act2", "act3", "act4", "act5", "act6", "act7", "act8", "act9", "postgame"]

func test_every_act_exit_stays_reachable() -> void:
	var runtime: MirrorRuntime = GameFixtures.runtime(true)
	var entry_known := true
	var searched := 0
	for index in ACTS.size():
		var act: String = ACTS[index]
		var exit_act: String = EXITS[index]
		if not entry_known or not DirAccess.dir_exists_absolute("res://data/mirror/areas/%s" % act):
			print("SKIP progress %s: its entry state is %s" % [act, "unknown" if not entry_known else "not written yet (no area package)"])
			ok(true, "%s: skipped, its area or its entry is not in the tree yet" % act)
			entry_known = false
			continue
		var report: Dictionary = ProgressExplorer.explore(runtime, {"story.act": exit_act}, MAX_DEPTH, MAX_EXPANSIONS)
		searched += 1
		print("PROGRESS %s -> %s: %d states, %d expanded, %d exits, %d frontier" % [act, exit_act, int(report["states"]), int(report["expanded"]), int(report["exits"]), int(report["frontier"])])
		eq(report["error"], "", "%s: the search replays without a refusal" % act)
		eq(report["violations"], [], "%s: from every reachable state its exit (%s) stays reachable" % [act, exit_act])
		var steps: Array = report["exit_steps"]
		var witness := "breadth-first"
		if steps.is_empty():
			steps = ProgressExplorer.find_exit(runtime, {"story.act": exit_act})
			witness = "depth-first"
		ok(not steps.is_empty(), "%s: its exit (%s) is reached from the entry state (%s search)" % [act, exit_act, witness])
		entry_known = not steps.is_empty() and ProgressExplorer.replay(runtime, steps) == ""
	ok(searched > 0, "the chain searched %d act(s)" % searched)

# A small game of one act: the lamp can be burnt, and the door leaves the act only while the magic is in a state that
# the exit allows. burn_to decides whether the burnt lamp closes the exit for good.
func test_the_explorer_finds_a_deliberate_softlock() -> void:
	var runtime := _fixture("soft", "gone", ["full"])
	var report: Dictionary = ProgressExplorer.explore(runtime, {"story.act": "act2"}, 20, 200)
	ok(int(report["exits"]) > 0, "the exit is reachable from the start (%d exit state(s))" % int(report["exits"]))
	ok(not report["violations"].is_empty(), "the search finds the soft-lock: after the lamp, no way out (%d state(s))" % report["violations"].size())
	ok(int(report["frontier"]) == 0, "the small game is searched to the end: nothing is left on the frontier")
	_remove_tree(WORK)

func test_the_explorer_passes_the_clean_twin_of_that_softlock() -> void:
	var runtime := _fixture("clean", "failing", ["full", "failing"])
	var report: Dictionary = ProgressExplorer.explore(runtime, {"story.act": "act2"}, 20, 200)
	ok(int(report["exits"]) > 0, "the exit is reachable from the start (%d exit state(s))" % int(report["exits"]))
	eq(report["violations"], [], "the clean twin has no soft-lock: the exit stays reachable after the lamp too")
	ok(int(report["frontier"]) == 0, "and the small game is searched to the end")
	_remove_tree(WORK)

# ---- helpers ----------------------------------------------------------------------------------

func _fixture(name: String, burn_to: String, exit_states: Array) -> MirrorRuntime:
	var dir := WORK.path_join(name)
	_remove_tree(dir)
	_write(dir.path_join("world.json"), {"world": {"story": {"act": "act1"}, "witch": {"place": "shop", "from": ""}, "magic": {"state": "full"}}, "npc_state": {}})
	_write(dir.path_join("prologue.json"), {"observer_id": "player", "subject_id": "fx_room", "observation": {"signature": ["PROLOGUE"]}, "context": {}, "knowledge_effects": [], "model_effects": [], "operator_effects": []})
	_write(dir.path_join("operators.json"), [])
	_write(dir.path_join("storylets.json"), [])
	_write(dir.path_join("hypotheses.json"), [])
	_write(dir.path_join("actions/fx.json"), _actions(burn_to, exit_states))
	var runtime: MirrorRuntime = track(MirrorRuntime.new())
	runtime.catalog_dir = dir
	runtime.include_areas = false
	var started := runtime.new_game()
	ok(bool(started.get("ok", false)), "%s: the fixture game starts" % name)
	return runtime

func _actions(burn_to: String, exit_states: Array) -> Array:
	var leave_when: Dictionary = {"story.act": "act1", "witch.place": "shop"}
	if exit_states.size() == 1:
		leave_when["magic.state"] = str(exit_states[0])
	else:
		leave_when["$in"] = {"magic.state": exit_states}
	return [
		{"id": "fx_burn", "action_type": "LOOK", "valid_targets": ["lamp"], "preconditions": {"story.act": "act1", "magic.state": "full"},
			"response_contracts": [{"id": "fx_burn.done", "observed": {"outcome": "burnt"}, "effects": {"world": {"magic": {"state": burn_to}}}, "presentation": [{"kind": "camera", "mode": "wide"}]}]},
		{"id": "fx_leave", "action_type": "GO", "valid_targets": ["door"], "preconditions": leave_when,
			"response_contracts": [{"id": "fx_leave.done", "observed": {"outcome": "left"}, "effects": {"world": {"story": {"act": "act2"}}}, "presentation": [{"kind": "camera", "mode": "wide"}]}]},
		{"id": "fx_go", "action_type": "GO", "valid_targets": ["door_out"], "preconditions": {"witch.place": "shop"},
			"response_contracts": [{"id": "fx_go.done", "observed": {"outcome": "moved"}, "effects": {"world": {"witch": {"place": "street", "from": "shop"}}}, "presentation": [{"kind": "camera", "mode": "wide"}]}]},
		{"id": "fx_back", "action_type": "GO", "valid_targets": ["door_in"], "preconditions": {"witch.place": "street"},
			"response_contracts": [{"id": "fx_back.done", "observed": {"outcome": "moved"}, "effects": {"world": {"witch": {"place": "shop", "from": "street"}}}, "presentation": [{"kind": "camera", "mode": "wide"}]}]},
	]

func _write(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)
