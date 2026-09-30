extends TestCase

func test_epistemic_status_is_semantic_not_ordinal() -> void:
	var D := MirrorDomain.EpistemicStatus
	ok(not MirrorDomain.epistemic_satisfies(D.DISCONFIRMED, D.POSSIBLE), "disconfirmed never satisfies")
	ok(MirrorDomain.epistemic_satisfies(D.ESTABLISHED, D.SUPPORTED), "established satisfies supported")
	ok(not MirrorDomain.epistemic_satisfies(D.POSSIBLE, D.SUPPORTED), "possible does not satisfy supported")
	ok(MirrorDomain.epistemic_satisfies(D.UNRESOLVED_BY_DESIGN, D.POSSIBLE), "unresolved-by-design counts as held, weakly")
	var M := MirrorDomain.ModelStatus
	ok(not MirrorDomain.model_satisfies(M.CONTRADICTED, M.HYPOTHESIS), "contradicted model never satisfies")
	ok(MirrorDomain.model_satisfies(M.REVISED, M.SUPPORTED), "revised satisfies supported")

func test_knowledge_is_holder_scoped() -> void:
	var k := MirrorKnowledgeStore.new()
	k.upsert("c1", {"a": 1}, MirrorDomain.EpistemicStatus.SUPPORTED, [], "t", "s", {}, "player")
	ok(k.has("c1", "player"), "player holds it")
	ok(not k.has("c1", "tomas"), "tomas does not")

func test_knowledge_evidence_accumulates_without_duplicates() -> void:
	var k := MirrorKnowledgeStore.new()
	k.upsert("c", {}, 1, ["e1"], "t", "s")
	k.upsert("c", {}, 1, ["e1", "e2"], "t", "s")
	eq(k.get_claim("c")["evidence"], ["e1", "e2"], "merged, deduplicated")

func test_evidence_identity_conflict_is_rejected() -> void:
	var s := MirrorEvidenceStore.new()
	ok(not s.record("e", 0, "player", "x", "ev1", {"a": 1}).is_empty(), "first record")
	ok(not s.record("e", 0, "player", "x", "ev1", {"a": 1}).is_empty(), "identical re-record is idempotent")
	ok(s.record("e", 0, "player", "x", "ev1", {"a": 2}).is_empty(), "conflicting re-record rejected")
	eq(s.last_error, "evidence_conflict", "error code")

func test_model_lifecycle_support_contradict_revise_transfer() -> void:
	var m := MirrorModelStore.new()
	m.upsert_rule("r1", "tomas", {"x": 1}, "clearing", 0.5)
	m.support("r1", "ev1")
	ok(m.query_rules("tomas")[0]["confidence"] > 0.5, "support raises confidence")
	m.contradict("r1", "ev2")
	eq(m.query_rules("tomas")[0]["status"], MirrorDomain.ModelStatus.CONTRADICTED, "contradicted")
	var revised := m.revise("r1", "r2", {"x": 2}, "clearing", "ev3", "tomas")
	eq(revised["supersedes"], "r1", "revision links back")
	var t := m.transfer("r2", "r3", "player", "player", "vera", "market", "ev4")
	eq(t["transferred_from"], "r2", "transfer links back")
	eq(t["status"], MirrorDomain.ModelStatus.CONTEXTUAL, "transferred rules are contextual, not assumed")
	ok(t["confidence"] < revised["confidence"], "transfer discounts confidence")
	eq(m.history("", "r3").size() >= 1, true, "history kept")

func test_model_depth_is_clamped() -> void:
	var m := MirrorModelStore.new()
	eq(m.upsert_rule("deep", "s", {}, "sc", 0.5, 0, 99)["depth"], MirrorDomain.MAX_MODEL_DEPTH, "clamped")

func test_operators_acquire_revoke_idempotent() -> void:
	var o := MirrorOperatorStore.new()
	ok(not o.acquire("op", "player", "e1").is_empty(), "acquire")
	ok(o.has("op"), "has")
	ok(o.revoke("op", "player", "e2"), "revoke")
	ok(not o.has("op"), "gone")
	ok(not o.revoke("op", "player", "e3"), "double revoke is a no-op")
	ok(o.acquire("", "player", "e").is_empty(), "empty id rejected")

func test_relationship_service_records_semantic_tags() -> void:
	var r := MirrorRelationshipService.new()
	r.record("player", "tomas", "e1", ["BOUNDARY"], {"domain": "help", "boundary": {"unasked": false}})
	r.record("player", "tomas", "e2", ["INVITATION"], {"topic": "machine"})
	r.record("player", "tomas", "e3", ["REFUSAL"], {"why": "no"})
	var rel := r.get_relation("player", "tomas")
	eq(rel["boundaries"]["help"], {"unasked": false}, "boundary")
	eq(rel["invitations"].size(), 1, "invitation")
	eq(rel["refusals"].size(), 1, "refusal")
	eq(rel["events"].size(), 3, "three events")
	eq(r.get_relation("tomas", "player"), {}, "relations are directional")

func test_hash_canonicalisation_is_stable() -> void:
	eq(MirrorHash.canonical_json({"b": 1, "a": 2}), MirrorHash.canonical_json({"a": 2, "b": 1}), "key order irrelevant")
	eq(MirrorHash.sha256({"n": 2}), MirrorHash.sha256({"n": 2.0}), "whole floats hash as ints (json round trip)")
	ok(MirrorHash.sha256({"n": 2.5}) != MirrorHash.sha256({"n": 2}), "real floats stay distinct")
	eq(MirrorHash.sha256({1: "a", "1": "b"}), MirrorHash.sha256({"1": "b", 1: "a"}), "int/string key collision is ordered deterministically")
