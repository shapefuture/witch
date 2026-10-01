class_name InteractionOption
extends RefCounted

# One thing the player can choose to do. The presenter renders `label` and nothing else:
# `ontology` (LOOK / ASK / SHOW / WAIT / GO / CAST) is an authoring primitive and is never
# shown to the player (DESIGN_INVARIANTS #1).

var option_id: String
var action_id: String
var target_id: String
var label_key: String
var label: String
var group: String
var ontology: int
var context: Dictionary = {}

func to_action(actor_id: String = "player", request_id: String = "") -> MirrorAction:
	var action := MirrorAction.new(action_id, actor_id, target_id, ontology, {}, context)
	action.client_request_id = request_id
	return action

func ontology_name() -> String:
	for key in MirrorDomain.ActionType.keys():
		if int(MirrorDomain.ActionType[key]) == ontology:
			return str(key)
	return "UNKNOWN"
