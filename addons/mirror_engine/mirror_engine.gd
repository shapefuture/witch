class_name MirrorEngine
extends RefCounted

signal transaction_committed(result: Dictionary)
signal transaction_failed(result: Dictionary)
signal catalog_lock_acquired(fingerprint: String)

var event_store: MirrorEventStore
var knowledge: MirrorKnowledgeStore
var models: MirrorModelStore
var evidence: MirrorEvidenceStore
var operators: MirrorOperatorStore
var relationships: MirrorRelationshipService
var prediction: MirrorPredictionService
var discrepancy: MirrorDiscrepancyService
var response_resolver: MirrorResponseResolver
var storylet_resolver: MirrorStoryletResolver
var planner: MirrorPlanner

var world_state: Dictionary = {}
var npc_state: Dictionary = {}
var initial_world_state: Dictionary = {}
var initial_npc_state: Dictionary = {}
var action_memory: Dictionary = {}
var action_definitions: Dictionary = {}
var encounter_definitions: Dictionary = {}
var transfer_rules: Dictionary = {}
var storylet_definitions: Dictionary = {}
var operator_definitions: Dictionary = {}
var causal_hypothesis_definitions: Dictionary = {}

var max_transaction_events := 256
var catalog_is_locked := false
var catalog_revision := 0
var catalog_fingerprint := ""
var _suppress_signals := false

func _init() -> void:
    event_store = MirrorEventStore.new()
    knowledge = MirrorKnowledgeStore.new()
    models = MirrorModelStore.new()
    evidence = MirrorEvidenceStore.new()
    operators = MirrorOperatorStore.new()
    relationships = MirrorRelationshipService.new()
    prediction = MirrorPredictionService.new()
    discrepancy = MirrorDiscrepancyService.new()
    response_resolver = MirrorResponseResolver.new()
    storylet_resolver = MirrorStoryletResolver.new()
    planner = MirrorPlanner.new()

func _register(catalog: Dictionary, definition: Dictionary) -> bool:
    if catalog_is_locked:
        return false
    var id := str(definition.get("id", ""))
    if id.is_empty():
        return false
    catalog[id] = definition.duplicate(true)
    catalog_revision += 1
    return true

func register_action_resource(resource: Resource) -> bool:
    if resource == null or not resource.has_method("to_definition"):
        return false
    return _register(action_definitions, resource.to_definition())

func register_encounter_resource(resource: Resource) -> bool:
    if resource == null or not resource.has_method("to_definition"):
        return false
    return _register(encounter_definitions, resource.to_definition())

func register_transfer_resource(resource: Resource) -> bool:
    if resource == null or not resource.has_method("to_definition"):
        return false
    return _register(transfer_rules, resource.to_definition())

func register_storylet_resource(resource: Resource) -> bool:
    if resource == null or not resource.has_method("to_definition"):
        return false
    return _register(storylet_definitions, resource.to_definition())

func register_operator_resource(resource: Resource) -> bool:
    if resource == null or not resource.has_method("to_definition"):
        return false
    return _register(operator_definitions, resource.to_definition())

func register_causal_hypothesis_resource(resource: Resource) -> bool:
    if resource == null or not resource.has_method("to_definition"):
        return false
    return _register(causal_hypothesis_definitions, resource.to_definition())

func register_action(definition: Dictionary) -> bool:
    return _register(action_definitions, definition)

func register_encounter(definition: Dictionary) -> bool:
    return _register(encounter_definitions, definition)

func register_transfer(rule: Dictionary) -> bool:
    return _register(transfer_rules, rule)

func register_storylet(definition: Dictionary) -> bool:
    return _register(storylet_definitions, definition)

func register_operator(definition: Dictionary) -> bool:
    return _register(operator_definitions, definition)

func register_causal_hypothesis(definition: Dictionary) -> bool:
    return _register(causal_hypothesis_definitions, definition)

func _catalog() -> Dictionary:
    return {
        "actions": action_definitions,
        "encounters": encounter_definitions,
        "transfers": transfer_rules,
        "storylets": storylet_definitions,
        "operators": operator_definitions,
        "causal_hypotheses": causal_hypothesis_definitions,
    }

func compute_catalog_fingerprint() -> String:
    return MirrorHash.sha256(_catalog())

func lock_catalog() -> bool:
    if catalog_is_locked:
        return true
    var validation := validate_catalog()
    if not validation.get("ok", false):
        return false
    catalog_fingerprint = compute_catalog_fingerprint()
    catalog_is_locked = true
    if not _suppress_signals:
        catalog_lock_acquired.emit(catalog_fingerprint)
    return true

func set_world(key: String, value: Variant) -> bool:
    if event_store.size() > 0 or catalog_is_locked:
        return false
    world_state[key] = value
    initial_world_state[key] = value
    return true

func get_world(key: String, default_value: Variant = null) -> Variant:
    return world_state.get(key, default_value)

func set_npc_state(npc_id: String, state: Dictionary) -> bool:
    if event_store.size() > 0 or catalog_is_locked:
        return false
    npc_state[npc_id] = state.duplicate(true)
    initial_npc_state[npc_id] = state.duplicate(true)
    return true

func get_npc_state(npc_id: String) -> Dictionary:
    return npc_state.get(npc_id, {}).duplicate(true)

func get_time() -> int:
    return int(world_state.get("__mirror_time", 0))

func _knowledge_requirement_matches(requirement: Variant, actor_id: String) -> bool:
    var claim_id := ""
    var holder_id := actor_id
    var min_status := MirrorDomain.EpistemicStatus.POSSIBLE
    if requirement is Dictionary:
        claim_id = str(requirement.get("id", ""))
        holder_id = str(requirement.get("holder_id", actor_id))
        min_status = int(requirement.get("min_status", min_status))
    else:
        claim_id = str(requirement)
    var claim := knowledge.get_claim(claim_id, holder_id)
    return not claim.is_empty() and MirrorDomain.epistemic_satisfies(int(claim.get("status", MirrorDomain.EpistemicStatus.UNKNOWN)), min_status)

func _model_requirement_matches(requirement: Dictionary, actor_id: String) -> bool:
    var observer := str(requirement.get("observer_id", actor_id))
    var subject := str(requirement.get("subject_id", ""))
    var scope := str(requirement.get("scope", ""))
    var required_id := str(requirement.get("id", ""))
    var min_confidence := float(requirement.get("min_confidence", 0.0))
    var min_status := int(requirement.get("min_status", MirrorDomain.ModelStatus.HYPOTHESIS))
    for rule in models.query_rules(subject, scope, observer):
        if not required_id.is_empty() and str(rule.get("id", "")) != required_id:
            continue
        if float(rule.get("confidence", 0.0)) < min_confidence:
            continue
        if not MirrorDomain.model_satisfies(int(rule.get("status", MirrorDomain.ModelStatus.HYPOTHESIS)), min_status):
            continue
        return true
    return false

func _operator_requirement_matches(requirement: Variant, actor_id: String, context: Dictionary = {}) -> bool:
    var operator_id := ""
    var observer := actor_id
    if requirement is Dictionary:
        operator_id = str(requirement.get("id", ""))
        observer = str(requirement.get("observer_id", actor_id))
        var required_context: Dictionary = requirement.get("context", {})
        if not required_context.is_empty() and not MirrorConditions.matches(required_context, context):
            return false
    else:
        operator_id = str(requirement)
    return not operator_id.is_empty() and operators.has(operator_id, observer)

func _operators_requirements_ok(definition: Dictionary, actor_id: String, context: Dictionary = {}) -> Dictionary:
    var reasons: Array = []
    for requirement in definition.get("requires_operators", []):
        if not _operator_requirement_matches(requirement, actor_id, context):
            reasons.append({"kind": "operator", "requirement": requirement})
    return {"ok": reasons.is_empty(), "reasons": reasons}

func _claims_requirements_ok(definition: Dictionary, actor_id: String) -> Dictionary:
    var reasons: Array = []
    for requirement in definition.get("requires_claims", []):
        if not _knowledge_requirement_matches(requirement, actor_id):
            reasons.append({"kind": "knowledge", "requirement": requirement})
    for requirement in definition.get("excludes_claims", []):
        if _knowledge_requirement_matches(requirement, actor_id):
            reasons.append({"kind": "knowledge_excluded", "requirement": requirement})
    for requirement in definition.get("requires_models", []):
        if not _model_requirement_matches(requirement, actor_id):
            reasons.append({"kind": "model", "requirement": requirement})
    return {"ok": reasons.is_empty(), "reasons": reasons}

func _action_context(action: MirrorAction) -> Dictionary:
    var context := world_state.duplicate(true)
    for key in action.context.keys():
        context[key] = action.context[key]
    context["action_id"] = action.id
    context["actor_id"] = action.actor_id
    context["target_id"] = action.target_id
    context["time"] = get_time()
    return context

func explain_action(action: MirrorAction) -> Dictionary:
    if catalog_is_locked and compute_catalog_fingerprint() != catalog_fingerprint:
        return {"available": false, "reasons": [{"kind": "catalog", "reason": "catalog_fingerprint_mismatch"}]}
    if action == null:
        return {"available": false, "reasons": [{"kind": "action", "reason": "null_action"}]}
    var definition: Dictionary = action_definitions.get(action.id, {})
    if definition.is_empty():
        return {"available": false, "reasons": [{"kind": "action", "reason": "unknown_action"}]}
    var reasons: Array = []
    if int(definition.get("action_type", action.action_type)) != action.action_type:
        reasons.append({"kind": "action", "reason": "action_type_mismatch", "expected": int(definition.get("action_type", action.action_type)), "actual": action.action_type})
    var context := _action_context(action)
    reasons.append_array(MirrorConditions.explain_failures(definition.get("preconditions", {}), context))
    var targets: Array = definition.get("valid_targets", [])
    if not targets.is_empty() and action.target_id not in targets:
        reasons.append({"kind": "target", "reason": "invalid_target", "target_id": action.target_id})
    var once_key := str(definition.get("once_key", ""))
    if not once_key.is_empty() and action_memory.has("action_once:" + once_key):
        reasons.append({"kind": "memory", "reason": "action_already_consumed", "once_key": once_key})
    var requirement_report := _claims_requirements_ok(definition, action.actor_id)
    reasons.append_array(requirement_report["reasons"])
    var operator_report := _operators_requirements_ok(definition, action.actor_id, context)
    reasons.append_array(operator_report["reasons"])
    for relation_requirement in definition.get("relationship_preconditions", []):
        var a := str(relation_requirement.get("actor_id", action.actor_id))
        var b := str(relation_requirement.get("target_id", action.target_id))
        if not MirrorConditions.matches(relation_requirement.get("requires", {}), relationships.get_relation(a, b)):
            reasons.append({"kind": "relationship", "requirement": relation_requirement})
    return {
        "available": reasons.is_empty(),
        "reasons": reasons,
        "affordance_state": _affordance_state(reasons),
        "latent": _is_latent_affordance(reasons),
        "context": context,
        "definition_id": definition.get("id", ""),
    }

func _affordance_state(reasons: Array) -> String:
    if reasons.is_empty():
        return "available"
    # "knowledge_excluded" is emitted by _claims_requirements_ok and honoured by
    # _is_latent_affordance, so it must also have a bucket here — otherwise an
    # action blocked solely by excludes_claims reported plain "blocked" while
    # simultaneously reporting latent=true.
    var precedence := ["action", "target", "state", "relationship", "knowledge", "knowledge_excluded", "model", "operator", "memory", "catalog"]
    for kind in precedence:
        for reason in reasons:
            var reason_kind := str(reason.get("kind", ""))
            if reason_kind == kind or (kind == "state" and reason_kind == "context"):
                return "blocked_by_" + kind
    return "blocked"

func _is_latent_affordance(reasons: Array) -> bool:
    if reasons.is_empty():
        return false
    var latent := true
    for reason in reasons:
        var kind := str(reason.get("kind", ""))
        if kind not in ["knowledge", "knowledge_excluded", "model", "operator"]:
            latent = false
            break
    return latent

func explain_affordances(target_id: String, context: Dictionary = {}, actor_id: String = "player") -> Array:
    var output: Array = []
    for definition in action_definitions.values():
        var action := MirrorAction.new(str(definition.get("id", "")), actor_id, target_id, int(definition.get("action_type", MirrorDomain.ActionType.CUSTOM)), {}, context)
        var report := explain_action(action)
        output.append({
            "action": definition.duplicate(true),
            "available": report.get("available", false),
            "reasons": report.get("reasons", []),
            "affordance_state": report.get("affordance_state", "blocked"),
            "latent": report.get("latent", false),
            "group": str(definition.get("affordance_group", "")),
        })
    output.sort_custom(func(a, b): return str(a["action"].get("id", "")) < str(b["action"].get("id", "")))
    return output

func get_affordances(target_id: String, context: Dictionary = {}, actor_id: String = "player") -> Array:
    var output: Array = []
    for entry in explain_affordances(target_id, context, actor_id):
        if entry["available"]:
            output.append(entry["action"])
    return output

func _normalize_evidence(raw: Array, tx_id: String, response_event_id: String, holder_id: String) -> Array:
    var output: Array = []
    var index := 0
    for item in raw:
        var evidence_item: Dictionary
        if item is Dictionary:
            evidence_item = item.duplicate(true)
        else:
            evidence_item = {"payload": {"value": item}}
        var evidence_id := str(evidence_item.get("id", ""))
        if evidence_id.is_empty():
            evidence_id = "event_evidence:%s:%d" % [tx_id, index]
        evidence_item["id"] = evidence_id
        evidence_item["type"] = int(evidence_item.get("type", MirrorDomain.EvidenceType.DIRECT))
        evidence_item["holder_id"] = str(evidence_item.get("holder_id", holder_id))
        evidence_item["source"] = str(evidence_item.get("source", "authored"))
        evidence_item["source_event"] = response_event_id
        if not evidence_item.has("payload"):
            evidence_item["payload"] = {}
        output.append(evidence_item)
        index += 1
    return output

func _resolve_transfer_applications(effects: Array, context: Dictionary, actor_id: String) -> Array:
    var output: Array = []
    for effect in effects:
        var transfer_id := str(effect.get("id", ""))
        var rule: Dictionary = transfer_rules.get(transfer_id, {})
        if rule.is_empty():
            output.append({"id": transfer_id, "status": "missing_definition", "reasons": []})
            continue
        var reasons: Array = []
        reasons.append_array(MirrorConditions.explain_failures(rule.get("requires_world", rule.get("requires", {})), world_state))
        for requirement in rule.get("requires_claims", []):
            if not _knowledge_requirement_matches(requirement, actor_id):
                reasons.append({"kind": "knowledge", "requirement": requirement})
        for requirement in rule.get("requires_models", []):
            if not _model_requirement_matches(requirement, actor_id):
                reasons.append({"kind": "model", "requirement": requirement})
        var valid_context := rule.get("valid_contexts", [])
        if not valid_context.is_empty():
            var matched_context := false
            for valid_requirement in valid_context:
                if MirrorConditions.matches(valid_requirement, context):
                    matched_context = true
                    break
            if not matched_context:
                reasons.append({"kind": "context", "reason": "no_valid_context"})
        for invalid_requirement in rule.get("invalid_contexts", []):
            if MirrorConditions.matches(invalid_requirement, context):
                reasons.append({"kind": "context", "reason": "invalid_context"})
        output.append({
            "id": transfer_id,
            "status": "matched" if reasons.is_empty() else "rejected",
            "reasons": reasons,
            "world_effects": rule.get("world_effects", {}).duplicate(true),
            "knowledge_effects": rule.get("knowledge_effects", []).duplicate(true),
            "model_effects": rule.get("model_effects", []).duplicate(true),
        })
    return output

func _result_from_transaction(transaction_id: String) -> Dictionary:
    var events := event_store.get_transaction(transaction_id)
    if events.is_empty():
        return {}
    var action_event: MirrorEvent = events[0]
    var response_event: MirrorEvent = null
    var discrepancy_payload: Dictionary = {}
    for event in events:
        if event.event_type == "ResponseResolved":
            response_event = event
        elif event.event_type == "DiscrepancyDetected":
            discrepancy_payload = event.payload.duplicate(true)
    var response_payload: Dictionary = response_event.payload if response_event != null else {}
    # A replay must return the same shape resolve_action() returns on a first commit.
    # Reporting the raw event payload as `response` left response.id null (the matched
    # contract id is persisted under "response_id") and omitted prediction_result,
    # response_result, knowledge_candidates and presentation, so consumers reading
    # those keys worked on first commit and silently misbehaved on every replay.
    var contract: Dictionary = {}
    if response_event != null:
        contract = {
            "id": str(response_payload.get("response_id", "")),
            "observed": response_payload.get("observed", {}).duplicate(true),
        }
    return {
        "ok": true,
        "transaction_id": transaction_id,
        "events": events,
        "prediction": action_event.payload.get("prediction", {}),
        # prediction_result and response_result are live resolver outputs that are not
        # persisted in the event log, so they cannot be reconstructed exactly. They are
        # present so a consumer reading the same keys as a first commit does not crash;
        # "reconstructed" marks them as derived from the log rather than replayed live.
        "prediction_result": {"reconstructed": true, "prediction": action_event.payload.get("prediction", {})},
        "response": contract,
        "response_result": {"reconstructed": true, "ok": response_event != null, "response": contract},
        "observed": response_payload.get("observed", {}),
        "discrepancy": discrepancy_payload,
        "knowledge_candidates": response_payload.get("knowledge_effects", []),
        "presentation": response_payload.get("presentation", []),
        "idempotent_replay": true,
        "catalog_fingerprint": catalog_fingerprint,
        "action": action_event.payload.get("action", {}),
    }

func _action_request_fingerprint(action: MirrorAction) -> String:
    var payload := action.to_dict()
    payload.erase("client_request_id")
    return MirrorHash.sha256(payload)

func resolve_action(action: MirrorAction) -> Dictionary:
    if action == null:
        return _fail("null_action")
    if not action.client_request_id.is_empty():
        var existing_tx := str(action_memory.get("request:" + action.client_request_id, ""))
        if not existing_tx.is_empty():
            var existing_fingerprint := str(action_memory.get("request_fingerprint:" + action.client_request_id, ""))
            var current_fingerprint := _action_request_fingerprint(action)
            if not existing_fingerprint.is_empty() and existing_fingerprint != current_fingerprint:
                return _fail("idempotency_key_conflict", {"client_request_id": action.client_request_id, "existing_transaction_id": existing_tx})
            var replayed := _result_from_transaction(existing_tx)
            if not replayed.is_empty():
                return replayed
    var availability := explain_action(action)
    if not availability.get("available", false):
        return _fail("action_unavailable", availability)
    var pending_catalog_fingerprint := compute_catalog_fingerprint()

    var definition: Dictionary = action_definitions[action.id].duplicate(true)
    var context := _action_context(action)
    var prediction_result := prediction.predict(context, definition.get("prediction_candidates", []))
    var predicted: Dictionary = prediction_result.get("prediction", {})
    var npc_result := response_resolver.choose(context, definition.get("response_contracts", []), get_npc_state(action.target_id), knowledge, models, action.target_id, operators)
    if not npc_result.get("matched", false) and not definition.get("allow_no_response", true):
        return _fail("no_response_contract", {"action_id": action.id})
    var response: Dictionary = npc_result.get("response", {})
    var observed: Dictionary = response.get("observed", definition.get("default_observed", {"outcome": "noop"})).duplicate(true)
    var discrepancy_result := discrepancy.compare(predicted, observed)

    var transaction_id := "tx_%s_%s" % [action.id, str(event_store.next_sequence())]
    var action_event_id := transaction_id + ":action"
    var response_event_id := transaction_id + ":response"
    var transfer_applications := _resolve_transfer_applications(response.get("transfer_effects", []), context, action.actor_id)
    var authored_evidence := _normalize_evidence(response.get("evidence", []), transaction_id, response_event_id, action.actor_id)
    var staged_events: Array[MirrorEvent] = []

    var action_event := _make_event(action_event_id, "ActionResolved", action.actor_id, action.target_id, {
        "action": action.to_dict(),
        "definition_id": definition.get("id", ""),
        "definition_hash": MirrorHash.sha256(definition),
        "catalog_fingerprint": catalog_fingerprint,
        "prediction": predicted,
        "model_observation": definition.get("prediction_signature", []),
        "action_once_key": str(definition.get("once_key", "")),
        "prediction_once_key": str(predicted.get("once_key", "")),
        "client_request_id": action.client_request_id,
        "request_fingerprint": _action_request_fingerprint(action),
        # Persisted unconditionally. Previously `observed` was written only inside the
        # response branch or the discrepancy payload, so an action whose response
        # contract matched nothing AND whose prediction had no `expected` block left no
        # record anywhere of the outcome the player actually received — contradicting
        # "every semantic fact needed to reconstruct a decision is persisted".
        # NOTE: this adds a payload key, so it rotates every event hash. Saves written
        # before this change fail hash_mismatch and are correctly rejected.
        "observed": observed,
    })
    action_event.transaction_id = transaction_id
    action_event.definition_hash = MirrorHash.sha256(definition)
    action_event.catalog_fingerprint = catalog_fingerprint
    action_event.prediction_signature = Array(definition.get("prediction_signature", []), TYPE_STRING, "", null)
    staged_events.append(action_event)

    if not response.is_empty():
        var response_payload := {
            "response_id": response.get("id", ""),
            "observed": observed,
            "effects": response.get("effects", {}).duplicate(true),
            "knowledge_effects": response.get("knowledge_effects", []).duplicate(true),
            "model_effects": response.get("model_effects", []).duplicate(true),
            "operator_effects": response.get("operator_effects", []).duplicate(true),
            "relationship_tags": response.get("relationship_tags", []).duplicate(),
            "relationship_payload": response.get("relationship_payload", {}).duplicate(true),
            "transfer_applications": transfer_applications,
            "evidence": authored_evidence,
            "presentation": response.get("presentation", []).duplicate(true),
        }
        var response_event := _make_event(response_event_id, "ResponseResolved", action.target_id, action.actor_id, response_payload)
        response_event.transaction_id = transaction_id
        response_event.causes = [action_event_id]
        response_event.effects = response.get("effects", {}).duplicate(true)
        response_event.definition_hash = MirrorHash.sha256(definition)
        for evidence_item in authored_evidence:
            response_event.evidence_refs.append(str(evidence_item.get("id", "")))
        response_event.catalog_fingerprint = catalog_fingerprint
        staged_events.append(response_event)

    if discrepancy_result.get("has_discrepancy", false):
        var discrepancy_event := _make_event(transaction_id + ":discrepancy", "DiscrepancyDetected", action.actor_id, action.target_id, discrepancy_result)
        discrepancy_event.transaction_id = transaction_id
        discrepancy_event.causes = [action_event_id]
        discrepancy_event.catalog_fingerprint = catalog_fingerprint
        staged_events.append(discrepancy_event)

    var time_cost := int(definition.get("time_cost", 0))
    if time_cost < 0:
        return _fail("negative_time_cost", {"action_id": action.id})
    if time_cost > 0:
        var time_event := _make_event(transaction_id + ":time", "TimeAdvanced", action.actor_id, "", {
            "from": get_time(),
            "to": get_time() + time_cost,
            "delta": time_cost,
            "reason": "action_time_cost",
        })
        time_event.transaction_id = transaction_id
        time_event.causes = [action_event_id]
        time_event.catalog_fingerprint = catalog_fingerprint
        staged_events.append(time_event)

    if staged_events.size() > max_transaction_events:
        return _fail("transaction_event_limit")
    if not lock_catalog():
        return _fail("catalog_invalid")
    if catalog_fingerprint != pending_catalog_fingerprint or compute_catalog_fingerprint() != catalog_fingerprint:
        return _fail("catalog_fingerprint_mismatch")
    for staged_event in staged_events:
        staged_event.catalog_fingerprint = catalog_fingerprint
        if staged_event.payload.has("catalog_fingerprint"):
            staged_event.payload["catalog_fingerprint"] = catalog_fingerprint

    var snapshot := _snapshot()
    if not event_store.append_bundle(staged_events, false):
        return _fail("event_store_rejected", {"reason": event_store.last_error})

    var semantic_event_id := response_event_id if not response.is_empty() else action_event_id
    _apply_response_effects(response.get("effects", {}), semantic_event_id)
    _update_models_from_action(action, definition, action_event_id)
    # Only record relationship effects when the replay path can reconstruct them.
    # Replaying an "ActionResolved" event does not touch relationships, and when no
    # response contract matched there is no "ResponseResolved" event to carry them
    # either. Recording unconditionally here made the live projection diverge from
    # the replayed one, so any save containing a no-response action failed to load
    # with projection_mismatch.
    if not response.is_empty():
        _update_relationships(action, response, semantic_event_id)
    _apply_knowledge_effects(response.get("knowledge_effects", []), semantic_event_id)
    _apply_model_effects(response.get("model_effects", []), semantic_event_id)
    _apply_operator_effects(response.get("operator_effects", []), semantic_event_id)
    _apply_transfer_applications(transfer_applications, semantic_event_id)
    if not _apply_evidence(authored_evidence):
        _restore_snapshot(snapshot)
        return _fail("evidence_conflict")
    _remember_action(definition, predicted, action_event_id, transaction_id, action.client_request_id)
    if time_cost > 0:
        world_state["__mirror_time"] = get_time() + time_cost

    if not _validate_post_commit():
        _restore_snapshot(snapshot)
        return _fail("post_commit_validation_failed")
    if not event_store.publish(staged_events):
        _restore_snapshot(snapshot)
        return _fail("event_publish_failed")

    var result := {
        "ok": true,
        "transaction_id": transaction_id,
        "events": staged_events,
        "prediction": predicted,
        "prediction_result": prediction_result,
        "response": response,
        "response_result": npc_result,
        "observed": observed,
        "discrepancy": discrepancy_result,
        "knowledge_candidates": response.get("knowledge_effects", []),
        "presentation": response.get("presentation", []),
        "catalog_fingerprint": catalog_fingerprint,
    }
    if not _suppress_signals:
        transaction_committed.emit(result)
    return result

func _remember_action(definition: Dictionary, predicted: Dictionary, event_id: String, transaction_id: String, client_request_id: String) -> void:
    var once_key := str(definition.get("once_key", ""))
    if not once_key.is_empty():
        action_memory["action_once:" + once_key] = event_id
    var prediction_once_key := str(predicted.get("once_key", ""))
    if not prediction_once_key.is_empty():
        prediction.consume_once(prediction_once_key)
    if not client_request_id.is_empty():
        action_memory["request:" + client_request_id] = transaction_id
        action_memory["request_fingerprint:" + client_request_id] = _action_request_fingerprint_from_event(event_id)
    action_memory["transaction:" + transaction_id] = event_id
    action_memory["__event_count"] = event_store.size()

func _action_request_fingerprint_from_event(event_id: String) -> String:
    var event := event_store.get_by_id(event_id)
    if event == null:
        return ""
    var stored := str(event.payload.get("request_fingerprint", ""))
    if not stored.is_empty():
        return stored
    var action_payload: Dictionary = event.payload.get("action", {})
    action_payload.erase("client_request_id")
    return MirrorHash.sha256(action_payload)

func _make_event(id: String, event_type: String, actor: String, target: String, payload: Dictionary) -> MirrorEvent:
    var event := MirrorEvent.new(event_type, actor, target, payload)
    event.event_id = id
    event.author_tag = "mirror_runtime"
    return event

func _apply_response_effects(effects: Dictionary, event_id: String) -> void:
    for key in effects.get("world", {}).keys():
        world_state[key] = effects["world"][key]
    for npc_id in effects.get("npc_state", {}).keys():
        var state: Dictionary = npc_state.get(npc_id, {}).duplicate(true)
        var patch: Dictionary = effects["npc_state"][npc_id]
        for key in patch.keys():
            state[key] = patch[key]
        npc_state[npc_id] = state

func _update_models_from_action(action: MirrorAction, definition: Dictionary, event_id: String) -> void:
    models.observe_action(action.actor_id, definition.get("prediction_signature", []), action.context, event_id, action.actor_id)

func _update_relationships(action: MirrorAction, response: Dictionary, event_id: String) -> void:
    if action.target_id.is_empty():
        return
    relationships.record(action.actor_id, action.target_id, event_id, response.get("relationship_tags", []), response.get("relationship_payload", {}))

func _apply_knowledge_effects(effects: Array, event_id: String) -> void:
    for effect in effects:
        var claim_id := str(effect.get("id", ""))
        if claim_id.is_empty():
            continue
        var holder := str(effect.get("holder_id", "player"))
        var claim := knowledge.upsert(claim_id, effect.get("proposition", {}), int(effect.get("status", MirrorDomain.EpistemicStatus.POSSIBLE)), effect.get("evidence", []), str(effect.get("source", "authored")), str(effect.get("scope", "global")), effect.get("context", {}), holder)
        var refs: Array = claim.get("evidence", [])
        if event_id not in refs:
            refs.append(event_id)
        claim["evidence"] = refs
        claim["last_updated_event"] = event_id
        if str(claim.get("first_seen_event", "")).is_empty():
            claim["first_seen_event"] = event_id
        knowledge._claims[knowledge._key(holder, claim_id)] = claim

func _apply_model_effects(effects: Array, event_id: String) -> void:
    for effect in effects:
        var type := str(effect.get("type", ""))
        var observer := str(effect.get("observer_id", "player"))
        match type:
            "support": models.support(str(effect.get("rule_id", "")), event_id, float(effect.get("delta", 0.12)), observer)
            "contradict": models.contradict(str(effect.get("rule_id", "")), event_id, observer)
            "upsert": models.upsert_rule(str(effect.get("rule_id", "")), str(effect.get("subject_id", "")), effect.get("proposition", {}), str(effect.get("scope", "global")), float(effect.get("confidence", 0.5)), int(effect.get("status", MirrorDomain.ModelStatus.HYPOTHESIS)), int(effect.get("depth", 1)), [event_id], observer)
            "revise": models.revise(str(effect.get("old_rule_id", "")), str(effect.get("new_rule_id", "")), effect.get("proposition", {}), str(effect.get("scope", "global")), event_id, str(effect.get("subject_id", "")), observer)
            "transfer": models.transfer(str(effect.get("source_rule_id", "")), str(effect.get("new_rule_id", "")), str(effect.get("source_observer_id", observer)), str(effect.get("target_observer_id", observer)), str(effect.get("subject_id", "")), str(effect.get("target_scope", "global")), event_id, float(effect.get("confidence_discount", 0.85)))

func _apply_operator_effects(effects: Array, event_id: String) -> void:
    for effect in effects:
        var type := str(effect.get("type", "acquire"))
        var operator_id := str(effect.get("operator_id", effect.get("id", "")))
        var observer := str(effect.get("observer_id", "player"))
        match type:
            "acquire": operators.acquire(operator_id, observer, event_id, str(effect.get("source", "authored")), effect.get("context", {}))
            "revoke": operators.revoke(operator_id, observer, event_id)

func _apply_transfer_applications(applications: Array, event_id: String) -> void:
    for application in applications:
        if str(application.get("status", "")) != "matched":
            continue
        for key in application.get("world_effects", {}).keys():
            world_state[key] = application["world_effects"][key]
        _apply_knowledge_effects(application.get("knowledge_effects", []), event_id)
        _apply_model_effects(application.get("model_effects", []), event_id)
        action_memory["transfer:" + str(application.get("id", ""))] = event_id

func _apply_evidence(items: Array) -> bool:
    # MirrorEvidenceStore.record() returns {} and sets last_error = "evidence_conflict"
    # when an evidence id is re-used with different content. The return value used to be
    # discarded, so a transaction could commit an event whose evidence_refs pointed at
    # an earlier transaction's evidence and payload — contradicting the immutability
    # guarantee and failing silently. Callers on the commit path must fail closed.
    var ok := true
    for item in items:
        if evidence.record(str(item.get("id", "")), int(item.get("type", MirrorDomain.EvidenceType.DIRECT)), str(item.get("holder_id", "player")), str(item.get("source", "authored")), str(item.get("source_event", "")), item.get("payload", {})).is_empty():
            ok = false
    return ok

func record_observation(observer_id: String, subject_id: String, observation: Dictionary, context: Dictionary = {}, evidence_items: Array = [], knowledge_effects: Array = [], model_effects: Array = [], operator_effects: Array = []) -> Dictionary:
    if not lock_catalog():
        return _fail("catalog_invalid")
    if compute_catalog_fingerprint() != catalog_fingerprint:
        return _fail("catalog_fingerprint_mismatch")
    var transaction_id := "tx_observation_%s" % str(event_store.next_sequence())
    var event_id := transaction_id + ":observation"
    var normalized_evidence := _normalize_evidence(evidence_items, transaction_id, event_id, observer_id)
    var observation_event := _make_event(event_id, "ObservationRecorded", observer_id, subject_id, {
        "observation": observation.duplicate(true),
        "context": context.duplicate(true),
        "knowledge_effects": knowledge_effects.duplicate(true),
        "model_effects": model_effects.duplicate(true),
        "operator_effects": operator_effects.duplicate(true),
        "evidence": normalized_evidence,
    })
    observation_event.transaction_id = transaction_id
    observation_event.catalog_fingerprint = catalog_fingerprint
    observation_event.evidence_refs = []
    for item in normalized_evidence:
        observation_event.evidence_refs.append(str(item.get("id", "")))
    var snapshot := _snapshot()
    if not event_store.append_bundle([observation_event], false):
        return _fail("event_store_rejected", {"reason": event_store.last_error})
    models.observe_action(subject_id, observation.get("signature", []), context, event_id, observer_id)
    _apply_knowledge_effects(knowledge_effects, event_id)
    _apply_model_effects(model_effects, event_id)
    _apply_operator_effects(operator_effects, event_id)
    if not _apply_evidence(normalized_evidence):
        _restore_snapshot(snapshot)
        return _fail("evidence_conflict")
    action_memory["__event_count"] = event_store.size()
    if not _validate_post_commit():
        _restore_snapshot(snapshot)
        return _fail("post_commit_validation_failed")
    if not event_store.publish([observation_event]):
        _restore_snapshot(snapshot)
        return _fail("event_publish_failed")
    var result := {"ok": true, "transaction_id": transaction_id, "events": [observation_event], "observation": observation, "catalog_fingerprint": catalog_fingerprint}
    if not _suppress_signals:
        transaction_committed.emit(result)
    return result

func share_claim(from_holder_id: String, to_holder_id: String, claim_id: String, event_context: Dictionary = {}) -> Dictionary:
    if from_holder_id.is_empty() or to_holder_id.is_empty() or claim_id.is_empty():
        return _fail("invalid_claim_transfer")
    if from_holder_id == to_holder_id:
        return _fail("self_claim_transfer")
    if not lock_catalog():
        return _fail("catalog_invalid")
    if compute_catalog_fingerprint() != catalog_fingerprint:
        return _fail("catalog_fingerprint_mismatch")
    var source := knowledge.get_claim(claim_id, from_holder_id)
    if source.is_empty():
        return _fail("claim_not_found", {"claim_id": claim_id, "holder_id": from_holder_id})
    var transaction_id := "tx_share_%s_%s" % [claim_id, str(event_store.next_sequence())]
    var event_id := transaction_id + ":share"
    var prior_evidence: Array = source.get("evidence", []).duplicate()
    var transfer_evidence_id := "hearsay:%s" % event_id
    var transfer_evidence := {
        "id": transfer_evidence_id,
        "type": MirrorDomain.EvidenceType.SECOND_HAND,
        "holder_id": to_holder_id,
        "source": "claim_share",
        "source_event": event_id,
        "payload": {"from_holder_id": from_holder_id, "claim_id": claim_id, "prior_evidence": prior_evidence},
    }
    var knowledge_effect := {
        "id": claim_id,
        "holder_id": to_holder_id,
        "proposition": source.get("proposition", {}).duplicate(true),
        "status": MirrorDomain.EpistemicStatus.POSSIBLE,
        "evidence": prior_evidence + [transfer_evidence_id],
        "source": "hearsay",
        "scope": str(source.get("scope", "")),
        "context": event_context.duplicate(true),
    }
    var event := _make_event(event_id, "KnowledgeShared", from_holder_id, to_holder_id, {
        "claim_id": claim_id,
        "from_holder_id": from_holder_id,
        "to_holder_id": to_holder_id,
        "knowledge_effect": knowledge_effect,
        "evidence": [transfer_evidence],
    })
    event.transaction_id = transaction_id
    event.catalog_fingerprint = catalog_fingerprint
    event.evidence_refs = [transfer_evidence_id]
    var snapshot := _snapshot()
    if not event_store.append_bundle([event], false):
        return _fail("event_store_rejected", {"reason": event_store.last_error})
    _apply_knowledge_effects([knowledge_effect], event_id)
    if not _apply_evidence([transfer_evidence]):
        _restore_snapshot(snapshot)
        return _fail("evidence_conflict")
    action_memory["__event_count"] = event_store.size()
    if not _validate_post_commit():
        _restore_snapshot(snapshot)
        return _fail("post_commit_validation_failed")
    if not event_store.publish([event]):
        _restore_snapshot(snapshot)
        return _fail("event_publish_failed")
    var result := {"ok": true, "transaction_id": transaction_id, "events": [event], "claim": knowledge_effect, "catalog_fingerprint": catalog_fingerprint}
    if not _suppress_signals:
        transaction_committed.emit(result)
    return result

func acquire_operator(observer_id: String, operator_id: String, context: Dictionary = {}, source: String = "authored") -> Dictionary:
    if observer_id.is_empty() or operator_id.is_empty():
        return _fail("invalid_operator_acquisition")
    if not operator_definitions.has(operator_id):
        return _fail("unknown_operator", {"operator_id": operator_id})
    if not lock_catalog():
        return _fail("catalog_invalid")
    if compute_catalog_fingerprint() != catalog_fingerprint:
        return _fail("catalog_fingerprint_mismatch")
    if operators.has(operator_id, observer_id):
        return {"ok": true, "idempotent": true, "operator": operators.get_operator(operator_id, observer_id), "catalog_fingerprint": catalog_fingerprint}
    var tx := "tx_operator_%s_%s" % [operator_id, str(event_store.next_sequence())]
    var event := _make_event(tx + ":acquire", "OperatorAcquired", observer_id, "", {"operator_id": operator_id, "observer_id": observer_id, "context": context.duplicate(true), "source": source})
    event.transaction_id = tx
    event.catalog_fingerprint = catalog_fingerprint
    event.definition_hash = MirrorHash.sha256(operator_definitions[operator_id])
    var snapshot := _snapshot()
    if not event_store.append_bundle([event], false):
        return _fail("event_store_rejected", {"reason": event_store.last_error})
    operators.acquire(operator_id, observer_id, event.event_id, source, context)
    action_memory["__event_count"] = event_store.size()
    if not _validate_post_commit():
        _restore_snapshot(snapshot)
        return _fail("post_commit_validation_failed")
    if not event_store.publish([event]):
        _restore_snapshot(snapshot)
        return _fail("event_publish_failed")
    var result := {"ok": true, "transaction_id": tx, "events": [event], "operator": operators.get_operator(operator_id, observer_id), "catalog_fingerprint": catalog_fingerprint}
    if not _suppress_signals:
        transaction_committed.emit(result)
    return result

func revoke_operator(observer_id: String, operator_id: String, reason: String = "authored") -> Dictionary:
    if observer_id.is_empty() or operator_id.is_empty():
        return _fail("invalid_operator_revocation")
    if not operators.has(operator_id, observer_id):
        return {"ok": true, "idempotent": true, "operator_id": operator_id, "observer_id": observer_id, "reason": "not_acquired"}
    if not lock_catalog():
        return _fail("catalog_invalid")
    if compute_catalog_fingerprint() != catalog_fingerprint:
        return _fail("catalog_fingerprint_mismatch")
    var tx := "tx_operator_revoke_%s_%s" % [operator_id, str(event_store.next_sequence())]
    var event := _make_event(tx + ":revoke", "OperatorRevoked", observer_id, "", {"operator_id": operator_id, "observer_id": observer_id, "reason": reason})
    event.transaction_id = tx
    event.catalog_fingerprint = catalog_fingerprint
    event.definition_hash = MirrorHash.sha256(operator_definitions.get(operator_id, {}))
    var snapshot := _snapshot()
    if not event_store.append_bundle([event], false):
        return _fail("event_store_rejected", {"reason": event_store.last_error})
    operators.revoke(operator_id, observer_id, event.event_id)
    action_memory["__event_count"] = event_store.size()
    if not _validate_post_commit():
        _restore_snapshot(snapshot)
        return _fail("post_commit_validation_failed")
    if not event_store.publish([event]):
        _restore_snapshot(snapshot)
        return _fail("event_publish_failed")
    var result := {"ok": true, "transaction_id": tx, "events": [event], "operator_id": operator_id, "observer_id": observer_id, "catalog_fingerprint": catalog_fingerprint}
    if not _suppress_signals:
        transaction_committed.emit(result)
    return result

func advance_time(delta: int, actor_id: String = "system", reason: String = "manual") -> Dictionary:
    if delta < 0:
        return _fail("negative_time")
    if not lock_catalog():
        return _fail("catalog_invalid")
    if compute_catalog_fingerprint() != catalog_fingerprint:
        return _fail("catalog_fingerprint_mismatch")
    var tx := "tx_time_%s" % str(event_store.next_sequence())
    var time_event := _make_event(tx + ":time", "TimeAdvanced", actor_id, "", {"from": get_time(), "to": get_time() + delta, "delta": delta, "reason": reason})
    time_event.transaction_id = tx
    time_event.catalog_fingerprint = catalog_fingerprint
    var snapshot := _snapshot()
    if not event_store.append_bundle([time_event], false):
        return _fail("event_store_rejected", {"reason": event_store.last_error})
    world_state["__mirror_time"] = get_time() + delta
    action_memory["__event_count"] = event_store.size()
    if not _validate_post_commit():
        _restore_snapshot(snapshot)
        return _fail("post_commit_validation_failed")
    if not event_store.publish([time_event]):
        _restore_snapshot(snapshot)
        return _fail("event_publish_failed")
    var result := {"ok": true, "transaction_id": tx, "events": [time_event], "time": get_time()}
    if not _suppress_signals:
        transaction_committed.emit(result)
    return result

func select_storylets(context: Dictionary = {}, actor_id: String = "player") -> Array:
    if catalog_is_locked and compute_catalog_fingerprint() != catalog_fingerprint:
        return []
    var candidates: Array = []
    for definition in storylet_definitions.values():
        candidates.append(definition)
    var augmented := context.duplicate(true)
    augmented["actor_id"] = actor_id
    var selected := storylet_resolver.select(candidates, augmented, knowledge, models, relationships, action_memory, operators)
    var output: Array = []
    for entry in selected:
        output.append(entry["definition"])
    return output

func explain_storylet(storylet_id: String, context: Dictionary = {}, actor_id: String = "player") -> Dictionary:
    var definition: Dictionary = storylet_definitions.get(storylet_id, {})
    if definition.is_empty():
        return {"eligible": false, "reasons": [{"kind": "storylet", "reason": "unknown"}]}
    var augmented := context.duplicate(true)
    augmented["actor_id"] = actor_id
    return storylet_resolver.explain(definition, augmented, knowledge, models, relationships, action_memory, operators)

func consume_storylet(storylet_id: String, actor_id: String = "player", context: Dictionary = {}) -> Dictionary:
    var definition: Dictionary = storylet_definitions.get(storylet_id, {})
    if definition.is_empty():
        return _fail("unknown_storylet")
    var augmented := context.duplicate(true)
    augmented["actor_id"] = actor_id
    var report := storylet_resolver.explain(definition, augmented, knowledge, models, relationships, action_memory, operators)
    if not report.get("eligible", false):
        return _fail("storylet_unavailable", report)
    if not lock_catalog():
        return _fail("catalog_invalid")
    if compute_catalog_fingerprint() != catalog_fingerprint:
        return _fail("catalog_fingerprint_mismatch")
    var transaction_id := "tx_storylet_%s_%s" % [storylet_id, str(event_store.next_sequence())]
    var content_event := _make_event(transaction_id + ":content", "ContentConsumed", actor_id, "", {
        "storylet_id": storylet_id,
        "definition_hash": MirrorHash.sha256(definition),
        "catalog_fingerprint": catalog_fingerprint,
        "presentation": definition.get("presentation", []),
        "once_key": str(definition.get("once_key", "")),
    })
    content_event.transaction_id = transaction_id
    content_event.catalog_fingerprint = catalog_fingerprint
    var snapshot := _snapshot()
    if not event_store.append_bundle([content_event], false):
        return _fail("event_store_rejected", {"reason": event_store.last_error})
    var once_key := str(definition.get("once_key", ""))
    if not once_key.is_empty():
        action_memory[once_key] = content_event.event_id
    action_memory["storylet_event:" + storylet_id] = event_store.size()
    action_memory["storylet_seen:" + storylet_id] = event_store.size()
    action_memory["storylet_count:" + storylet_id] = int(action_memory.get("storylet_count:" + storylet_id, 0)) + 1
    action_memory["__event_count"] = event_store.size()
    if not _validate_post_commit():
        _restore_snapshot(snapshot)
        return _fail("post_commit_validation_failed")
    if not event_store.publish([content_event]):
        _restore_snapshot(snapshot)
        return _fail("event_publish_failed")
    var result := {"ok": true, "transaction_id": transaction_id, "events": [content_event], "storylet": definition.duplicate(true)}
    if not _suppress_signals:
        transaction_committed.emit(result)
    return result

func evaluate_causal_hypothesis(hypothesis_id: String, observer_id: String = "player", context: Dictionary = {}) -> Dictionary:
    var definition: Dictionary = causal_hypothesis_definitions.get(hypothesis_id, {})
    if definition.is_empty():
        return {"ok": false, "error": "unknown_causal_hypothesis"}
    var augmented := context.duplicate(true)
    augmented["observer_id"] = observer_id
    var missing_evidence: Array = []
    for requirement in definition.get("requires_evidence", []):
        if not _knowledge_requirement_matches(requirement, observer_id):
            missing_evidence.append(requirement)
    var missing_models: Array = []
    for requirement in definition.get("requires_models", []):
        var model_requirement: Dictionary = requirement.duplicate(true)
        if not model_requirement.has("observer_id"):
            model_requirement["observer_id"] = observer_id
        if not _model_requirement_matches(model_requirement, observer_id):
            missing_models.append(requirement)
    var operator_ready := true
    var operator_id := str(definition.get("operator_id", ""))
    if not operator_id.is_empty():
        operator_ready = operators.has(operator_id, observer_id)
    var experiments: Array = []
    for experiment in definition.get("experiments", []):
        var action_id := str(experiment.get("action_id", ""))
        var target_id := str(experiment.get("target_id", ""))
        var action_context: Dictionary = experiment.get("context", augmented)
        if action_id.is_empty():
            experiments.append({"status": "invalid", "reason": "missing_action_id"})
            continue
        var probe := MirrorAction.new(action_id, observer_id, target_id, int(experiment.get("action_type", MirrorDomain.ActionType.CUSTOM)), {}, action_context)
        var probe_report := explain_action(probe)
        experiments.append({"action_id": action_id, "available": probe_report.get("available", false), "explanation": probe_report})
    var boundary_match: bool = not definition.get("boundary", {}).is_empty() and MirrorConditions.matches(definition.get("boundary", {}), augmented)
    var anomaly_match: bool = definition.get("anomaly", {}).is_empty() or MirrorConditions.matches(definition.get("anomaly", {}), augmented)
    var evidence_ready := missing_evidence.is_empty()
    var model_ready := missing_models.is_empty()
    var state := "hypothesis"
    if not anomaly_match:
        state = "inactive"
    elif not evidence_ready:
        state = "evidence_needed"
    elif not model_ready:
        state = "model_needed"
    elif boundary_match:
        state = "boundary"
    elif not operator_ready:
        state = "operator_unacquired"
    else:
        state = "ready"
    return {
        "ok": true,
        "id": hypothesis_id,
        "observer_id": observer_id,
        "state": state,
        "rule": definition.get("rule", {}).duplicate(true),
        "baseline_model": definition.get("baseline_model", {}).duplicate(true),
        "anomaly": definition.get("anomaly", {}).duplicate(true),
        "missing_evidence": missing_evidence,
        "missing_models": missing_models,
        "operator_id": operator_id,
        "operator_ready": operator_ready,
        "experiments": experiments,
        "boundary_match": boundary_match,
        "reframe_id": str(definition.get("reframe_id", "")),
        "semantic_distance": int(definition.get("semantic_distance", 0)),
        "importance": int(definition.get("importance", 0)),
    }

func model_transition_report(before: Dictionary, after: Dictionary) -> Dictionary:
    return {
        "diff": diff_projections({"models": before}, {"models": after}),
        "before": before.duplicate(true),
        "after": after.duplicate(true),
    }

func predict_for_observer(observer_id: String, subject_id: String, context: Dictionary, candidates: Array) -> Dictionary:
    var filtered: Array = []
    var augmented := context.duplicate(true)
    augmented["observer_id"] = observer_id
    augmented["subject_id"] = subject_id
    augmented["actor_id"] = observer_id
    for candidate in candidates:
        if not MirrorConditions.matches(candidate.get("when", {}), augmented):
            continue
        var requirements_ok := true
        for requirement in candidate.get("requires_claims", []):
            if not _knowledge_requirement_matches(requirement, observer_id):
                requirements_ok = false
                break
        if not requirements_ok:
            continue
        for requirement in candidate.get("requires_models", []):
            var model_requirement: Dictionary = requirement.duplicate(true)
            if not model_requirement.has("subject_id"):
                model_requirement["subject_id"] = subject_id
            if not _model_requirement_matches(model_requirement, observer_id):
                requirements_ok = false
                break
        if requirements_ok:
            filtered.append(candidate)
    return prediction.predict(augmented, filtered)

func preview_action(action: MirrorAction) -> Dictionary:
    if action == null:
        return {"ok": false, "error": "null_action"}
    var snapshot := _snapshot()
    var before_projection := projection_snapshot()
    var previous_suppression := _suppress_signals
    var previous_store_suppression := event_store.suppress_signal
    _suppress_signals = true
    # event_store is a public member with a public signal, so muting the engine's own
    # transaction signals is not enough. Without this, a listener received MirrorEvent
    # objects from a speculative resolution that _restore_snapshot then removed, and
    # get_by_id() on those ids returned null afterwards.
    event_store.suppress_signal = true
    var result := resolve_action(action)
    var after := projection_snapshot()
    _restore_snapshot(snapshot)
    event_store.suppress_signal = previous_store_suppression
    _suppress_signals = previous_suppression
    if not result.get("ok", false):
        return {"ok": false, "preview": true, "error": result.get("error", "preview_failed"), "details": result.get("details", {})}
    return {
        "ok": true,
        "preview": true,
        "would_commit": true,
        "prediction": result.get("prediction", {}),
        "response": result.get("response", {}),
        "observed": result.get("observed", {}),
        "discrepancy": result.get("discrepancy", {}),
        "projection_diff": diff_projections(before_projection, after),
        "event_types": result.get("events", []).map(func(e): return e.event_type),
        "catalog_fingerprint": catalog_fingerprint,
    }

func explain_event(event_id: String, include_transaction: bool = true) -> Dictionary:
    var event := event_store.get_by_id(event_id)
    if event == null:
        return {"ok": false, "error": "event_not_found", "event_id": event_id}
    var causes: Array = []
    for cause_id in event.causes:
        var cause_event := event_store.get_by_id(str(cause_id))
        if cause_event != null:
            causes.append(cause_event.to_dict())
    var caused_by: Array = []
    for candidate in event_store.get_all():
        if event_id in candidate.causes:
            caused_by.append(candidate.to_dict())
    var transaction_events: Array = []
    if include_transaction:
        for tx_event in event_store.get_transaction(event.transaction_id):
            transaction_events.append(tx_event.to_dict())
    var evidence_items := evidence.for_event(event_id)
    return {
        "ok": true,
        "event": event.to_dict(),
        "causes": causes,
        "caused_by": caused_by,
        "transaction": transaction_events,
        "evidence": evidence_items,
        "catalog_fingerprint_matches": catalog_fingerprint.is_empty() or event.catalog_fingerprint.is_empty() or event.catalog_fingerprint == catalog_fingerprint,
        "definition_hash_known": event.definition_hash.is_empty() or _definition_hash_exists(event.definition_hash),
    }

func _definition_hash_exists(definition_hash: String) -> bool:
    for definition in action_definitions.values():
        if MirrorHash.sha256(definition) == definition_hash:
            return true
    for definition in encounter_definitions.values():
        if MirrorHash.sha256(definition) == definition_hash:
            return true
    for definition in transfer_rules.values():
        if MirrorHash.sha256(definition) == definition_hash:
            return true
    for definition in storylet_definitions.values():
        if MirrorHash.sha256(definition) == definition_hash:
            return true
    for definition in operator_definitions.values():
        if MirrorHash.sha256(definition) == definition_hash:
            return true
    for definition in causal_hypothesis_definitions.values():
        if MirrorHash.sha256(definition) == definition_hash:
            return true
    return false

func diff_projections(before: Dictionary, after: Dictionary) -> Array:
    var differences: Array = []
    _diff_values(before, after, "", differences)
    return differences

func _diff_values(before: Variant, after: Variant, path: String, out: Array) -> void:
    if before is Dictionary and after is Dictionary:
        var keys: Array = before.keys()
        for key in after.keys():
            if key not in keys:
                keys.append(key)
        for key in keys:
            var current_path := str(key) if path.is_empty() else path + "." + str(key)
            if not before.has(key):
                out.append({"path": current_path, "kind": "added", "value": after[key]})
            elif not after.has(key):
                out.append({"path": current_path, "kind": "removed", "value": before[key]})
            else:
                _diff_values(before[key], after[key], current_path, out)
    elif before is Array and after is Array:
        var limit := maxi(before.size(), after.size())
        for i in range(limit):
            var current_path := str(i) if path.is_empty() else path + "." + str(i)
            if i >= before.size():
                out.append({"path": current_path, "kind": "added", "value": after[i]})
            elif i >= after.size():
                out.append({"path": current_path, "kind": "removed", "value": before[i]})
            else:
                _diff_values(before[i], after[i], current_path, out)
    elif before != after:
        out.append({"path": path, "kind": "changed", "before": before, "after": after})

func _snapshot() -> Dictionary:
    return {
        "event_store": event_store.to_dict(),
        "knowledge": knowledge.to_dict(),
        "models": models.to_dict(),
        "evidence": evidence.to_dict(),
        "relationships": relationships.to_dict(),
        "prediction": prediction.to_dict(),
        "operators": operators.to_dict(),
        "world_state": world_state.duplicate(true),
        "npc_state": npc_state.duplicate(true),
        "initial_world_state": initial_world_state.duplicate(true),
        "initial_npc_state": initial_npc_state.duplicate(true),
        "action_memory": action_memory.duplicate(true),
        "catalog_is_locked": catalog_is_locked,
        "catalog_revision": catalog_revision,
        "catalog_fingerprint": catalog_fingerprint,
    }

func _restore_snapshot(snapshot: Dictionary) -> void:
    event_store.restore_from_dict(snapshot["event_store"])
    knowledge.restore(snapshot["knowledge"].get("claims", {}))
    models.restore(snapshot["models"])
    evidence.restore(snapshot["evidence"])
    relationships.restore(snapshot["relationships"].get("relations", {}))
    prediction.restore(snapshot["prediction"])
    operators.restore(snapshot.get("operators", {}))
    world_state = snapshot["world_state"].duplicate(true)
    npc_state = snapshot["npc_state"].duplicate(true)
    initial_world_state = snapshot["initial_world_state"].duplicate(true)
    initial_npc_state = snapshot["initial_npc_state"].duplicate(true)
    action_memory = snapshot["action_memory"].duplicate(true)
    catalog_is_locked = bool(snapshot.get("catalog_is_locked", false))
    catalog_revision = int(snapshot.get("catalog_revision", 0))
    catalog_fingerprint = str(snapshot.get("catalog_fingerprint", ""))

func _validate_post_commit() -> bool:
    if not event_store.verify_chain().get("ok", false):
        return false
    if not evidence.validate().get("ok", false):
        return false
    for event in event_store.get_all():
        for evidence_id in event.evidence_refs:
            if evidence.get_evidence(str(evidence_id)).is_empty():
                return false
        for evidence_item in evidence.for_event(event.event_id):
            if evidence_item.is_empty():
                return false
    for evidence_item in evidence.all():
        var source_event := str(evidence_item.get("source_event", ""))
        if not source_event.is_empty() and event_store.get_by_id(source_event) == null:
            return false
    return true

func _fail(code: String, details: Dictionary = {}) -> Dictionary:
    var result := {"ok": false, "error": code, "details": details}
    if not _suppress_signals:
        transaction_failed.emit(result)
    return result

func validate_catalog() -> Dictionary:
    var errors: Array = []
    var warnings: Array = []

    var action_once_keys: Dictionary = {}
    for key in action_definitions.keys():
        var definition: Dictionary = action_definitions[key]
        var id := str(definition.get("id", key))
        if id.is_empty():
            errors.append("Action has empty id")
        var action_once := str(definition.get("once_key", ""))
        if not action_once.is_empty():
            if action_once_keys.has(action_once):
                errors.append("Duplicate action once_key %s" % action_once)
            else:
                action_once_keys[action_once] = id

        var prediction_ids: Dictionary = {}
        for candidate in definition.get("prediction_candidates", []):
            var prediction_id := str(candidate.get("id", ""))
            if prediction_id.is_empty():
                errors.append("Action %s has prediction candidate without id" % id)
            elif prediction_ids.has(prediction_id):
                errors.append("Action %s has duplicate prediction id %s" % [id, prediction_id])
            else:
                prediction_ids[prediction_id] = true
            for condition_error in MirrorConditions.validate(candidate.get("when", {}), "prediction.when"):
                errors.append("Action %s: %s" % [id, str(condition_error)])

        var response_ids: Dictionary = {}
        for response in definition.get("response_contracts", []):
            var response_id := str(response.get("id", ""))
            if response_id.is_empty():
                errors.append("Action %s has response without id" % id)
            elif response_ids.has(response_id):
                errors.append("Action %s has duplicate response id %s" % [id, response_id])
            else:
                response_ids[response_id] = true
            for condition_error in MirrorConditions.validate(response.get("when", {}), "response.when"):
                errors.append("Action %s: %s" % [id, str(condition_error)])
            for requirement in response.get("requires_operators", []):
                var response_operator_id := str(requirement.get("id", "") if requirement is Dictionary else requirement)
                if response_operator_id.is_empty():
                    errors.append("Action %s response %s has empty operator requirement" % [id, response_id])
                elif not operator_definitions.has(response_operator_id):
                    errors.append("Action %s response %s references unknown operator %s" % [id, response_id, response_operator_id])

        var depth := int(definition.get("model_depth", 1))
        if depth < 0 or depth > MirrorDomain.MAX_MODEL_DEPTH:
            errors.append("Action %s has invalid model depth" % id)
        if int(definition.get("time_cost", 0)) < 0:
            errors.append("Action %s has negative time cost" % id)
        for condition_error in MirrorConditions.validate(definition.get("preconditions", {}), "preconditions"):
            errors.append("Action %s: %s" % [id, str(condition_error)])
        for requirement in definition.get("requires_operators", []):
            if str(requirement.get("id", requirement) if requirement is Dictionary else requirement).is_empty():
                errors.append("Action %s has empty operator requirement" % id)
            elif requirement is Dictionary and not operator_definitions.has(str(requirement.get("id", ""))):
                errors.append("Action %s references unknown operator %s" % [id, str(requirement.get("id", ""))])
        for candidate in definition.get("prediction_candidates", []):
            if not candidate.has("expected"):
                warnings.append("Action %s prediction %s has no expected observation." % [id, str(candidate.get("id", ""))])

    for key in encounter_definitions.keys():
        if str(encounter_definitions[key].get("id", key)).is_empty():
            errors.append("Encounter has empty id")

    for key in transfer_rules.keys():
        var transfer: Dictionary = transfer_rules[key]
        var transfer_id := str(transfer.get("id", key))
        if transfer_id.is_empty():
            errors.append("Transfer has empty id")
        for condition_error in MirrorConditions.validate(transfer.get("requires_world", transfer.get("requires", {})), "transfer.requires_world"):
            errors.append("Transfer %s: %s" % [transfer_id, str(condition_error)])
        for valid_context in transfer.get("valid_contexts", []):
            for condition_error in MirrorConditions.validate(valid_context, "transfer.valid_context"):
                errors.append("Transfer %s: %s" % [transfer_id, str(condition_error)])
        for invalid_context in transfer.get("invalid_contexts", []):
            for condition_error in MirrorConditions.validate(invalid_context, "transfer.invalid_context"):
                errors.append("Transfer %s: %s" % [transfer_id, str(condition_error)])

    var storylet_once_keys: Dictionary = {}
    for key in storylet_definitions.keys():
        var storylet: Dictionary = storylet_definitions[key]
        var storylet_id := str(storylet.get("id", key))
        if storylet_id.is_empty():
            errors.append("Storylet has empty id")
        var once := str(storylet.get("once_key", ""))
        if not once.is_empty():
            if storylet_once_keys.has(once):
                errors.append("Duplicate storylet once_key %s" % once)
            else:
                storylet_once_keys[once] = storylet_id
        if int(storylet.get("cooldown_events", 0)) < 0:
            errors.append("Storylet %s has negative cooldown" % storylet_id)
        for condition_error in MirrorConditions.validate(storylet.get("preconditions", {}), "storylet.preconditions"):
            errors.append("Storylet %s: %s" % [storylet_id, str(condition_error)])
        for requirement in storylet.get("requires_operators", []):
            var op_id := str(requirement.get("id", "") if requirement is Dictionary else requirement)
            if op_id.is_empty():
                errors.append("Storylet %s has empty operator requirement" % storylet_id)
            elif not operator_definitions.has(op_id):
                errors.append("Storylet %s references unknown operator %s" % [storylet_id, op_id])

    for key in operator_definitions.keys():
        var operator_definition: Dictionary = operator_definitions[key]
        var operator_id := str(operator_definition.get("id", key))
        if operator_id.is_empty():
            errors.append("Operator has empty id")
        for condition_error in MirrorConditions.validate(operator_definition.get("preconditions", {}), "operator.preconditions"):
            errors.append("Operator %s: %s" % [operator_id, str(condition_error)])
        for valid_context in operator_definition.get("valid_contexts", []):
            for condition_error in MirrorConditions.validate(valid_context, "operator.valid_context"):
                errors.append("Operator %s: %s" % [operator_id, str(condition_error)])
        for invalid_context in operator_definition.get("invalid_contexts", []):
            for condition_error in MirrorConditions.validate(invalid_context, "operator.invalid_context"):
                errors.append("Operator %s: %s" % [operator_id, str(condition_error)])
        for action_id in operator_definition.get("action_ids", []):
            if not action_definitions.has(str(action_id)):
                errors.append("Operator %s references unknown action %s" % [operator_id, str(action_id)])
        for transfer_id in operator_definition.get("transfer_rule_ids", []):
            if not transfer_rules.has(str(transfer_id)):
                errors.append("Operator %s references unknown transfer %s" % [operator_id, str(transfer_id)])

    for key in causal_hypothesis_definitions.keys():
        var hypothesis: Dictionary = causal_hypothesis_definitions[key]
        var hypothesis_id := str(hypothesis.get("id", key))
        if hypothesis_id.is_empty():
            errors.append("Causal hypothesis has empty id")
        var semantic_distance := int(hypothesis.get("semantic_distance", 0))
        var importance := int(hypothesis.get("importance", 0))
        if semantic_distance < 0 or importance < 0:
            errors.append("Causal hypothesis %s has negative difficulty metadata" % hypothesis_id)
        for condition_error in MirrorConditions.validate(hypothesis.get("anomaly", {}), "hypothesis.anomaly"):
            errors.append("Causal hypothesis %s: %s" % [hypothesis_id, str(condition_error)])
        for condition_error in MirrorConditions.validate(hypothesis.get("boundary", {}), "hypothesis.boundary"):
            errors.append("Causal hypothesis %s: %s" % [hypothesis_id, str(condition_error)])
        var operator_id := str(hypothesis.get("operator_id", ""))
        if not operator_id.is_empty() and not operator_definitions.has(operator_id):
            errors.append("Causal hypothesis %s references unknown operator %s" % [hypothesis_id, operator_id])
        if semantic_distance >= 4 and Array(hypothesis.get("requires_evidence", [])).size() < 2:
            warnings.append("Causal hypothesis %s has high semantic distance but fewer than two evidence requirements." % hypothesis_id)
        var boundary_data: Dictionary = hypothesis.get("boundary", {})
        if importance >= 5 and boundary_data.is_empty():
            warnings.append("Causal hypothesis %s is high-importance without an authored boundary." % hypothesis_id)
        if not hypothesis.get("boundary", {}).is_empty() and str(hypothesis.get("reframe_id", "")).is_empty():
            warnings.append("Causal hypothesis %s has a boundary but no reframe_id." % hypothesis_id)
        for transfer_id in hypothesis.get("transfer_ids", []):
            if not transfer_rules.has(str(transfer_id)):
                errors.append("Causal hypothesis %s references unknown transfer %s" % [hypothesis_id, str(transfer_id)])

    return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}

func save_json() -> String:
    return MirrorPersistence.to_json(self)

func load_json(text: String) -> Dictionary:
    return MirrorPersistence.load_json(self, text)

func restore_from_save(data: Dictionary) -> bool:
    if data.is_empty():
        return false
    # "operators" and "catalog" are read below without a type check of their own, so
    # they must be guarded here. Both are always present in a well-formed save and
    # back-filled by MirrorPersistence.migrate(). Guarding them turns a corrupt value
    # into a clean `false` instead of a hard SCRIPT ERROR stack trace.
    var required_sections := ["event_store", "knowledge", "models", "evidence", "relationships", "prediction", "world_state", "npc_state", "initial_world_state", "initial_npc_state", "action_memory", "operators", "catalog"]
    for key in required_sections:
        if not data.get(key, {}) is Dictionary:
            return false
    var candidate_store := MirrorEventStore.new(int(data["event_store"].get("max_events", 100000)))
    if not candidate_store.restore_from_dict(data["event_store"]):
        return false
    if not candidate_store.verify_chain().get("ok", false):
        return false
    var candidate_knowledge := MirrorKnowledgeStore.from_dict(data["knowledge"])
    var candidate_models := MirrorModelStore.from_dict(data["models"])
    var candidate_evidence := MirrorEvidenceStore.from_dict(data["evidence"])
    var candidate_relationships := MirrorRelationshipService.from_dict(data["relationships"])
    var candidate_prediction := MirrorPredictionService.new()
    candidate_prediction.restore(data["prediction"])
    var candidate_operators := MirrorOperatorStore.from_dict(data.get("operators", {}))
    var saved_catalog: Dictionary = data.get("catalog", {})
    var saved_fingerprint := str(saved_catalog.get("fingerprint", ""))
    var current_catalog_fingerprint := compute_catalog_fingerprint()
    if not saved_fingerprint.is_empty() and saved_fingerprint != current_catalog_fingerprint:
        return false
    if saved_fingerprint.is_empty() and candidate_store.size() > 0:
        # Schema 4 had no catalog fingerprint. Preserve compatibility by binding the
        # recovered session to the currently registered catalog after event integrity passes.
        saved_fingerprint = current_catalog_fingerprint

    event_store.max_events = candidate_store.max_events
    event_store._events = candidate_store._events.duplicate()
    event_store._by_id = candidate_store._by_id.duplicate()
    # The transaction index is derived state and must be rebuilt here too.
    # restore_from_dict() rebuilds it, but this method copies fields by hand and
    # bypasses it. Without this, get_transaction() returned {} after load_json(),
    # the idempotency short-circuit was skipped, and retrying a client_request_id
    # committed the transaction a second time. Deep copy: the value arrays must not
    # alias the candidate's.
    event_store._by_transaction = candidate_store._by_transaction.duplicate(true)
    event_store._head_hash = candidate_store._head_hash
    event_store._next_sequence = candidate_store._next_sequence
    knowledge.restore(candidate_knowledge.snapshot())
    models.restore(candidate_models.snapshot())
    evidence.restore(candidate_evidence.snapshot())
    relationships.restore(candidate_relationships.snapshot())
    prediction.restore(candidate_prediction.snapshot())
    operators.restore(candidate_operators.snapshot())
    world_state = data["world_state"].duplicate(true)
    npc_state = data["npc_state"].duplicate(true)
    initial_world_state = data["initial_world_state"].duplicate(true)
    initial_npc_state = data["initial_npc_state"].duplicate(true)
    action_memory = data["action_memory"].duplicate(true)
    catalog_revision = int(saved_catalog.get("revision", catalog_revision))
    catalog_fingerprint = saved_fingerprint if not saved_fingerprint.is_empty() else current_catalog_fingerprint
    catalog_is_locked = bool(saved_catalog.get("locked", event_store.size() > 0))
    return true

func projection_snapshot() -> Dictionary:
    return {
        "world_state": world_state.duplicate(true),
        "npc_state": npc_state.duplicate(true),
        "knowledge": knowledge.to_dict(),
        "models": models.to_dict(),
        "evidence": evidence.to_dict(),
        "relationships": relationships.to_dict(),
        "prediction": prediction.to_dict(),
        "operators": operators.to_dict(),
        "action_memory": action_memory.duplicate(true),
        "catalog": {"revision": catalog_revision, "fingerprint": catalog_fingerprint, "locked": catalog_is_locked},
    }

func rebuild_projections_from_event_log() -> Dictionary:
    if not event_store.verify_chain().get("ok", false):
        return {"ok": false, "error": "event_chain_invalid"}
    world_state = initial_world_state.duplicate(true)
    npc_state = initial_npc_state.duplicate(true)
    knowledge.restore({})
    models.restore({"rules": {}, "observations": []})
    evidence.restore({"items": {}, "by_event": {}})
    relationships.restore({})
    prediction.restore({"seen_once": {}})
    operators.restore({})
    action_memory = {}
    for event in event_store.get_all():
        match event.event_type:
            "ActionResolved":
                var action_payload: Dictionary = event.payload.get("action", {})
                var actor := str(action_payload.get("actor_id", event.actor_id))
                models.observe_action(actor, event.payload.get("model_observation", event.prediction_signature), action_payload.get("context", {}), event.event_id, actor)
                var action_once := str(event.payload.get("action_once_key", ""))
                if not action_once.is_empty(): action_memory["action_once:" + action_once] = event.event_id
                var prediction_once := str(event.payload.get("prediction_once_key", ""))
                if not prediction_once.is_empty(): prediction.consume_once(prediction_once)
                var request_id := str(event.payload.get("client_request_id", ""))
                if not request_id.is_empty():
                    action_memory["request:" + request_id] = event.transaction_id
                    action_memory["request_fingerprint:" + request_id] = str(event.payload.get("request_fingerprint", ""))
                    if str(action_memory["request_fingerprint:" + request_id]).is_empty():
                        action_memory["request_fingerprint:" + request_id] = _action_request_fingerprint_from_event(event.event_id)
                action_memory["transaction:" + event.transaction_id] = event.event_id
            "KnowledgeShared":
                var shared := event.payload
                _apply_knowledge_effects([shared.get("knowledge_effect", {})], event.event_id)
                _apply_evidence(shared.get("evidence", []))
            "ObservationRecorded":
                var observation_payload: Dictionary = event.payload
                models.observe_action(str(event.target_id), observation_payload.get("observation", {}).get("signature", []), observation_payload.get("context", {}), event.event_id, str(event.actor_id))
                _apply_knowledge_effects(observation_payload.get("knowledge_effects", []), event.event_id)
                _apply_model_effects(observation_payload.get("model_effects", []), event.event_id)
                _apply_operator_effects(observation_payload.get("operator_effects", []), event.event_id)
                _apply_evidence(observation_payload.get("evidence", []))
            "ResponseResolved":
                var response_payload: Dictionary = event.payload
                _apply_response_effects(response_payload.get("effects", {}), event.event_id)
                _apply_knowledge_effects(response_payload.get("knowledge_effects", []), event.event_id)
                _apply_model_effects(response_payload.get("model_effects", []), event.event_id)
                _apply_operator_effects(response_payload.get("operator_effects", []), event.event_id)
                relationships.record(str(event.target_id), str(event.actor_id), event.event_id, response_payload.get("relationship_tags", []), response_payload.get("relationship_payload", {}))
                _apply_transfer_applications(response_payload.get("transfer_applications", []), event.event_id)
                _apply_evidence(response_payload.get("evidence", []))
            "TimeAdvanced":
                world_state["__mirror_time"] = int(event.payload.get("to", get_time()))
            "OperatorAcquired":
                operators.acquire(str(event.payload.get("operator_id", "")), str(event.payload.get("observer_id", event.actor_id)), event.event_id, str(event.payload.get("source", "authored")), event.payload.get("context", {}))
            "OperatorRevoked":
                operators.revoke(str(event.payload.get("operator_id", "")), str(event.payload.get("observer_id", event.actor_id)), event.event_id)
            "ContentConsumed":
                var storylet_id := str(event.payload.get("storylet_id", ""))
                action_memory["storylet_event:" + storylet_id] = event.sequence
                action_memory["storylet_seen:" + storylet_id] = event.sequence
                action_memory["storylet_count:" + storylet_id] = int(action_memory.get("storylet_count:" + storylet_id, 0)) + 1
                var storylet_once := str(event.payload.get("once_key", ""))
                if not storylet_once.is_empty(): action_memory[storylet_once] = event.event_id
    action_memory["__event_count"] = event_store.size()
    catalog_is_locked = event_store.size() > 0
    if catalog_fingerprint.is_empty() and catalog_is_locked:
        catalog_fingerprint = compute_catalog_fingerprint()
    return {"ok": true, "before": {}, "after": projection_snapshot(), "event_count": event_store.size()}

func replay_all() -> Dictionary:
    var result := rebuild_projections_from_event_log()
    if not result.get("ok", false):
        return result
    return {"ok": true, "event_count": result["event_count"], "head_hash": event_store.head_hash(), "projection": result["after"]}
