extends SceneTree

# Soak: seeded random play on the AUTHORED catalog, many seeds, long runs. Not part of the gate.
#   godot --headless --path . --script res://tools/soak.gd -- [seeds] [steps] [audit_every]
# Each seed omits a random subset of actions (a swarm), so feature mixes are explored that a fully
# enabled run would not produce. Every step is either a request the engine must refuse (an unknown
# action or target, 15%) or a random authored action. Every `audit_every` steps the audit checks:
#   - the event chain verifies,
#   - a save reloads into a twin engine with the identical projection and chain head (the twin's load
#     replays the log, so this also checks live state against replay).
# Any failure stops the run and prints the seed and step. Writes one JSON summary to stdout.

const DEFAULT_SEEDS := 4
const DEFAULT_STEPS := 300
const DEFAULT_AUDIT_EVERY := 25
const GARBAGE_RATE := 0.15
const OMIT_RATE := 0.3

var _failures: Array = []

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else DEFAULT_SEEDS
	var steps := int(args[1]) if args.size() > 1 else DEFAULT_STEPS
	var audit_every := int(args[2]) if args.size() > 2 else DEFAULT_AUDIT_EVERY
	var summary := {"godot": Engine.get_version_info()["string"], "seeds": seeds, "steps": steps, "audit_every": audit_every, "runs": []}
	var started := Time.get_ticks_usec()
	for seed_index in seeds:
		summary["runs"].append(_run_seed(1000 + seed_index, steps, audit_every))
	summary["seconds"] = snapped((Time.get_ticks_usec() - started) / 1000000.0, 0.01)
	summary["failures"] = _failures
	print(JSON.stringify(summary, "  "))
	quit(0 if _failures.is_empty() else 1)

func _run_seed(seed_value: int, steps: int, audit_every: int) -> Dictionary:
	var engine: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ids: Array = engine.action_definitions.keys()
	ids.sort()
	var omitted: Dictionary = {}
	for id in ids:
		if rng.randf() < OMIT_RATE:
			omitted[id] = true
	var available: Array = []
	for id in ids:
		if not omitted.has(id):
			available.append(id)
	var result := {"seed": seed_value, "omitted": omitted.keys().size(), "committed": 0, "refused": 0, "garbage_refused": 0, "audits": 0, "events": 0}
	var memory_start := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var seed_failed := false
	for step in steps:
		var before := engine.event_store.head_hash()
		if rng.randf() < GARBAGE_RATE or available.is_empty():
			var garbage := engine.resolve_action(MirrorAction.new("no_such_action_%d" % step, "player", "nowhere", MirrorDomain.ActionType.CUSTOM, {}, {}))
			if garbage.get("ok", true) or engine.event_store.head_hash() != before:
				_fail(seed_value, step, "a request for an unknown action was not refused cleanly")
				seed_failed = true
				break
			result["garbage_refused"] += 1
			continue
		var action_id: String = available[rng.randi() % available.size()]
		var definition: Dictionary = engine.action_definitions[action_id]
		var targets: Array = definition.get("valid_targets", [""])
		var target := str(targets[rng.randi() % targets.size()]) if not targets.is_empty() else ""
		var type: int = definition.get("action_type", MirrorDomain.ActionType.CUSTOM)
		var action := MirrorAction.new(action_id, "player", target, type, {}, {})
		action.client_request_id = "soak-%d-%d" % [seed_value, step]
		var outcome := engine.resolve_action(action)
		if outcome.get("ok", false):
			result["committed"] += 1
		else:
			result["refused"] += 1
			if engine.event_store.head_hash() != before:
				_fail(seed_value, step, "a refused action (%s) changed the chain head" % action_id)
				seed_failed = true
				break
		if (step + 1) % audit_every == 0:
			result["audits"] += 1
			if not _audit(engine, seed_value, step):
				seed_failed = true
				break
	result["events"] = engine.event_store.size()
	result["memory_growth_bytes"] = int(Performance.get_monitor(Performance.MEMORY_STATIC)) - memory_start
	result["failed"] = seed_failed
	return result

func _audit(engine: MirrorEngine, seed_value: int, step: int) -> bool:
	if not engine.event_store.verify_chain().get("ok", false):
		_fail(seed_value, step, "the event chain does not verify")
		return false
	var twin: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	var loaded: Dictionary = twin.load_json(engine.save_json())
	if not loaded.get("ok", false):
		_fail(seed_value, step, "the save does not reload: %s" % str(loaded.get("error", "")))
		return false
	if MirrorHash.canonical_json(twin.projection_snapshot()) != MirrorHash.canonical_json(engine.projection_snapshot()):
		_fail(seed_value, step, "the reloaded projection differs from the live one")
		return false
	if twin.event_store.head_hash() != engine.event_store.head_hash():
		_fail(seed_value, step, "the reloaded chain head differs from the live one")
		return false
	return true

func _fail(seed_value: int, step: int, reason: String) -> void:
	_failures.append({"seed": seed_value, "step": step, "reason": reason})
