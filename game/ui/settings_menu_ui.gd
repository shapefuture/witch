class_name SettingsMenuUI
extends Node3D

# The game has a single language, so settings are sound and accessibility. Two pages of plaques over
# the veil: the main page (sound, text size, screen effects, back) and the volume page (quieter, louder,
# back). A row that shows a value is rebuilt when it changes, so a new text size is seen at once.

signal closed

const STEP := 0.1
enum Page { MAIN, VOLUME }

var camera: Camera3D
var _stack: PlaqueStack
var _page := Page.MAIN

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stack = PlaqueStack.new()
	_stack.process_mode = Node.PROCESS_MODE_ALWAYS
	_stack.camera = camera
	_stack.upright = false
	_stack.chosen.connect(_on_chosen)
	add_child(_stack)
	_show(Page.MAIN)

func page() -> Page:
	return _page

func stack() -> PlaqueStack:
	return _stack

func _show(which: Page) -> void:
	_page = which
	if which == Page.VOLUME:
		var labels: Array[String] = [tr("ui.volume_down"), tr("ui.volume_up"), tr("ui.back")]
		_stack.open(_volume_title(), labels, Vector2.ZERO, true, true, true)
	else:
		var text := "%s: %d%%" % [tr("ui.text_size"), roundi(SettingsState.text_scale * 100.0)]
		var effects := "%s: %s" % [tr("ui.effects"), tr("ui.effects_reduced") if SettingsState.reduced_effects else tr("ui.effects_full")]
		var labels: Array[String] = [tr("ui.sound"), text, effects, tr("ui.back")]
		_stack.open(tr("ui.settings"), labels, Vector2.ZERO, true, true, true)

func _volume_title() -> String:
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
	if _page == Page.VOLUME:
		match index:
			0:
				SettingsState.set_master_volume(SettingsState.master_volume - STEP)
				_stack.set_title(_volume_title())
			1:
				SettingsState.set_master_volume(SettingsState.master_volume + STEP)
				_stack.set_title(_volume_title())
			2:
				_show(Page.MAIN)
		return
	match index:
		0:
			_show(Page.VOLUME)
		1:
			SettingsState.cycle_text_scale()
			_show(Page.MAIN)
		2:
			SettingsState.set_reduced_effects(not SettingsState.reduced_effects)
			_show(Page.MAIN)
		3:
			closed.emit()
			queue_free()
