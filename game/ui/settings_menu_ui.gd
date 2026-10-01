class_name SettingsMenuUI
extends Node3D

# Volume, and nothing else: the game has a single language. Three plaques over the veil.

signal closed

const STEP := 0.1

var camera: Camera3D
var _stack: PlaqueStack

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stack = PlaqueStack.new()
	_stack.process_mode = Node.PROCESS_MODE_ALWAYS
	_stack.camera = camera
	_stack.chosen.connect(_on_chosen)
	add_child(_stack)
	var labels: Array[String] = [tr("ui.volume_down"), tr("ui.volume_up"), tr("ui.back")]
	_stack.open(_title(), labels, Vector2.ZERO, true, true, true)

func _title() -> String:
	return "%s: %d%%" % [tr("ui.volume"), roundi(SettingsState.master_volume * 100.0)]

func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and not mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.device != InputEvent.DEVICE_ID_EMULATION:
		_stack.handle_tap(mouse.position)
	var touch := event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		_stack.handle_tap(touch.position)
	var motion := event as InputEventMouseMotion
	if motion != null:
		_stack.hover(motion.position)

func _on_chosen(index: int) -> void:
	match index:
		0:
			SettingsState.set_master_volume(SettingsState.master_volume - STEP)
			_stack.set_title(_title())
		1:
			SettingsState.set_master_volume(SettingsState.master_volume + STEP)
			_stack.set_title(_title())
		2:
			closed.emit()
			queue_free()
