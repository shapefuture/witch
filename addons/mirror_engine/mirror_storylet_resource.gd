class_name MirrorStoryletResource
extends Resource

@export var id: StringName
@export var priority := 0
@export var salience := 0
@export var recency_weight := 1
@export var complexity_weight := 1
@export var visit_penalty := 1
@export var preconditions: Dictionary = {}
@export var requires_claims: Array[Dictionary] = []
@export var excludes_claims: Array[Dictionary] = []
@export var requires_operators: Array[Dictionary] = []
@export var requires_models: Array[Dictionary] = []
@export var relationship_preconditions: Array[Dictionary] = []
@export var once_key := ""
@export var cooldown_events := 0
@export var presentation: Array[Dictionary] = []

func to_definition() -> Dictionary:
    return {"id": str(id), "priority": priority, "salience": salience,
        "recency_weight": recency_weight, "complexity_weight": complexity_weight, "visit_penalty": visit_penalty, "preconditions": preconditions.duplicate(true), "requires_claims": requires_claims.duplicate(true), "excludes_claims": excludes_claims.duplicate(true), "requires_operators": requires_operators.duplicate(true), "requires_models": requires_models.duplicate(true), "relationship_preconditions": relationship_preconditions.duplicate(true), "once_key": once_key, "cooldown_events": cooldown_events, "presentation": presentation.duplicate(true)}
