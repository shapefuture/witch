class_name MirrorFixtures
extends RefCounted

# Small but feature-complete catalog used by the engine tests. It is deliberately
# NOT the game's content: it exists to exercise the engine's contracts.

static func engine() -> MirrorEngine:
	var e := MirrorEngine.new()
	e.set_world("door", "closed")
	e.set_world("lamp", {"lit": false})
	e.set_npc_state("tomas", {"mood": "guarded", "expects": "EXPECT_MAGIC"})

	e.register_action({
		"id": "look_door", "action_type": MirrorDomain.ActionType.LOOK,
		"valid_targets": ["door"],
		"prediction_signature": ["LOOK"],
		"response_contracts": [{
			"id": "look_door.seen", "priority": 0,
			"observed": {"outcome": "door_sealed"},
			"knowledge_effects": [{"id": "door_sealed", "proposition": {"door": "sealed"}, "status": MirrorDomain.EpistemicStatus.SUPPORTED, "scope": "clearing"}],
			"evidence": [{"id": "ev.door_seen", "type": MirrorDomain.EvidenceType.DIRECT, "payload": {"saw": "seal"}}],
			"presentation": [{"kind": "line", "speaker": "narrator", "text": "It is sealed."}],
		}],
	})
	e.register_action({
		"id": "ask_tomas", "action_type": MirrorDomain.ActionType.ASK,
		"valid_targets": ["tomas"],
		"prediction_signature": ["ASK", "EXPECT_PERMISSION"],
		"prediction_candidates": [{"id": "p.helpful", "when": {}, "expected": {"outcome": "helpful"}}],
		"response_contracts": [
			{"id": "ask_tomas.deflect", "priority": 0, "npc_preconditions": {"mood": "guarded"},
				"observed": {"outcome": "deflect"},
				"relationship_tags": ["BOUNDARY"], "relationship_payload": {"domain": "help", "boundary": {"unasked": false}},
				"effects": {"npc_state": {"tomas": {"mood": "curious"}}},
				"knowledge_effects": [{"id": "tomas_deflects", "proposition": {"tomas": "deflects"}, "status": MirrorDomain.EpistemicStatus.POSSIBLE, "scope": "tomas"}]},
			{"id": "ask_tomas.open", "priority": 5, "npc_preconditions": {"mood": "curious"},
				"observed": {"outcome": "helpful"},
				"relationship_tags": ["INVITATION"], "relationship_payload": {"topic": "machine"}},
		],
	})
	e.register_action({
		"id": "wait", "action_type": MirrorDomain.ActionType.WAIT,
		"time_cost": 8,
		"response_contracts": [{"id": "wait.passes", "observed": {"outcome": "time_passes"},
			"relationship_tags": ["NOTE"], "relationship_payload": {"waited": true}}],
	})
	e.register_action({
		"id": "cast_light", "action_type": MirrorDomain.ActionType.CAST,
		"valid_targets": ["lamp"],
		"time_cost": 2,
		"once_key": "cast_light_once",
		"response_contracts": [{"id": "cast_light.lit", "observed": {"outcome": "lamp_lit", "motive": "unknown"},
			"effects": {"world": {"lamp": {"lit": true}}},
			"operator_effects": [{"type": "acquire", "operator_id": "light_bringer"}]}],
		"prediction_candidates": [{"id": "p.cast", "when": {}, "expected": {"outcome": "lamp_lit", "motive": "grateful"}}],
	})
	e.register_action({
		"id": "gated_ask", "action_type": MirrorDomain.ActionType.ASK,
		"valid_targets": ["tomas"],
		"requires_claims": [{"id": "door_sealed", "min_status": MirrorDomain.EpistemicStatus.SUPPORTED}],
		"response_contracts": [{"id": "gated_ask.r", "observed": {"outcome": "answered"}}],
	})
	e.register_operator({"id": "light_bringer", "action_ids": ["cast_light"]})
	e.register_storylet({"id": "story.intro", "priority": 1, "once_key": "story_intro", "preconditions": {"door": "closed"}, "presentation": [{"kind": "line", "text": "hello"}]})
	e.register_causal_hypothesis({
		"id": "h.door", "anomaly": {}, "requires_evidence": [{"id": "door_sealed"}],
		"operator_id": "light_bringer", "reframe_id": "reframe.door",
		"experiments": [{"action_id": "look_door", "target_id": "door", "action_type": MirrorDomain.ActionType.LOOK}],
	})
	return e

static func act(id: String, target: String, type: int, ctx: Dictionary = {}, request_id: String = "") -> MirrorAction:
	var a := MirrorAction.new(id, "player", target, type, {}, ctx)
	a.client_request_id = request_id
	return a

# A scripted session touching every transaction type. Used by persistence tests and the
# golden-master test, so its exact sequence is part of the regression contract.
static func rich_engine() -> MirrorEngine:
	var t := MirrorDomain.ActionType
	var e := engine()
	e.resolve_action(act("look_door", "door", t.LOOK, {}, "r-look"))
	e.resolve_action(act("ask_tomas", "tomas", t.ASK))
	e.resolve_action(act("wait", "", t.WAIT))
	e.resolve_action(act("cast_light", "lamp", t.CAST))
	e.record_observation("player", "tomas", {"signature": ["OBS"], "note": "paused"}, {"where": "clearing"},
		[{"id": "ev.pause", "type": MirrorDomain.EvidenceType.INDIRECT, "payload": {"seconds": 2}}],
		[{"id": "tomas_paused", "proposition": {"tomas": "paused"}, "status": MirrorDomain.EpistemicStatus.POSSIBLE, "scope": "tomas"}],
		[{"type": "upsert", "rule_id": "m.distrust", "subject_id": "tomas", "proposition": {"tomas": "distrusts"}, "scope": "tomas", "confidence": 0.4}])
	e.share_claim("player", "tomas", "door_sealed")
	e.advance_time(4, "system", "test")
	e.consume_storylet("story.intro", "player", {"door": "closed"})
	e.revoke_operator("player", "light_bringer")
	return e
