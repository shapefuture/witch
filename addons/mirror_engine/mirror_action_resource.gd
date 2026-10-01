class_name MirrorActionResource
extends Resource

@export var id: StringName
@export_enum("LOOK", "ASK", "SHOW", "WAIT", "GO", "CAST", "CUSTOM") var action_type: int = MirrorDomain.ActionType.CUSTOM
@export var valid_targets: PackedStringArray
@export var preconditions: Dictionary = {}
@export var prediction_signature: PackedStringArray
@export var prediction_candidates: Array[Dictionary] = []
@export var response_contracts: Array[Dictionary] = []
@export var requires_claims: Array[Dictionary] = []
@export var excludes_claims: Array[Dictionary] = []
@export var requires_operators: Array[Dictionary] = []
@export var requires_models: Array[Dictionary] = []
@export var relationship_preconditions: Array[Dictionary] = []
@export var time_cost := 0
@export var once_key := ""
@export var affordance_group := ""
@export var allow_no_response := true
@export var default_observed: Dictionary = {"outcome": "noop"}

func to_definition() -> Dictionary:
    return {"id":str(id),"action_type":action_type,"valid_targets":Array(valid_targets),"preconditions":preconditions.duplicate(true),"prediction_signature":Array(prediction_signature),"prediction_candidates":prediction_candidates.duplicate(true),"response_contracts":response_contracts.duplicate(true),"requires_claims":requires_claims.duplicate(true),"excludes_claims":excludes_claims.duplicate(true),"requires_operators":requires_operators.duplicate(true),"requires_models":requires_models.duplicate(true),"relationship_preconditions":relationship_preconditions.duplicate(true),"time_cost":time_cost,"once_key":once_key,"affordance_group":affordance_group,"allow_no_response":allow_no_response,"default_observed":default_observed.duplicate(true)}
