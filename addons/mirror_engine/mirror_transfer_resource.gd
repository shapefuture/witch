class_name MirrorTransferResource
extends Resource

@export var id: StringName
@export var abstract_pattern: Dictionary = {}
@export var original_context: Dictionary = {}
@export var valid_contexts: Array[Dictionary] = []
@export var invalid_contexts: Array[Dictionary] = []
@export var requires_world: Dictionary = {}
@export var requires_claims: Array[Dictionary] = []
@export var requires_models: Array[Dictionary] = []
@export var world_effects: Dictionary = {}
@export var knowledge_effects: Array[Dictionary] = []
@export var model_effects: Array[Dictionary] = []

func to_definition() -> Dictionary:
    return {"id":str(id),"abstract_pattern":abstract_pattern.duplicate(true),"original_context":original_context.duplicate(true),"valid_contexts":valid_contexts.duplicate(true),"invalid_contexts":invalid_contexts.duplicate(true),"requires_world":requires_world.duplicate(true),"requires_claims":requires_claims.duplicate(true),"requires_models":requires_models.duplicate(true),"world_effects":world_effects.duplicate(true),"knowledge_effects":knowledge_effects.duplicate(true),"model_effects":model_effects.duplicate(true)}
