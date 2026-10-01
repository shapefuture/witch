class_name MirrorDiscrepancyService
extends RefCounted

func compare(prediction: Dictionary, observed: Dictionary) -> Dictionary:
    var expected: Dictionary = prediction.get("expected", {})
    var result := {
        "has_discrepancy": false,
        "kinds": [],
        "vector": {
            "outcome": false,
            "timing": false,
            "scope": false,
            "motive": false,
            "relationship": false,
            "knowledge": false,
            "identity": false,
            "semantic": false,
        },
        "explanations": [],
        "expected": expected.duplicate(true),
        "observed": observed.duplicate(true),
    }
    if expected.is_empty():
        return result
    _compare_dimension(result, MirrorDomain.DiscrepancyKind.OUTCOME, "outcome", "Observed outcome differs from prediction.")
    if expected.has("timing") and expected.get("timing") != observed.get("timing"):
        _add(result, MirrorDomain.DiscrepancyKind.TIMING, "Timing differs from prediction.")
    if expected.has("scope") and expected.get("scope") != observed.get("scope"):
        _add(result, MirrorDomain.DiscrepancyKind.SCOPE, "Prediction scope differs from observed scope.")
    if expected.has("motive") and expected.get("motive") != observed.get("motive"):
        _add(result, MirrorDomain.DiscrepancyKind.MOTIVE, "Observed motive differs from predicted motive.")
    if expected.has("relationship_signature") and expected.get("relationship_signature") != observed.get("relationship_signature"):
        _add(result, MirrorDomain.DiscrepancyKind.RELATIONAL, "Relational meaning differs from prediction.")
    if expected.has("knowledge") and expected.get("knowledge") != observed.get("knowledge"):
        _add(result, MirrorDomain.DiscrepancyKind.KNOWLEDGE, "Information state differs from prediction.")
    if expected.has("actor_id") and expected.get("actor_id") != observed.get("actor_id"):
        _add(result, MirrorDomain.DiscrepancyKind.ACTOR, "Acting identity differs from prediction.")
    if expected.has("semantic") and expected.get("semantic") != observed.get("semantic"):
        _add(result, MirrorDomain.DiscrepancyKind.SEMANTIC, "Semantic interpretation differs from prediction.")
    return result

func _compare_dimension(result: Dictionary, kind: int, key: String, explanation: String) -> void:
    if not result["expected"].has(key):
        return
    if result["expected"].get(key) != result["observed"].get(key):
        _add(result, kind, explanation)

func _add(result: Dictionary, kind: int, explanation: String) -> void:
    result["has_discrepancy"] = true
    if kind not in result["kinds"]:
        result["kinds"].append(kind)
    match kind:
        MirrorDomain.DiscrepancyKind.OUTCOME: result["vector"]["outcome"] = true
        MirrorDomain.DiscrepancyKind.TIMING: result["vector"]["timing"] = true
        MirrorDomain.DiscrepancyKind.SCOPE: result["vector"]["scope"] = true
        MirrorDomain.DiscrepancyKind.MOTIVE: result["vector"]["motive"] = true
        MirrorDomain.DiscrepancyKind.RELATIONAL: result["vector"]["relationship"] = true
        MirrorDomain.DiscrepancyKind.KNOWLEDGE: result["vector"]["knowledge"] = true
        MirrorDomain.DiscrepancyKind.ACTOR: result["vector"]["identity"] = true
        MirrorDomain.DiscrepancyKind.SEMANTIC: result["vector"]["semantic"] = true
    result["explanations"].append(explanation)
