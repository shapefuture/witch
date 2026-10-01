class_name MirrorRelationshipService
extends RefCounted

var _relations: Dictionary = {}
func _key(a: String, b: String) -> String: return a + "::" + b

func record(a: String, b: String, event_id: String, semantic_tags: Array, payload: Dictionary = {}) -> Dictionary:
    var key := _key(a,b)
    var relation: Dictionary = _relations.get(key, {"actor_id":a,"target_id":b,"events":[],"boundaries":{},"commitments":{},"invitations":[],"refusals":[],"interpretations":[],"expectations":{}})
    relation["events"].append({"event_id":event_id,"tags":semantic_tags.duplicate(),"payload":payload.duplicate(true)})
    if relation["events"].size() > 10000: relation["events"].pop_front()
    if "BOUNDARY" in semantic_tags: relation["boundaries"][str(payload.get("domain","general"))] = payload.get("boundary", {}).duplicate(true)
    if "COMMITMENT" in semantic_tags: relation["commitments"][str(payload.get("commitment_id",event_id))] = payload.duplicate(true)
    if "INVITATION" in semantic_tags: relation["invitations"].append(payload.duplicate(true))
    if "REFUSAL" in semantic_tags: relation["refusals"].append(payload.duplicate(true))
    if payload.has("interpretation"): relation["interpretations"].append({"event_id":event_id,"value":payload["interpretation"]})
    _relations[key]=relation; return relation.duplicate(true)

func get_relation(a:String,b:String)->Dictionary: return _relations.get(_key(a,b),{}).duplicate(true)
func snapshot()->Dictionary: return _relations.duplicate(true)
func restore(data:Dictionary)->void: _relations=data.duplicate(true)
func to_dict()->Dictionary: return {"relations":snapshot()}
static func from_dict(data:Dictionary)->MirrorRelationshipService:
    var s:=MirrorRelationshipService.new(); s.restore(data.get("relations",{})); return s
