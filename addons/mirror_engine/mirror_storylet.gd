class_name MirrorStoryletResolver
extends RefCounted

func select(candidates: Array, context: Dictionary, knowledge: MirrorKnowledgeStore = null, models: MirrorModelStore = null, relationships: MirrorRelationshipService = null, memory: Dictionary = {}, operators: MirrorOperatorStore = null) -> Array:
    var eligible: Array = []
    var current_event_count := int(memory.get("__event_count", 0))
    for candidate in candidates:
        var check := explain(candidate, context, knowledge, models, relationships, memory, operators)
        if check.get("eligible", false):
            var specificity := Array(candidate.get("requires_claims", [])).size() + Array(candidate.get("requires_models", [])).size() + Array(candidate.get("relationship_preconditions", [])).size()
            var condition_complexity := MirrorConditions.complexity(candidate.get("preconditions", {}))
            var priority := int(candidate.get("priority", 0))
            var salience := int(candidate.get("salience", 0))
            var storylet_id := str(candidate.get("id", ""))
            var last_seen := int(memory.get("storylet_seen:" + storylet_id, -1))
            var visit_count := int(memory.get("storylet_count:" + storylet_id, 0))
            # Unseen content gets a bounded bonus; older content wins only after
            # priority/salience/specificity are equal. This mirrors saliency systems
            # without turning content selection into hidden randomness.
            var recency_bonus := 1000 if last_seen < 0 else clampi(current_event_count - last_seen, 0, 1000)
            var recency_weight := maxi(0, int(candidate.get("recency_weight", 1)))
            var complexity_weight := maxi(0, int(candidate.get("complexity_weight", 1)))
            var visit_penalty := visit_count * maxi(0, int(candidate.get("visit_penalty", 1)))
            var score := priority * 1000000000 + salience * 1000000 + specificity * 1000 + condition_complexity * complexity_weight * 10 + recency_bonus * recency_weight - visit_penalty
            eligible.append({
                "definition": candidate.duplicate(true),
                "score": score,
                "score_components": {
                    "priority": priority,
                    "salience": salience,
                    "specificity": specificity,
                    "condition_complexity": condition_complexity,
                    "complexity_weight": complexity_weight,
                    "recency_bonus": recency_bonus,
                    "recency_weight": recency_weight,
                    "visit_count": visit_count,
                    "visit_penalty": visit_penalty,
                    "last_seen_event": last_seen,
                },
            })
    eligible.sort_custom(func(a, b):
        if int(a["score"]) == int(b["score"]): return str(a["definition"].get("id", "")) < str(b["definition"].get("id", ""))
        return int(a["score"]) > int(b["score"])
    )
    return eligible

func explain(candidate: Dictionary, context: Dictionary, knowledge: MirrorKnowledgeStore = null, models: MirrorModelStore = null, relationships: MirrorRelationshipService = null, memory: Dictionary = {}, operators: MirrorOperatorStore = null) -> Dictionary:
    var reasons: Array = []
    for failure in MirrorConditions.explain_failures(candidate.get("preconditions", {}), context):
        reasons.append({"kind": "context", "detail": failure})
    var once_key := str(candidate.get("once_key", ""))
    if not once_key.is_empty() and memory.has(once_key):
        reasons.append({"kind": "memory", "detail": "already_consumed", "once_key": once_key})
    var cooldown := int(candidate.get("cooldown_events", 0))
    if cooldown > 0:
        var current_event_count := int(memory.get("__event_count", 0))
        var consumed_at := int(memory.get("storylet_event:" + str(candidate.get("id", "")), -1000000))
        if current_event_count - consumed_at < cooldown:
            reasons.append({"kind": "memory", "detail": "cooldown", "remaining": cooldown - (current_event_count - consumed_at)})
    if knowledge != null:
        # Storylet eligibility is observer-bound. A storylet's presentation payload is
        # handed to the requesting observer, so a claim requirement scoped to a
        # different holder would gate that content on another actor's private
        # knowledge and leak it across holders. Such a requirement is therefore out
        # of scope for this requester: `requires` fails closed (an absence cannot
        # leak) and `excludes` becomes a no-op (it also cannot leak).
        # This deliberately differs from the world-predicate gates in
        # MirrorEngine._knowledge_requirement_matches, which must stay permissive so
        # cross-observer transfer keeps working.
        var observer := str(context.get("actor_id", "player"))
        for requirement in candidate.get("requires_claims", []):
            var claim_id := ""
            var min_status := MirrorDomain.EpistemicStatus.POSSIBLE
            if requirement is Dictionary:
                claim_id = str(requirement.get("id", ""))
                min_status = int(requirement.get("min_status", min_status))
                if str(requirement.get("holder_id", observer)) != observer:
                    reasons.append({"kind": "knowledge", "detail": claim_id, "reason": "scoped_to_other_observer"})
                    continue
            else:
                claim_id = str(requirement)
            var claim := knowledge.get_claim(claim_id, observer)
            if claim.is_empty() or not MirrorDomain.epistemic_satisfies(int(claim.get("status", MirrorDomain.EpistemicStatus.UNKNOWN)), min_status):
                reasons.append({"kind": "knowledge", "detail": claim_id})
        for requirement in candidate.get("excludes_claims", []):
            var excluded_claim_id := ""
            if requirement is Dictionary:
                excluded_claim_id = str(requirement.get("id", ""))
                if str(requirement.get("holder_id", observer)) != observer:
                    continue
            else:
                excluded_claim_id = str(requirement)
            if not knowledge.get_claim(excluded_claim_id, observer).is_empty():
                reasons.append({"kind": "knowledge_excluded", "detail": excluded_claim_id})
    if models != null:
        for requirement in candidate.get("requires_models", []):
            var matched := false
            var observer := str(requirement.get("observer_id", context.get("actor_id", "player")))
            for rule in models.query_rules(str(requirement.get("subject_id", "")), str(requirement.get("scope", "")), observer):
                if not str(requirement.get("id", "")).is_empty() and str(rule.get("id", "")) != str(requirement.get("id", "")):
                    continue
                if float(rule.get("confidence", 0.0)) < float(requirement.get("min_confidence", 0.0)):
                    continue
                if not MirrorDomain.model_satisfies(int(rule.get("status", MirrorDomain.ModelStatus.HYPOTHESIS)), int(requirement.get("min_status", MirrorDomain.ModelStatus.HYPOTHESIS))):
                    continue
                matched = true
                break
            if not matched:
                reasons.append({"kind": "model", "detail": requirement})
    if operators != null:
        var observer := str(context.get("actor_id", "player"))
        for requirement in candidate.get("requires_operators", []):
            var operator_id := str(requirement.get("id", "") if requirement is Dictionary else requirement)
            if operator_id.is_empty() or not operators.has(operator_id, str(requirement.get("observer_id", observer)) if requirement is Dictionary else observer):
                reasons.append({"kind": "operator", "detail": requirement})
    if relationships != null:
        for requirement in candidate.get("relationship_preconditions", []):
            var a := str(requirement.get("actor_id", context.get("actor_id", "player")))
            var b := str(requirement.get("target_id", context.get("target_id", "")))
            if not MirrorConditions.matches(requirement.get("requires", {}), relationships.get_relation(a, b)):
                reasons.append({"kind": "relationship", "detail": requirement})
    var storylet_id := str(candidate.get("id", ""))
    var current_event_count := int(memory.get("__event_count", 0))
    var last_seen := int(memory.get("storylet_seen:" + storylet_id, -1))
    return {
        "eligible": reasons.is_empty(),
        "reasons": reasons,
        "saliency": int(candidate.get("salience", 0)),
        "priority": int(candidate.get("priority", 0)),
        "specificity": Array(candidate.get("requires_claims", [])).size() + Array(candidate.get("requires_models", [])).size() + Array(candidate.get("relationship_preconditions", [])).size(),
        "condition_complexity": MirrorConditions.complexity(candidate.get("preconditions", {})),
        "visit_count": int(memory.get("storylet_count:" + storylet_id, 0)),
        "operator_count": Array(candidate.get("requires_operators", [])).size(),
        "last_seen_event": last_seen,
        "seen_age": -1 if last_seen < 0 else max(0, current_event_count - last_seen),
    }
