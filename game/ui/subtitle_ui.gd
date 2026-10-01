class_name SubtitleUI
extends Node3D

# Dialogue and narration as speech bubbles hung in the scene next to whoever is talking (see
# SpeechBubble): a typewriter with a per-speaker blip. One tap (or click, or Enter) completes the
# line being typed; the next tap dismisses it. show_line() is awaitable, so the presentation
# director simply waits for the player.

signal line_finished
signal active_changed(active: bool)

const CHAR_INTERVAL := 0.03
const BLIP_RATE := 11025.0
const BLIP_DURATION := 0.05
const BLIP_FREQ := 520.0

# >= 0: the line advances by itself this many seconds after it finishes typing. Used by the
# headless capture mode and tests; the shipped game leaves it at -1 (the player advances).
var auto_advance_delay := -1.0
# Speaker id -> blip pitch. Narration (no speaker) is silent.
var voice_pitch := {"tomas": 0.78}
# The camera the bubble is placed against, and where each speaker's head is: func(id) -> Vector3.
var camera: Camera3D
var anchor_provider: Callable
# func() -> Array of screen Rect2s: what the picture is about right now, kept clear of the bubble.
var hero_provider: Callable

var _bubble: SpeechBubble
var _audio: AudioStreamPlayer
var _timer: Timer
var _full := ""
var _shown := 0
var _typing := false
var _active := false
var _pitch := 1.0

func _ready() -> void:
	_bubble = SpeechBubble.new()
	_bubble.name = "SpeechBubble"
	add_child(_bubble)
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

func bubble() -> SpeechBubble:
	return _bubble

# Shows one line and resolves when the player dismisses it.
func show_line(speaker: String, text: String, speaker_id: String = "") -> void:
	_full = text
	_shown = 0
	_typing = true
	_pitch = float(voice_pitch.get(speaker_id, 0.0))
	var anchor := Vector3.ZERO
	if anchor_provider.is_valid():
		anchor = anchor_provider.call(speaker_id)
	_bubble.camera = camera
	var heroes: Array = hero_provider.call() if hero_provider.is_valid() else []
	_bubble.present(speaker, text, anchor, speaker.is_empty(), heroes)
	_full = _bubble.wrapped_text()
	_bubble.set_shown(0)
	_bubble.set_prompt(false)
	_set_active(true)
	_timer.start()
	await line_finished

func _on_tick() -> void:
	if _shown >= _full.length():
		_finish_typing()
		return
	_shown += 1
	_bubble.set_shown(_shown)
	if _pitch > 0.0 and _full[_shown - 1] != " ":
		_blip()

func _finish_typing() -> void:
	_timer.stop()
	_bubble.show_all()
	_typing = false
	_bubble.set_prompt(true)
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
	_bubble.dismiss()
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
