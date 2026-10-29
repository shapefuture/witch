extends TestCase

# Whole-graph content rules (addons/mirror_engine/mirror_progress_validator.gd). The authored game
# must pass every rule; each rule must reject at least one seeded broken catalog in
# tests/mirror/fixtures_validators/. Each fixture must load cleanly first, so that the rule under
# test is the only thing rejecting it.

const FIXTURES := "res://tests/mirror/fixtures_validators"
const ENDINGS := [{"clearing.departed": true}]
const GOAL := "help_respected_authorship"

var _game_report: Dictionary = {}

func _game_engine() -> MirrorEngine:
	return MirrorCatalog.build_engine()["engine"]

func _game() -> Dictionary:
	if _game_report.is_empty():
		_game_report = MirrorValidator.new().validate_progress(_game_engine(), {"terminal": ENDINGS, "goals": [GOAL]})
	return _game_report

func _fixture(name: String) -> Dictionary:
	var built := MirrorCatalog.build_engine("%s/%s" % [FIXTURES, name])
	ok(built["report"]["ok"], "fixture %s loads cleanly: %s" % [name, JSON.stringify(built["report"]["errors"])])
	return {"engine": built["engine"], "report": built["report"]}

func _containing(messages: Array, fragment: String) -> Array:
	var found: Array = []
	for message in messages:
		if str(message).contains(fragment):
			found.append(message)
	return found

func test_the_authored_game_passes_every_whole_graph_rule() -> void:
	var report := _game()
	eq(report["errors"], [], "no errors on data/mirror")
	eq(report["stats"]["truncated"], false, "the whole reachable state space was explored")
	ok(report["stats"]["states"] > 1000, "the analysis covered real state (%d states)" % report["stats"]["states"])
	ok(report["stats"]["transitions"] > report["stats"]["states"], "and real transitions (%d)" % report["stats"]["transitions"])

func test_the_known_findings_on_the_authored_game_are_advisory_warnings() -> void:
	# Three gates have one evidence route each. That is a fragility to review, not a failure: the
	# schema has no critical flag, so no claim is declared critical yet.
	var routes := _containing(_game()["warnings"], "single evidence route")
	eq(routes.size(), 3, "three single-route gates reported")
	for claim_id in ["bell_tilted_into_wind", "tomas_explained_alignment", "tomas_paused_at_wand"]:
		ok(_containing(routes, "'%s'" % claim_id).size() == 1, "%s is reported as fragile" % claim_id)

func test_the_authored_text_passes_the_vocabulary_lint() -> void:
	var texts: Dictionary = Localization.load_table()
	var report := MirrorValidator.new().validate_player_text(_game_engine(), texts)
	eq(report["errors"], [], "no engine identifiers or vocabulary in ru.json")
	ok(report["stats"]["texts"] > 50, "the lint read the whole table (%d texts)" % report["stats"]["texts"])

func test_an_unreachable_gate_is_rejected() -> void:
	var fixture := _fixture("unreachable_gate")
	var report := MirrorValidator.new().validate_progress(fixture["engine"], {"terminal": ENDINGS})
	ok(not report["ok"], "rejected")
	eq(_containing(report["errors"], "'never_made' is unreachable").size(), 1, "the gate nothing produces is named")

func test_a_critical_claim_with_one_route_is_rejected() -> void:
	var fixture := _fixture("single_route_critical")
	var declared := MirrorValidator.new().validate_progress(fixture["engine"], {"critical_claims": ["rare_fact"]})
	eq(_containing(declared["errors"], "'rare_fact' has 1 evidence route").size(), 1, "declared critical with one route is an error")
	var undeclared := MirrorValidator.new().validate_progress(fixture["engine"], {})
	eq(undeclared["errors"], [], "the same content is not an error until a claim is declared critical")
	eq(_containing(undeclared["warnings"], "'rare_fact' comes only from look_c").size(), 1, "and it is reported as fragile")

func test_a_response_that_destroys_progress_is_rejected() -> void:
	var fixture := _fixture("destroys_progress")
	var report := MirrorValidator.new().validate_progress(fixture["engine"], {"terminal": ENDINGS, "goals": ["goal_fact"]})
	eq(_containing(report["errors"], "response hush/hush.quiet destroys progress").size(), 1, "the response that makes the goal unreachable is named")

func test_an_ending_is_exempt_from_the_progress_rule() -> void:
	var fixture := _fixture("destroys_progress")
	var with_ending := MirrorValidator.new().validate_progress(fixture["engine"], {"terminal": ENDINGS, "goals": ["goal_fact"]})
	eq(_containing(with_ending["errors"], "leave").size(), 0, "leaving the hall is an ending, not a loss of progress")
	var without_ending := MirrorValidator.new().validate_progress(fixture["engine"], {"goals": ["goal_fact"]})
	eq(_containing(without_ending["errors"], "leave/leave.depart").size(), 1, "without the ending declared, leaving is treated as a loss")

func test_an_intended_unresolved_closure_is_a_warning_not_an_error() -> void:
	var fixture := _fixture("destroys_progress_marked")
	var report := MirrorValidator.new().validate_progress(fixture["engine"], {"terminal": ENDINGS, "goals": ["goal_fact"]})
	eq(report["errors"], [], "the author marked the loss as intended")
	eq(_containing(report["warnings"], "response hush/hush.quiet closes goal 'goal_fact'").size(), 1, "the loss is still reported, as a warning")

func test_engine_vocabulary_in_player_text_is_rejected() -> void:
	var texts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "/leaky_text/text.json"))
	var report := MirrorValidator.new().validate_player_text(_game_engine(), texts)
	ok(not report["ok"], "rejected")
	ok(_containing(report["errors"], "line.word: engine vocabulary 'SUPPORTED'").size() == 1, "an enum name")
	ok(_containing(report["errors"], "line.word: engine vocabulary 'claim'").size() == 1, "a vocabulary word")
	ok(_containing(report["errors"], "line.identifier: engine identifier 'tomas_explained_alignment'").size() == 1, "a catalog identifier")
	ok(_containing(report["errors"], "line.enum: engine identifier 'EXPECT_MAGIC'").size() == 1, "an epistemic expectation name")
	eq(_containing(report["errors"], "line.clean").size(), 0, "ordinary prose passes")

func test_the_exploration_is_bounded_and_says_so() -> void:
	var report := MirrorValidator.new().validate_progress(_game_engine(), {"max_states": 3})
	ok(not report["ok"], "a truncated analysis is never a pass")
	eq(_containing(report["errors"], "progress analysis incomplete").size(), 1, "the truncation is reported as an error")
