class_name SightPresenter
extends Node

# The `sight` presentation step (GAME_SPEC section 4): shows the chuika's ghosts of the NPCs in the room, for a few
# seconds. Each ghost is a translucent copy of the actor's own meshes, sharing its skeleton, so it takes the actor's pose
# and then makes its entry's move. Seeing a ghost writes nothing to Mirror: this only reads the state and the room.

signal finished

const STAGGER := 0.35
const TAIL := 0.25
const SHADER := "res://render/psx/ghost_silhouette.gdshader"
const GHOST_META := "chuika_ghost"

# True for a copy this presenter made (so a second ghost of the same actor is not a copy of the first).
static func is_ghost_copy(node: Node) -> bool:
	return node.has_meta(GHOST_META)

# The host (the game root) offers the witch, for a look_at:witch ghost.
var host: Node
# Returns the room (RoomSlot: stage_actors(), anchor()) and the Mirror runtime, read when the step plays.
var room_provider: Callable
var runtime_provider: Callable
var sidecar_dir := ExpectationSight.DIR
# Scene seconds per real second (tests shorten the step).
var time_scale := 1.0

static var _shader: Shader

var _entries: Array = []
var _loaded := false
var _ghosts: Array = []
var _elapsed := 0.0
var _active := false

func play_entry(_entry: Dictionary) -> void:
	var runtime: MirrorRuntime = runtime_provider.call() if runtime_provider.is_valid() else null
	var room: Object = room_provider.call() if room_provider.is_valid() else null
	if runtime == null or runtime.engine == null or room == null or not room.has_method("stage_actors"):
		return
	_load()
	var context: Dictionary = runtime.context_snapshot()
	var actors: Dictionary = room.call("stage_actors")
	var present := ExpectationSight.present_npcs(context, actors.keys())
	var shown := ExpectationSight.selected(_entries, context, present)
	if shown.is_empty():
		return
	_clear()
	var slots: Dictionary = {}
	var longest := 0.0
	for i in shown.size():
		var entry: Dictionary = shown[i]
		var npc := str(entry["npc"])
		var slot := int(slots.get(npc, 0))
		slots[npc] = slot + 1
		var start := float(i) * STAGGER
		_spawn(actors[npc] as Node3D, room, str(entry["ghost"]), slot, start)
		longest = maxf(longest, start + ExpectationSight.MOVE_SECONDS + TAIL)
	_elapsed = 0.0
	_active = true
	await get_tree().create_timer(longest * time_scale).timeout
	_clear()
	finished.emit()

func _exit_tree() -> void:
	_clear()

func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var loaded: Dictionary = ExpectationSight.load_entries(sidecar_dir)
	_entries = loaded["entries"]
	for error in loaded["errors"]:
		push_warning("expectation sidecar: %s" % str(error))

# One copy per mesh of the actor, under the same parent and skeleton, so the copy keeps the actor's pose.
func _spawn(actor: Node3D, room: Object, ghost: String, slot: int, start: float) -> void:
	if actor == null:
		return
	var lateral := (0.12 + 0.05 * floorf(float(slot) * 0.5)) * (1.0 if slot % 2 == 0 else -1.0)
	var look_yaw := 0.0
	if ExpectationSight.is_look(ghost):
		var target: Variant = _look_position(ExpectationSight.look_target(ghost), room)
		if target is Vector3:
			look_yaw = ExpectationSight.yaw_towards(actor.global_position, target) - actor.global_rotation.y
	for node in actor.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		if source == null or source.mesh == null or source.get_parent() == null or is_ghost_copy(source):
			continue
		var copy := MeshInstance3D.new()
		copy.name = "Ghost%d" % _ghosts.size()
		copy.set_meta(GHOST_META, true)
		copy.mesh = source.mesh
		copy.skin = source.skin
		copy.skeleton = source.skeleton
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = _ghost_shader()
		copy.material_override = material
		source.get_parent().add_child(copy)
		_ghosts.append({"ghost": copy, "source": source, "material": material, "name": ghost, "start": start, "lateral": lateral, "look_yaw": look_yaw})

func _look_position(target: String, room: Object) -> Variant:
	var witch: Variant = host.get("witch") if host != null and (target == "witch" or target == "player") else null
	if witch is Node3D:
		return (witch as Node3D).global_position
	return room.call("anchor", target) if room.has_method("anchor") else null

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta / maxf(time_scale, 0.001)
	for item: Dictionary in _ghosts:
		_pose(item)

func _pose(item: Dictionary) -> void:
	var copy := item["ghost"] as MeshInstance3D
	var source := item["source"] as MeshInstance3D
	if not is_instance_valid(copy) or not is_instance_valid(source):
		return
	var progress := (_elapsed - float(item["start"])) / ExpectationSight.MOVE_SECONDS
	copy.visible = progress >= 0.0
	if progress < 0.0:
		return
	var pose := ExpectationSight.pose_at(str(item["name"]), clampf(progress, 0.0, 1.0))
	var turn := float(pose["turn"]) + float(item["look_yaw"]) * float(pose["look_weight"])
	var rotation_basis := Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, float(pose["lean"]))
	var factor := float(pose["scale"])
	var step: Vector3 = pose["step"] + Vector3(float(item["lateral"]), 0.0, 0.0)
	copy.transform = Transform3D(rotation_basis.scaled(Vector3.ONE * factor), step) * source.transform
	(item["material"] as ShaderMaterial).set_shader_parameter("strength", float(pose["alpha"]))

func _clear() -> void:
	_active = false
	for item: Dictionary in _ghosts:
		var copy := item["ghost"] as MeshInstance3D
		if is_instance_valid(copy):
			copy.queue_free()
	_ghosts.clear()

static func _ghost_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER) as Shader
	return _shader
