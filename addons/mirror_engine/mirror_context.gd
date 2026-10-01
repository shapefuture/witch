class_name MirrorContext
extends RefCounted

var engine: MirrorEngine

func _init(p_engine: MirrorEngine) -> void:
    engine = p_engine

func world(key: String, default_value: Variant = null) -> Variant:
    return engine.get_world(key, default_value)

func knows(claim_id: String, holder_id: String = "player") -> bool:
    return engine.knowledge.has(claim_id, holder_id)

func evidence_for(event_id: String) -> Array:
    return engine.evidence.for_event(event_id)

func evidence(evidence_id: String) -> Dictionary:
    return engine.evidence.get_evidence(evidence_id)

func relation(actor_id: String, target_id: String) -> Dictionary:
    return engine.relationships.get_relation(actor_id, target_id)

func model(subject_id: String, scope: String = "", observer_id: String = "") -> Array:
    return engine.models.query_rules(subject_id, scope, observer_id)

func time() -> int:
    return engine.get_time()

func explain_action(action: MirrorAction) -> Dictionary:
    return engine.explain_action(action)

func affordances(target_id: String, context: Dictionary = {}, actor_id: String = "player") -> Array:
    return engine.explain_affordances(target_id, context, actor_id)

func storylets(context: Dictionary = {}, actor_id: String = "player") -> Array:
    return engine.select_storylets(context, actor_id)

func predict(observer_id: String, subject_id: String, context: Dictionary, candidates: Array) -> Dictionary:
    return engine.predict_for_observer(observer_id, subject_id, context, candidates)

func observe(observer_id: String, subject_id: String, observation: Dictionary, context: Dictionary = {}, evidence_items: Array = [], knowledge_effects: Array = [], model_effects: Array = []) -> Dictionary:
    return engine.record_observation(observer_id, subject_id, observation, context, evidence_items, knowledge_effects, model_effects)

func share_claim(from_holder_id: String, to_holder_id: String, claim_id: String, event_context: Dictionary = {}) -> Dictionary:
    return engine.share_claim(from_holder_id, to_holder_id, claim_id, event_context)
