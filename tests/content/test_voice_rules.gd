extends TestCase

# The act fragments the lint must read, by name; one that is not in the tree yet is reported as SKIP.
const ACT_FRAGMENTS := ["prologue", "act1", "act2", "act3", "act4", "act5", "act6", "act7", "act8", "act9", "postgame"]

# VOICES.md "Form", the glossary, the reserved phrases and their budgets, run over every line of the Russian table
# (the rules live in voice_lint.gd). Each rule is also proven on a fixture: a violation it must catch and a clean twin
# it must pass, so a lint that catches nothing cannot pass.

func test_every_line_of_the_table_keeps_the_form_rules() -> void:
	var table: Dictionary = Localization.load_table()
	var usage: Dictionary = VoiceLint.usage()
	ok(table.size() > 100, "the lint reads the whole table (%d lines)" % table.size())
	ok(usage["captions"].has("line.bell.tilted"), "the narrator's captions are told apart from bubbles")
	ok(usage["bubbles"].has("dlg.tomas_ask_what.1"), "and the spoken dialogue lines are bubbles")
	ok(usage["root_keys"].has("menu.continue"),"the root table is told apart from the area fragments (the hall's lines)")
	ok(usage["untestable"].size() > 0, "the untestable notes are read from the notebook (%d)" % usage["untestable"].size())
	eq(VoiceLint.check(table, usage), [], "no line breaks a form rule (key | rule | text)")

func test_the_reserved_phrases_stay_within_their_budgets_across_the_game() -> void:
	var table: Dictionary = Localization.load_table()
	eq(VoiceLint.budget_failures(table), [], "reserved phrases are counted over every line of the table")

func test_a_budget_counts_every_occurrence_and_refuses_one_more() -> void:
	for phrase in VoiceLint.BUDGETS.keys():
		var cap := int(VoiceLint.BUDGETS[phrase])
		var at_cap: Dictionary = {}
		for i in cap:
			at_cap["fx.line_%d" % i] = "x %s" % phrase
		var over: Dictionary = at_cap.duplicate()
		over["fx.extra"] = "y %s" % phrase
		eq(VoiceLint.budget_failures(at_cap), [], "%s: exactly at its budget is allowed" % phrase)
		eq(VoiceLint.budget_failures(over).size(), 1, "%s: one use over its budget is refused" % phrase)

func test_every_rule_catches_its_violation_and_passes_its_clean_twin() -> void:
	var fixtures := VoiceLint.fixtures()
	ok(fixtures.size() >= 18, "the lint has a fixture for every rule (%d)" % fixtures.size())
	for fixture: Dictionary in fixtures:
		var rule := str(fixture["rule"])
		var key := str(fixture["key"])
		var bad: Array[String] = VoiceLint.check({key: str(fixture["bad"])}, fixture.get("usage", {}))
		ok(_mentions(bad, rule), "%s: the violation is caught (%s)" % [rule, JSON.stringify(bad)])
		var clean_key := str(fixture.get("clean_key", key))
		var clean: Array[String] = VoiceLint.check({clean_key: str(fixture["clean"])}, fixture.get("clean_usage", {}))
		eq(clean, [], "%s: the clean twin passes" % rule)

func test_every_act_text_fragment_is_linted() -> void:
	var table: Dictionary = Localization.load_table()
	var present := 0
	for name in ACT_FRAGMENTS:
		var path := "res://data/text/ru/%s.json" % name
		if not FileAccess.file_exists(path):
			print("SKIP voice lint: data/text/ru/%s.json is not in the tree yet" % name)
			continue
		present += 1
		var fragment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var lines := 0
		var linted := 0
		for key in fragment.keys():
			if str(key).begins_with("_"):
				continue
			lines += 1
			if table.has(str(key)):
				linted += 1
		ok(lines > 0 and linted == lines, "%s.json: all %d of its lines are in the linted table" % [name, lines])
	ok(present > 0, "the act text fragments are read (%d of %d present)" % [present, ACT_FRAGMENTS.size()])
	for path in ContentFiles.files_in("res://data/text/ru", "json"):
		var fragment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var missing := 0
		for key in fragment.keys():
			if not str(key).begins_with("_") and not table.has(str(key)):
				missing += 1
		eq(missing, 0, "%s: every line of the fragment is linted" % path.get_file())

func _mentions(failures: Array[String], rule: String) -> bool:
	for failure in failures:
		if failure.contains(rule):
			return true
	return false
