extends TestCase

func test_every_authored_sim_script_passes_its_expectations() -> void:
	var scripts := SimulationRunner.list_scripts()
	ok(scripts.size() >= 5, "found the authored sims")
	for path in scripts:
		var r := GameFixtures.runtime()
		var outcome := SimulationRunner.new().run(r, SimulationRunner.load_script(path))
		ok(outcome["ok"], "%s: failed_step=%d expect=%s" % [path.get_file(), outcome["failed_step"], outcome["expect_failures"]])

func test_a_sim_is_deterministic_same_steps_same_chain() -> void:
	for path in SimulationRunner.list_scripts():
		var script := SimulationRunner.load_script(path)
		var a := SimulationRunner.new().run(GameFixtures.runtime(), script)
		var b := SimulationRunner.new().run(GameFixtures.runtime(), script)
		eq(a["head_hash"], b["head_hash"], "%s replays to an identical event chain" % path.get_file())
		eq(a["event_count"], b["event_count"], "%s event count" % path.get_file())

func test_different_choices_diverge() -> void:
	var a := SimulationRunner.new().run(GameFixtures.runtime(), SimulationRunner.load_script("res://data/sim/impulsive_recovery.json"))
	var b := SimulationRunner.new().run(GameFixtures.runtime(), SimulationRunner.load_script("res://data/sim/patient_no_bell.json"))
	ok(a["head_hash"] != b["head_hash"], "a different play is a different history")

func test_report_is_a_readable_transcript_of_events_and_state() -> void:
	var r := GameFixtures.runtime()
	var runner := SimulationRunner.new()
	runner.run(r, SimulationRunner.load_script("res://data/sim/wand_then_patience.json"))
	var report := runner.report(r)
	ok(report.any(func(l): return l.begins_with("EVENT #001")), "numbered EVENT lines starting with the prologue")
	ok(report.any(func(l): return "show_tomas_wand" in l), "actions are named")
	ok(report.any(func(l): return "prediction missed" in l), "discrepancies are visible in the log")
	ok(report.has("Mirror State:"), "state section")
	ok(report.any(func(l): return "m.tomas_distrusts_witch = REVISED" in l), "the belief revision is visible")
	ok(report.any(func(l): return l.strip_edges().begins_with("head:")), "head hash for diffing runs")

func test_a_failing_step_stops_the_run_and_is_reported() -> void:
	var r := GameFixtures.runtime()
	var outcome := SimulationRunner.new().run(r, {"name": "bad", "steps": [{"action": "look_tomas", "target": "tomas"}, {"action": "go_assist", "target": "machine"}, {"action": "look_bell", "target": "bell"}]})
	ok(not outcome["ok"], "not ok")
	eq(outcome["failed_step"], 1, "the un-invited assist is refused")
	eq(outcome["results"].size(), 2, "later steps did not run")

func test_unmet_expectations_are_reported() -> void:
	var r := GameFixtures.runtime()
	var outcome := SimulationRunner.new().run(r, {"name": "x", "steps": [{"action": "look_tomas", "target": "tomas"}], "expect": {"knows": ["machine_sings"], "state": {"machine.state": "singing"}, "operators": ["op.ask_before_acting"]}})
	ok(not outcome["ok"], "not ok")
	eq(outcome["expect_failures"].size(), 3, "each unmet expectation named")

func test_save_mid_run_then_resume_equals_an_uninterrupted_run() -> void:
	# The save/reload determinism requirement: state -> save -> reload -> identical canonical state.
	for path in SimulationRunner.list_scripts():
		var script := SimulationRunner.load_script(path)
		var steps: Array = script["steps"]
		var whole := SimulationRunner.new().run(GameFixtures.runtime(), script)
		for cut in range(1, steps.size()):
			var first := GameFixtures.runtime()
			SimulationRunner.new().run(first, script, cut)
			var saved := SaveCodec.encode(first.engine, {"cut": cut})
			var second: MirrorRuntime = track(MirrorRuntime.new())
			second.setup()
			var loaded := SaveGame.load_text(second.engine, saved)
			ok(loaded.get("ok", false), "%s cut %d loads: %s" % [path.get_file(), cut, JSON.stringify(loaded)])
			eq(MirrorHash.canonical_json(second.engine.projection_snapshot()), MirrorHash.canonical_json(first.engine.projection_snapshot()), "%s cut %d: identical canonical state after reload" % [path.get_file(), cut])
			var rest := {"steps": steps.slice(cut), "expect": script.get("expect", {})}
			var finished := SimulationRunner.new().run(second, rest)
			ok(finished["ok"], "%s cut %d resumes: %s" % [path.get_file(), cut, finished["expect_failures"]])
			eq(second.engine.event_store.head_hash(), whole["head_hash"], "%s cut %d: resumed run ends on the identical chain head" % [path.get_file(), cut])
