extends TestCase

const T := MirrorDomain.ActionType

func test_catalog_validates_and_locks_on_first_action() -> void:
	var e := MirrorFixtures.engine()
	eq(e.validate_catalog()["errors"], [], "fixture catalog has no errors")
	ok(not e.catalog_is_locked, "catalog open before first action")
	var r := e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	ok(r.get("ok", false), "look resolves: %s" % JSON.stringify(r.get("details", {})))
	ok(e.catalog_is_locked, "first resolve locks the catalog")
	ok(not e.register_action({"id": "late"}), "registration rejected after lock")
	ok(not e.set_world("x", 1), "set_world rejected after events exist")

func test_resolve_produces_chain_evidence_and_knowledge() -> void:
	var e := MirrorFixtures.engine()
	var r := e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	ok(r["ok"], "ok")
	eq(e.event_store.size(), 2, "action + response events")
	ok(e.event_store.verify_chain()["ok"], "hash chain verifies")
	ok(e.knowledge.has("door_sealed"), "claim recorded for player")
	eq(e.evidence.get_evidence("ev.door_seen")["payload"]["saw"], "seal", "authored evidence stored")
	eq(r["presentation"][0]["text"], "It is sealed.", "presentation forwarded")

func test_discrepancy_between_prediction_and_observation() -> void:
	var e := MirrorFixtures.engine()
	var r := e.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	ok(r["ok"], "ask ok")
	ok(r["discrepancy"]["has_discrepancy"], "predicted helpful, observed deflect")
	ok(r["discrepancy"]["vector"]["outcome"], "outcome dimension flagged")
	var types: Array = r["events"].map(func(ev): return ev.event_type)
	in_array("DiscrepancyDetected", types, "discrepancy is a first-class event")

func test_outcome_certainty_up_motive_certainty_down() -> void:
	var e := MirrorFixtures.engine()
	var r := e.resolve_action(MirrorFixtures.act("cast_light", "lamp", T.CAST))
	ok(r["ok"], "cast ok")
	ok(r["discrepancy"]["vector"]["motive"], "motive mismatch flagged")
	ok(not r["discrepancy"]["vector"]["outcome"], "outcome matched prediction")
	eq(e.get_world("lamp")["lit"], true, "world effect applied")
	ok(e.operators.has("light_bringer"), "operator acquired by effect")
	eq(e.get_time(), 2, "time cost advanced the clock")

func test_once_key_blocks_second_cast() -> void:
	var e := MirrorFixtures.engine()
	ok(e.resolve_action(MirrorFixtures.act("cast_light", "lamp", T.CAST))["ok"], "first")
	var second := e.resolve_action(MirrorFixtures.act("cast_light", "lamp", T.CAST))
	ok(not second["ok"], "second rejected")
	eq(second["error"], "action_unavailable", "error code")

func test_knowledge_gates_action_and_reports_latent() -> void:
	var e := MirrorFixtures.engine()
	var before := e.explain_action(MirrorFixtures.act("gated_ask", "tomas", T.ASK))
	ok(not before["available"], "blocked before knowledge")
	ok(before["latent"], "knowledge-only block is latent (hideable, revealable)")
	eq(before["affordance_state"], "blocked_by_knowledge", "state bucket")
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	ok(e.explain_action(MirrorFixtures.act("gated_ask", "tomas", T.ASK))["available"], "available after LOOK")

func test_same_action_different_knowledge_different_affordance_set() -> void:
	var e1 := MirrorFixtures.engine()
	var e2 := MirrorFixtures.engine()
	e2.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	var ids1: Array = e1.get_affordances("tomas").map(func(d): return d["id"])
	var ids2: Array = e2.get_affordances("tomas").map(func(d): return d["id"])
	not_in_array("gated_ask", ids1, "hidden without knowledge")
	in_array("gated_ask", ids2, "offered with knowledge")

func test_relationship_replay_matches_for_targetless_action() -> void:
	# A WAIT with no target still carries relationship tags in its response contract.
	# Live recording skips empty targets; the replay path must agree or save/load breaks.
	var e := MirrorFixtures.engine()
	var r := e.resolve_action(MirrorFixtures.act("wait", "", T.WAIT))
	ok(r["ok"], "wait ok")
	var json := e.save_json()
	var e2 := MirrorFixtures.engine()
	var loaded := e2.load_json(json)
	ok(loaded.get("ok", false), "load ok: %s" % JSON.stringify(loaded))

func test_preview_does_not_mutate_or_leak() -> void:
	var e := MirrorFixtures.engine()
	var seen: Array = []
	e.event_store.events_appended.connect(func(evs): seen.append(evs.size()))
	var committed: Array = []
	e.transaction_committed.connect(func(res): committed.append(res["transaction_id"]))
	var head_before := e.event_store.head_hash()
	var p := e.preview_action(MirrorFixtures.act("cast_light", "lamp", T.CAST))
	ok(p["ok"], "preview ok")
	ok(p["would_commit"], "would_commit")
	eq(e.event_store.head_hash(), head_before, "no event committed")
	eq(e.event_store.size(), 0, "store empty")
	eq(seen.size(), 0, "no append signal leaked")
	eq(committed.size(), 0, "no commit signal leaked")
	ok(not e.catalog_is_locked, "preview leaves an unlocked catalog unlocked")
	eq(e.get_world("lamp")["lit"], false, "world untouched")
	in_array("ActionResolved", p["event_types"], "preview reports staged event types")

func test_idempotent_replay_of_client_request() -> void:
	var e := MirrorFixtures.engine()
	var a := MirrorFixtures.act("look_door", "door", T.LOOK, {}, "req-1")
	var r1 := e.resolve_action(a)
	var r2 := e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK, {}, "req-1"))
	ok(r2.get("idempotent_replay", false), "second identical request is a replay")
	eq(e.event_store.size(), 2, "no duplicate commit")
	eq(r2["transaction_id"], r1["transaction_id"], "same transaction")
	var conflict := e.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK, {}, "req-1"))
	eq(conflict.get("error", ""), "idempotency_key_conflict", "same key different request is rejected")

func test_failed_transaction_rolls_back_cleanly() -> void:
	var e := MirrorFixtures.engine()
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	var before := e.projection_snapshot()
	var head := e.event_store.head_hash()
	var bad := e.resolve_action(MirrorFixtures.act("nonexistent", "door", T.LOOK))
	ok(not bad["ok"], "unknown action fails")
	eq(e.event_store.head_hash(), head, "chain head unchanged")
	eq(MirrorHash.canonical_json(e.projection_snapshot()), MirrorHash.canonical_json(before), "projection unchanged")

func test_determinism_same_sequence_same_head_hash() -> void:
	var heads: Array[String] = []
	for i in 2:
		var e := MirrorFixtures.engine()
		e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
		e.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
		e.resolve_action(MirrorFixtures.act("wait", "", T.WAIT))
		e.resolve_action(MirrorFixtures.act("cast_light", "lamp", T.CAST))
		heads.append(e.event_store.head_hash())
	eq(heads[0], heads[1], "two runs produce an identical hash chain")

func test_storylet_selection_and_consumption() -> void:
	var e := MirrorFixtures.engine()
	eq(e.select_storylets({"door": "closed"}).size(), 1, "eligible")
	var c := e.consume_storylet("story.intro", "player", {"door": "closed"})
	ok(c["ok"], "consumed: %s" % JSON.stringify(c.get("details", {})))
	eq(e.select_storylets({"door": "closed"}).size(), 0, "once_key consumed")

func test_causal_hypothesis_states() -> void:
	var e := MirrorFixtures.engine()
	eq(e.evaluate_causal_hypothesis("h.door")["state"], "evidence_needed", "needs evidence first")
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	eq(e.evaluate_causal_hypothesis("h.door")["state"], "operator_unacquired", "evidence in, operator missing")
	e.resolve_action(MirrorFixtures.act("cast_light", "lamp", T.CAST))
	eq(e.evaluate_causal_hypothesis("h.door")["state"], "ready", "all satisfied")
