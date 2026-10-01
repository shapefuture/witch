class_name MirrorCausalHypothesisStore
extends RefCounted

var _definitions: Dictionary = {}

func register(definition: Dictionary) -> bool:
    var id := str(definition.get("id", ""))
    if id.is_empty() or _definitions.has(id):
        return false
    _definitions[id] = definition.duplicate(true)
    return true

func get_hypothesis(id: String) -> Dictionary:
    return _definitions.get(id, {}).duplicate(true)

func all() -> Array:
    var out: Array = []
    for item in _definitions.values():
        out.append(item.duplicate(true))
    out.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
    return out

func snapshot() -> Dictionary:
    return _definitions.duplicate(true)

func restore(data: Dictionary) -> void:
    _definitions = data.duplicate(true)

func to_dict() -> Dictionary:
    return snapshot()
