class_name ConsequenceQueue
extends RefCounted

# The deferred-effects queue: what the world will do once time has passed ("the pigeon is on another roof
# when you come back"). Derived state: it is rebuilt from the event log and never saved on its own, so it
# cannot drift from the history, cannot be forged, and cannot touch the catalog fingerprint.
#
# An entry is {id, due, event, origin, slot, when}. `event` is a world-event spec exactly like the ones
# MirrorMinds.perceive() takes; `due` is a point on the Mirror clock; ids ("c1", "c2", ...) are issued in
# the order entries were scheduled, which is also the tie-break between entries due at the same time. That
# (due, id) order is the whole determinism contract: advancing the clock in one step or in many fires the
# same entries in the same order.

var _entries: Dictionary = {}
var _next_seq := 1

func reset() -> void:
	_entries = {}
	_next_seq = 1

func size() -> int:
	return _entries.size()

func has(id: String) -> bool:
	return _entries.has(id)

func get_entry(id: String) -> Dictionary:
	var entry: Dictionary = _entries.get(id, {})
	return entry.duplicate(true)

# The id the next scheduled entry will get (used to number a batch before it is committed).
func next_id(offset: int = 0) -> String:
	return "c%d" % (_next_seq + offset)

func add(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if id.is_empty():
		return
	_entries[id] = entry.duplicate(true)
	_next_seq = maxi(_next_seq, _sequence_of(id) + 1)

func remove(id: String) -> void:
	_entries.erase(id)

# Everything pending, in firing order.
func pending() -> Array:
	var out: Array = []
	for entry in _entries.values():
		out.append(entry.duplicate(true))
	out.sort_custom(ConsequenceQueue.earlier)
	return out

func due(now: int) -> Array:
	var out: Array = []
	for entry in pending():
		if int(entry.get("due", 0)) <= now:
			out.append(entry)
	return out

func in_slot(slot: String) -> Array:
	var out: Array = []
	if slot.is_empty():
		return out
	for entry in pending():
		if str(entry.get("slot", "")) == slot:
			out.append(entry)
	return out

static func earlier(a: Dictionary, b: Dictionary) -> bool:
	var da := int(a.get("due", 0))
	var db := int(b.get("due", 0))
	if da == db:
		return _sequence_of(str(a.get("id", ""))) < _sequence_of(str(b.get("id", "")))
	return da < db

static func _sequence_of(id: String) -> int:
	return int(id.substr(1)) if id.length() > 1 else 0
