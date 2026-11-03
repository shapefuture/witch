class_name MirrorProgressValidator
extends RefCounted

# Whole-graph content checks: knowledge gates reachable from the start, critical claims with
# redundant routes, responses that cannot destroy progress, and a diagnostic-vocabulary lint for
# player-facing text. The mapping onto this engine's schema is in docs/engine/HARDENING.md.
#
# The definitions are explored as an abstract state machine: world state, NPC state and the
# player's knowledge statuses. Every state the engine could reach is represented, so a gate
# missing from every reachable state is a real problem. Two things are over-approximated (treated
# as always satisfiable): model and operator requirements, and once-only actions. Over-approximation
# can hide a problem, never invent one.
#
# options (all optional):
#   terminal          Array of conditions. A state matching one is an ending; transitions into an
#                     ending are exempt from the progress rule (ENDING_ACTION in DESIGN_INVARIANTS).
#   goals             Array of claim ids that must stay reachable: no response may make one
#                     unreachable for good. Success legitimately closes side branches, so only
#                     goals are protected, not every gate.
#   critical_claims   Array of claim ids that need at least min_routes evidence routes.
#   min_routes        default 2.
#   max_states        default 20000. Past it the analysis says so as an error, never a silent pass.

const DEFAULT_MIN_ROUTES := 2
const DEFAULT_MAX_STATES := 20000
const LINT_IGNORED_TOP_LEVEL_PREFIX := "_"

# Checks every knowledge gate and every response against the abstract state graph.
# Returns {"ok", "errors", "warnings", "stats"}.
static func check(engine: MirrorEngine, options: Dictionary = {}) -> Dictionary:
    var errors: Array = []
    var warnings: Array = []
    var critical: Array = options.get("critical_claims", [])
    var goals: Array = options.get("goals", [])
    var min_routes := int(options.get("min_routes", DEFAULT_MIN_ROUTES))
    var graph := explore(engine, options)
    var stats := {"states": graph["states"].size(), "transitions": graph["edges"].size(), "truncated": graph["truncated"]}
    var gates := _gates(engine)

    _check_routes(_routes(engine), gates, critical, min_routes, errors, warnings)
    if graph["truncated"]:
        errors.append("progress analysis incomplete: more than %d reachable states; raise max_states or split the content" % int(options.get("max_states", DEFAULT_MAX_STATES)))
        return _report(errors, warnings, stats)

    var targets := _targets(gates, goals)
    var reach := _reach_by_gate(graph, targets)
    var target_ids: Array = targets.keys()
    target_ids.sort()
    for claim_id in target_ids:
        if not reach[claim_id].is_empty():
            continue
        if gates.has(claim_id):
            errors.append("knowledge gate '%s' is unreachable from the start (required by %s)" % [claim_id, ", ".join(gates[claim_id]["owners"])])
        else:
            errors.append("goal '%s' is unreachable from the start" % claim_id)
    _check_progress(graph, goals, reach, errors, warnings)
    return _report(errors, warnings, stats)

# Gates and goals together: the claims whose reachability is checked. A goal that is not also a
# gate is asked for at the weakest status.
static func _targets(gates: Dictionary, goals: Array) -> Dictionary:
    var targets: Dictionary = gates.duplicate(true)
    for goal in goals:
        var claim_id := str(goal)
        if not targets.has(claim_id):
            targets[claim_id] = {"min": MirrorDomain.EpistemicStatus.POSSIBLE, "owners": ["goal"]}
    return targets

# Lints player-facing prose. `texts` maps text keys to strings; keys starting with "_" are
# metadata and are skipped. A token is rejected when it is an engine identifier (anything with an
# underscore), an engine enum or ontology name, or a word from the engine's own vocabulary.
static func lint_text(engine: MirrorEngine, texts: Dictionary) -> Dictionary:
    var errors: Array = []
    var warnings: Array = []
    var vocabulary := _vocabulary(engine)
    var word := RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
    var keys: Array = []
    for key in texts.keys():
        if not str(key).begins_with(LINT_IGNORED_TOP_LEVEL_PREFIX):
            keys.append(key)
    keys.sort()
    for key in keys:
        var text := str(texts[key])
        for found in word.search_all(text):
            var token := found.get_string()
            if token.contains("_"):
                errors.append("%s: engine identifier '%s' in player-facing text" % [key, token])
            elif vocabulary.has(token.to_lower()):
                errors.append("%s: engine vocabulary '%s' in player-facing text" % [key, token])
    return _report(errors, warnings, {"texts": keys.size()})

# The explored state graph. States are dictionaries {world, npc, claims}; claims maps a claim id
# to its epistemic status. Edges record which response produced each transition.
static func explore(engine: MirrorEngine, options: Dictionary = {}) -> Dictionary:
    var terminal: Array = options.get("terminal", [])
    var max_states := int(options.get("max_states", DEFAULT_MAX_STATES))
    var start := {"world": engine.world_state.duplicate(true), "npc": engine.npc_state.duplicate(true), "claims": {}}
    var states: Array = [start]
    var ends: Array = [_matches_any(terminal, _context(start))]
    var index: Dictionary = {MirrorHash.canonical_json(start): 0}
    var edges: Array = []
    var truncated := false
    var action_ids: Array = engine.action_definitions.keys()
    action_ids.sort()
    var cursor := 0
    while cursor < states.size():
        var state: Dictionary = states[cursor]
        var from := cursor
        cursor += 1
        if ends[from]:
            continue
        var context := _context(state)
        for action_id in action_ids:
            var definition: Dictionary = engine.action_definitions[action_id]
            if not _action_enabled(definition, context, state["claims"]):
                continue
            for response in definition.get("response_contracts", []):
                if not MirrorConditions.matches(response.get("when", {}), context):
                    continue
                var next := _apply(state, response)
                var key := MirrorHash.canonical_json(next)
                if not index.has(key):
                    if states.size() >= max_states:
                        truncated = true
                        continue
                    index[key] = states.size()
                    states.append(next)
                    ends.append(_matches_any(terminal, _context(next)))
                edges.append({"from": from, "to": index[key], "action": str(action_id), "response": str(response.get("id", "")), "marked": _is_marked(response)})
    return {"states": states, "ends": ends, "edges": edges, "truncated": truncated}

# Knowledge gates: every claim a requirement names, with the strictest minimum status asked of it
# and the actions, storylets or hypotheses that ask. Only the player's own claims are gates.
static func _gates(engine: MirrorEngine) -> Dictionary:
    var gates: Dictionary = {}
    for action_id in engine.action_definitions.keys():
        var definition: Dictionary = engine.action_definitions[action_id]
        _collect_gates(definition.get("requires_claims", []), str(action_id), gates)
        for response in definition.get("response_contracts", []):
            _collect_gates(response.get("requires_claims", []), str(action_id), gates)
    for storylet_id in engine.storylet_definitions.keys():
        var storylet: Dictionary = engine.storylet_definitions[storylet_id]
        _collect_gates(storylet.get("requires_claims", []), "storylet " + str(storylet_id), gates)
    for hypothesis_id in engine.causal_hypothesis_definitions.keys():
        var hypothesis: Dictionary = engine.causal_hypothesis_definitions[hypothesis_id]
        _collect_gates(hypothesis.get("requires_evidence", []), "hypothesis " + str(hypothesis_id), gates)
    return gates

static func _collect_gates(requirements: Variant, owner: String, gates: Dictionary) -> void:
    if not requirements is Array:
        return
    for requirement in requirements:
        var claim_id := ""
        var minimum := MirrorDomain.EpistemicStatus.POSSIBLE
        if requirement is Dictionary:
            if str(requirement.get("holder_id", "player")) != "player":
                continue
            claim_id = str(requirement.get("id", ""))
            minimum = int(requirement.get("min_status", minimum))
        else:
            claim_id = str(requirement)
        if claim_id.is_empty():
            continue
        if not gates.has(claim_id):
            gates[claim_id] = {"min": minimum, "owners": []}
        elif MirrorDomain.epistemic_rank(minimum) > MirrorDomain.epistemic_rank(int(gates[claim_id]["min"])):
            gates[claim_id]["min"] = minimum
        if owner not in gates[claim_id]["owners"]:
            gates[claim_id]["owners"].append(owner)

# Evidence routes: for each claim, the distinct actions whose responses can give it. Two responses
# of one action are one route; two actions are two routes.
static func _routes(engine: MirrorEngine) -> Dictionary:
    var routes: Dictionary = {}
    for action_id in engine.action_definitions.keys():
        var definition: Dictionary = engine.action_definitions[action_id]
        for response in definition.get("response_contracts", []):
            for effect in response.get("knowledge_effects", []):
                if not effect is Dictionary or str(effect.get("holder_id", "player")) != "player":
                    continue
                var claim_id := str(effect.get("id", ""))
                if claim_id.is_empty():
                    continue
                if not routes.has(claim_id):
                    routes[claim_id] = []
                if str(action_id) not in routes[claim_id]:
                    routes[claim_id].append(str(action_id))
    return routes

static func _check_routes(routes: Dictionary, gates: Dictionary, critical: Array, min_routes: int, errors: Array, warnings: Array) -> void:
    for claim_id in critical:
        var count: int = routes.get(str(claim_id), []).size()
        if count < min_routes:
            errors.append("critical claim '%s' has %d evidence route(s), needs %d (epistemic redundancy)" % [str(claim_id), count, min_routes])
    var gate_ids: Array = gates.keys()
    gate_ids.sort()
    for claim_id in gate_ids:
        var count: int = routes.get(claim_id, []).size()
        if count == 1 and claim_id not in critical:
            warnings.append("single evidence route (fragile): '%s' comes only from %s" % [claim_id, str(routes[claim_id][0])])

# For each gate, the states from which some state achieving it is reachable (a backward search over
# the explored edges). A gate whose set is empty is unreachable from the start.
static func _reach_by_gate(graph: Dictionary, gates: Dictionary) -> Dictionary:
    var states: Array = graph["states"]
    var incoming: Array = []
    incoming.resize(states.size())
    for i in states.size():
        incoming[i] = []
    for edge in graph["edges"]:
        incoming[edge["to"]].append(edge["from"])
    var reach: Dictionary = {}
    for claim_id in gates.keys():
        var minimum := int(gates[claim_id]["min"])
        var seen: Dictionary = {}
        var frontier: Array = []
        for i in states.size():
            if _achieves(states[i]["claims"], claim_id, minimum):
                seen[i] = true
                frontier.append(i)
        while not frontier.is_empty():
            var at: int = frontier.pop_back()
            for previous in incoming[at]:
                if not seen.has(previous):
                    seen[previous] = true
                    frontier.append(previous)
        reach[claim_id] = seen
    return reach

static func _check_progress(graph: Dictionary, goals: Array, reach: Dictionary, errors: Array, warnings: Array) -> void:
    var goal_ids: Array = goals.duplicate()
    goal_ids.sort()
    var closed_by: Dictionary = {}
    for edge in graph["edges"]:
        if graph["ends"][edge["to"]]:
            continue
        for goal in goal_ids:
            var can: Dictionary = reach[goal]
            if can.has(edge["from"]) and not can.has(edge["to"]):
                var where := "%s/%s" % [edge["action"], edge["response"]]
                if not closed_by.has(where):
                    closed_by[where] = {"goals": [], "marked": edge["marked"]}
                if str(goal) not in closed_by[where]["goals"]:
                    closed_by[where]["goals"].append(str(goal))
    var wheres: Array = closed_by.keys()
    wheres.sort()
    for where in wheres:
        var entry: Dictionary = closed_by[where]
        var names := ", ".join(entry["goals"])
        if entry["marked"]:
            warnings.append("response %s closes goal '%s' for good; allowed because it is marked UNRESOLVED_BY_DESIGN" % [where, names])
        else:
            errors.append("response %s destroys progress: no reachable state after it achieves goal '%s' (mark it UNRESOLVED_BY_DESIGN if the loss is intended, or make it an ending)" % [where, names])

static func _report(errors: Array, warnings: Array, stats: Dictionary) -> Dictionary:
    return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "stats": stats}

static func _context(state: Dictionary) -> Dictionary:
    var context: Dictionary = state["world"].duplicate()
    context["npc"] = state["npc"]
    return context

static func _matches_any(conditions: Array, context: Dictionary) -> bool:
    for condition in conditions:
        if MirrorConditions.matches(condition, context):
            return true
    return false

static func _action_enabled(definition: Dictionary, context: Dictionary, claims: Dictionary) -> bool:
    if not MirrorConditions.matches(definition.get("preconditions", {}), context):
        return false
    for requirement in definition.get("requires_claims", []):
        if not _holds(requirement, claims, true):
            return false
    for requirement in definition.get("excludes_claims", []):
        if _holds(requirement, claims, false):
            return false
    return true

# A requirement on another holder cannot be decided from the player's state. `other_holder` is
# the answer to give for it: true for a requirement that must hold, false for an exclusion.
static func _holds(requirement: Variant, claims: Dictionary, other_holder: bool) -> bool:
    var claim_id := ""
    var minimum := MirrorDomain.EpistemicStatus.POSSIBLE
    if requirement is Dictionary:
        if str(requirement.get("holder_id", "player")) != "player":
            return other_holder
        claim_id = str(requirement.get("id", ""))
        minimum = int(requirement.get("min_status", minimum))
    else:
        claim_id = str(requirement)
    return _achieves(claims, claim_id, minimum)

static func _achieves(claims: Dictionary, claim_id: String, minimum: int) -> bool:
    return claims.has(claim_id) and MirrorDomain.epistemic_satisfies(int(claims[claim_id]), minimum)

static func _apply(state: Dictionary, response: Dictionary) -> Dictionary:
    var world: Dictionary = state["world"].duplicate(true)
    var npc: Dictionary = state["npc"].duplicate(true)
    var claims: Dictionary = state["claims"].duplicate(true)
    var effects: Dictionary = response.get("effects", {})
    for key in effects.get("world", {}).keys():
        world[key] = effects["world"][key]
    for npc_id in effects.get("npc_state", {}).keys():
        var patched: Dictionary = npc.get(npc_id, {}).duplicate(true)
        var patch: Dictionary = effects["npc_state"][npc_id]
        for field in patch.keys():
            patched[field] = patch[field]
        npc[npc_id] = patched
    for effect in response.get("knowledge_effects", []):
        if not effect is Dictionary or str(effect.get("holder_id", "player")) != "player":
            continue
        var claim_id := str(effect.get("id", ""))
        if claim_id.is_empty():
            continue
        claims[claim_id] = _status_of(effect.get("status", MirrorDomain.EpistemicStatus.POSSIBLE))
    return {"world": world, "npc": npc, "claims": claims}

static func _is_marked(response: Dictionary) -> bool:
    for effect in response.get("knowledge_effects", []):
        if effect is Dictionary and _status_of(effect.get("status", MirrorDomain.EpistemicStatus.POSSIBLE)) == MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN:
            return true
    return false

# Definitions are normalised to ints by MirrorCatalog; a raw name is accepted too, so a check
# never reads "UNRESOLVED_BY_DESIGN" as status 0.
static func _status_of(value: Variant) -> int:
    if value is String or value is StringName:
        return int(MirrorDomain.EpistemicStatus.get(str(value), MirrorDomain.EpistemicStatus.POSSIBLE))
    return int(value)

static func _vocabulary(engine: MirrorEngine) -> Dictionary:
    var vocabulary: Dictionary = {}
    for table in [MirrorDomain.EpistemicStatus, MirrorDomain.ActionType, MirrorDomain.ModelStatus, MirrorDomain.EvidenceType, MirrorDomain.DiscrepancyKind]:
        for name in table.keys():
            vocabulary[str(name).to_lower()] = true
    for word in ["claim", "claims", "proposition", "epistemic", "discrepancy", "prediction", "predicts", "outcome", "motive", "ontology", "expect", "knowledge", "mirror", "engine", "affordance", "storylet", "operator", "hypothesis", "checksum"]:
        vocabulary[word] = true
    for id_source in [engine.action_definitions, engine.storylet_definitions, engine.causal_hypothesis_definitions, engine.operator_definitions]:
        for id in id_source.keys():
            vocabulary[str(id).to_lower()] = true
    for key in engine.world_state.keys():
        vocabulary[str(key).to_lower()] = true
    for key in engine.npc_state.keys():
        vocabulary[str(key).to_lower()] = true
    return vocabulary
