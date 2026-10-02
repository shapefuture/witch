class_name MindsState
extends RefCounted

# Everything the Minds layer keeps between events: who is where, the deferred-effects queue, the folklore
# book, and whether the starting beliefs have been written. ALL of it is derived from the Mirror event log:
# `apply()` is the only way it changes, it reads nothing but a committed event's payload, and a rebuild is
# `reset()` followed by `apply()` over the whole log. Live play uses the same path, so a loaded save, a
# replay and a run that never stopped cannot disagree.

var seeded := false
var presence: Dictionary = {}
var queue := ConsequenceQueue.new()
var conventions := ConventionBook.new()

func reset(data: Dictionary) -> void:
	seeded = false
	presence = {}
	for holder in data.get("holders", {}).keys():
		presence[holder] = str(data["holders"][holder].get("place", ""))
	queue.reset()
	conventions.reset()

func apply(event: MirrorEvent) -> void:
	if event.event_type != "WorldEventHappened":
		return
	var payload: Dictionary = event.payload
	if bool(payload.get("seed", false)):
		seeded = true
	if payload.has("presence"):
		var change: Dictionary = payload["presence"]
		presence[str(change.get("holder", ""))] = str(change.get("place", ""))
	for id in payload.get("cancelled", []):
		queue.remove(str(id))
	for id in payload.get("fired", []):
		queue.remove(str(id))
	for entry in payload.get("scheduled", []):
		queue.add(entry)
	conventions.apply_updates(payload.get("convention_updates", []))
