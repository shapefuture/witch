class_name MirrorMinds
extends RefCounted

# The Minds layer: what the people (and animals, and statues) in a place make of what happens there.
#
#   perceive(event)  ->  who witnesses it (WitnessSelector)  ->  how each reads it (MindsInterpreter)
#                    ->  which world rules answer it (MindsRules) -> what is scheduled for later
#                    ->  which conventions it feeds (ConventionBook)
#                    ->  ONE atomic Mirror transaction: the happening plus every witness's observation.
#
# Mirror stays the only authority. This class decides nothing a scene may decide and keeps no truth of its
# own: its state (presence, the deferred queue, the folklore) is derived from the event log by MindsState,
# re-synchronised before every call, so it follows a save/load, a rollback or a replay with no hook at all.
# Every choice is made at commit time and written into the event's payload; applying it later needs none.
#
# Time: deferred consequences fall due when the Mirror clock passes them. Any committed transaction that
# advances the clock (advance_time(), an action with a time_cost) pumps the queue, in (due, id) order, so the
# order of effects does not depend on how time was chunked.
#
# Events a caller may pass (see data/mirror/minds/minds.json for the kinds):
#   {kind, actor, subject, place?, data?, hints?, truth?}
# `hints` is perception data only the scene can know: {present: [ids on stage], absent: [ids],
# distance: {id: metres}, los: {id: bool}, attention: {id: idle|attending|busy|away|asleep}, loudness: pct}.

signal world_event(result: Dictionary)
signal consequence_fired(result: Dictionary)

var engine: MirrorEngine
var data: Dictionary
var state := MindsState.new()

var _rules: MindsRules
var _interpreter: MindsInterpreter
var _applied := 0
var _tip_id := ""
var _tip_hash := ""
var _pumping := false
var _fired_log: Array = []

func _init(p_engine: MirrorEngine, p_data: Dictionary = {}) -> void:
	engine = p_engine
	data = p_data if not p_data.is_empty() else MindsCatalog.empty()
	_rules = MindsRules.new(data)
	_interpreter = MindsInterpreter.new(engine, data)
	state.reset(data)
	engine.transaction_committed.connect(_on_committed)

# ---- public API ---------------------------------------------------------------------------------------

# Commits one happening and everything it causes in the minds around it. Returns {ok, recorded, event_id,
# witnesses, unaware, interpretations, reactions, presentation, scheduled, cancelled, convention_changes,
# fired}. `recorded` is false only for a quiet kind (a walk) that nobody reacted to: nothing is written.
func perceive(raw_event: Dictionary) -> Dictionary:
	_sync()
	var seeded := _ensure_seeded()
	if not seeded.get("ok", false):
		return seeded
	var result := _commit_event(_normalize(raw_event), {})
	if result.get("ok", false):
		_pump()
	return result

# Time passes: the clock moves, and whatever fell due happens, in order. Returns the engine's result plus
# `fired`: the results of the consequences that fell due during this call.
func advance_time(delta: int, reason: String = "wait") -> Dictionary:
	_sync()
	var before := _fired_log.size()
	var result := engine.advance_time(delta, "player", reason)
	if not result.get("ok", false):
		return result
	_pump()
	result["fired"] = _fired_log.slice(before)
	return result

# Somebody comes or goes. Presence is Mirror's truth (it decides who can witness), recorded as an event.
func set_presence(holder: String, place: String) -> Dictionary:
	_sync()
	if not data.get("holders", {}).has(holder):
		return {"ok": false, "error": "unknown_holder", "details": {"holder": holder}}
	if not data.get("places", {}).has(place):
		return {"ok": false, "error": "unknown_place", "details": {"place": place}}
	return engine.record_world_event("world", holder, {"kind": "presence.changed", "time": engine.get_time(), "presence": {"holder": holder, "place": place}})

# Who WOULD perceive this event, without committing anything.
func preview_witnesses(raw_event: Dictionary) -> Dictionary:
	_sync()
	var event := _normalize(raw_event)
	return _select(event, data.get("event_kinds", {}).get(str(event["kind"]), {}))

# What two holders each took to have happened, and how their accounts differ (the engine's own discrepancy
# vector: ACTOR if they blame different people, OUTCOME if they saw different things...).
func compare_accounts(event_id: String, holder_a: String, holder_b: String) -> Dictionary:
	var event := engine.event_store.get_by_id(event_id)
	if event == null or event.event_type != "WorldEventHappened":
		return {"ok": false, "error": "event_not_found"}
	var accounts: Dictionary = {}
	for reading in event.payload.get("interpretations", []):
		accounts[str(reading.get("holder", ""))] = reading.get("perceived", {})
	if not accounts.has(holder_a) or not accounts.has(holder_b):
		return {"ok": false, "error": "not_a_witness", "details": {"witnesses": accounts.keys()}}
	var a: Dictionary = accounts[holder_a]
	var b: Dictionary = accounts[holder_b]
	var comparison := engine.discrepancy.compare({"expected": MindsInterpreter.shared(a, b)}, b)
	return {"ok": true, "agree": not bool(comparison.get("has_discrepancy", false)), "kinds": comparison.get("kinds", []), "vector": comparison.get("vector", {}), "accounts": {holder_a: a, holder_b: b}}

func pending() -> Array:
	_sync()
	return state.queue.pending()

func presence_of(holder: String) -> String:
	_sync()
	return str(state.presence.get(holder, ""))

func active_conventions() -> Array:
	_sync()
	return state.conventions.active_ids()

func is_convention_active(id: String) -> bool:
	_sync()
	return state.conventions.is_active(id)

func convention_state(id: String) -> Dictionary:
	_sync()
	return state.conventions.get_state(id)

# Results of the consequences that fell due since the last call (a time-costing action pumps the queue from
# inside its own commit, so a caller that wants to present them reads them here afterwards).
func take_fired() -> Array:
	var out := _fired_log.duplicate()
	_fired_log.clear()
	return out

# Derives the state again from the log. Calls re-synchronise themselves, so this is only for tests/tools.
func rebuild() -> void:
	_applied = 0
	_tip_id = ""
	_tip_hash = ""
	state.reset(data)
	_sync()

# ---- synchronisation with the log -----------------------------------------------------------------------

func _sync() -> void:
	var store := engine.event_store
	var size := store.size()
	if _applied > 0:
		var tip := store.get_by_id(_tip_id)
		if tip == null or tip.hash != _tip_hash or tip.sequence != _applied or size < _applied:
			_applied = 0
			state.reset(data)
	if size > _applied:
		for event in store.tail(size - _applied):
			state.apply(event)
		var last: MirrorEvent = store.tail(1)[0]
		_applied = size
		_tip_id = last.event_id
		_tip_hash = last.hash

func _on_committed(result: Dictionary) -> void:
	if _pumping:
		return
	for event in result.get("events", []):
		if event is MirrorEvent and event.event_type == "TimeAdvanced":
			_pump()
			return

func _pump() -> void:
	if _pumping:
		return
	_pumping = true
	_sync()
	var limits: Dictionary = data["limits"]
	var fired := 0
	while fired < int(limits["max_fired_per_pump"]):
		var due := state.queue.due(engine.get_time())
		if due.is_empty():
			break
		var result := _fire(due[0])
		if not result.get("ok", false):
			push_error("MirrorMinds: could not fire %s: %s" % [due[0].get("id", "?"), JSON.stringify(result)])
			break
		fired += 1
		_fired_log.append(result)
		consequence_fired.emit(result)
	_pumping = false

func _fire(entry: Dictionary) -> Dictionary:
	var origin: Dictionary = entry.get("origin", {}).duplicate(true)
	origin["consequence"] = str(entry["id"])
	origin["due"] = int(entry["due"])
	var spec: Dictionary = entry["event"]
	var event := _normalize(spec)
	event["time"] = int(entry["due"])
	if entry.has("when"):
		var tags := _subject_tags(event)
		var context := _context(event, tags, [], state.conventions.active_ids(), int(entry["due"]))
		if not MirrorConditions.matches(entry["when"], context):
			var payload := {"kind": "consequence.fizzled", "time": int(entry["due"]), "fired": [str(entry["id"])], "origin": origin, "reason": "conditions", "subject": str(event["subject"])}
			var fizzled := engine.record_world_event("world", str(event["subject"]), payload)
			if fizzled.get("ok", false):
				_sync()
				fizzled["fired"] = [str(entry["id"])]
				fizzled["kind"] = "consequence.fizzled"
			return fizzled
	return _commit_event(event, origin)

# Starting beliefs are written once, as the first event of the layer, so they are history like everything else.
func _ensure_seeded() -> Dictionary:
	if state.seeded:
		return {"ok": true}
	var beliefs: Array = data.get("initial_beliefs", [])
	if beliefs.is_empty():
		return {"ok": true}
	var observations: Array = []
	for belief in beliefs:
		var holder := str(belief.get("holder", ""))
		var acc := _accumulator(holder)
		acc["subject_id"] = holder
		acc["observation"] = {"signature": ["SEED"]}
		_add_effects(acc, belief, {"holder": holder}, holder, "")
		observations.append(_finish(acc))
	var result := engine.record_world_event("world", "", {"kind": "minds.seed", "seed": true, "time": engine.get_time()}, observations)
	if result.get("ok", false):
		_sync()
	return result

# ---- one happening ------------------------------------------------------------------------------------------

func _normalize(raw: Dictionary) -> Dictionary:
	var event: Dictionary = {
		"kind": str(raw.get("kind", "")),
		"actor": str(raw.get("actor", "player")),
		"subject": str(raw.get("subject", "")),
		"data": (raw.get("data", {}) as Dictionary).duplicate(true),
		"hints": (raw.get("hints", {}) as Dictionary).duplicate(true),
		"truth": (raw.get("truth", {}) as Dictionary).duplicate(true),
	}
	var place := str(raw.get("place", ""))
	if place.is_empty():
		place = str(state.presence.get(event["actor"], ""))
	if place.is_empty():
		var places: Array = data.get("places", {}).keys()
		places.sort()
		place = str(data.get("default_place", places[0] if not places.is_empty() else ""))
	event["place"] = place
	return event

func _commit_event(event: Dictionary, origin: Dictionary) -> Dictionary:
	var kind := str(event["kind"])
	var kind_def: Dictionary = data["event_kinds"].get(kind, {})
	if kind_def.is_empty():
		return {"ok": false, "error": "unknown_event_kind", "details": {"kind": kind}}
	var limits: Dictionary = data["limits"]
	var at := int(origin.get("due", engine.get_time()))
	var depth := int(origin.get("depth", 0))
	event["time"] = at
	var event_id := engine.next_world_event_id()
	var tags := _subject_tags(event)
	var picked := _select(event, kind_def)
	var witnesses: Array = picked["witnesses"]
	var witness_ids: Array = []
	for witness in witnesses:
		witness_ids.append(str(witness["holder"]))
	var truth: Dictionary = kind_def.get("truth", {}).duplicate(true)
	truth.merge(event["truth"], true)
	truth["actor_id"] = str(event["actor"])
	var active: Array = state.conventions.active_ids()
	var context := _context(event, tags, witness_ids, active, at)
	var base_vars: Dictionary = MindsInterpreter.variables(event)

	var observers: Dictionary = {}
	var reactions: Array = []
	var interpretations: Array = []
	var readings: Array = []
	var world_effects: Dictionary = {"world": {}, "npc_state": {}}
	var plan := {"pending": state.queue.pending(), "scheduled": [], "cancelled": [], "dropped": []}

	for witness in witnesses:
		var holder := str(witness["holder"])
		var reading := _interpreter.interpret(event, witness, context, active, truth)
		var acc := _observer(observers, holder)
		acc["subject_id"] = str(event["subject"])
		acc["observation"] = {"signature": ["WITNESS", kind], "channel": str(witness["channel"]), "clarity": int(witness["clarity"]), "reads": str(reading["reads"])}
		acc["context"] = {"event_kind": kind, "place": str(event["place"]), "attention": str(witness.get("attention", "idle"))}
		(acc["evidence"] as Array).append_array(reading["evidence"])
		_add_effects(acc, reading, {}, holder, str(event["place"]), true)
		reactions.append_array(reading["reactions"])
		interpretations.append({
			"holder": holder, "rule": str(reading["rule_id"]), "reads": str(reading["reads"]), "perceived": reading["perceived"],
			"misread": bool(reading["misread"]), "kinds": reading["kinds"], "surprise": reading["surprise"], "channel": str(witness["channel"]),
		})
		if str(reading["reads"]) != "noticed":
			readings.append({"holder": holder, "reads": str(reading["reads"]), "subject": str(event["subject"]), "kind": kind})

	# Folklore first: what this event's readings did to the conventions, so a variant can react to a change.
	var evaluation := ConventionBook.evaluate(data.get("conventions", []), state.conventions, data.get("communities", {}), readings, event_id, kind, at, tags, limits)
	var reads_by_holder: Dictionary = {}
	for reading in interpretations:
		reads_by_holder[str(reading["holder"])] = str(reading["reads"])
	context["reads"] = reads_by_holder
	context["convention_changes"] = evaluation["changes"]

	# The variant this very event is the consequence of: its evidence lands now, for whoever sees it.
	var origin_variant: Dictionary = _rules.variant(str(origin.get("variant", "")))
	if not origin_variant.is_empty():
		var origin_evidence: Dictionary = origin_variant.get("evidence", {})
		if str(origin_evidence.get("at", "consequence")) == "consequence":
			_deliver(origin_evidence, base_vars, witness_ids, observers, str(event["place"]))

	for hit in _rules.triggered(event, witness_ids, tags, active, depth, context, int(limits["max_chain_depth"])):
		var variant: Dictionary = hit["variant"]
		var vars: Dictionary = base_vars.duplicate()
		vars["holder"] = str(hit["holder"])
		var transformation: Dictionary = variant.get("transformation", {})
		for reaction in transformation.get("reactions", []):
			var entry: Dictionary = MindsTemplate.apply(reaction, vars)
			entry["by"] = str(hit["variant_id"])
			reactions.append(entry)
		var effects: Dictionary = MindsTemplate.apply(transformation.get("effects", {}), vars)
		for key in effects.get("world", {}).keys():
			world_effects["world"][key] = effects["world"][key]
		for npc_id in effects.get("npc_state", {}).keys():
			var patch: Dictionary = world_effects["npc_state"].get(npc_id, {})
			patch.merge(effects["npc_state"][npc_id], true)
			world_effects["npc_state"][npc_id] = patch
		for spec in transformation.get("schedule", []):
			_schedule(spec, vars, {"rule": str(hit["rule"]), "variant": str(hit["variant_id"])}, at, depth, plan, observers, witness_ids, str(event["place"]), limits)
		var evidence: Dictionary = variant.get("evidence", {})
		var has_schedule := not (transformation.get("schedule", []) as Array).is_empty()
		if str(evidence.get("at", "consequence" if has_schedule else "trigger")) == "trigger":
			_deliver(evidence, vars, witness_ids, observers, str(event["place"]))

	for change in evaluation["changes"]:
		_apply_convention_change(change, observers)

	var recorded_effects: bool = not reactions.is_empty() or not (plan["scheduled"] as Array).is_empty() or not (plan["cancelled"] as Array).is_empty() \
		or not (evaluation["updates"] as Array).is_empty() or not world_effects["world"].is_empty() or not world_effects["npc_state"].is_empty()
	var observations: Array = []
	var observer_ids: Array = observers.keys()
	observer_ids.sort()
	for holder in observer_ids:
		var acc: Dictionary = observers[holder]
		if not _is_bare(acc):
			recorded_effects = true
		observations.append(_finish(acc))
	if bool(kind_def.get("quiet", false)) and not recorded_effects and origin.is_empty():
		return {"ok": true, "recorded": false, "kind": kind, "witnesses": witness_ids, "unaware": picked["unaware"]}

	var payload: Dictionary = {
		"kind": kind, "place": str(event["place"]), "actor": str(event["actor"]), "subject": str(event["subject"]),
		"data": event["data"], "time": at, "truth": truth,
		"witnesses": witnesses.map(func(w: Dictionary) -> Dictionary: return {"holder": w["holder"], "channel": w["channel"], "clarity": w["clarity"]}),
		"unaware": picked["unaware"],
		"interpretations": interpretations, "reactions": reactions,
		"scheduled": plan["scheduled"], "cancelled": plan["cancelled"], "dropped": plan["dropped"],
		"convention_updates": evaluation["updates"], "convention_changes": evaluation["changes"],
	}
	if not origin.is_empty():
		payload["origin"] = origin
		payload["fired"] = [str(origin.get("consequence", ""))]
	var effects_payload: Dictionary = {}
	if not world_effects["world"].is_empty():
		effects_payload["world"] = world_effects["world"]
	if not world_effects["npc_state"].is_empty():
		effects_payload["npc_state"] = world_effects["npc_state"]
	if not effects_payload.is_empty():
		payload["effects"] = effects_payload
	var committed := engine.record_world_event(str(event["actor"]), str(event["subject"]), payload, observations)
	if not committed.get("ok", false):
		return committed
	_sync()
	var result := _result(committed, payload, event_id)
	world_event.emit(result)
	return result

func _result(committed: Dictionary, payload: Dictionary, event_id: String) -> Dictionary:
	var presentation: Array = []
	for reaction in payload["reactions"]:
		if str(reaction.get("op", "")) == "COMMENT":
			presentation.append({"kind": "line", "speaker": str(reaction.get("actor", "")), "key": str(reaction.get("key", ""))})
	var witness_ids: Array = []
	for witness in payload["witnesses"]:
		witness_ids.append(str(witness["holder"]))
	var unaware: Array = []
	for item in payload["unaware"]:
		unaware.append(str(item["holder"]))
	var scheduled_ids: Array = []
	for entry in payload["scheduled"]:
		scheduled_ids.append(str(entry["id"]))
	return {
		"ok": true, "recorded": true, "transaction_id": committed["transaction_id"], "event_id": event_id, "events": committed["events"],
		"kind": str(payload["kind"]), "subject": str(payload["subject"]), "actor": str(payload["actor"]), "time": int(payload["time"]),
		"witnesses": witness_ids, "unaware": unaware, "interpretations": payload["interpretations"],
		"reactions": payload["reactions"], "presentation": presentation,
		"scheduled": scheduled_ids, "cancelled": payload["cancelled"], "dropped": payload["dropped"],
		"convention_changes": payload["convention_changes"], "fired": payload.get("fired", []),
	}

# ---- helpers: perception, context, effects ----------------------------------------------------------------

func _select(event: Dictionary, kind_def: Dictionary) -> Dictionary:
	var candidates: Array = []
	for holder in data.get("holders", {}).keys():
		var definition: Dictionary = data["holders"][holder]
		var npc: Dictionary = engine.npc_state.get(holder, {})
		candidates.append({"id": str(holder), "place": str(state.presence.get(holder, definition.get("place", ""))), "tags": definition.get("tags", []), "attention": str(npc.get("attention", "idle"))})
	var place: Dictionary = data.get("places", {}).get(str(event.get("place", "")), {})
	var perception: Dictionary = data["perception"]
	return WitnessSelector.select(event, kind_def, candidates, {
		"attention": data["attention"], "overheard_clarity": int(perception["overheard_clarity"]), "min_clarity": int(perception["min_clarity"]),
		"adjacent": place.get("adjacent", []),
	})

func _subject_tags(event: Dictionary) -> Array:
	var place: Dictionary = data.get("places", {}).get(str(event.get("place", "")), {})
	var subject: Dictionary = place.get("subjects", {}).get(str(event.get("subject", "")), {})
	return subject.get("tags", [])

func _context(event: Dictionary, tags: Array, witness_ids: Array, active: Array, at: int) -> Dictionary:
	var context: Dictionary = engine.world_state.duplicate(true)
	context["npc"] = engine.npc_state.duplicate(true)
	context["time"] = at
	context["event"] = {"kind": event["kind"], "place": event["place"], "actor": event["actor"], "subject": event["subject"], "data": event["data"], "subject_tags": tags}
	context["witnessed_by"] = witness_ids
	context["active_conventions"] = active
	return context

func _accumulator(holder: String) -> Dictionary:
	return {
		"observer_id": holder, "subject_id": "", "observation": {"signature": ["WITNESS"]}, "context": {}, "evidence": [],
		"knowledge_effects": [], "model_effects": [], "operator_effects": [], "relationship_effects": [], "_models": {},
	}

func _finish(acc: Dictionary) -> Dictionary:
	var out: Dictionary = acc.duplicate(true)
	out.erase("_models")
	return out

# True when an observation carries nothing beyond the bare typed record of having perceived the event.
func _is_bare(acc: Dictionary) -> bool:
	return (acc["knowledge_effects"] as Array).is_empty() and (acc["model_effects"] as Array).is_empty() \
		and (acc["operator_effects"] as Array).is_empty() and (acc["relationship_effects"] as Array).is_empty()

# Appends a block's knowledge / model / operator / relationship effects to a holder's observation.
# `ready` means they already carry their holder defaults (an interpretation); otherwise they are templated here.
func _add_effects(acc: Dictionary, block: Dictionary, vars: Dictionary, holder: String, place: String, ready: bool = false) -> void:
	var knowledge: Array = block.get("knowledge_effects", [])
	var models: Array = block.get("model_effects", [])
	var operators: Array = block.get("operator_effects", [])
	var relationships: Array = block.get("relationship_effects", [])
	if not ready:
		knowledge = MindsInterpreter.with_holder(MindsTemplate.apply(knowledge, vars), "holder_id", holder, "scope", place)
		models = MindsInterpreter.with_holder(MindsTemplate.apply(models, vars), "observer_id", holder)
		operators = MindsInterpreter.with_holder(MindsTemplate.apply(operators, vars), "observer_id", holder)
		relationships = MindsInterpreter.with_holder(MindsTemplate.apply(relationships, vars), "a", holder)
	(acc["knowledge_effects"] as Array).append_array(knowledge)
	(acc["model_effects"] as Array).append_array(_resolve_models(models, holder, acc["_models"]))
	(acc["operator_effects"] as Array).append_array(operators)
	(acc["relationship_effects"] as Array).append_array(relationships)

# `ensure` is the Minds layer's own model effect: support the model if the holder has it, else begin it.
# Authored evidence can then say "this is more evidence for the hypothesis" without knowing whether it is
# the first. Resolved here, at commit time, into the plain upsert / support the engine replays.
func _resolve_models(effects: Array, holder: String, seen: Dictionary) -> Array:
	var out: Array = []
	for effect in effects:
		if str(effect.get("type", "")) != "ensure":
			out.append(effect)
			continue
		var rule_id := str(effect.get("rule_id", ""))
		if seen.has(rule_id):
			continue
		seen[rule_id] = true
		var existing: Dictionary = {}
		var superseded := false
		for rule in engine.models.query_rules("", "", holder):
			if str(rule.get("id", "")) == rule_id:
				existing = rule
			if str(rule.get("supersedes", "")) == rule_id:
				superseded = true
		if existing.is_empty():
			var begin: Dictionary = (effect as Dictionary).duplicate(true)
			begin["type"] = "upsert"
			begin.erase("delta")
			out.append(begin)
		elif int(existing["status"]) in [MirrorDomain.ModelStatus.RETIRED, MirrorDomain.ModelStatus.CONTRADICTED] or superseded:
			continue
		else:
			out.append({"type": "support", "rule_id": rule_id, "delta": float(effect.get("delta", 0.12)), "observer_id": holder})
	return out

# Evidence blocks: {holders, at, knowledge_effects, model_effects, ...}. Delivered to the listed holders (the
# witch by default) when they are among the witnesses.
func _deliver(block: Dictionary, vars: Dictionary, witness_ids: Array, observers: Dictionary, place: String) -> void:
	if block.is_empty():
		return
	for holder in block.get("holders", ["player"]):
		if str(holder) not in witness_ids:
			continue
		var holder_vars: Dictionary = vars.duplicate()
		holder_vars["holder"] = str(holder)
		_add_effects(_observer(observers, str(holder)), block, holder_vars, str(holder), place)

func _observer(observers: Dictionary, holder: String) -> Dictionary:
	if not observers.has(holder):
		observers[holder] = _accumulator(holder)
	return observers[holder]

# One scheduled consequence: numbered, keyed, bounded. A pending entry with the same key is replaced,
# skipped over, or stacked on, per the spec; a full queue or a too-deep chain drops the new entry instead.
func _schedule(spec: Dictionary, vars: Dictionary, origin_ref: Dictionary, at: int, depth: int, plan: Dictionary, observers: Dictionary, witness_ids: Array, place: String, limits: Dictionary) -> void:
	var entry_event: Dictionary = MindsTemplate.apply(spec.get("event", {}), vars)
	if not entry_event.has("place"):
		entry_event["place"] = place
	if not entry_event.has("actor"):
		entry_event["actor"] = "world"
	var key := str(MindsTemplate.apply(spec.get("key", ""), vars))
	var policy := str(spec.get("if_pending", "stack"))
	if depth + 1 > int(limits["max_chain_depth"]):
		(plan["dropped"] as Array).append({"why": "chain_depth", "key": key})
		return
	var pending: Array = plan["pending"]
	var same: Array = []
	if not key.is_empty():
		for entry in pending:
			if str(entry.get("key", "")) == key:
				same.append(entry)
	if not same.is_empty():
		if policy == "skip":
			(plan["dropped"] as Array).append({"why": "already_pending", "key": key})
			return
		if policy == "replace":
			for old in same:
				pending.erase(old)
				var scheduled: Array = plan["scheduled"]
				var born_here := -1
				for i in range(scheduled.size()):
					if str(scheduled[i]["id"]) == str(old["id"]):
						born_here = i
				if born_here >= 0:
					scheduled.remove_at(born_here)
				else:
					(plan["cancelled"] as Array).append(str(old["id"]))
				_deliver(old.get("on_replace", {}), vars, witness_ids, observers, place)
	if pending.size() >= int(limits["max_pending"]):
		(plan["dropped"] as Array).append({"why": "queue_full", "key": key})
		return
	var scheduled_now: Array = plan["scheduled"]
	var entry: Dictionary = {
		"id": state.queue.next_id(scheduled_now.size()),
		"due": at + maxi(0, int(spec.get("delay", 0))),
		"event": entry_event,
		"origin": {"rule": str(origin_ref["rule"]), "variant": str(origin_ref["variant"]), "depth": depth + 1},
		"key": key,
	}
	if spec.has("when"):
		entry["when"] = spec["when"]
	if spec.has("on_replace"):
		entry["on_replace"] = MindsTemplate.apply(spec["on_replace"], vars)
	scheduled_now.append(entry)
	pending.append(entry)

# What a convention changing state does to its members: they learn it (and are granted, or lose, the operators
# it enables). Its other consequences are world-rule variants triggered by the change (`convention_change`).
func _apply_convention_change(change: Dictionary, observers: Dictionary) -> void:
	var kind := str(change["change"])
	if kind != "adopted" and kind != "retired":
		return
	var definition: Dictionary = {}
	for candidate in data.get("conventions", []):
		if str(candidate.get("id", "")) == str(change["id"]):
			definition = candidate
	if definition.is_empty():
		return
	var members: Array = data.get("communities", {}).get(str(definition.get("community", "")), {}).get("members", [])
	var force: Dictionary = definition.get("force", {})
	for member in members:
		var acc := _observer(observers, str(member))
		if (acc["observation"] as Dictionary).get("signature", []) == ["WITNESS"]:
			acc["observation"] = {"signature": ["CONVENTION", kind]}
		(acc["knowledge_effects"] as Array).append({
			"id": str(change["id"]), "holder_id": str(member),
			"proposition": {"convention": str(change["id"]), "reads": str(definition.get("reads", ""))},
			"status": MirrorDomain.EpistemicStatus.ESTABLISHED if kind == "adopted" else MirrorDomain.EpistemicStatus.CONTESTED,
			"scope": str(definition.get("community", "")), "source": "convention"})
		for operator_id in force.get("enables_operators", []):
			if kind == "adopted":
				(acc["operator_effects"] as Array).append({"type": "acquire", "operator_id": str(operator_id), "observer_id": str(member), "source": "convention"})
			else:
				(acc["operator_effects"] as Array).append({"type": "revoke", "operator_id": str(operator_id), "observer_id": str(member)})
