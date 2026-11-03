extends SceneTree

# Engine benchmark on the AUTHORED catalog (data/mirror), measured on the machine that runs it:
#   godot --headless --path . --script res://tools/bench.gd -- [events] [samples] [curve_sizes]
# Builds a log of about `events` committed events (default 5000), then reports:
#   action        p50 / p95 / max of `samples` committed resolve_action calls, on a fresh log and at size
#   lookup        indexed event lookups at size (get_by_id, get_transaction)
#   verify        full hash-chain verification at size
#   save / load   engine save_json and reload (with the state check), and the game envelope encode
#   tap_curve     tap-to-commit latency (MirrorRuntime.submit, the path a tap takes) at each of
#                 `curve_sizes` (comma-separated, default 1000,2000,3000,4000,5000), on two logs: the
#                 session mix of tests/mirror/test_engine_latency.gd (CLOCK_TICKS_PER_ACTION clock ticks per
#                 authored action) and authored actions only. p50 / p95 / max of CURVE_SAMPLES taps.
# Every number is wall-clock; compare runs made on the same machine only. Not part of the gate.

const DEFAULT_EVENTS := 5000
const DEFAULT_SAMPLES := 200
const LOOKUPS := 200
const DEFAULT_CURVE := "1000,2000,3000,4000,5000"
const CURVE_SAMPLES := 100
const CLOCK_TICKS_PER_ACTION := 15
const ACTIONS := [
	["look_bell", "bell", MirrorDomain.ActionType.LOOK],
	["look_tomas", "tomas", MirrorDomain.ActionType.LOOK],
	["wait_watch", "tomas", MirrorDomain.ActionType.WAIT],
	["look_machine", "machine", MirrorDomain.ActionType.LOOK],
]

var _serial := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var target_events := int(args[0]) if args.size() > 0 else DEFAULT_EVENTS
	var samples := int(args[1]) if args.size() > 1 else DEFAULT_SAMPLES
	var curve_sizes: Array = []
	for size in (args[2] if args.size() > 2 else DEFAULT_CURVE).split(",", false):
		curve_sizes.append(int(size))
	var engine: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	var report := {"godot": Engine.get_version_info()["string"], "events_target": target_events, "samples": samples}

	report["action_fresh"] = _measure_actions(engine, samples)

	var build_start := Time.get_ticks_usec()
	var attempts := 0
	while engine.event_store.size() < target_events and attempts < target_events * 4:
		_resolve(engine, attempts)
		attempts += 1
	report["build"] = {"attempts": attempts, "events": engine.event_store.size(), "seconds": snapped((Time.get_ticks_usec() - build_start) / 1000000.0, 0.01)}

	report["action_at_size"] = _measure_actions(engine, samples)

	var all_events := engine.event_store.get_all()
	var lookup_ids: Array = []
	for i in range(0, all_events.size(), maxi(1, all_events.size() / LOOKUPS)):
		lookup_ids.append(all_events[i].event_id)
	var lookup_times: Array = []
	for event_id in lookup_ids:
		var t := Time.get_ticks_usec()
		engine.event_store.get_by_id(event_id)
		lookup_times.append(Time.get_ticks_usec() - t)
	report["lookup_by_id"] = _percentiles(lookup_times)

	var verify_start := Time.get_ticks_usec()
	var verified: Dictionary = engine.event_store.verify_chain()
	report["verify_chain_ms"] = (Time.get_ticks_usec() - verify_start) / 1000.0
	report["chain_ok"] = verified.get("ok", false)

	var save_start := Time.get_ticks_usec()
	var text := engine.save_json()
	report["save_engine_ms"] = (Time.get_ticks_usec() - save_start) / 1000.0
	report["save_engine_bytes"] = text.to_utf8_buffer().size()

	var envelope_start := Time.get_ticks_usec()
	var envelope := SaveCodec.encode(engine)
	report["save_envelope_ms"] = (Time.get_ticks_usec() - envelope_start) / 1000.0
	report["save_envelope_bytes"] = envelope.to_utf8_buffer().size()

	var twin: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	var load_start := Time.get_ticks_usec()
	var loaded: Dictionary = twin.load_json(text)
	report["load_engine_ms"] = (Time.get_ticks_usec() - load_start) / 1000.0
	report["load_ok"] = loaded.get("ok", false)
	report["load_identical"] = loaded.get("ok", false) and MirrorHash.canonical_json(twin.projection_snapshot()) == MirrorHash.canonical_json(engine.projection_snapshot()) and twin.event_store.head_hash() == engine.event_store.head_hash()

	report["tap_curve_session_mix"] = _tap_curve(curve_sizes, CLOCK_TICKS_PER_ACTION)
	report["tap_curve_actions_only"] = _tap_curve(curve_sizes, 0)

	print(JSON.stringify(report, "  "))
	var all_good: bool = report["chain_ok"] and report["load_ok"] and report["load_identical"]
	quit(0 if all_good else 1)

# Resolves one authored action, cycling through ACTIONS. Returns the engine result.
func _resolve(engine: MirrorEngine, index: int) -> Dictionary:
	var entry: Array = ACTIONS[index % ACTIONS.size()]
	_serial += 1
	var action := MirrorAction.new(str(entry[0]), "player", str(entry[1]), int(entry[2]), {}, {})
	action.client_request_id = "bench-%d" % _serial
	return engine.resolve_action(action)

# Times `samples` committed actions. Refused attempts are not counted in the percentiles.
func _measure_actions(engine: MirrorEngine, samples: int) -> Dictionary:
	var times: Array = []
	var refused := 0
	var attempts := 0
	while times.size() < samples and attempts < samples * 4:
		var start := Time.get_ticks_usec()
		var result := _resolve(engine, attempts)
		var elapsed := Time.get_ticks_usec() - start
		attempts += 1
		if result.get("ok", false):
			times.append(elapsed)
		else:
			refused += 1
	var summary := _percentiles(times)
	summary["refused"] = refused
	summary["events_after"] = engine.event_store.size()
	return summary

func _percentiles(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var n := sorted.size()
	return {
		"count": n,
		"p50_us": sorted[n / 2],
		"p95_us": sorted[mini(n - 1, int(ceil(n * 0.95)) - 1)],
		"max_us": sorted[n - 1],
	}

# Tap-to-commit latency at growing log sizes, on one runtime whose log grows between measurements. With
# `ticks_per_action` > 0 the log is built like the latency test's (that many Mirror clock ticks per authored
# action); with 0, from authored actions only. The timed taps themselves add to the log.
func _tap_curve(sizes: Array, ticks_per_action: int) -> Array:
	var runtime := MirrorRuntime.new()
	runtime.new_game()
	var rows: Array = []
	var step := 0
	var build_start := Time.get_ticks_usec()
	for size in sizes:
		while runtime.engine.event_store.size() < int(size) and step < int(size) * 4:
			if ticks_per_action > 0 and step % (ticks_per_action + 1) != ticks_per_action:
				runtime.minds.advance_time(1, "clock")
			else:
				_tap(runtime, step)
			step += 1
		var times: Array = []
		var attempts := 0
		while times.size() < CURVE_SAMPLES and attempts < CURVE_SAMPLES * 4:
			var start := Time.get_ticks_usec()
			var result := _tap(runtime, attempts)
			var elapsed := Time.get_ticks_usec() - start
			attempts += 1
			if result.get("ok", false):
				times.append(elapsed)
		var row := _percentiles(times)
		row["events"] = runtime.engine.event_store.size()
		row["elapsed_s"] = snapped((Time.get_ticks_usec() - build_start) / 1000000.0, 0.1)
		rows.append(row)
	runtime.free()
	return rows

# One tap as the game submits it: through the runtime's queue, returning the result the queue finished with.
func _tap(runtime: MirrorRuntime, index: int) -> Dictionary:
	var entry: Array = ACTIONS[index % ACTIONS.size()]
	_serial += 1
	var finished: Array = []
	var on_finished := func(result: Dictionary) -> void: finished.append(result)
	runtime.queue.finished.connect(on_finished)
	runtime.submit(runtime.make_action(str(entry[0]), str(entry[1]), {}, "tap-%d" % _serial))
	runtime.queue.finished.disconnect(on_finished)
	return finished[0] if not finished.is_empty() else {}
