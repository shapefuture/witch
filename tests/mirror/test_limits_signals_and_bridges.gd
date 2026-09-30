extends TestCase

const T := MirrorDomain.ActionType

func test_signals_fire_once_per_commit_and_on_failure() -> void:
	var e := MirrorFixtures.engine()
	var committed := []
	var failed := []
	e.transaction_committed.connect(func(r): committed.append(r["transaction_id"]))
	e.transaction_failed.connect(func(r): failed.append(r["error"]))
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	e.resolve_action(MirrorFixtures.act("nonexistent", "door", T.LOOK))
	eq(committed.size(), 1, "one commit signal")
	eq(failed, ["action_unavailable"], "one failure signal with its code")

func test_events_appended_signal_carries_the_committed_bundle() -> void:
	var e := MirrorFixtures.engine()
	var bundles := []
	e.event_store.events_appended.connect(func(evs): bundles.append(evs.size()))
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	eq(bundles, [2], "one announcement, action + response")

func test_event_capacity_is_enforced_without_partial_commit() -> void:
	var e := MirrorFixtures.engine()
	e.event_store.max_events = 3
	ok(e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))["ok"], "2 events fit")
	var head := e.event_store.head_hash()
	var r := e.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	ok(not r["ok"], "next bundle would exceed capacity")
	eq(r["error"], "event_store_rejected", "rejected")
	eq(e.event_store.head_hash(), head, "no partial append")

func test_transaction_event_limit() -> void:
	var e := MirrorFixtures.engine()
	e.max_transaction_events = 1
	var r := e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	eq(r.get("error", ""), "transaction_event_limit", "limit enforced before anything is written")
	eq(e.event_store.size(), 0, "nothing written")

func test_observation_evidence_conflict_rolls_back() -> void:
	var e := MirrorFixtures.engine()
	ok(e.record_observation("player", "tomas", {"signature": []}, {}, [{"id": "ev.x", "payload": {"a": 1}}])["ok"], "first")
	var size := e.event_store.size()
	var r := e.record_observation("player", "tomas", {"signature": []}, {}, [{"id": "ev.x", "payload": {"a": 2}}],
		[{"id": "claim_late", "proposition": {}, "status": 2}])
	eq(r.get("error", ""), "evidence_conflict", "conflict detected")
	eq(e.event_store.size(), size, "event rolled back")
	ok(not e.knowledge.has("claim_late"), "knowledge effect rolled back")

func test_catalog_tampering_after_lock_is_detected() -> void:
	var e := MirrorFixtures.engine()
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	e.action_definitions["look_door"]["response_contracts"][0]["observed"]["outcome"] = "rewritten"
	var r := e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	ok(not r["ok"], "a locked catalog cannot be silently edited")
	ok(not e.explain_action(MirrorFixtures.act("look_door", "door", T.LOOK))["available"], "explain agrees")
	eq(e.explain_affordances("door").filter(func(a): return a["available"]).size(), 0, "affordances agree")

func test_advance_time_validation() -> void:
	var e := MirrorFixtures.engine()
	eq(e.advance_time(-1).get("error", ""), "negative_time", "negative rejected")
	ok(e.advance_time(5)["ok"], "positive ok")
	eq(e.get_time(), 5, "clock")

func test_share_claim_creates_second_hand_knowledge_for_another_holder() -> void:
	var e := MirrorFixtures.engine()
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	var r := e.share_claim("player", "tomas", "door_sealed")
	ok(r["ok"], "shared")
	var claim := e.knowledge.get_claim("door_sealed", "tomas")
	eq(claim["status"], MirrorDomain.EpistemicStatus.POSSIBLE, "hearsay is only possible, not supported")
	eq(claim["source"], "hearsay", "provenance")
	ok(not e.share_claim("player", "player", "door_sealed")["ok"], "no self share")
	ok(not e.share_claim("player", "tomas", "missing")["ok"], "unknown claim")

func test_dialogue_bridge_requires_its_action_to_be_registered_before_lock() -> void:
	var e := MirrorFixtures.engine()
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	var bridge := MirrorDialogueBridge.new(e)
	var r := bridge.record_choice("player", "tomas", "yes")
	ok(not r["ok"], "a choice recorded after the catalog locked cannot lazily register its action")
	var e2 := MirrorEngine.new()
	var bridge2 := MirrorDialogueBridge.new(e2)
	ok(bridge2.record_choice("player", "tomas", "yes")["ok"], "before lock the bridge registers it")

func test_popochiu_bridge_resolves_clicks_through_the_engine() -> void:
	var e := MirrorFixtures.engine()
	var bridge := MirrorPopochiuBridge.new(e)
	var r := bridge.resolve_click("player", "door", "look_door")
	ok(r["ok"], "click resolved")
	eq(bridge.affordances_for("door").size() >= 1, true, "affordances exposed")

func test_validator_reports_catalog_problems() -> void:
	var e := MirrorEngine.new()
	e.register_action({"id": "a", "preconditions": {"$bogus": {}}, "time_cost": -1})
	e.register_operator({"id": "op", "action_ids": ["missing"]})
	var report := MirrorValidator.new().validate_engine(e)
	ok(not report["ok"], "invalid catalog")
	ok(report["errors"].size() >= 3, "bogus operator, negative time, unknown action ref all reported")
