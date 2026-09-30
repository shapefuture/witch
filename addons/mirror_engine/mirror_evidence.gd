class_name MirrorEvidenceStore
extends RefCounted

var _items: Dictionary = {}
var _by_event: Dictionary = {}
var last_error := ""

func record(evidence_id: String, evidence_type: int, holder_id: String, source: String, source_event: String, payload: Dictionary = {}) -> Dictionary:
    last_error = ""
    if evidence_id.is_empty():
        last_error = "empty_id"
        return {}
    var existing: Dictionary = _items.get(evidence_id, {})
    var item := {
        "id": evidence_id,
        "type": evidence_type,
        "holder_id": holder_id,
        "source": source,
        "source_event": source_event,
        "payload": payload.duplicate(true),
    }
    if not existing.is_empty():
        var existing_body := {
            "id": existing.get("id", ""),
            "type": existing.get("type", 0),
            "holder_id": existing.get("holder_id", ""),
            "source": existing.get("source", ""),
            "source_event": existing.get("source_event", ""),
            "payload": existing.get("payload", {}),
        }
        if MirrorHash.canonical_json(existing_body) != MirrorHash.canonical_json(item):
            last_error = "evidence_conflict"
            return {}
    _items[evidence_id] = item
    if not source_event.is_empty():
        var ids: Array = _by_event.get(source_event, [])
        if evidence_id not in ids: ids.append(evidence_id)
        _by_event[source_event] = ids
    return item.duplicate(true)

func ensure_event_evidence(event_id: String, holder_id: String, payload: Dictionary, prefix: String = "event") -> Array:
    var out: Array = []
    var index := 0
    for entry in payload.get("evidence", []):
        var e: Dictionary = entry if entry is Dictionary else {"payload": {"value": entry}}
        var evidence_id := str(e.get("id", "%s:%s:%d" % [prefix, event_id, index]))
        out.append(record(evidence_id, int(e.get("type", MirrorDomain.EvidenceType.DIRECT)), str(e.get("holder_id", holder_id)), str(e.get("source", "event")), event_id, e.get("payload", e.duplicate(true))))
        index += 1
    return out

func get_evidence(evidence_id: String) -> Dictionary:
    return _items.get(evidence_id, {}).duplicate(true)

func for_event(event_id: String) -> Array:
    var out: Array = []
    for id in _by_event.get(event_id, []): out.append(get_evidence(str(id)))
    return out

func all() -> Array:
    var out: Array = []
    for item in _items.values(): out.append(item.duplicate(true))
    out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
    return out

func snapshot() -> Dictionary:
    return {"items": _items.duplicate(true), "by_event": _by_event.duplicate(true)}

func restore(data: Dictionary) -> void:
    _items = data.get("items", {}).duplicate(true)
    _by_event = data.get("by_event", {}).duplicate(true)

func validate() -> Dictionary:
    var errors: Array = []
    for id in _items.keys():
        var item: Dictionary = _items[id]
        if str(item.get("id", "")) != str(id):
            errors.append("evidence_id_mismatch:" + str(id))
        var source_event := str(item.get("source_event", ""))
        if not source_event.is_empty() and str(id) not in Array(_by_event.get(source_event, [])):
            errors.append("evidence_index_missing:" + str(id))
    return {"ok": errors.is_empty(), "errors": errors}

func to_dict() -> Dictionary:
    return snapshot()

static func from_dict(data: Dictionary) -> MirrorEvidenceStore:
    var s := MirrorEvidenceStore.new()
    s.restore(data)
    return s
