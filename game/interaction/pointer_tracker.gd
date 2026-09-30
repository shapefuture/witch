class_name PointerTracker
extends RefCounted

# Decides whether a press/release pair is a TAP. Shared by mouse and touch so both obey the
# same slop and timing rules; a drag or a second finger is never a tap.

const TAP_SLOP_PX := 12.0
const TAP_MAX_SEC := 0.45

var _down: Dictionary = {}
var _poisoned := false

func press(pointer_id: int, position: Vector2, time: float) -> void:
	if not _down.is_empty():
		# A second pointer means a gesture (pinch / two-finger drag), not a tap.
		_poisoned = true
	_down[pointer_id] = {"position": position, "time": time}

# Returns the tap position, or null when the gesture was not a tap.
func release(pointer_id: int, position: Vector2, time: float) -> Variant:
	var start: Variant = _down.get(pointer_id)
	_down.erase(pointer_id)
	# A pinch poisons every pointer that took part in it, including the one that lifts first
	# while the other is still down; the flag only clears once all pointers are up.
	var was_poisoned := _poisoned
	if _down.is_empty():
		_poisoned = false
	if was_poisoned or start == null:
		return null
	if position.distance_to(start["position"]) > TAP_SLOP_PX:
		return null
	if time - float(start["time"]) > TAP_MAX_SEC:
		return null
	return start["position"]

func cancel_all() -> void:
	_down.clear()
	_poisoned = false
