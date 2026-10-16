extends TestCase

# The notebook (ALIVENESS; ROOM_OF_US items 1 and 2): entries are the witch's claims, labelled seen, told, guessed or
# open; open questions stay visible; every entry opens the event it came from; discovery classes interleave.

const S := MirrorDomain.EpistemicStatus

func _played() -> MirrorRuntime:
	var r := GameFixtures.runtime()
	GameFixtures.play(r, [["look_bell", "bell"], ["ask_tomas_what", "tomas"], ["wait_watch", "tomas"]])
	return r

func test_the_notebook_lists_what_the_witch_holds_with_a_known_kind() -> void:
	var entries := NotebookView.entries(_played().engine)
	ok(entries.size() > 0, "the witch holds something after a few actions (%d entries)" % entries.size())
	for entry in entries:
		ok(entry["kind"] in NotebookView.KINDS, "%s is labelled seen, told, guessed or open" % entry["claim"])

func test_every_entry_opens_the_event_it_came_from() -> void:
	var r := _played()
	for entry in NotebookView.entries(r.engine):
		var source := NotebookView.source_event(r.engine, entry)
		ok(not source.is_empty(), "%s: its event %s is in the log" % [entry["claim"], entry["event_id"]])
		eq(str(source.get("event_id", "")), str(entry["event_id"]), "%s: and that is the event it names" % entry["claim"])

func test_an_open_question_stays_visible_and_is_not_labelled_guessed() -> void:
	var r := _played()
	r.engine.record_observation("player", "bell", {"signature": ["PUZZLE"]}, {}, [], [{"id": "q.open_bell", "holder_id": "player", "proposition": {"open": "bell"}, "status": S.UNRESOLVED_BY_DESIGN, "scope": "room"}])
	var found: Array = NotebookView.entries(r.engine).filter(func(e: Dictionary) -> bool: return e["claim"] == "q.open_bell")
	eq(found.size(), 1, "the open question is in the notebook")
	eq(str(found[0]["kind"]), NotebookView.OPEN, "labelled open")

func test_seen_told_guessed_and_open_are_told_apart() -> void:
	eq(NotebookView.kind_of({"status": S.SUPPORTED, "source": "hearsay", "evidence": []}), NotebookView.TOLD, "hearsay is told")
	eq(NotebookView.kind_of({"status": S.ESTABLISHED, "source": "authored", "evidence": ["e1"]}), NotebookView.SEEN, "established on evidence is seen")
	eq(NotebookView.kind_of({"status": S.POSSIBLE, "source": "authored", "evidence": []}), NotebookView.GUESSED, "a possibility is guessed")
	eq(NotebookView.kind_of({"status": S.UNRESOLVED_BY_DESIGN, "source": "hearsay", "evidence": []}), NotebookView.OPEN, "an open question wins over its source")

func test_the_notebook_interleaves_discovery_classes_so_neighbours_differ() -> void:
	var r := _played()
	var ids: Array = []
	for entry in NotebookView.entries(r.engine):
		ids.append(entry["claim"])
	var classes := {}
	for i in ids.size():
		classes[ids[i]] = "humour" if i % 2 == 0 else "lore"
	var ordered := NotebookView.entries(r.engine, classes)
	eq(ordered.size(), ids.size(), "every entry is still there")
	var neighbours_differ := true
	for i in range(1, ordered.size()):
		if ordered[i]["discovery_class"] == ordered[i - 1]["discovery_class"]:
			neighbours_differ = false
	ok(neighbours_differ, "two classes in turn: no two neighbours share a class")

func test_a_motif_that_recurs_in_another_room_and_form_is_noted_as_a_rhyme() -> void:
	var entries := [{"claim": "c.bell"}, {"claim": "c.machine"}, {"claim": "c.globe"}, {"claim": "c.hidden"}]
	var motifs := [
		{"claim": "c.bell", "tag": "chime", "room": "hall", "form": "sound"},
		{"claim": "c.machine", "tag": "chime", "room": "den", "form": "light"},
		{"claim": "c.globe", "tag": "chime", "room": "den", "form": "sound"},
		{"claim": "c.hidden", "tag": "chime", "room": "attic", "form": "object"},
		{"claim": "c.bell", "tag": "stillness", "room": "hall", "form": "object"},
	]
	var notes := NotebookView.rhymes(entries.slice(0, 3), motifs)
	eq(notes.size(), 1, "one rhyme: bell and machine share a tag, a room and a form apart; globe shares the room, so it is not one")
	eq(notes[0]["claims"], ["c.bell", "c.machine"], "the note names the two claims")
	eq(notes[0]["motif"], "chime", "and the motif")
	eq(NotebookView.rhymes(entries.slice(0, 1), motifs).size(), 0, "a claim the notebook does not show makes no rhyme")
