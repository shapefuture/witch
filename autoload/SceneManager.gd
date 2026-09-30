extends CanvasLayer

# Fade-to-black transition used for room changes. Route every scene change through
# change_scene() so fades, pause state and future per-room hooks stay in one place.

signal transition_started(path: String)
signal transition_finished(path: String)

const GAME_W := 320
const GAME_H := 240
const FADE_OUT := 0.35
const FADE_IN := 0.45

var _overlay: ColorRect
var busy := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.size = Vector2(GAME_W, GAME_H)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.modulate.a = 0.0
	add_child(_overlay)

func change_scene(path: String) -> void:
	if busy:
		return
	_transition(path)

func _transition(path: String) -> void:
	busy = true
	transition_started.emit(path)
	var resolved := resolve(path)
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, FADE_OUT)
	await tween.finished
	get_tree().change_scene_to_file(resolved)
	await get_tree().process_frame
	tween = create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, FADE_IN)
	await tween.finished
	busy = false
	transition_finished.emit(resolved)

# uid:// paths (stored by Godot 4.4+ file pickers) must be resolved before loading.
static func resolve(path: String) -> String:
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(uid):
			return ResourceUID.get_id_path(uid)
	return path
