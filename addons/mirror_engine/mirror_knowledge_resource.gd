class_name MirrorKnowledgeResource
extends Resource

@export var id: StringName
@export var holder_id := "player"
@export var proposition: Dictionary = {}
@export_enum("UNKNOWN", "POSSIBLE", "SUPPORTED", "ESTABLISHED", "CONTESTED", "DISCONFIRMED", "CONTEXTUAL", "TRANSFERABLE", "UNRESOLVED_BY_DESIGN") var status: int = MirrorDomain.EpistemicStatus.POSSIBLE
@export var scope := "global"
@export var source := "authored"
@export var evidence: PackedStringArray
@export var context: Dictionary = {}

func to_definition() -> Dictionary:
    return {"id":str(id),"holder_id":holder_id,"proposition":proposition.duplicate(true),"status":status,"scope":scope,"source":source,"evidence":Array(evidence),"context":context.duplicate(true)}
