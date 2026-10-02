class_name MirrorRuntime
extends Node

# Game-side facade over the Mirror engine (registered as the `Mirror` autoload).
#
#   YAKO owned presentation mechanics. Mirror owns meaning.
#
# Nothing in a scene, an NPC or a dialogue file is allowed to be the authority on what
# happened: they submit actions here, the engine commits (or refuses), and only then does
# anything play. The runtime owns the engine, loads the authored catalog, serialises commits
# through an ActionQueue, and exposes read models (options, explanations, logs) for the UI.

signal committed(result: Dictionary)
signal failed(result: Dictionary)
signal game_started()
signal game_loaded(meta: Dictionary)

const PLAYER := "player"

var engine: MirrorEngine
# What the minds around the witch make of what happens (witnesses, readings, deferred consequences, folklore).
# Always built from the same engine; see game/mirror/minds/mirror_minds.gd.
var minds: MirrorMinds
var catalog_dir: String = MirrorCatalog.DEFAULT_DIR
var minds_dir: String = MindsCatalog.DEFAULT_DIR
var catalog_report: Dictionary = {}
var minds_report: Dictionary = {}
var queue := ActionQueue.new()
# func(presentation: Array, result: Dictionary) -> void   (may be a coroutine)
var presenter: Callable

func _init() -> void:
	queue.resolver = _resolve_and_publish
	queue.presenter = _present

func _ready() -> void:
	if engine == null:
		setup()

# Builds a fresh engine and registers the whole authored catalog (unlocked until first commit).
func setup(dir: String = "") -> Dictionary:
	if not dir.is_empty():
		catalog_dir = dir
	var built := MirrorCatalog.build_engine(catalog_dir)
	engine = built["engine"]
	catalog_report = built["report"]
	engine.transaction_committed.connect(func(result: Dictionary) -> void: committed.emit(result))
	engine.transaction_failed.connect(func(result: Dictionary) -> void: failed.emit(result))
	for error in catalog_report.get("errors", []):
		push_error("Mirror catalog: %s" % error)
	minds_report = MindsCatalog.load_dir(minds_dir)
	minds = MirrorMinds.new(engine, minds_report["data"])
	for error in minds_report.get("errors", []):
		push_error("Minds catalog: %s" % error)
	return catalog_report

# Starts from scratch: fresh engine + the prologue observation (what the witch already believes).
func new_game() -> Dictionary:
	setup()
	var prologue := MirrorCatalog.load_prologue(catalog_dir)
	var result := engine.record_observation(
		str(prologue.get("observer_id", PLAYER)), str(prologue.get("subject_id", "")),
		prologue.get("observation", {}), prologue.get("context", {}), prologue.get("evidence", []),
		prologue.get("knowledge_effects", []), prologue.get("model_effects", []), prologue.get("operator_effects", []))
	if result.get("ok", false):
		game_started.emit()
	return result

# ---- actions ----------------------------------------------------------------------------------

func make_action(action_id: String, target_id: String = "", context: Dictionary = {}, request_id: String = "") -> MirrorAction:
	var definition: Dictionary = engine.action_definitions.get(action_id, {})
	var action := MirrorAction.new(action_id, PLAYER, target_id, int(definition.get("action_type", MirrorDomain.ActionType.CUSTOM)), {}, context)
	action.client_request_id = request_id
	return action

# Queued: resolves, then presents to completion, then the next. The normal in-game path.
func submit(action: MirrorAction) -> void:
	queue.enqueue(action)

# Immediate and headless: resolves without presentation. Used by the simulation runner and tests.
func resolve_now(action: MirrorAction) -> Dictionary:
	return engine.resolve_action(action)

func is_busy() -> bool:
	return queue.is_busy()

func _resolve_and_publish(action: MirrorAction) -> Dictionary:
	return engine.resolve_action(action)

func _present(result: Dictionary) -> void:
	if presenter.is_valid():
		await presenter.call(result.get("presentation", []), result)

# ---- read models ------------------------------------------------------------------------------

func options_for(target_id: String, nearby: PackedStringArray = PackedStringArray()) -> Array[InteractionOption]:
	var ctx := InteractionContext.new(target_id, PLAYER)
	ctx.nearby = nearby
	return InteractionResolver.new(engine).resolve(ctx)

func explain_for(target_id: String) -> Array[Dictionary]:
	return InteractionResolver.new(engine).explain(InteractionContext.new(target_id, PLAYER))

# The state conditions are evaluated against: world, every NPC as npc.<id>, and the clock.
func context_snapshot() -> Dictionary:
	var context := engine.world_state.duplicate(true)
	context["npc"] = engine.npc_state.duplicate(true)
	context["time"] = engine.get_time()
	return context

# Selects and consumes the highest-ranked eligible storylet (e.g. the arrival beat).
# Returns the commit result, whose "presentation" is what to play, or {} if none is eligible.
func next_story() -> Dictionary:
	var context := context_snapshot()
	var candidates := engine.select_storylets(context, PLAYER)
	if candidates.is_empty():
		return {}
	var result := engine.consume_storylet(str(candidates[0].get("id", "")), PLAYER, context)
	if result.get("ok", false):
		result["presentation"] = result.get("storylet", {}).get("presentation", [])
	return result

func evaluate_hypotheses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := engine.causal_hypothesis_definitions.keys()
	ids.sort()
	for id in ids:
		out.append(engine.evaluate_causal_hypothesis(str(id), PLAYER, context_snapshot()))
	return out

func describe_log(last: int = 0) -> Array[String]:
	return EventLogView.describe_all(engine, last)

# ---- persistence ------------------------------------------------------------------------------

func save_game(slot: int, meta: Dictionary = {}) -> Error:
	return SaveGame.save(engine, slot, meta)

func load_game(slot: int) -> Dictionary:
	var result := SaveGame.load_into(engine, slot)
	if result.get("ok", false):
		game_loaded.emit(result.get("meta", {}))
	return result
