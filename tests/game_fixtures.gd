class_name GameFixtures
extends RefCounted

static var _localized := false

# Registers the Russian text table once so option labels resolve to prose in tests.
static func ensure_localization() -> void:
	if _localized:
		return
	var localization: Node = load("res://autoload/Localization.gd").new()
	localization.register()
	localization.free()
	_localized = true

# A fresh runtime with the authored catalog and the prologue recorded, exactly as a new game.
static func runtime() -> MirrorRuntime:
	ensure_localization()
	var r: MirrorRuntime = TestCase.track(MirrorRuntime.new())
	var result := r.new_game()
	assert(result.get("ok", false), "new_game failed: %s" % JSON.stringify(result))
	return r

# Resolves one authored action headlessly. Returns the engine result.
static func do(r: MirrorRuntime, action_id: String, target_id: String) -> Dictionary:
	return r.resolve_now(r.make_action(action_id, target_id))

# Plays [[action_id, target_id], ...]; returns every result. Stops at the first failure.
static func play(r: MirrorRuntime, steps: Array) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for step in steps:
		var result := do(r, step[0], step[1])
		results.append(result)
		if not result.get("ok", false):
			break
	return results

static func labels(r: MirrorRuntime, target_id: String) -> Array[String]:
	var out: Array[String] = []
	for option in r.options_for(target_id):
		out.append(option.label)
	return out

static func action_ids(r: MirrorRuntime, target_id: String) -> Array[String]:
	var out: Array[String] = []
	for option in r.options_for(target_id):
		out.append(option.action_id)
	return out

static func stance(r: MirrorRuntime) -> String:
	return str(r.engine.get_npc_state("tomas").get("stance", ""))

static func machine_state(r: MirrorRuntime) -> String:
	return str(r.engine.get_world("machine", {}).get("state", ""))

const PATIENT_WITH_BELL := [
	["look_tomas", "tomas"], ["look_bell", "bell"], ["ask_tomas_what", "tomas"],
	["look_machine_informed", "machine"], ["wait_watch", "tomas"], ["go_assist", "machine"],
	["cast_flourish", "machine"], ["go_path_out", "path_out"],
]
const PATIENT_NO_BELL := [
	["ask_tomas_what", "tomas"], ["wait_watch", "tomas"], ["wait_watch", "tomas"],
	["go_assist", "machine"], ["go_path_out", "path_out"],
]
const IMPULSIVE := [
	["cast_repair", "machine"], ["ask_tomas_help", "tomas"], ["go_assist", "machine"],
	["cast_flourish", "machine"], ["go_path_out", "path_out"],
]
