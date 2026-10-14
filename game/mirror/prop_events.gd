class_name PropEvents
extends Node

# The thin bridge between a room and Mirror's Minds layer. The room knows what was TAPPED and where people stand;
# Mirror knows what that MEANS: who saw it, what each of them made of it, and what the world does about it later.
# This script carries the first to the second and brings the answer back as reactions.
#
#   room.prop_pressed(prop_id, reaction[, world_position])   ->  a PROP_POKED happening by the witch
#   room.walked(pixel, world)                                 ->  a WALKED happening (throttled)
#   Mirror.minds.consequence_fired                            ->  reactions of things that fell due
#
# It holds no game truth. It reads perception data off the scene (who is on stage, how far each one is from
# the thing touched) and passes it as hints; it never decides who noticed. The room is only touched through its
# signals (game/world/room_slot.gd), so a stub with the same signals stands in for it in tests
# (tests/mirror/test_prop_events.gd).
#
# What comes back, per happening:
#   reaction_requested(reaction)       one per reaction, in order. {op, ...}: PROP_REACT {target, reaction},
#                                      LOOK_AT {actor, target}, FOLLOW, APPROACH {actor, target}, COMMENT {actor, key}
#   presentation_ready(entries, result)  existing presentation kinds (a COMMENT is a `line`), for PresentationDirector
#   reaction_presented(reaction, presented)  a PROP_REACT that reached the room, and whether the room could show it
# Time: one Mirror tick per `seconds_per_tick` of real time while the node is in the tree and `run_clock` is on,
# which is what lets "the hall answers late" happen without a WAIT action. Call pass_time() to do it by hand.

signal reaction_requested(reaction: Dictionary)
signal presentation_ready(entries: Array, result: Dictionary)
signal happened(result: Dictionary)
signal reaction_presented(reaction: Dictionary, presented: bool)

# Mirror holder ids for the scene's actor ids (the painted room calls the witch "witch").
var actor_map: Dictionary = {"witch": "player"}
var place := "clearing"
var seconds_per_tick := 1.0
var run_clock := true
# Metres the witch must have moved since the last reported step (a walk is not worth a log entry per frame).
var walk_min_distance := 1.5

var runtime: MirrorRuntime
var room: Object
var attention: Dictionary = {}
var _clock := 0.0
var _last_walk := Vector3(INF, INF, INF)
var _watched_minds: MirrorMinds

# Wires `scene` (anything with the room's signals) to `mirror`. Add the result to the tree to run the clock.
static func attach(scene: Object, mirror: MirrorRuntime, options: Dictionary = {}) -> PropEvents:
	var bridge := PropEvents.new()
	bridge.name = "PropEvents"
	bridge.runtime = mirror
	bridge.room = scene
	for key in options.keys():
		bridge.set(str(key), options[key])
	if scene.has_signal("prop_pressed"):
		scene.connect("prop_pressed", bridge._on_prop_pressed)
	if scene.has_signal("walked"):
		scene.connect("walked", bridge._on_walked)
	return bridge

func detach() -> void:
	if room != null and is_instance_valid(room):
		if room.is_connected("prop_pressed", _on_prop_pressed):
			room.disconnect("prop_pressed", _on_prop_pressed)
		if room.has_signal("walked") and room.is_connected("walked", _on_walked):
			room.disconnect("walked", _on_walked)
	room = null

# What the scene says about attention (idle, attending, busy, away, asleep): a raccoon looking elsewhere is
# set here by whoever animates it, and travels to Mirror as a hint with the next happening.
func set_attention(holder: String, state: String) -> void:
	attention[holder] = state

# ---- the room's signals ---------------------------------------------------------------------------------

func _on_prop_pressed(prop_id: String, reaction: String = "", world_position: Vector3 = Vector3.INF) -> void:
	poke(prop_id, reaction, world_position)

func _on_walked(pixel: Vector2 = Vector2.ZERO, world: Vector3 = Vector3.ZERO) -> void:
	walked(pixel, world)

# A prop was pressed. Returns Mirror's result ({} if there is no runtime).
func poke(prop_id: String, reaction: String, world_position: Vector3 = Vector3.INF) -> Dictionary:
	if runtime == null or runtime.minds == null:
		return {}
	_watch()
	var result := runtime.minds.perceive({
		"kind": "PROP_POKED", "actor": "player", "subject": prop_id, "place": place,
		"data": {"reaction": reaction}, "hints": hints(world_position),
	})
	_deliver(result)
	return result

# The witch moved. Quiet: recorded only if somebody reacted, and not more often than walk_min_distance.
func walked(_pixel: Vector2, world: Vector3) -> Dictionary:
	if runtime == null or runtime.minds == null:
		return {}
	if _last_walk.is_finite() and _last_walk.distance_to(world) < walk_min_distance:
		return {}
	_last_walk = world
	_watch()
	var result := runtime.minds.perceive({"kind": "WALKED", "actor": "player", "subject": "", "place": place, "hints": hints(world)})
	_deliver(result)
	return result

# Time passes. Returns the consequences that fell due.
func pass_time(ticks: int, reason: String = "wait") -> Array:
	if runtime == null or runtime.minds == null or ticks <= 0:
		return []
	_watch()
	var result := runtime.minds.advance_time(ticks, reason)
	return result.get("fired", [])

func _process(delta: float) -> void:
	if not run_clock or runtime == null or runtime.minds == null or seconds_per_tick <= 0.0:
		return
	_clock += delta
	var ticks := int(_clock / seconds_per_tick)
	if ticks > 0:
		_clock -= ticks * seconds_per_tick
		pass_time(ticks, "clock")

# ---- perception data off the scene -----------------------------------------------------------------------

# {present: [holders on stage], distance: {holder: metres from `at`}, attention: {...}}. Anything the scene
# does not know is simply absent, and Mirror's defaults apply.
func hints(at: Vector3 = Vector3.INF) -> Dictionary:
	var out: Dictionary = {}
	var stage: Dictionary = _stage_actors()
	if not stage.is_empty():
		var present: Array = []
		var distance: Dictionary = {}
		for scene_id in stage.keys():
			var holder := str(actor_map.get(scene_id, scene_id))
			present.append(holder)
			var node: Variant = stage[scene_id]
			if at.is_finite() and node is Node3D and holder != "player":
				distance[holder] = snappedf((node as Node3D).position.distance_to(at), 0.01)
		present.sort()
		out["present"] = present
		if not distance.is_empty():
			out["distance"] = distance
	if not attention.is_empty():
		out["attention"] = attention.duplicate()
	return out

# Who is on stage, {scene id: Node3D}. A room that implements the slot says so; any other room's `actors` is read.
func _stage_actors() -> Dictionary:
	if room == null:
		return {}
	if room.has_method("stage_actors"):
		var stage: Variant = room.call("stage_actors")
		if stage is Dictionary:
			return stage as Dictionary
		return {}
	var legacy: Variant = room.get("actors")
	if legacy is Dictionary:
		return legacy as Dictionary
	return {}

# ---- what comes back ---------------------------------------------------------------------------------------

# Makes Mirror's deferred consequences reach the same outputs as a poke does.
func _watch() -> void:
	if _watched_minds == runtime.minds:
		return
	if _watched_minds != null and _watched_minds.consequence_fired.is_connected(_on_consequence):
		_watched_minds.consequence_fired.disconnect(_on_consequence)
	_watched_minds = runtime.minds
	_watched_minds.consequence_fired.connect(_on_consequence)

func _on_consequence(result: Dictionary) -> void:
	_deliver(result)

func _deliver(result: Dictionary) -> void:
	if not result.get("ok", false) or not result.get("recorded", true):
		return
	happened.emit(result)
	for reaction in result.get("reactions", []):
		reaction_requested.emit(reaction)
	var lines: Array = result.get("presentation", [])
	if not lines.is_empty():
		presentation_ready.emit(lines, result)

# Optional convenience: plays PROP_REACT on the room (see _present_prop_reaction). The coordinator connects it
# when it attaches a live room, so Mirror's reactions reach the room without anyone else wiring them.
func play_prop_reactions_on_room() -> void:
	if not reaction_requested.is_connected(_play_prop_reaction):
		reaction_requested.connect(_play_prop_reaction)

func _play_prop_reaction(reaction: Dictionary) -> void:
	if str(reaction.get("op", "")) != "PROP_REACT":
		return
	var presented := _present_prop_reaction(str(reaction.get("target", "")), str(reaction.get("reaction", "wobble")))
	reaction_presented.emit(reaction, presented)

# A room that implements the slot answers request_reaction(). Any other room is duck-typed on purpose: its `props`
# array of things with `prop_id` and `play(reaction)`. False when the room has no such thing to move.
func _present_prop_reaction(target: String, move: String) -> bool:
	if room == null:
		return false
	if room.has_method("request_reaction"):
		return bool(room.call("request_reaction", target, move))
	var props: Variant = room.get("props")
	if not props is Array:
		return false
	for prop: Variant in props:
		if prop != null and str(prop.get("prop_id")) == target and prop.has_method("play"):
			prop.play(move)
			return true
	return false
