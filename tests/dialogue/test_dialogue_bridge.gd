extends TestCase

func _t(key: String) -> String:
	return Localization.load_table()[key]

func _bridge(r: MirrorRuntime) -> DialogueBridge:
	var manager: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DialogueManager")
	ok(manager != null, "the DialogueManager autoload is registered")
	return DialogueBridge.new(r.engine, manager)

func _collect(bridge: DialogueBridge, title: String) -> Array[Dictionary]:
	var sink := func(_speaker: String, _text: String, _responses: Array) -> int: return 0
	return await bridge.run(title, sink)

func test_a_title_resolves_to_russian_prose_from_the_single_table() -> void:
	var r := GameFixtures.runtime()
	var shown := await _collect(_bridge(r), "tomas_show_wand")
	eq(shown.size(), 3, "three lines")
	eq(shown[0]["speaker"], _t("speaker.tomas"), "speaker name comes from speaker.tomas")
	eq(shown[1]["text"], _t("dlg.tomas_show_wand.2"), "line text comes from dlg.tomas_show_wand.2")
	eq(shown[2]["text"], _t("dlg.tomas_show_wand.3"), "third line")

func test_wording_follows_mirror_state_through_the_read_only_context() -> void:
	var r := GameFixtures.runtime()
	var bridge := _bridge(r)
	var first := await _collect(bridge, "tomas_ask_what")
	eq(first[1]["text"], _t("dlg.tomas_ask_what.2a"), "while he expects magic he says so")
	GameFixtures.do(r, "wait_watch", "tomas")
	var second := await _collect(bridge, "tomas_ask_what")
	eq(Expectation.of(r.engine, "tomas"), "EXPECT_DISTANCE", "waiting changed what he expects")
	eq(second[1]["text"], _t("dlg.tomas_ask_what.2b"), "and the same title now reads differently")

func test_a_line_without_a_speaker_is_narration() -> void:
	var shown := await _collect(_bridge(GameFixtures.runtime()), "tomas_quiet")
	eq(shown.size(), 1, "one line")
	eq(shown[0]["speaker"], "", "no speaker")
	eq(shown[0]["text"], _t("dlg.tomas_quiet.1"), "narration text")

func test_every_authored_title_plays_to_the_end_in_russian() -> void:
	var r := GameFixtures.runtime()
	var bridge := _bridge(r)
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	var titles: Array[String] = []
	for line in FileAccess.get_file_as_string(DialogueBridge.DEFAULT_RESOURCE).split("\n"):
		if line.begins_with("~ "):
			titles.append(line.substr(2).strip_edges())
	ok(titles.size() >= 11, "found the titles")
	for title in titles:
		var shown := await _collect(bridge, title)
		ok(shown.size() > 0, "%s produced lines" % title)
		for entry in shown:
			ok(cyrillic.search(entry["text"]) != null or entry["text"] == "...", "%s resolved to prose, not a key: %s" % [title, entry["text"]])

func test_dialogue_reads_but_never_writes_game_state() -> void:
	var r := GameFixtures.runtime()
	var before := MirrorHash.canonical_json(r.engine.projection_snapshot())
	var head := r.engine.event_store.head_hash()
	await _collect(_bridge(r), "tomas_thanks_together")
	eq(r.engine.event_store.head_hash(), head, "no event from merely speaking")
	eq(MirrorHash.canonical_json(r.engine.projection_snapshot()), before, "no state change")

func test_a_player_choice_is_committed_to_mirror_as_a_recorded_action() -> void:
	var r := GameFixtures.runtime()
	var manager: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("DialogueManager")
	var script: Resource = manager.create_resource_from_text("~ start\ntomas: test.prompt\n- test.yes [ID:test.yes]\n\ttomas: test.after_yes\n- test.no [ID:test.no]\n\ttomas: test.after_no\n=> END\n")
	var bridge := DialogueBridge.new(r.engine, manager)
	var seen_responses: Array = []
	var sink := func(_speaker: String, _text: String, responses: Array) -> int:
		if not responses.is_empty():
			seen_responses.append(responses.map(func(x): return x["id"]))
		return 1 if not responses.is_empty() else 0
	var shown := await bridge.run("start", sink, script)
	eq(seen_responses, [["test.yes", "test.no"]], "stable ids from [ID:] tags")
	eq(shown.back()["text"], "test.after_no", "the chosen branch continued")
	var events := r.engine.event_store.get_all()
	var choice_events := events.filter(func(e): return e.event_type == "ActionResolved" and e.payload["action"]["id"] == "DIALOGUE_CHOICE")
	eq(choice_events.size(), 1, "the choice is in the canonical log")
	eq(choice_events[0].payload["action"]["payload"]["choice_id"], "test.no", "with its stable id")

func test_the_dialogue_context_answers_from_mirror() -> void:
	var r := GameFixtures.runtime()
	var ctx := MirrorDialogueContext.new(r.engine)
	ok(ctx.can_ask("tomas", "machine"), "can ask what he is doing")
	ok(not ctx.can_ask("tomas", "help"), "cannot yet ask about help")
	ok(not ctx.has_knowledge("bell_tilted_into_wind"), "does not know")
	eq(ctx.expected_action("tomas"), "EXPECT_MAGIC", "his expectation")
	eq(ctx.relationship_value("tomas", "boundaries.intervention"), null, "nothing recorded yet")
	GameFixtures.do(r, "show_tomas_wand", "tomas")
	eq(ctx.relationship_value("tomas", "boundaries.intervention"), {"wand_shown_not_used": true}, "a boundary is now on record")
	ok(ctx.last_event("ActionResolved") != "", "last_event finds events")
	eq(ctx.last_event("OperatorRevoked"), "", "or reports none")
