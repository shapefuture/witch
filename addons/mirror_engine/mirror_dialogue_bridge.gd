class_name MirrorDialogueBridge
extends RefCounted

var engine:MirrorEngine
func _init(p_engine:MirrorEngine)->void:engine=p_engine
func get_context()->MirrorContext:return MirrorContext.new(engine)
func can_enter_dialogue(npc_id:String,requirements:Dictionary={},actor_id:String="player")->bool:
    return not npc_id.is_empty() and MirrorConditions.matches(requirements,engine.world_state)
func record_choice(player_id:String,npc_id:String,choice_id:String)->Dictionary:
    var action:=MirrorAction.new("DIALOGUE_CHOICE",player_id,npc_id,MirrorDomain.ActionType.CUSTOM,{"choice_id":choice_id},{})
    if not engine.action_definitions.has(action.id) and not engine.catalog_is_locked:
        engine.register_action({"id":action.id,"action_type":MirrorDomain.ActionType.CUSTOM,"allow_no_response":true,"default_observed":{"outcome":"dialogue_choice"}})
    return engine.resolve_action(action)
