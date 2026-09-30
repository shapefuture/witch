class_name MirrorEventStore
extends RefCounted

signal events_appended(events: Array)

var max_events: int = 100000
var _events: Array[MirrorEvent] = []
var _head_hash := "GENESIS"
var _next_sequence := 1
var _by_id: Dictionary = {}
var _by_transaction: Dictionary = {}
# Set while a caller is running a speculative resolution (see MirrorEngine.preview_action).
# Appending a bundle with emit_signal=true is not the same as announcing a durable commit,
# so both emitters have to be muted explicitly or listeners observe rolled-back events.
# Runtime-only: deliberately absent from to_dict() so it can never reach a save file.
var suppress_signal := false
var last_error := ""

func _init(p_max_events: int = 100000): max_events = maxi(1, p_max_events)
func size() -> int: return _events.size()
func head_hash() -> String: return _head_hash
func next_sequence() -> int: return _next_sequence
func get_all() -> Array[MirrorEvent]: return _events.duplicate()
func get_by_id(event_id: String) -> MirrorEvent: return _by_id.get(event_id, null)

func append(event: MirrorEvent) -> bool: return append_bundle([event], true)

func append_bundle(events: Array[MirrorEvent], emit_signal: bool = true) -> bool:
    last_error = ""
    if events.is_empty(): return true
    if _events.size() + events.size() > max_events: last_error = "capacity_exceeded"; return false
    var expected_sequence := _next_sequence
    var seen_ids: Dictionary = _by_id.duplicate()
    var bundle_transaction_id := ""
    for event in events:
        if event == null or event.event_id.is_empty(): last_error = "invalid_event"; return false
        if seen_ids.has(event.event_id): last_error = "duplicate_event_id"; return false
        if event.sequence not in [0, expected_sequence]: last_error = "invalid_sequence"; return false
        if bundle_transaction_id.is_empty():
            bundle_transaction_id = event.transaction_id
            if events.size() > 1 and bundle_transaction_id.is_empty(): last_error = "missing_transaction_id"; return false
        elif event.transaction_id != bundle_transaction_id: last_error = "mixed_transaction_id"; return false
        seen_ids[event.event_id] = true
        expected_sequence += 1
    expected_sequence = _next_sequence
    var expected_prev := _head_hash
    for event in events:
        event.sequence = expected_sequence
        event.prev_hash = expected_prev
        event.schema_version = MirrorDomain.SCHEMA_VERSION
        event.finalize()
        expected_prev = event.hash
        expected_sequence += 1
    for event in events:
        _events.append(event)
        _by_id[event.event_id] = event
        var tx := event.transaction_id
        if not tx.is_empty():
            var tx_events: Array = _by_transaction.get(tx, [])
            tx_events.append(event)
            _by_transaction[tx] = tx_events
    _head_hash = expected_prev; _next_sequence = expected_sequence
    if emit_signal and not suppress_signal: events_appended.emit(events)
    return true

func publish(events: Array[MirrorEvent]) -> bool:
    if events.is_empty(): return true
    if events.size() > _events.size(): return false
    var offset := _events.size() - events.size()
    for i in events.size():
        if _events[offset + i] != events[i]: return false
    if not suppress_signal: events_appended.emit(events)
    return true

func get_transaction(transaction_id: String) -> Array[MirrorEvent]:
    var out: Array[MirrorEvent] = []
    if transaction_id.is_empty():
        return out
    for event in _by_transaction.get(transaction_id, []):
        out.append(event)
    return out

# Full audit: re-hashes every event. O(n) in the log, so it belongs on load / explicit
# audit, NOT on every commit (see verify_tail).
func verify_chain() -> Dictionary:
    return _verify_from(0)

# Re-hashes only the last `count` events and checks they link to their predecessor.
# Committing appends events that were finalised a moment earlier, so re-verifying the
# untouched prefix on every transaction made each action cost O(log size) in SHA-256
# work (~215 ms at 900 events, i.e. 87% of the transaction) for no added safety.
func verify_tail(count: int) -> Dictionary:
    return _verify_from(maxi(0, _events.size() - maxi(0, count)))

func _verify_from(start: int) -> Dictionary:
    var expected_prev := "GENESIS" if start == 0 else _events[start - 1].hash
    var expected_sequence := 1 if start == 0 else _events[start - 1].sequence + 1
    var seen: Dictionary = {}
    for i in range(start, _events.size()):
        var event := _events[i]
        if event.sequence != expected_sequence: return {"ok": false, "error": "sequence_gap", "event_id": event.event_id}
        if event.prev_hash != expected_prev: return {"ok": false, "error": "prev_hash_mismatch", "event_id": event.event_id}
        var original_hash := event.hash; event.finalize()
        if event.hash != original_hash:
            event.hash = original_hash
            return {"ok": false, "error": "hash_mismatch", "event_id": event.event_id}
        if seen.has(event.event_id): return {"ok": false, "error": "duplicate_event_id", "event_id": event.event_id}
        seen[event.event_id] = true; expected_prev = event.hash; expected_sequence += 1
    if _head_hash != expected_prev: return {"ok": false, "error": "head_hash_mismatch"}
    if _next_sequence != expected_sequence: return {"ok": false, "error": "next_sequence_mismatch"}
    return {"ok": true, "count": _events.size(), "head_hash": _head_hash}

func tail(count: int) -> Array[MirrorEvent]:
    var out: Array[MirrorEvent] = []
    for i in range(maxi(0, _events.size() - maxi(0, count)), _events.size()):
        out.append(_events[i])
    return out

# Drops every event after the first `count`. The store is append-only, so this is an exact
# inverse of the append that a failed transaction performed; it replaces rebuilding the
# whole store from a serialised copy (which re-hashed the entire log on every rollback,
# including every preview_action).
func truncate_to(count: int) -> bool:
    if count < 0 or count > _events.size(): return false
    if count == _events.size(): return true
    for i in range(count, _events.size()):
        var event := _events[i]
        _by_id.erase(event.event_id)
        var tx := event.transaction_id
        if not tx.is_empty() and _by_transaction.has(tx):
            var remaining: Array = []
            for candidate in _by_transaction[tx]:
                if candidate != event: remaining.append(candidate)
            if remaining.is_empty(): _by_transaction.erase(tx)
            else: _by_transaction[tx] = remaining
    _events.resize(count)
    _head_hash = "GENESIS" if count == 0 else _events[count - 1].hash
    _next_sequence = 1 if count == 0 else _events[count - 1].sequence + 1
    return true

func to_dict() -> Dictionary:
    var event_data: Array = []
    for event in _events: event_data.append(event.to_dict())
    return {"max_events": max_events, "head_hash": _head_hash, "next_sequence": _next_sequence, "events": event_data}

func restore_from_dict(data: Dictionary) -> bool:
    last_error = ""
    if not data.get("events", []) is Array: last_error = "invalid_event_payload"; return false
    var incoming: Array = data.get("events", [])
    var candidate_max := maxi(1, int(data.get("max_events", max_events)))
    if incoming.size() > candidate_max: last_error = "capacity_exceeded"; return false
    var new_events: Array[MirrorEvent] = []; var previous := "GENESIS"; var expected_sequence := 1; var seen: Dictionary = {}
    for raw in incoming:
        if not raw is Dictionary or not MirrorEvent.validate_dict(raw).is_empty(): last_error = "invalid_event_payload"; return false
        var event := MirrorEvent.from_dict(raw)
        if event == null: last_error = "invalid_event_payload"; return false
        if event.event_id.is_empty() or seen.has(event.event_id): last_error = "duplicate_event_id"; return false
        if event.sequence != expected_sequence: last_error = "invalid_sequence"; return false
        if event.prev_hash != previous: last_error = "prev_hash_mismatch"; return false
        var provided_hash := event.hash
        if provided_hash.is_empty(): last_error = "missing_hash"; return false
        event.finalize()
        if event.hash != provided_hash: last_error = "hash_mismatch"; return false
        seen[event.event_id] = true; previous = event.hash; expected_sequence += 1; new_events.append(event)
    if str(data.get("head_hash", previous)) != previous: last_error = "head_hash_mismatch"; return false
    if int(data.get("next_sequence", expected_sequence)) != expected_sequence: last_error = "next_sequence_mismatch"; return false
    max_events = candidate_max
    _events = new_events
    _by_id = {}
    _by_transaction = {}
    for event in _events:
        _by_id[event.event_id] = event
        var tx := event.transaction_id
        if not tx.is_empty():
            var tx_events: Array = _by_transaction.get(tx, [])
            tx_events.append(event)
            _by_transaction[tx] = tx_events
    _head_hash = previous
    _next_sequence = expected_sequence
    return true

static func from_dict(data: Dictionary) -> MirrorEventStore:
    var store := MirrorEventStore.new(int(data.get("max_events", 100000)))
    if not store.restore_from_dict(data): return MirrorEventStore.new(int(data.get("max_events", 100000)))
    return store
