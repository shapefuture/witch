extends TestCase

const T := MirrorDomain.ActionType

func _engine() -> MirrorEngine:
	var e := MirrorEngine.new()
	e.set_npc_state("tomas", {"stance": "braced", "expects": "EXPECT_MAGIC"})
	e.set_npc_state("vera", {"stance": "calm"})
	e.register_action({
		"id": "touch_machine", "action_type": T.CUSTOM, "valid_targets": ["machine"],
		# target is the machine, but the decision depends on Tomas, who is not the target
		"preconditions": {"npc.vera.stance": "calm"},
		"prediction_candidates": [{"id": "p", "when": {"npc.tomas.expects": "EXPECT_MAGIC"}, "expected": {"outcome": "x"}}],
		"response_contracts": [
			{"id": "braced", "priority": 5, "when": {"npc.tomas.stance": "braced"}, "observed": {"outcome": "braced_reaction"}},
			{"id": "default", "observed": {"outcome": "default_reaction"}},
		],
	})
	return e

func test_conditions_can_read_any_npcs_state_not_only_the_targets() -> void:
	var e := _engine()
	var r := e.resolve_action(MirrorFixtures.act("touch_machine", "machine", T.CUSTOM))
	ok(r["ok"], "available because vera is calm: %s" % JSON.stringify(r.get("details", {}).get("reasons", [])))
	eq(r["response"]["id"], "braced", "response chosen from Tomas's stance while the target was the machine")
	eq(r["prediction"].get("id", ""), "p", "prediction candidates see npc state too")

func test_npc_state_changes_are_visible_to_the_next_action() -> void:
	var e := _engine()
	e.npc_state["tomas"]["stance"] = "working"
	var r := e.resolve_action(MirrorFixtures.act("touch_machine", "machine", T.CUSTOM))
	eq(r["response"]["id"], "default", "state change respected")

func test_action_blocked_by_another_npcs_state() -> void:
	var e := _engine()
	e.npc_state["vera"]["stance"] = "angry"
	var report := e.explain_action(MirrorFixtures.act("touch_machine", "machine", T.CUSTOM))
	ok(not report["available"], "blocked")
	eq(report["affordance_state"], "blocked_by_state", "bucketed as a state block")
