class_name SubtitleUI
extends CanvasLayer

# Bottom-of-screen subtitles: a typewriter with a per-speaker blip. One tap (or click, or
# Enter) completes the line being typed; the next tap dismisses it. show_line() is awaitable,
# so the presentation director simply waits for the player.

signal line_finished
signal active_changed(active: bool)

const CHAR_INTERVAL := 0.03
const BLIP_RATE := 11025.0
const BLIP_DURATION := 0.05
const BLIP_FREQ := 520.0
const PANEL_POSITION := Vector2(8, 184)
const PANEL_SIZE := Vector2(304, 50)

# >= 0: the line advances by itself this many seconds after it finishes typing. Used by the
# headless capture mode and tests; the shipped game leaves it at -1 (the player advances).
var auto_advance_delay := -1.0
# Speaker id -> blip pitch. Narration (no speaker) is silent.
var voice_pitch := {"tomas": 0.78}

var _panel: PanelContainer
var _speaker: Label
var _text: Label
var _prompt: Label
var _audio: AudioStreamPlayer
var _timer: Timer
var _full := ""
var _shown := 0
var _typing := false
var _active := false
var _pitch := 1.0

func _ready() -> void:
	layer = 5
	_panel = PanelContainer.new()
	_panel.position = PANEL_POSITION
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.size = PANEL_SIZE
	_panel.add_theme_stylebox_override("panel", UIKit.panel_style())
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_speaker = UIKit.label("", UIKit.FONT_SIZE, UIKit.ACCENT)
	column.add_child(_speaker)
	_text = UIKit.label("", UIKit.FONT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text)
	_prompt = UIKit.label("▼", UIKit.FONT_SIZE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.visible = false
	column.add_child(_prompt)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = BLIP_RATE
	generator.buffer_length = BLIP_DURATION + 0.02
	_audio = AudioStreamPlayer.new()
	_audio.stream = generator
	_audio.volume_db = -10.0
	add_child(_audio)
	_timer = Timer.new()
	_timer.wait_time = CHAR_INTERVAL
	_timer.timeout.connect(_on_tick)
	add_child(_timer)

func is_active() -> bool:
	return _active

# Shows one line and resolves when the player dismisses it.
func show_line(speaker: String, text: String, speaker_id: String = "") -> void:
	_full = text
	_shown = 0
	_typing = true
	_pitch = float(voice_pitch.get(speaker_id, 0.0))
	_speaker.text = speaker
	_speaker.visible = not speaker.is_empty()
	UIKit.style_label(_text, UIKit.FONT_SIZE, Color.WHITE if not speaker.is_empty() else Color(0.78, 0.82, 0.95))
	_text.text = ""
	_prompt.visible = false
	_panel.visible = true
	_set_active(true)
	_timer.start()
	await line_finished

func _on_tick() -> void:
	if _shown >= _full.length():
		_finish_typing()
		return
	_shown += 1
	_text.text = _full.substr(0, _shown)
	if _pitch > 0.0 and _full[_shown - 1] != " ":
		_blip()

func _finish_typing() -> void:
	_timer.stop()
	_text.text = _full
	_typing = false
	_prompt.visible = true
	if auto_advance_delay >= 0.0:
		await get_tree().create_timer(auto_advance_delay).timeout
		if _active and not _typing:
			_dismiss()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	var pressed := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		pressed = true
	if pressed:
		advance()
		get_viewport().set_input_as_handled()

# First call completes the typing; the second dismisses the line.
func advance() -> void:
	if not _active:
		return
	if _typing:
		_finish_typing()
	else:
		_dismiss()

func _dismiss() -> void:
	_timer.stop()
	_panel.visible = false
	_prompt.visible = false
	_set_active(false)
	line_finished.emit()

func _set_active(value: bool) -> void:
	if _active != value:
		_active = value
		active_changed.emit(value)

func _blip() -> void:
	_audio.play()
	var playback := _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := int(BLIP_RATE * BLIP_DURATION)
	var frequency := BLIP_FREQ * _pitch * randf_range(0.94, 1.06)
	for i in frames:
		var envelope := pow(1.0 - float(i) / frames, 0.4)
		var wave := 1.0 if sin(TAU * frequency * float(i) / BLIP_RATE) >= 0.0 else -1.0
		playback.push_frame(Vector2.ONE * wave * envelope * 0.4)
