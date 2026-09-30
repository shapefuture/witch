class_name PresentationDirector
extends RefCounted

# Plays the presentation entries of a COMMITTED result, strictly in order, each awaited to
# completion. Entries are authored in the Mirror catalog ("camera", "line", "dialogue", "anim",
# "npc", "magic", "leave_frame", "wait"); handlers are registered by whoever owns the matching
# capability (subtitles, camera, actors), so this class knows none of them.

# kind -> Callable(entry: Dictionary) -> void (may be a coroutine)
var handlers: Dictionary = {}
# Kinds that arrived with no handler. Surfaced so a typo in content is found, not silently skipped.
var unhandled: Array[String] = []
var played: Array[String] = []

func register(kind: String, handler: Callable) -> void:
	handlers[kind] = handler

func play(entries: Array) -> void:
	for entry in entries:
		var kind := str(entry.get("kind", ""))
		if not handlers.has(kind):
			unhandled.append(kind)
			push_warning("PresentationDirector: no handler for '%s'" % kind)
			continue
		played.append(kind)
		await handlers[kind].call(entry)
