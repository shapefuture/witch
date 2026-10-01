class_name IntentInput
extends Node

# Translates raw pointer events (mouse OR touch) into PlayerIntents. Everything downstream
# sees only intents, never InputEvents.

signal intent_emitted(intent: PlayerIntent)

const MOUSE_ID := -1

# func(screen_position: Vector2) -> Dictionary
#   {"target_id": String ("" if none), "ground": Vector3 (valid when has_ground)}, "has_ground": bool
var picker: Callable
# func(screen_position: Vector2) -> bool: true when something else (an option plaque) took the tap.
var intercept: Callable
var enabled := true
var tracker := PointerTracker.new()
# Injectable clock so tests are deterministic.
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0

func _unhandled_input(event: InputEvent) -> void:
	var intent := handle_event(event)
	if intent != null:
		get_viewport().set_input_as_handled()

# Returns the intent produced by this event (also emitted), or null.
func handle_event(event: InputEvent) -> PlayerIntent:
	if not enabled:
		return null
	var now: float = clock.call()
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		# A touch also arrives as an emulated mouse click (for UI controls). The touch event is
		# handled natively below; counting the emulated click too would double every tap.
		if mouse.device == InputEvent.DEVICE_ID_EMULATION:
			return null
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				tracker.press(MOUSE_ID, mouse.position, now)
				return null
			return _finish(tracker.release(MOUSE_ID, mouse.position, now), "mouse")
		if mouse.button_index == MOUSE_BUTTON_RIGHT and not mouse.pressed:
			return _emit(PlayerIntent.cancel("mouse"))
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			tracker.press(touch.index, touch.position, now)
			return null
		return _finish(tracker.release(touch.index, touch.position, now), "touch")
	elif event is InputEventScreenDrag:
		# Movement beyond the slop is detected at release from the start position.
		return null
	return null

func _finish(tap: Variant, source: String) -> PlayerIntent:
	if tap == null or not picker.is_valid():
		return null
	if intercept.is_valid() and intercept.call(tap):
		return null
	var hit: Dictionary = picker.call(tap)
	var target_id := str(hit.get("target_id", ""))
	if not target_id.is_empty():
		return _emit(PlayerIntent.inspect(target_id, hit.get("ground", Vector3.ZERO), source))
	if hit.get("has_ground", false):
		return _emit(PlayerIntent.move_to(hit["ground"], source))
	return null

func _emit(intent: PlayerIntent) -> PlayerIntent:
	intent_emitted.emit(intent)
	return intent
