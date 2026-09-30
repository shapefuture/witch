class_name PauseMenuUI
extends CanvasLayer

# Esc (or the pause action) opens it; the tree pauses, so nothing in the world moves. Save and
# load go through Mirror's save layer: the file is primarily MirrorState.

signal load_requested
signal save_requested
signal quit_requested

const SLOT := 1

var _open := false
var _status: Label
var _settings: CanvasLayer

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.size = Vector2(320, 240)
	add_child(dim)
	var title := UIKit.label(tr("ui.paused"), UIKit.TITLE_SIZE)
	title.position = Vector2(0, 28)
	title.size = Vector2(320, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var y := 68.0
	for entry in [["ui.resume", close], ["ui.save", _on_save], ["ui.load", _on_load], ["ui.settings", _on_settings], ["ui.quit", _on_quit]]:
		var button := UIKit.button(tr(entry[0]))
		button.position = Vector2(100, y)
		button.size = Vector2(120, 18)
		button.pressed.connect(entry[1])
		add_child(button)
		y += 24.0
	_status = UIKit.label("", UIKit.FONT_SIZE, UIKit.ACCENT)
	_status.position = Vector2(0, 204)
	_status.size = Vector2(320, 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()

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
	_status.text = ""
	get_tree().paused = true

func close() -> void:
	_open = false
	visible = false
	get_tree().paused = false

func say(text: String) -> void:
	_status.text = text

func _on_save() -> void:
	save_requested.emit()

func _on_load() -> void:
	load_requested.emit()

func _on_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsMenuUI.new()
	add_child(_settings)
	_settings.tree_exited.connect(func() -> void: _settings = null)

func _on_quit() -> void:
	quit_requested.emit()
