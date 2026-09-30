class_name MirrorKnowledgeStore
extends RefCounted

var _claims: Dictionary = {}

func _key(holder_id: String, claim_id: String) -> String:
    return (holder_id if not holder_id.is_empty() else "__global__") + "::" + claim_id

func upsert(claim_id: String, proposition: Dictionary, status: int, evidence: Array, source: String, scope: String, context: Dictionary = {}, holder_id: String = "player") -> Dictionary:
    var key := _key(holder_id, claim_id)
    var claim: Dictionary = _claims.get(key, {
        "id": claim_id, "holder_id": holder_id, "proposition": {}, "evidence": [], "status": status,
        "source": source, "scope": scope, "context": {}, "first_seen_event": "", "last_updated_event": "",
        "contradictions": [], "revision_of": ""
    })
    claim["id"] = claim_id; claim["holder_id"] = holder_id
    claim["proposition"] = proposition.duplicate(true); claim["status"] = status; claim["source"] = source
    claim["scope"] = scope; claim["context"] = context.duplicate(true)
    var existing: Array = claim.get("evidence", [])
    for ref in evidence: if ref not in existing: existing.append(ref)
    claim["evidence"] = existing; _claims[key] = claim
    return claim.duplicate(true)

func mark_contradicted(claim_id: String, event_id: String, revision_id: String = "", holder_id: String = "player") -> bool:
    var key := _key(holder_id, claim_id)
    if not _claims.has(key): return false
    var claim: Dictionary = _claims[key]
    claim["status"] = MirrorDomain.EpistemicStatus.CONTESTED
    var contradictions: Array = claim.get("contradictions", [])
    if event_id not in contradictions: contradictions.append(event_id)
    claim["contradictions"] = contradictions
    if not revision_id.is_empty(): claim["revision_of"] = revision_id
    _claims[key] = claim
    return true

func get_claim(claim_id: String, holder_id: String = "player") -> Dictionary:
    var exact := _claims.get(_key(holder_id, claim_id), {})
    if not exact.is_empty(): return exact.duplicate(true)
    # Backward compatibility: legacy saves did not carry holder ids.
    if holder_id == "player" and _claims.has(claim_id): return _claims[claim_id].duplicate(true)
    return {}

func has(claim_id: String, holder_id: String = "player") -> bool: return not get_claim(claim_id, holder_id).is_empty()

func all(holder_id: String = "") -> Array:
    var out: Array = []
    for claim in _claims.values():
        if not holder_id.is_empty() and str(claim.get("holder_id", "player")) != holder_id: continue
        out.append(claim.duplicate(true))
    out.sort_custom(func(a, b):
        var ak := str(a.get("holder_id", "")) + "::" + str(a.get("id", "")); var bk := str(b.get("holder_id", "")) + "::" + str(b.get("id", ""))
        return ak < bk
    )
    return out

func snapshot() -> Dictionary: return _claims.duplicate(true)
func restore(snapshot_data: Dictionary) -> void: _claims = snapshot_data.duplicate(true)
func to_dict() -> Dictionary: return {"claims": snapshot()}
static func from_dict(data: Dictionary) -> MirrorKnowledgeStore:
    var store := MirrorKnowledgeStore.new(); store.restore(data.get("claims", {})); return store
