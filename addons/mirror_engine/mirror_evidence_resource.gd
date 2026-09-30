class_name MirrorEvidenceResource
extends Resource

@export var id: StringName
@export_enum("DIRECT", "INDIRECT", "SECOND_HAND", "AMBIGUOUS", "CONTRADICTORY", "SYMBOLIC") var type: int = MirrorDomain.EvidenceType.DIRECT
@export var holder_id := ""
@export var source := "authored"
@export var payload: Dictionary = {}

func to_definition() -> Dictionary:
    return {"id": str(id), "type": type, "holder_id": holder_id, "source": source, "payload": payload.duplicate(true)}
