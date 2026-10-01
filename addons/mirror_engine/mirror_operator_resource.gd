class_name MirrorOperatorResource
extends Resource

@export var id: StringName
@export var abstraction: Dictionary = {}
@export var preconditions: Dictionary = {}
@export var requires_claims: Array[Dictionary] = []
@export var requires_models: Array[Dictionary] = []
@export var valid_contexts: Array[Dictionary] = []
@export var invalid_contexts: Array[Dictionary] = []
@export var action_ids: PackedStringArray
@export var source_model_ids: PackedStringArray
@export var transfer_rule_ids: PackedStringArray

func to_definition() -> Dictionary:
    return {
        "id": str(id),
        "abstraction": abstraction.duplicate(true),
        "preconditions": preconditions.duplicate(true),
        "requires_claims": requires_claims.duplicate(true),
        "requires_models": requires_models.duplicate(true),
        "valid_contexts": valid_contexts.duplicate(true),
        "invalid_contexts": invalid_contexts.duplicate(true),
        "action_ids": Array(action_ids),
        "source_model_ids": Array(source_model_ids),
        "transfer_rule_ids": Array(transfer_rule_ids),
    }
