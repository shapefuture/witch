class_name ActionQueue
extends RefCounted

# Serialises consequential actions so that two never interleave.
#
# Each entry is resolved (an atomic Mirror transaction) and then PRESENTED to completion before
# the next one starts. This is what prevents "dialogue starts -> another action changes state
# -> the object vanishes -> half the dialogue fires anyway": presentation is driven only from a
# committed result, and nothing else can commit while it plays.

signal started(action: MirrorAction)
signal finished(result: Dictionary)
signal idle

# func(action: MirrorAction) -> Dictionary     (the committed or failed result)
var resolver: Callable
# func(result: Dictionary) -> void             (may be a coroutine; awaited to completion)
var presenter: Callable

var _pending: Array[MirrorAction] = []
var _running := false

func is_busy() -> bool:
	return _running

func pending_count() -> int:
	return _pending.size()

func enqueue(action: MirrorAction) -> void:
	_pending.append(action)
	if not _running:
		_pump()

func _pump() -> void:
	_running = true
	while not _pending.is_empty():
		var action: MirrorAction = _pending.pop_front()
		started.emit(action)
		var result: Dictionary = resolver.call(action)
		if result.get("ok", false) and presenter.is_valid():
			await presenter.call(result)
		finished.emit(result)
	_running = false
	idle.emit()
