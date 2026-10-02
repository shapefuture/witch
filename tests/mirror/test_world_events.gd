extends TestCase

# The engine primitive under the Minds layer: one atomic transaction for "something happened", plus what
# each witness made of it. These tests pin its contract; tests/mirror/test_minds_*.gd cover the layer.

const S := MirrorDomain.EpistemicStatus

func _observation(observer: String, claim: String) -> Dictionary:
	return {
		"observer_id": observer, "subject_id": "globe",
		"observation": {"signature": ["WITNESS", "PROP_POKED"]},
		"context": {"channel": "sight"},
		"evidence": [{"type": MirrorDomain.EvidenceType.DIRECT, "payload": {"saw": "globe"}}],
		"knowledge_effects": [{"id": claim, "holder_id": observer, "proposition": {"globe": "moved"}, "status": S.SUPPORTED, "scope": "hall"}],
		"model_effects": [{"type": "upsert", "observer_id": observer, "rule_id": "m.globe_moves", "subject_id": "globe", "proposition": {"globe": "moves"}, "scope": "hall", "confidence": 0.5}],
		"relationship_effects": [{"a": observer, "b": "player", "tags": ["NOTE"], "payload": {"interpretation": "play"}}],
	}

func _engine() -> MirrorEngine:
	var e := MirrorFixtures.engine()
	e.set_world("hall", {"lamp": "off"})
	return e

func test_a_world_event_and_its_witnesses_commit_in_one_transaction() -> void:
	var e := _engine()
	var before := e.event_store.size()
	var result := e.record_world_event("player", "globe", {"kind": "PROP_POKED"}, [_observation("raccoon", "saw_poke"), _observation("tomas", "saw_poke")])
	ok(result.get("ok", false), "committed: %s" % JSON.stringify(result.get("details", {})))
	eq(e.event_store.size() - before, 3, "one world event and two witness observations")
	var events: Array = result["events"]
	eq(events[0].event_type, "WorldEventHappened", "the happening comes first")
	eq(events[1].event_type, "ObservationRecorded", "then each witness")
	eq(events[1].causes, ["%s:event" % result["transaction_id"]], "a witness's observation names the happening as its cause")
	eq(events[1].transaction_id, events[0].transaction_id, "one transaction")
	ok(e.knowledge.has("saw_poke", "raccoon") and e.knowledge.has("saw_poke", "tomas"), "each witness knows it")
	ok(not e.knowledge.has("saw_poke", "player"), "a non-witness learns nothing")

func test_witness_evidence_does_not_collide_between_witnesses() -> void:
	var e := _engine()
	var result := e.record_world_event("player", "globe", {}, [_observation("raccoon", "a"), _observation("tomas", "a")])
	ok(result.get("ok", false), "two witnesses with auto-numbered evidence commit together")
	var ids: Array = []
	for event in result["events"]:
		ids.append_array(event.evidence_refs)
	eq(ids.size(), 2, "one typed evidence item per witness")
	ok(ids[0] != ids[1], "and their ids differ")
	eq(e.evidence.get_evidence(str(ids[0]))["holder_id"], "raccoon", "evidence belongs to the witness who saw it")

func test_relationship_effects_are_recorded() -> void:
	var e := _engine()
	e.record_world_event("player", "globe", {}, [_observation("raccoon", "a")])
	var relation := e.relationships.get_relation("raccoon", "player")
	eq(relation["interpretations"].size(), 1, "the raccoon's reading of the witch is a relationship fact")
	eq(relation["interpretations"][0]["value"], "play", "the reading itself")

func test_payload_effects_change_the_world_and_replay_reapplies_them() -> void:
	var e := _engine()
	e.record_world_event("player", "lamp", {"effects": {"world": {"hall": {"lamp": "on"}}}}, [_observation("raccoon", "a")])
	eq(e.get_world("hall"), {"lamp": "on"}, "the world changed")
	var live := MirrorHash.canonical_json(e.projection_snapshot())
	var replayed := e.replay_all()
	ok(replayed.get("ok", false), "replay ok")
	eq(MirrorHash.canonical_json(e.projection_snapshot()), live, "replaying the log reproduces every projection, relationships and witness models included")

func test_world_events_survive_save_and_load() -> void:
	var e := _engine()
	e.record_world_event("player", "globe", {"kind": "PROP_POKED", "effects": {"world": {"hall": {"lamp": "on"}}}}, [_observation("raccoon", "a")])
	e.advance_time(3, "system", "test")
	var json := e.save_json()
	var loaded := _engine()
	var res := loaded.load_json(json)
	ok(res.get("ok", false), "a save with world events loads: %s" % JSON.stringify(res))
	eq(MirrorHash.canonical_json(loaded.projection_snapshot()), MirrorHash.canonical_json(e.projection_snapshot()), "identical projection")
	eq(loaded.event_store.head_hash(), e.event_store.head_hash(), "identical chain")
	ok(loaded.audit_integrity()["ok"], "integrity audit passes")

func test_a_bad_observation_rolls_the_whole_transaction_back() -> void:
	var e := _engine()
	var before := e.event_store.size()
	var bad := _observation("tomas", "a")
	bad["observer_id"] = ""
	var result := e.record_world_event("player", "globe", {"effects": {"world": {"hall": {"lamp": "on"}}}}, [_observation("raccoon", "a"), bad])
	ok(not result.get("ok", true), "refused")
	eq(e.event_store.size(), before, "nothing was appended")
	eq(e.get_world("hall"), {"lamp": "off"}, "and the world did not change")
	ok(not e.knowledge.has("a", "raccoon"), "the valid witness did not learn it either")

func test_check_requirements_gates_on_a_holders_own_beliefs() -> void:
	var e := _engine()
	e.record_world_event("player", "globe", {}, [_observation("raccoon", "saw_poke")])
	var needs := {"requires_claims": [{"id": "saw_poke", "min_status": S.SUPPORTED}]}
	ok(e.check_requirements(needs, "raccoon")["ok"], "the raccoon saw it")
	ok(not e.check_requirements(needs, "tomas")["ok"], "Tomas did not")
	var model_needs := {"requires_models": [{"id": "m.globe_moves", "min_confidence": 0.4}]}
	ok(e.check_requirements(model_needs, "raccoon")["ok"], "the raccoon holds the model")
	ok(not e.check_requirements(model_needs, "player")["ok"], "the player does not: models are per observer")

func test_a_world_event_does_not_disturb_ordinary_actions() -> void:
	var e := _engine()
	e.record_world_event("player", "globe", {}, [_observation("raccoon", "a")])
	var result := e.resolve_action(MirrorFixtures.act("look_door", "door", MirrorDomain.ActionType.LOOK))
	ok(result.get("ok", false), "actions still resolve after a world event")
	ok(e.audit_integrity()["ok"], "and the chain is intact")
