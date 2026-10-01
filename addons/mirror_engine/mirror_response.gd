class_name MirrorResponseResolver
extends RefCounted

func choose(context: Dictionary, response_contracts: Array, npc_state: Dictionary = {}, knowledge: MirrorKnowledgeStore = null, models: MirrorModelStore = null, observer_id: String = "", operators: MirrorOperatorStore = null) -> Dictionary:
    var candidates: Array = []
    var observer := observer_id if not observer_id.is_empty() else str(context.get("target_id", ""))
    for contract in response_contracts:
        if not MirrorConditions.matches(contract.get("when", {}), context):
            continue
        if not MirrorConditions.matches(contract.get("npc_preconditions", {}), npc_state):
            continue
        if knowledge != null and not _epistemic_requirements(contract, knowledge, observer):
            continue
        if models != null and not _model_requirements(contract, models, observer):
            continue
        if operators != null and not _operator_requirements(contract, operators, observer):
            continue
        candidates.append(contract.duplicate(true))
    candidates.sort_custom(func(a, b):
        var pa := int(a.get("priority", 0)); var pb := int(b.get("priority", 0))
        if pa == pb:
            return str(a.get("id", "")) < str(b.get("id", ""))
        return pa > pb
    )
    if candidates.is_empty():
        return {"matched": false, "response": {}, "candidates": []}
    return {"matched": true, "response": candidates[0], "candidates": candidates}

func _epistemic_requirements(contract: Dictionary, knowledge: MirrorKnowledgeStore, observer: String) -> bool:
    for requirement in contract.get("requires_claims", []):
        var holder := observer
        var claim_id := str(requirement)
        var min_status := MirrorDomain.EpistemicStatus.POSSIBLE
        if requirement is Dictionary:
            holder = str(requirement.get("holder_id", observer))
            claim_id = str(requirement.get("id", ""))
            min_status = int(requirement.get("min_status", min_status))
        var claim := knowledge.get_claim(claim_id, holder)
        if claim.is_empty() or not MirrorDomain.epistemic_satisfies(int(claim.get("status", MirrorDomain.EpistemicStatus.UNKNOWN)), min_status):
            return false
    return true

func _operator_requirements(contract: Dictionary, operators: MirrorOperatorStore, observer: String) -> bool:
    for requirement in contract.get("requires_operators", []):
        var operator_id := str(requirement.get("id", "") if requirement is Dictionary else requirement)
        var holder := str(requirement.get("observer_id", observer)) if requirement is Dictionary else observer
        if operator_id.is_empty() or not operators.has(operator_id, holder):
            return false
    return true

func _model_requirements(contract: Dictionary, models: MirrorModelStore, observer: String) -> bool:
    for requirement in contract.get("requires_models", []):
        var subject := str(requirement.get("subject_id", ""))
        var scope := str(requirement.get("scope", ""))
        var required_id := str(requirement.get("id", ""))
        var min_confidence := float(requirement.get("min_confidence", 0.0))
        var min_status := int(requirement.get("min_status", MirrorDomain.ModelStatus.HYPOTHESIS))
        # Claims and operators already honour a requirement's own holder/observer; model
        # requirements ignored it and always queried the responding NPC's models, so a
        # contract gated on the PLAYER's model could never match.
        var model_observer := str(requirement.get("observer_id", observer))
        var found := false
        for rule in models.query_rules(subject, scope, model_observer):
            if not required_id.is_empty() and str(rule.get("id", "")) != required_id:
                continue
            if float(rule.get("confidence", 0.0)) < min_confidence:
                continue
            if not MirrorDomain.model_satisfies(int(rule.get("status", MirrorDomain.ModelStatus.HYPOTHESIS)), min_status):
                continue
            found = true
            break
        if not found:
            return false
    return true
