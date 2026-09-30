class_name MirrorPredictionService
extends RefCounted
var _seen_once: Dictionary = {}

func predict(context: Dictionary, candidates: Array) -> Dictionary:
    var matches: Array = []
    for candidate in candidates:
        if not MirrorConditions.matches(candidate.get("when", {}), context): continue
        var once_key := str(candidate.get("once_key", ""))
        if not once_key.is_empty() and _seen_once.has(once_key): continue
        matches.append(candidate.duplicate(true))
    matches.sort_custom(func(a,b):
        var pa:=int(a.get("priority",0)); var pb:=int(b.get("priority",0));
        if pa==pb: return str(a.get("id","")) < str(b.get("id",""))
        return pa>pb
    )
    if matches.is_empty(): return {"matched":false,"prediction":{},"candidates":[]}
    return {"matched":true,"prediction":matches[0],"candidates":matches}

func consume_once(key:String)->bool:
    if key.is_empty(): return true
    if _seen_once.has(key): return false
    _seen_once[key]=true; return true
func has_once(key:String)->bool: return not key.is_empty() and _seen_once.has(key)
func snapshot()->Dictionary: return {"seen_once":_seen_once.duplicate(true)}
func restore(data:Dictionary)->void: _seen_once=data.get("seen_once",{}).duplicate(true)
func to_dict()->Dictionary: return snapshot()
