extends TestCase

# The four laws of comic causal worldmaking, enforced over the authored catalog (data/mirror/minds) by
# FourLawsLinter. The real catalog must pass; for each law, a deliberately broken fixture must fail with a
# message that says what to fix.

func _table() -> Dictionary:
	GameFixtures.ensure_localization()
	return Localization.load_table()

func _real() -> Dictionary:
	var loaded := MindsCatalog.load_dir()
	eq(loaded["errors"], [], "the authored minds catalog loads clean")
	return loaded["data"]

func test_the_authored_hall_obeys_the_four_laws() -> void:
	var engine: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	var findings := FourLawsLinter.lint(_real(), {"table": _table(), "engine": engine})
	var failing := FourLawsLinter.errors(findings)
	eq(failing.size(), 0, "no law is broken:\n%s" % FourLawsLinter.format(failing))

func test_each_hall_rule_passes_the_five_tests() -> void:
	var tests := FourLawsLinter.five_tests(_real(), _table())
	eq(tests.size(), 3, "three rules")
	for rule_id in tests.keys():
		for name in tests[rule_id].keys():
			ok(tests[rule_id][name], "%s: %s" % [rule_id, name])

func test_every_hall_rule_recombines_with_another() -> void:
	var meets := FourLawsLinter.recombinations(_real())
	for rule_id in meets.keys():
		ok(not (meets[rule_id] as Array).is_empty(), "%s meets another rule: %s" % [rule_id, JSON.stringify(meets[rule_id])])
	var via_echo: Array = meets["rule.hall.echo"].map(func(m: Dictionary) -> String: return m["with"])
	in_array("rule.hall.regard", via_echo, "an echo is something to look at: regard answers to the events echo schedules")
	in_array("rule.hall.name", via_echo, "and a custom changes how the echo behaves")

func test_the_report_is_readable() -> void:
	var data := _valid()
	data["rules"][0]["invariant"] = {}
	var text := FourLawsLinter.format(FourLawsLinter.lint(MindsCatalog.build(data)["data"]))
	ok("[law 1 error] rule.t.echo (no_invariant)" in text, "names the law, the rule and the code: %s" % text)
	ok("declare its invariant" in text, "and says what to do")

# ---- fixtures: a rule that satisfies every law, then one thing broken at a time -----------------------------

func _valid() -> Dictionary:
	var data := MindsFixtures.raw()
	var rule := MindsFixtures.echo_rule(3)
	rule["invariant"]["constraints"]["same_reaction"] = true
	rule["revision"] = {"model": "m.t.each", "deeper_model": "m.t.latest", "exception": "t.exception.latest", "teaches": {"key": "k.teaches"}}
	rule["variants"][0]["evidence"]["model_effects"] = [{"type": "ensure", "rule_id": "m.t.each", "subject_id": "room", "proposition": {"answers": "each"}, "scope": "room"}]
	rule["variants"].append({
		"id": "t.ana_copies", "domain": "social", "form": "social", "source": "ana",
		"relation": {"id": "answers_later", "polarity": "+", "bindings": {"q": "door", "a": "ana"}},
		"trigger": {"event_kind": "KNOCK", "actor": "player", "witnessed_by": "ana"},
		"transformation": {"schedule": [{"delay": 2, "event": {"kind": "KNOCK", "actor": "ana", "subject": "$subject", "data": {"reaction": "$reaction"}}}]},
		"evidence": {"holders": ["player"], "at": "consequence", "knowledge_effects": [{"id": "ana_copies", "proposition": {"ana": "copies"}, "status": "SUPPORTED"}]},
	})
	rule["exceptions"] = [{
		"id": "t.exception.latest", "domain": "epistemic", "form": "counter", "source": "bell", "polarity": "+", "scope": "two knocks before an answer",
		"teaches": {"key": "k.teaches"},
		"trigger": {"event_kind": "KNOCK", "subject": "bell", "actor": "player"},
		"evidence": {"holders": ["player"], "at": "trigger", "knowledge_effects": [{"id": "latest_only", "proposition": {"x": 1}, "status": "SUPPORTED"}],
			"model_effects": [{"type": "revise", "old_rule_id": "m.t.each", "new_rule_id": "m.t.latest", "proposition": {"answers": "latest"}, "scope": "room", "subject_id": "room"}]},
	}]
	data["rules"] = [rule]
	data["conventions"] = [MindsFixtures.door_convention()]
	return data

func _lint(mutator: Callable, options: Dictionary = {}) -> Array:
	var data := _valid()
	mutator.call(data)
	var built := MindsCatalog.build(data)
	return FourLawsLinter.lint(built["data"], options)

func _codes(findings: Array, severity: String = "error") -> Array:
	var out: Array = []
	for finding in findings:
		if finding["severity"] == severity:
			out.append(finding["code"])
	return out

func _message(findings: Array, code: String) -> String:
	for finding in findings:
		if finding["code"] == code:
			return finding["message"]
	return ""

func test_the_baseline_fixture_is_clean() -> void:
	var findings := _lint(func(_d: Dictionary) -> void: pass)
	eq(_codes(findings), [], "the valid fixture has no errors: %s" % FourLawsLinter.format(findings))

# LAW 1

func test_law_1_a_variant_may_not_change_the_relation() -> void:
	var findings := _lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["relation"]["id"] = "something_else")
	in_array("variant_relation_mismatch", _codes(findings), "relation changed")
	ok("may not" in _message(findings, "variant_relation_mismatch"), "message explains the law")

func test_law_1_a_variant_may_not_reverse_the_polarity() -> void:
	var findings := _lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["relation"]["polarity"] = "-")
	in_array("polarity_flip", _codes(findings), "polarity flipped")

func test_law_1_every_role_must_be_bound() -> void:
	var findings := _lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["relation"]["bindings"].erase("a"))
	in_array("unbound_role", _codes(findings), "a role is left unbound")
	ok("'a'" in _message(findings, "unbound_role"), "and the message names it")

func test_law_1_the_transformation_must_satisfy_the_invariants_constraints() -> void:
	var too_soon := _lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["transformation"]["schedule"][0]["delay"] = 0)
	in_array("constraint_violation", _codes(too_soon), "delay under delay_min")
	ok("delay_min" in _message(too_soon, "constraint_violation"), "message names the constraint")
	var not_in_kind := _lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["transformation"]["schedule"][0]["event"]["data"]["reaction"] = "spin")
	ok("in kind" in _message(not_in_kind, "constraint_violation"), "an answer that is not the same move is flagged")

func test_law_1_a_convention_may_not_break_the_invariant_either() -> void:
	var findings := _lint(func(d: Dictionary) -> void:
		d["rules"][0]["variants"][0]["conventions"] = {"conv.t.door_is_a_game": {"patch": {"set": {"schedule.0.delay": 0}}}})
	in_array("convention_patch_breaks_invariant", _codes(findings), "the patched variant is checked too")
	ok("Folklore may alter" in _message(findings, "convention_patch_breaks_invariant"), "message explains")

func test_law_1_a_rule_must_declare_an_invariant_and_know_its_constraints() -> void:
	in_array("no_invariant", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["invariant"] = {})), "no invariant")
	in_array("unknown_constraint", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["invariant"]["constraints"]["delay_mni"] = 1)), "a typo in a constraint is an error, not silence")

func test_law_1_an_exception_narrows_it_may_not_reverse() -> void:
	in_array("exception_flips_polarity", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["exceptions"][0]["polarity"] = "-")), "flipped")
	in_array("exception_without_scope", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["exceptions"][0]["scope"] = "")), "no scope")

# LAW 2

func test_law_2_a_rule_needs_enough_independent_manifestations() -> void:
	var findings := _lint(func(d: Dictionary) -> void:
		d["rules"][0]["variants"].remove_at(1)
		d["rules"][0]["exceptions"][0].erase("trigger"))
	in_array("too_few_manifestations", _codes(findings), "one manifestation is a trick, not a rule")
	ok("needs 2" in _message(findings, "too_few_manifestations"), "message gives the number")
	var major := _lint(func(d: Dictionary) -> void:
		d["rules"][0]["major"] = true
		d["rules"][0]["exceptions"][0].erase("trigger"))
	ok("a major rule needs 3" in _message(major, "too_few_manifestations"), "a major rule needs three")

func test_law_2_manifestations_must_span_domains() -> void:
	var findings := _lint(func(d: Dictionary) -> void:
		for variant in d["rules"][0]["variants"]:
			variant["domain"] = "physical"
		d["rules"][0]["exceptions"][0]["domain"] = "physical")
	in_array("too_few_domains", _codes(findings), "all in one domain")

func test_law_2_every_manifestation_must_teach_the_witch_something() -> void:
	var findings := _lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][1].erase("evidence"))
	in_array("no_player_evidence", _codes(findings), "a manifestation she cannot learn from")
	var wrong_holder := _lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][1]["evidence"]["holders"] = ["ana"])
	in_array("no_player_evidence", _codes(wrong_holder), "evidence only for a non-player is no evidence for her")

func test_law_2_domain_and_form_must_be_known() -> void:
	var findings := _lint(func(d: Dictionary) -> void:
		d["rules"][0]["variants"][0]["domain"] = "spooky"
		d["rules"][0]["variants"][0]["form"] = "vibes")
	in_array("unknown_domain", _codes(findings), "domain")
	in_array("unknown_form", _codes(findings), "form")

# LAW 3

func test_law_3_a_learnable_rule_needs_a_revision_path() -> void:
	in_array("no_revision_path", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0].erase("revision"))), "none declared")
	var unreachable := _lint(func(d: Dictionary) -> void: d["rules"][0]["exceptions"][0]["evidence"]["model_effects"] = [])
	in_array("revision_unreachable", _codes(unreachable), "declared but no effect revises")
	ok("revise" in _message(unreachable, "revision_unreachable"), "the message names the fix")

func test_law_3_contradicting_a_model_without_revising_it_is_punishment() -> void:
	var findings := _lint(func(d: Dictionary) -> void:
		var effects: Array = d["rules"][0]["exceptions"][0]["evidence"]["model_effects"]
		effects[0] = {"type": "contradict", "rule_id": "m.t.each"})
	in_array("punishing_contradiction", _codes(findings), "contradict without revise")

func test_law_3_an_exception_must_teach_and_the_model_must_exist_to_be_revised() -> void:
	in_array("exception_teaches_nothing", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["exceptions"][0].erase("teaches"))), "an exception that teaches nothing is just 'this one works differently'")
	in_array("model_never_formed", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["evidence"]["model_effects"] = [])), "nothing ever gives the witch the model")
	in_array("unknown_exception", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["revision"]["exception"] = "nope")), "revision names an exception that is not there")

# LAW 4

func test_law_4_a_convention_must_declare_its_origin() -> void:
	var findings := _lint(func(d: Dictionary) -> void: d["conventions"][0].erase("origin"))
	in_array("no_origin", _codes(findings), "no origin")
	ok("gimmick" in _message(findings, "no_origin"), "message explains")
	in_array("fed_by_mismatch", _codes(_lint(func(d: Dictionary) -> void: d["conventions"][0]["origin"]["fed_by"] = ["i.ana.rude"])), "the named interpretation reads something else")
	in_array("fed_by_unknown", _codes(_lint(func(d: Dictionary) -> void: d["conventions"][0]["origin"]["fed_by"] = ["i.nobody"])), "or does not exist")

func test_law_4_a_convention_must_be_bounded_and_reachable() -> void:
	in_array("never_decays", _codes(_lint(func(d: Dictionary) -> void: d["conventions"][0].erase("decay"))), "it must fade unless declared permanent")
	in_array("unbounded_tally", _codes(_lint(func(d: Dictionary) -> void: d["conventions"][0]["cap"] = 1)), "cap below the threshold")
	in_array("unreachable_adoption", _codes(_lint(func(d: Dictionary) -> void: d["conventions"][0]["adopt"]["min_holders"] = 3)), "needs more minds than the community has")
	in_array("unbounded_adoption", _codes(_lint(func(d: Dictionary) -> void: d["conventions"][0]["adopt"]["threshold"] = 0)), "no threshold")

func test_law_4_a_convention_must_do_something() -> void:
	var findings := _lint(func(d: Dictionary) -> void: d["conventions"][0]["force"] = {})
	in_array("no_causal_force", _codes(findings), "a convention that changes nothing is flavour")
	var with_variant := _lint(func(d: Dictionary) -> void:
		d["conventions"][0]["force"] = {}
		d["rules"][0]["variants"][0]["conventions"] = {"conv.t.door_is_a_game": {"patch": {"set": {"schedule.0.delay": 2}}}})
	not_in_array("no_causal_force", _codes(with_variant), "a variant that depends on it is force enough")

func test_law_4_an_enabled_operator_must_exist() -> void:
	var engine := MirrorEngine.new()
	var findings := _lint(func(d: Dictionary) -> void: d["conventions"][0]["force"]["enables_operators"] = ["op.nope"], {"engine": engine})
	in_array("unknown_operator", _codes(findings), "operator not in the engine catalog")
	engine.register_operator({"id": "op.nope"})
	not_in_array("unknown_operator", _codes(_lint(func(d: Dictionary) -> void: d["conventions"][0]["force"]["enables_operators"] = ["op.nope"], {"engine": engine})), "and fine once it is")

func test_law_4_at_runtime_whatever_is_adopted_has_origin_events() -> void:
	var rig := MindsFixtures.rig(_valid())
	ok(FourLawsLinter.lint_state(rig.minds).is_empty(), "an untouched world is clean")
	rig.minds.state.conventions.apply_updates([{"id": "conv.t.door_is_a_game", "adopted": true, "origin_events": []}])
	in_array("adopted_without_origin", _codes(FourLawsLinter.lint_state(rig.minds)), "a custom with no recorded origin")
	rig.minds.state.conventions.apply_updates([{"id": "conv.t.door_is_a_game", "adopted": true, "origin_events": ["tx_not_there:event"]}])
	in_array("origin_not_in_log", _codes(FourLawsLinter.lint_state(rig.minds)), "an origin that is not in the log")

# STRUCTURE

func test_references_must_resolve() -> void:
	in_array("unknown_event_kind", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["trigger"]["event_kind"] = "NOPE")), "event kind")
	in_array("unknown_subject", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["trigger"]["subject"] = "teapot")), "subject")
	in_array("unknown_holder", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][1]["trigger"]["witnessed_by"] = "ghost")), "holder")
	in_array("unknown_convention", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["conventions"] = {"conv.nope": {"patch": {}}})), "convention")
	in_array("unknown_template_token", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["evidence"]["knowledge_effects"][0]["id"] = "x.$colour")), "template token")
	in_array("unknown_model_effect", _codes(_lint(func(d: Dictionary) -> void: d["rules"][0]["variants"][0]["evidence"]["model_effects"][0]["type"] = "ensuer")), "model effect type")
	var ops := _lint(func(d: Dictionary) -> void:
		d["reaction_ops"] = ["LOOK_AT"]
		d["rules"][0]["variants"][0]["transformation"]["reactions"] = [{"op": "DANCE"}])
	in_array("unknown_reaction_op", _codes(ops), "reaction op")

func test_text_keys_must_exist_in_the_table() -> void:
	var table := {"k.teaches": "x", "x": "x"}
	var clean := _lint(func(_d: Dictionary) -> void: pass, {"table": table})
	eq(_codes(clean), [], "every key present")
	var findings := _lint(func(d: Dictionary) -> void: d["rules"][0]["exceptions"][0]["teaches"]["key"] = "k.missing", {"table": table})
	in_array("missing_text", _codes(findings), "a key that is not in ru.json")
	ok("k.missing" in _message(findings, "missing_text"), "named in the message")
