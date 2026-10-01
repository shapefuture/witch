class_name PauseMenuUI
extends Node3D

# Esc (or the pause action) opens it; the tree pauses, so nothing in the world moves. Save and
# load go through Mirror's save layer: the file is primarily MirrorState. The menu is a stack of
# carved plaques over a dark veil, like the options (see PlaqueStack).

signal load_requested
signal save_requested
signal quit_requested

const SLOT := 1

var camera: Camera3D:
	set(value):
		camera = value
		if _stack != null:
			_stack.camera = value

var _open := false
var _status := ""
var _stack: PlaqueStack
var _settings: SettingsMenuUI

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_stack = PlaqueStack.new()
	_stack.name = "Plaques"
	_stack.process_mode = Node.PROCESS_MODE_ALWAYS
	_stack.camera = camera
	_stack.upright = false
	_stack.chosen.connect(_on_chosen)
	add_child(_stack)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not _open or _settings != null:
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and not mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.device != InputEvent.DEVICE_ID_EMULATION:
		_stack.handle_tap(mouse.position)
	var touch := event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		_stack.handle_tap(touch.position)
	var motion := event as InputEventMouseMotion
	if motion != null:
		_stack.hover(motion.position)

func is_open() -> bool:
	return _open

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	_open = true
	visible = true
	_status = ""
	get_tree().paused = true
	_show()

func close() -> void:
	_open = false
	visible = false
	_stack.close()
	if _settings != null:
		_settings.queue_free()
		_settings = null
	get_tree().paused = false

func say(text: String) -> void:
	_status = text
	if _open:
		_stack.set_title(text if not text.is_empty() else tr("ui.paused"))

func _show() -> void:
	var labels: Array[String] = [tr("ui.resume"), tr("ui.save"), tr("ui.load"), tr("ui.settings"), tr("ui.quit")]
	_stack.camera = camera
	_stack.open(tr("ui.paused"), labels, Vector2.ZERO, true, true, false)

func _on_chosen(index: int) -> void:
	match index:
		0:
			close()
		1:
			save_requested.emit()
		2:
			load_requested.emit()
		3:
			_on_settings()
		4:
			quit_requested.emit()

func _on_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsMenuUI.new()
	_settings.camera = camera
	add_child(_settings)
	_stack.visible = false
	_settings.tree_exited.connect(func() -> void:
		_settings = null
		if _open:
			_stack.visible = true)
