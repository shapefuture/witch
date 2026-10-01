class_name MirrorPlanner
extends RefCounted

func find_plan(initial_state: Dictionary, actions: Array, goal: Dictionary, max_depth: int = 3, knowledge: MirrorKnowledgeStore = null, models: MirrorModelStore = null, relationships: MirrorRelationshipService = null, actor_id: String = "player", operators: MirrorOperatorStore = null) -> Dictionary:
    max_depth = clampi(max_depth, 0, 8)
    var frontier: Array = [{"state": initial_state.duplicate(true), "plan": []}]
    var visited: Dictionary = {MirrorHash.canonical_json(initial_state): true}
    for depth in range(max_depth + 1):
        var next_frontier: Array = []
        for node in frontier:
            if MirrorConditions.matches(goal, node.state):
                return {"found": true, "plan": node.plan.duplicate(), "state": node.state.duplicate(true), "depth": depth}
            if depth == max_depth:
                continue
            for action in actions:
                if not _available(action, node.state, knowledge, models, relationships, actor_id, operators):
                    continue
                var next_state := _apply_effects(node.state, action.get("effects", action.get("world_effects", {})))
                var key := MirrorHash.canonical_json(next_state)
                if visited.has(key):
                    continue
                visited[key] = true
                var next_plan: Array = node.plan.duplicate()
                next_plan.append(str(action.get("id", "")))
                next_frontier.append({"state": next_state, "plan": next_plan})
        frontier = next_frontier
    return {"found": false, "plan": [], "state": initial_state.duplicate(true), "depth": max_depth}

func explain_unavailable(state: Dictionary, actions: Array, knowledge: MirrorKnowledgeStore = null, models: MirrorModelStore = null, relationships: MirrorRelationshipService = null, actor_id: String = "player", operators: MirrorOperatorStore = null) -> Array:
    var output: Array = []
    for action in actions:
        var reasons: Array = []
        for failure in MirrorConditions.explain_failures(action.get("preconditions", {}), state):
            reasons.append({"kind": "state", "detail": failure})
        for requirement in action.get("requires_operators", []):
            var operator_id := str(requirement.get("id", "") if requirement is Dictionary else requirement)
            var observer := str(requirement.get("observer_id", actor_id)) if requirement is Dictionary else actor_id
            if operators == null or operator_id.is_empty() or not operators.has(operator_id, observer):
                reasons.append({"kind": "operator", "operator_id": operator_id, "observer_id": observer})
        for requirement in action.get("requires_claims", []):
            var holder := actor_id
            var claim_id := str(requirement)
            if requirement is Dictionary:
                holder = str(requirement.get("holder_id", actor_id)); claim_id = str(requirement.get("id", ""))
            if knowledge == null or not knowledge.has(claim_id, holder):
                reasons.append({"kind": "knowledge", "claim_id": claim_id, "holder_id": holder})
        for requirement in action.get("requires_models", []):
            var observer := str(requirement.get("observer_id", actor_id))
            if models == null or models.query_rules(str(requirement.get("subject_id", "")), str(requirement.get("scope", "")), observer).is_empty():
                reasons.append({"kind": "model", "requirement": requirement})
        for requirement in action.get("relationship_preconditions", []):
            var a := str(requirement.get("actor_id", actor_id)); var b := str(requirement.get("target_id", ""))
            if relationships == null or not MirrorConditions.matches(requirement.get("requires", {}), relationships.get_relation(a, b)):
                reasons.append({"kind": "relationship", "requirement": requirement})
        output.append({"id": str(action.get("id", "")), "available": reasons.is_empty(), "reasons": reasons})
    return output

func _available(action: Dictionary, state: Dictionary, knowledge: MirrorKnowledgeStore, models: MirrorModelStore, relationships: MirrorRelationshipService, actor_id: String, operators: MirrorOperatorStore = null) -> bool:
    if not MirrorConditions.matches(action.get("preconditions", {}), state):
        return false
    for requirement in action.get("requires_claims", []):
        var holder := actor_id; var claim_id := str(requirement)
        if requirement is Dictionary:
            holder = str(requirement.get("holder_id", actor_id)); claim_id = str(requirement.get("id", ""))
        if knowledge == null or not knowledge.has(claim_id, holder):
            return false
    for requirement in action.get("requires_models", []):
        var observer := str(requirement.get("observer_id", actor_id))
        if models == null or models.query_rules(str(requirement.get("subject_id", "")), str(requirement.get("scope", "")), observer).is_empty():
            return false
    for requirement in action.get("relationship_preconditions", []):
        if relationships == null:
            return false
        var a := str(requirement.get("actor_id", actor_id)); var b := str(requirement.get("target_id", ""))
        if not MirrorConditions.matches(requirement.get("requires", {}), relationships.get_relation(a, b)):
            return false
    return true

func _apply_effects(state: Dictionary, effects: Dictionary) -> Dictionary:
    var out := state.duplicate(true)
    for key in effects.keys(): out[key] = effects[key]
    return out
