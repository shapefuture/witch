class_name MirrorModelResource
extends Resource

@export var id: StringName
@export var observer_id := "player"
@export var subject_id := ""
@export var proposition: Dictionary = {}
@export var scope := "global"
@export_range(0.0,1.0,0.01) var confidence := 0.5
@export_enum("HYPOTHESIS", "SUPPORTED", "CONTEXTUAL", "CONTRADICTED", "REVISED", "RETIRED") var status: int = MirrorDomain.ModelStatus.HYPOTHESIS
@export_range(0,3,1) var depth := 1

func to_definition() -> Dictionary:
    return {"id":str(id),"observer_id":observer_id,"subject_id":subject_id,"proposition":proposition.duplicate(true),"scope":scope,"confidence":confidence,"status":status,"depth":depth}
