class_name InteractionPresenter
extends Node3D

# The contextual action surface: a short list of natural-language options for whatever the player
# tapped, as carved plaques hung beside the thing (see PlaqueStack). It renders
# InteractionOption.label and NOTHING else; the ontology never reaches the screen. A tap inside a
# plaque chooses it, whether it came from a finger or a mouse (IntentInput asks handle_tap first).

signal option_chosen(option: InteractionOption)
signal dismissed

var camera: Camera3D:
	set(value):
		camera = value
		if _stack != null:
			_stack.camera = value

var _stack: PlaqueStack
var _options: Array[InteractionOption] = []

func _ready() -> void:
	_stack = PlaqueStack.new()
	_stack.name = "Plaques"
	_stack.camera = camera
	_stack.chosen.connect(_on_chosen)
	add_child(_stack)

func is_open() -> bool:
	return _stack != null and _stack.is_open()

func current_options() -> Array[InteractionOption]:
	return _options

# `title` is what is being pointed at, already translated (an object name from the text table).
# `anchor` is where it is in the world; the plaques hang beside it on the roomier side.
func show_options(title: String, options: Array[InteractionOption], anchor: Vector3 = Vector3.INF) -> void:
	_options = options
	var labels: Array[String] = []
	for option in options:
		labels.append(option.label)
	labels.append(tr("ui.never_mind"))
	var viewport_size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(480, 360)
	var anchor_px := Vector2(viewport_size.x * 0.5, viewport_size.y * 0.6)
	if camera != null and anchor.is_finite():
		anchor_px = camera.unproject_position(anchor)
	_stack.camera = camera
	_stack.open(title.substr(0, 1).to_upper() + title.substr(1), labels, anchor_px, false, false, true)

func close() -> void:
	if is_open():
		_stack.close()
		_options = []
		dismissed.emit()

func choose(index: int) -> void:
	_on_chosen(index)

# True when the tap landed on a plaque (the choice itself follows after a short press animation).
func handle_tap(px: Vector2) -> bool:
	return _stack != null and _stack.handle_tap(px)

func hover(px: Vector2) -> void:
	if _stack != null:
		_stack.hover(px)

func _on_chosen(index: int) -> void:
	if not is_open():
		return
	if index == _options.size():
		close()
		return
	if index < 0 or index >= _options.size():
		return
	var option := _options[index]
	_stack.close()
	_options = []
	option_chosen.emit(option)

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		var index: int = key_event.keycode - KEY_1
		if index >= 0 and index < _options.size():
			choose(index)
			get_viewport().set_input_as_handled()
