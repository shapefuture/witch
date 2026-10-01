class_name MirrorEncounterResource
extends Resource

@export var id: StringName
@export var setup: Dictionary = {}
@export var player_hypotheses: Array[Dictionary] = []
@export var response_contracts: Array[Dictionary] = []
@export var evidence: Array[Dictionary] = []
@export var transfers: PackedStringArray
@export var invariants: Dictionary = {}

func to_definition() -> Dictionary:
    return {
        "id": str(id),
        "setup": setup.duplicate(true),
        "player_hypotheses": player_hypotheses.duplicate(true),
        "response_contracts": response_contracts.duplicate(true),
        "evidence": evidence.duplicate(true),
        "transfers": Array(transfers),
        "invariants": invariants.duplicate(true),
    }
