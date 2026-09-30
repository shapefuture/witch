class_name MirrorOperatorStore
extends RefCounted

var _acquired: Dictionary = {}
var _history: Array = []

func _key(observer_id: String, operator_id: String) -> String:
    return (observer_id if not observer_id.is_empty() else "__global__") + "::" + operator_id

func acquire(operator_id: String, observer_id: String, event_id: String, source: String = "authored", context: Dictionary = {}) -> Dictionary:
    if operator_id.is_empty() or observer_id.is_empty():
        return {}
    var key := _key(observer_id, operator_id)
    var existing: Dictionary = _acquired.get(key, {})
    if not existing.is_empty():
        return existing.duplicate(true)
    var item := {
        "id": operator_id,
        "observer_id": observer_id,
        "acquired_at_event": event_id,
        "source": source,
        "context": context.duplicate(true),
        "revoked_at_event": "",
    }
    _acquired[key] = item
    _history.append({"operation": "acquire", "event_id": event_id, "observer_id": observer_id, "operator_id": operator_id, "snapshot": item.duplicate(true)})
    return item.duplicate(true)

func revoke(operator_id: String, observer_id: String, event_id: String) -> bool:
    var key := _key(observer_id, operator_id)
    if not _acquired.has(key):
        return false
    var item: Dictionary = _acquired[key]
    if not str(item.get("revoked_at_event", "")).is_empty():
        return false
    item["revoked_at_event"] = event_id
    _acquired[key] = item
    _history.append({"operation": "revoke", "event_id": event_id, "observer_id": observer_id, "operator_id": operator_id, "snapshot": item.duplicate(true)})
    return true

func has(operator_id: String, observer_id: String = "player") -> bool:
    var item: Dictionary = _acquired.get(_key(observer_id, operator_id), {})
    return not item.is_empty() and str(item.get("revoked_at_event", "")).is_empty()

func get_operator(operator_id: String, observer_id: String = "player") -> Dictionary:
    var item: Dictionary = _acquired.get(_key(observer_id, operator_id), {})
    return item.duplicate(true)

func all(observer_id: String = "") -> Array:
    var out: Array = []
    for item in _acquired.values():
        if not observer_id.is_empty() and str(item.get("observer_id", "")) != observer_id:
            continue
        if not str(item.get("revoked_at_event", "")).is_empty():
            continue
        out.append(item.duplicate(true))
    out.sort_custom(func(a, b):
        var ak := str(a.get("observer_id", "")) + "::" + str(a.get("id", ""))
        var bk := str(b.get("observer_id", "")) + "::" + str(b.get("id", ""))
        return ak < bk
    )
    return out

func history(observer_id: String = "", operator_id: String = "") -> Array:
    var out: Array = []
    for item in _history:
        if not observer_id.is_empty() and str(item.get("observer_id", "")) != observer_id:
            continue
        if not operator_id.is_empty() and str(item.get("operator_id", "")) != operator_id:
            continue
        out.append(item.duplicate(true))
    return out

func snapshot() -> Dictionary:
    return {"acquired": _acquired.duplicate(true), "history": _history.duplicate(true)}

func restore(data: Dictionary) -> void:
    _acquired = data.get("acquired", {}).duplicate(true)
    _history = data.get("history", []).duplicate(true)

func to_dict() -> Dictionary:
    return snapshot()

static func from_dict(data: Dictionary) -> MirrorOperatorStore:
    var store := MirrorOperatorStore.new()
    store.restore(data)
    return store
