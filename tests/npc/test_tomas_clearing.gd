extends TestCase

func test_initial_state() -> void:
	var r := GameFixtures.runtime()
	eq(GameFixtures.stance(r), "braced", "Tomas starts braced")
	eq(Expectation.of(r.engine, "tomas"), "EXPECT_MAGIC", "he expects the witch to simply solve it")
	eq(GameFixtures.machine_state(r), "jammed", "machine starts jammed")
	eq(r.engine.models.query_rules("tomas", "help", "player")[0]["id"], "m.helping_is_welcome", "the witch's naive model is on the record from event one")

func test_expectation_policy_classifies_each_verb_against_what_tomas_expects() -> void:
	var r := GameFixtures.runtime()
	var K := ResponsePolicy.Kind
	eq(ResponsePolicy.classify_action(r.engine, "tomas", "cast_repair"), K.CONFIRMED, "acting unasked is exactly what he expects")
	eq(ResponsePolicy.classify_action(r.engine, "tomas", "ask_tomas_what"), K.VIOLATED, "asking violates it")
	eq(ResponsePolicy.classify_action(r.engine, "tomas", "wait_watch"), K.VIOLATED, "waiting violates it")
	eq(ResponsePolicy.classify_action(r.engine, "tomas", "look_tomas"), K.NEUTRAL, "looking engages nothing")

func test_impulsive_magic_raises_outcome_certainty_and_lowers_motive_certainty() -> void:
	var r := GameFixtures.runtime()
	var result := GameFixtures.do(r, "cast_repair", "machine")
	ok(result["ok"], "cast resolves: %s" % JSON.stringify(result.get("details", {})))
	var vector: Dictionary = result["discrepancy"]["vector"]
	ok(not vector["outcome"], "the outcome is exactly what the witch predicted")
	ok(vector["motive"], "but the witch's model of why people respond to help does not hold")
	ok(vector["relationship"], "and the relationship does not land where predicted")
	eq(r.engine.knowledge.get_claim("machine_runs")["status"], MirrorDomain.EpistemicStatus.ESTABLISHED, "what happened: beyond doubt")
	eq(r.engine.knowledge.get_claim("why_tomas_withdrew")["status"], MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "why: unresolved by design")
	eq(GameFixtures.machine_state(r), "running_by_magic", "magic is spectacularly effective")
	eq(GameFixtures.stance(r), "withdrawn", "Tomas withdraws")
	eq(Expectation.of(r.engine, "tomas"), "EXPECT_MAGIC", "his expectation was confirmed, which is why it did not please him")

func test_the_contradiction_is_recorded_as_a_model_revision_not_a_flag() -> void:
	var r := GameFixtures.runtime()
	GameFixtures.do(r, "cast_repair", "machine")
	var old: Dictionary = r.engine.models.query_rules("tomas", "help", "player").filter(func(m): return m["id"] == "m.helping_is_welcome")[0]
	eq(old["status"], MirrorDomain.ModelStatus.CONTRADICTED, "the naive model is contradicted")
	var revised: Dictionary = r.engine.models.query_rules("tomas", "help", "player").filter(func(m): return m["id"] == "m.help_needs_authorship")[0]
	eq(revised["status"], MirrorDomain.ModelStatus.REVISED, "and a replacement exists")
	var kinds: Array = r.engine.models.history("player", "m.helping_is_welcome").map(func(h): return h["operation"])
	in_array("contradict", kinds, "history shows how the belief changed")

func test_contradictions_are_survivable_the_impulsive_path_recovers() -> void:
	var r := GameFixtures.runtime()
	var results := GameFixtures.play(r, GameFixtures.IMPULSIVE)
	for result in results:
		ok(result["ok"], "step resolves: %s" % JSON.stringify(result.get("details", {})))
	eq(results.size(), GameFixtures.IMPULSIVE.size(), "every step of the impulsive path was possible")
	ok(r.engine.operators.has("op.ask_before_acting"), "the learned abstraction is acquired at the end")
	eq(r.engine.get_world("clearing")["departed"], true, "the player chose to leave")

func test_patient_path_with_bell() -> void:
	var r := GameFixtures.runtime()
	var results := GameFixtures.play(r, GameFixtures.PATIENT_WITH_BELL)
	for result in results:
		ok(result["ok"], "step resolves: %s" % JSON.stringify(result.get("details", {})))
	eq(results.size(), GameFixtures.PATIENT_WITH_BELL.size(), "every step possible")
	eq(results[4]["response"]["id"], "wait_watch.bell_invites", "knowing the bell turns one wait into an invitation")

func test_patient_path_without_bell_takes_two_waits() -> void:
	var r := GameFixtures.runtime()
	var results := GameFixtures.play(r, GameFixtures.PATIENT_NO_BELL)
	eq(results.size(), GameFixtures.PATIENT_NO_BELL.size(), "all possible")
	eq(results[1]["response"]["id"], "wait_watch.relaxes", "first wait: he relaxes")
	eq(results[2]["response"]["id"], "wait_watch.invites_component", "second wait: he invites")

func test_showing_the_wand_produces_the_natural_but_wrong_hypothesis() -> void:
	var r := GameFixtures.runtime()
	var result := GameFixtures.do(r, "show_tomas_wand", "tomas")
	ok(result["ok"], "resolves")
	ok(result["discrepancy"]["vector"]["outcome"], "the witch expected to impress him")
	var rule: Dictionary = r.engine.models.query_rules("tomas", "help", "player").filter(func(m): return m["id"] == "m.tomas_distrusts_witch")[0]
	eq(rule["status"], MirrorDomain.ModelStatus.HYPOTHESIS, "'he doesn't trust me' is only a hypothesis")
	GameFixtures.do(r, "wait_watch", "tomas")
	GameFixtures.do(r, "wait_watch", "tomas")
	var after: Array = r.engine.models.query_rules("tomas", "help", "player").filter(func(m): return m["id"] == "m.tomas_distrusts_witch")
	eq(after[0]["status"], MirrorDomain.ModelStatus.REVISED, "being invited revises it into something truer")

func test_unsolicited_options_are_gated_by_what_has_happened() -> void:
	var r := GameFixtures.runtime()
	ok(not GameFixtures.do(r, "go_assist", "machine")["ok"], "cannot step in before being invited")
	ok(not GameFixtures.do(r, "ask_tomas_help", "tomas")["ok"], "cannot ask 'do you want help' before understanding that asking matters")
	ok(not GameFixtures.do(r, "cast_flourish", "machine")["ok"], "no flourish on a broken machine")
	ok(GameFixtures.do(r, "cast_repair", "machine")["ok"], "magic is available from the first moment")
	ok(not GameFixtures.do(r, "cast_repair", "machine")["ok"], "but only once, the machine is no longer jammed")

func test_flourish_is_powerful_and_socially_ambiguous_even_on_the_good_path() -> void:
	var r := GameFixtures.runtime()
	GameFixtures.play(r, GameFixtures.PATIENT_NO_BELL.slice(0, 4))
	var result := GameFixtures.do(r, "cast_flourish", "machine")
	ok(result["ok"], "resolves")
	ok(result["discrepancy"]["vector"]["motive"], "even here the witch cannot know why he went quiet")
	eq(r.engine.knowledge.get_claim("why_tomas_went_quiet")["status"], MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "unresolved by design")
	eq(GameFixtures.machine_state(r), "singing", "spectacle")

func test_ending_action_contract() -> void:
	var r := GameFixtures.runtime()
	var result := GameFixtures.do(r, "go_path_out", "path_out")
	ok(result["ok"], "GO is always available")
	var modes: Array = result["presentation"].map(func(p): return p.get("mode", p.get("kind")))
	in_array("stay", modes, "the camera does not follow")
	in_array("leave_frame", modes, "the witch leaves the frame")
	eq(result["observed"]["ending"], "unresolved", "the world remains unresolved")
	ok(not GameFixtures.do(r, "go_path_out", "path_out")["ok"], "it happens once")

func test_hypothesis_walks_from_evidence_needed_to_ready() -> void:
	var r := GameFixtures.runtime()
	eq(r.engine.evaluate_causal_hypothesis("h.authorship_not_trust", "player", r.context_snapshot())["state"], "evidence_needed", "starts without evidence")
	GameFixtures.do(r, "show_tomas_wand", "tomas")
	GameFixtures.do(r, "wait_watch", "tomas")
	GameFixtures.do(r, "wait_watch", "tomas")
	eq(r.engine.evaluate_causal_hypothesis("h.authorship_not_trust", "player", r.context_snapshot())["state"], "operator_unacquired", "evidence and model in place; the abstraction is not yet owned")
	GameFixtures.do(r, "go_assist", "machine")
	eq(r.engine.evaluate_causal_hypothesis("h.authorship_not_trust", "player", r.context_snapshot())["state"], "ready", "owned after the partnership")
