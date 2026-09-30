class_name MirrorModelStore
extends RefCounted

var _rules: Dictionary = {}
var _observations: Array = []
var _history: Array = []

func _key(observer_id: String, rule_id: String) -> String:
    return (observer_id if not observer_id.is_empty() else "__global__") + "::" + rule_id

func upsert_rule(rule_id: String, subject_id: String, proposition: Dictionary, scope: String, confidence: float = 0.5, status: int = MirrorDomain.ModelStatus.HYPOTHESIS, depth: int = 1, provenance: Array = [], observer_id: String = "player") -> Dictionary:
    depth = MirrorDomain.clamp_model_depth(depth)
    var key := _key(observer_id, rule_id)
    var rule: Dictionary = _rules.get(key, {"id": rule_id, "observer_id": observer_id, "subject_id": subject_id, "proposition": {}, "scope": scope, "confidence": 0.5, "status": status, "depth": depth, "provenance": [], "created_at_event": "", "last_supported_event": "", "last_contradicted_event": "", "supersedes": "", "transferred_from": ""})
    rule["id"] = rule_id; rule["observer_id"] = observer_id; rule["subject_id"] = subject_id; rule["proposition"] = proposition.duplicate(true)
    rule["scope"] = scope; rule["confidence"] = clampf(confidence, 0.0, 1.0); rule["status"] = status; rule["depth"] = depth
    var refs: Array = rule.get("provenance", []); for ref in provenance: if ref not in refs: refs.append(ref)
    rule["provenance"] = refs; _rules[key] = rule
    _history.append({"operation":"upsert","rule_id":rule_id,"observer_id":observer_id,"event_id":provenance[-1] if not provenance.is_empty() else "","snapshot":rule.duplicate(true)})
    return rule.duplicate(true)

func support(rule_id: String, event_id: String, delta: float = 0.12, observer_id: String = "player") -> bool:
    var key := _key(observer_id, rule_id)
    if not _rules.has(key): return false
    var rule: Dictionary = _rules[key]
    rule["confidence"] = clampf(float(rule["confidence"]) + delta, 0.0, 1.0)
    rule["status"] = MirrorDomain.ModelStatus.SUPPORTED
    rule["last_supported_event"] = event_id
    var refs: Array = rule.get("provenance", [])
    if event_id not in refs: refs.append(event_id)
    rule["provenance"] = refs
    _rules[key] = rule
    _history.append({"operation":"support","rule_id":rule_id,"observer_id":observer_id,"event_id":event_id,"snapshot":rule.duplicate(true)})
    return true

func contradict(rule_id: String, event_id: String, observer_id: String = "player") -> bool:
    var key := _key(observer_id, rule_id)
    if not _rules.has(key): return false
    var rule: Dictionary = _rules[key]
    rule["confidence"] = clampf(float(rule["confidence"]) * 0.55, 0.0, 1.0)
    rule["status"] = MirrorDomain.ModelStatus.CONTRADICTED
    rule["last_contradicted_event"] = event_id
    var refs: Array = rule.get("provenance", [])
    if event_id not in refs: refs.append(event_id)
    rule["provenance"] = refs
    _rules[key] = rule
    _history.append({"operation":"contradict","rule_id":rule_id,"observer_id":observer_id,"event_id":event_id,"snapshot":rule.duplicate(true)})
    return true

func revise(old_rule_id: String, new_rule_id: String, proposition: Dictionary, scope: String, event_id: String, subject_id: String, observer_id: String = "player") -> Dictionary:
    var old_key := _key(observer_id, old_rule_id)
    if _rules.has(old_key): _rules[old_key]["status"] = MirrorDomain.ModelStatus.REVISED
    var new_rule := upsert_rule(new_rule_id, subject_id, proposition, scope, 0.6, MirrorDomain.ModelStatus.REVISED, 1, [event_id], observer_id)
    new_rule["supersedes"] = old_rule_id; _rules[_key(observer_id, new_rule_id)] = new_rule
    _history.append({"operation":"revise","rule_id":new_rule_id,"observer_id":observer_id,"event_id":event_id,"supersedes":old_rule_id,"snapshot":new_rule.duplicate(true)})
    return new_rule

func transfer(source_rule_id: String, new_rule_id: String, source_observer_id: String, target_observer_id: String, subject_id: String, target_scope: String, event_id: String, confidence_discount: float = 0.85) -> Dictionary:
    var source := _rules.get(_key(source_observer_id, source_rule_id), {})
    if source.is_empty(): return {}
    var depth := MirrorDomain.clamp_model_depth(int(source.get("depth", 1)) + 1)
    var rule := upsert_rule(new_rule_id, subject_id if not subject_id.is_empty() else str(source.get("subject_id", "")), source.get("proposition", {}).duplicate(true), target_scope, float(source.get("confidence", 0.5)) * clampf(confidence_discount, 0.0, 1.0), MirrorDomain.ModelStatus.CONTEXTUAL, depth, [event_id], target_observer_id)
    rule["transferred_from"] = source_rule_id; _rules[_key(target_observer_id, new_rule_id)] = rule
    _history.append({"operation":"transfer","rule_id":new_rule_id,"observer_id":target_observer_id,"event_id":event_id,"source_rule_id":source_rule_id,"snapshot":rule.duplicate(true)})
    return rule.duplicate(true)

func observe_action(subject_id: String, action_signature: Array, context: Dictionary, event_id: String, observer_id: String = "player") -> void:
    _observations.append({"subject_id": subject_id, "observer_id": observer_id, "signature": action_signature.duplicate(), "context": context.duplicate(true), "event_id": event_id})
    if _observations.size() > 10000: _observations.pop_front()

func query_rules(subject_id: String = "", scope: String = "", observer_id: String = "") -> Array:
    var out: Array = []
    for rule in _rules.values():
        if not observer_id.is_empty() and str(rule.get("observer_id", "player")) != observer_id: continue
        if not subject_id.is_empty() and str(rule.get("subject_id", "")) != subject_id: continue
        if not scope.is_empty() and str(rule.get("scope", "")) != scope: continue
        out.append(rule.duplicate(true))
    out.sort_custom(func(a, b):
        var ca := float(a.get("confidence", 0.0)); var cb := float(b.get("confidence", 0.0))
        if is_equal_approx(ca, cb): return str(a.get("observer_id", "")) + "::" + str(a.get("id", "")) < str(b.get("observer_id", "")) + "::" + str(b.get("id", ""))
        return ca > cb
    )
    return out

func history(observer_id: String = "", rule_id: String = "") -> Array:
    var out: Array = []
    for item in _history:
        if not observer_id.is_empty() and str(item.get("observer_id", "")) != observer_id: continue
        if not rule_id.is_empty() and str(item.get("rule_id", "")) != rule_id: continue
        out.append(item.duplicate(true))
    return out

func snapshot() -> Dictionary: return {"rules": _rules.duplicate(true), "observations": _observations.duplicate(true), "history": _history.duplicate(true)}
func restore(snapshot_data: Dictionary) -> void: _rules = snapshot_data.get("rules", {}).duplicate(true); _observations = snapshot_data.get("observations", []).duplicate(true); _history = snapshot_data.get("history", []).duplicate(true)
func to_dict() -> Dictionary: return snapshot()
static func from_dict(data: Dictionary) -> MirrorModelStore:
    var store := MirrorModelStore.new(); store.restore(data); return store
