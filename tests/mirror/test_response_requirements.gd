extends TestCase

const T := MirrorDomain.ActionType

func _engine_with_model_gated_response() -> MirrorEngine:
	var e := MirrorEngine.new()
	e.set_npc_state("tomas", {})
	e.register_action({
		"id": "ask", "action_type": T.ASK, "valid_targets": ["tomas"],
		"response_contracts": [
			{"id": "informed", "priority": 5, "observed": {"outcome": "informed"},
				"requires_models": [{"observer_id": "player", "subject_id": "tomas", "id": "m.authorship", "min_status": MirrorDomain.ModelStatus.SUPPORTED}]},
			{"id": "plain", "priority": 0, "observed": {"outcome": "plain"}},
		],
	})
	return e

func test_response_model_requirement_honours_explicit_observer() -> void:
	var e := _engine_with_model_gated_response()
	e.models.upsert_rule("m.authorship", "tomas", {"values": "authorship"}, "clearing", 0.8, MirrorDomain.ModelStatus.SUPPORTED, 1, [], "player")
	var r := e.resolve_action(MirrorFixtures.act("ask", "tomas", T.ASK))
	ok(r["ok"], "resolved")
	eq(r["response"].get("id", ""), "informed", "a contract requiring the PLAYER's model must see the player's model, not the NPC's")

func test_response_model_requirement_defaults_to_the_responder() -> void:
	var e := MirrorEngine.new()
	e.register_action({
		"id": "ask", "action_type": T.ASK,
		"response_contracts": [
			{"id": "npc_knows", "priority": 5, "observed": {"outcome": "x"}, "requires_models": [{"subject_id": "player", "id": "m.npc_view"}]},
			{"id": "plain", "observed": {"outcome": "y"}},
		],
	})
	e.models.upsert_rule("m.npc_view", "player", {}, "g", 0.6, MirrorDomain.ModelStatus.SUPPORTED, 1, [], "tomas")
	var r := e.resolve_action(MirrorFixtures.act("ask", "tomas", T.ASK))
	eq(r["response"].get("id", ""), "npc_knows", "with no observer_id the NPC (responder) is the observer, as before")
