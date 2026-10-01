extends TestCase

const T := MirrorDomain.ActionType

# Captured from the engine BEFORE the incremental-validation / truncation-rollback
# optimisation. Hashing semantics must not change, so a scripted session must keep
# producing byte-identical chains and projections.
const GOLDEN_HEAD := "cca9acdc81d0c314a71de113d70fc44327dcfc17707276680301434f64e496d5"
const GOLDEN_PROJECTION := "3602ed6e0774b7a33f6adcdbeef1092ec1a01b0bec8b1588e9aa9286261d03a2"
const GOLDEN_CATALOG := "b06a9bf656a9c599f482a2040e52b3c44a50388f7a560093429f3971f702658f"

func test_golden_master_chain_projection_and_catalog() -> void:
	var e := MirrorFixtures.rich_engine()
	eq(e.event_store.size(), 17, "event count")
	eq(e.event_store.head_hash(), GOLDEN_HEAD, "event chain head")
	eq(MirrorHash.sha256(e.projection_snapshot()), GOLDEN_PROJECTION, "projection hash")
	eq(e.catalog_fingerprint, GOLDEN_CATALOG, "catalog fingerprint")

func _conflicting_evidence_engine() -> MirrorEngine:
	var e := MirrorEngine.new()
	e.set_world("n", 0)
	for id in ["one", "two"]:
		e.register_action({
			"id": id, "action_type": T.CUSTOM,
			"response_contracts": [{
				"id": id + ".r", "observed": {"outcome": id},
				"effects": {"world": {"n": 1 if id == "one" else 2}},
				"knowledge_effects": [{"id": "claim_" + id, "proposition": {"x": id}, "status": 2}],
				"evidence": [{"id": "shared.evidence", "payload": {"from": id}}],
			}],
		})
	return e

func test_mid_commit_failure_rolls_everything_back() -> void:
	var e := _conflicting_evidence_engine()
	ok(e.resolve_action(MirrorFixtures.act("one", "", T.CUSTOM))["ok"], "first commits")
	var head := e.event_store.head_hash()
	var size := e.event_store.size()
	var before := MirrorHash.canonical_json(e.projection_snapshot())
	var r := e.resolve_action(MirrorFixtures.act("two", "", T.CUSTOM))
	ok(not r["ok"], "conflicting evidence identity fails the transaction")
	eq(r["error"], "evidence_conflict", "error code")
	eq(e.event_store.size(), size, "appended events were rolled back")
	eq(e.event_store.head_hash(), head, "chain head restored")
	eq(MirrorHash.canonical_json(e.projection_snapshot()), before, "every projection restored")
	ok(e.event_store.verify_chain()["ok"], "chain still verifies after rollback")
	ok(e.event_store.get_by_id("tx_two_4:action") == null, "rolled back events are not indexed")
	eq(e.event_store.get_transaction("tx_two_4").size(), 0, "rolled back transaction is not indexed")
	ok(not e.knowledge.has("claim_two"), "rolled back knowledge effect is gone")
	var again := e.resolve_action(MirrorFixtures.act("one", "", T.CUSTOM))
	ok(again["ok"] or again["error"] == "evidence_conflict", "engine remains usable after a rollback")

func test_rolled_back_engine_continues_with_the_same_chain_as_a_clean_one() -> void:
	var clean := _conflicting_evidence_engine()
	clean.resolve_action(MirrorFixtures.act("one", "", T.CUSTOM))
	var dirty := _conflicting_evidence_engine()
	dirty.resolve_action(MirrorFixtures.act("one", "", T.CUSTOM))
	dirty.resolve_action(MirrorFixtures.act("two", "", T.CUSTOM))
	dirty.advance_time(3)
	clean.advance_time(3)
	eq(dirty.event_store.head_hash(), clean.event_store.head_hash(), "a failed transaction leaves no trace in the chain")

func test_preview_equals_commit_and_is_repeatable() -> void:
	var e := MirrorFixtures.rich_engine()
	var before := MirrorHash.canonical_json(e.projection_snapshot())
	var head := e.event_store.head_hash()
	var p1 := e.preview_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	var p2 := e.preview_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	ok(p1["ok"] and p2["ok"], "previews resolve")
	eq(MirrorHash.canonical_json(p1["projection_diff"]), MirrorHash.canonical_json(p2["projection_diff"]), "preview is repeatable")
	eq(e.event_store.head_hash(), head, "preview leaves the chain alone")
	eq(MirrorHash.canonical_json(e.projection_snapshot()), before, "preview leaves the projection alone")
	var committed := e.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	eq(committed["observed"], p1["observed"], "what preview promised is what commit delivered")

func test_audit_detects_tampering_with_a_committed_event() -> void:
	var e := MirrorFixtures.rich_engine()
	ok(e.audit_integrity()["ok"], "clean engine audits")
	e.event_store.get_all()[3].payload["tampered"] = true
	var report := e.audit_integrity()
	ok(not report["ok"], "in-memory tampering is caught by an explicit audit")
