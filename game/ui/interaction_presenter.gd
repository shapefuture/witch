class_name InteractionPresenter
extends CanvasLayer

# The contextual action surface: a short list of natural-language options for whatever the
# player tapped. It renders InteractionOption.label and NOTHING else; the ontology never
# reaches the screen. Buttons are real Controls, so touch and mouse both work, and they are
# sized for a finger (a 16px row is ~70px on a 1080p screen).

signal option_chosen(option: InteractionOption)
signal dismissed

const PANEL_WIDTH := 300.0
const ROW_MIN_HEIGHT := 16.0

var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _options: Array[InteractionOption] = []

func _ready() -> void:
	layer = 4
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.panel_style())
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.visible = false
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_panel.add_child(column)
	_title = UIKit.label("", UIKit.FONT_SIZE, UIKit.ACCENT)
	column.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	column.add_child(_list)

func is_open() -> bool:
	return _panel != null and _panel.visible

func current_options() -> Array[InteractionOption]:
	return _options

# `title` is what is being pointed at, already translated (an object name from the text table).
func show_options(title: String, options: Array[InteractionOption]) -> void:
	_options = options
	_title.text = title.substr(0, 1).to_upper() + title.substr(1)
	for child in _list.get_children():
		child.queue_free()
		_list.remove_child(child)
	for i in range(options.size()):
		var button := UIKit.button(options[i].label)
		button.custom_minimum_size = Vector2(PANEL_WIDTH - 10.0, ROW_MIN_HEIGHT)
		button.pressed.connect(_on_pressed.bind(i))
		_list.add_child(button)
	var cancel := UIKit.button(tr("ui.never_mind"))
	cancel.custom_minimum_size = Vector2(PANEL_WIDTH - 10.0, ROW_MIN_HEIGHT)
	cancel.pressed.connect(close)
	_list.add_child(cancel)
	_panel.visible = true
	_panel.reset_size()
	# Bottom-centre, above the subtitle strip's resting place.
	_panel.position = Vector2((320.0 - _panel.size.x) * 0.5, 236.0 - _panel.size.y)

func close() -> void:
	if is_open():
		_panel.visible = false
		_options = []
		dismissed.emit()

func choose(index: int) -> void:
	_on_pressed(index)

func _on_pressed(index: int) -> void:
	if index < 0 or index >= _options.size():
		return
	var option := _options[index]
	_panel.visible = false
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
