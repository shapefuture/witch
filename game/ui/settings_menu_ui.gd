class_name SettingsMenuUI
extends CanvasLayer

# Volume, and nothing else: the game has a single language.

signal closed

var _title: Label
var _volume_label: Label
var _slider: HSlider
var _back: Button

func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.size = Vector2(320, 240)
	add_child(dim)
	_title = UIKit.label(tr("ui.settings"), UIKit.TITLE_SIZE)
	_title.position = Vector2(0, 32)
	_title.size = Vector2(320, 24)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_volume_label = UIKit.label(tr("ui.volume"))
	_volume_label.position = Vector2(60, 100)
	add_child(_volume_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.05
	_slider.value = SettingsState.master_volume
	_slider.position = Vector2(60, 116)
	_slider.size = Vector2(200, 16)
	_slider.value_changed.connect(SettingsState.set_master_volume)
	add_child(_slider)
	_back = UIKit.button(tr("ui.back"))
	_back.position = Vector2(110, 180)
	_back.size = Vector2(100, 18)
	_back.pressed.connect(_on_back)
	add_child(_back)

func _on_back() -> void:
	closed.emit()
	queue_free()
