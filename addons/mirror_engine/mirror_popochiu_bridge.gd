class_name MirrorPopochiuBridge
extends RefCounted

var engine: MirrorEngine

func _init(p_engine: MirrorEngine):
    engine = p_engine

func resolve_click(actor_id: String, target_id: String, semantic_action_id: String, context: Dictionary = {}, payload: Dictionary = {}) -> Dictionary:
    var action := MirrorAction.new(semantic_action_id, actor_id, target_id, int(engine.action_definitions.get(semantic_action_id, {}).get("action_type", MirrorDomain.ActionType.CUSTOM)), payload, context)
    return engine.resolve_action(action)

func affordances_for(target_id: String, context: Dictionary = {}) -> Array:
    return engine.get_affordances(target_id, context)
