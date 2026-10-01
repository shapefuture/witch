class_name MirrorAction
extends RefCounted

var id: String
var actor_id: String
var target_id: String
var action_type: int
var payload: Dictionary
var context: Dictionary
var client_request_id: String

func _init(p_id: String = "", p_actor_id: String = "", p_target_id: String = "", p_action_type: int = MirrorDomain.ActionType.CUSTOM, p_payload: Dictionary = {}, p_context: Dictionary = {}):
    id = p_id
    actor_id = p_actor_id
    target_id = p_target_id
    action_type = p_action_type
    payload = p_payload.duplicate(true)
    context = p_context.duplicate(true)
    client_request_id = ""

func to_dict() -> Dictionary:
    return {
        "id": id,
        "actor_id": actor_id,
        "target_id": target_id,
        "action_type": action_type,
        "payload": payload.duplicate(true),
        "context": context.duplicate(true),
        "client_request_id": client_request_id,
    }
