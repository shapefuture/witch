class_name MirrorCausalHypothesisResource
extends Resource

@export var id: StringName
@export var rule: Dictionary = {}
@export var baseline_model: Dictionary = {}
@export var anomaly: Dictionary = {}
@export var requires_evidence: Array[Dictionary] = []
@export var experiments: Array[Dictionary] = []
@export var operator_id := ""
@export var transfer_ids: PackedStringArray
@export var boundary: Dictionary = {}
@export var reframe_id := ""
@export var semantic_distance := 0
@export var importance := 0
@export var tags: PackedStringArray

func to_definition() -> Dictionary:
    return {
        "id": str(id),
        "rule": rule.duplicate(true),
        "baseline_model": baseline_model.duplicate(true),
        "anomaly": anomaly.duplicate(true),
        "requires_evidence": requires_evidence.duplicate(true),
        "experiments": experiments.duplicate(true),
        "operator_id": operator_id,
        "transfer_ids": Array(transfer_ids),
        "boundary": boundary.duplicate(true),
        "reframe_id": reframe_id,
        "semantic_distance": semantic_distance,
        "importance": importance,
        "tags": Array(tags),
    }
