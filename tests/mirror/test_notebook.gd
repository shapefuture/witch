extends TestCase

# The notebook (ALIVENESS; ROOM_OF_US items 1 and 2; GAME_SPEC section 4): entries are the witch's claims that a sidecar
# names, each with the kind the sidecar gives it; an UNRESOLVED_BY_DESIGN claim stays visible as untestable; every entry
# opens the event it came from; discovery classes interleave.

const S := MirrorDomain.EpistemicStatus

func _played() -> MirrorRuntime:
	var r := GameFixtures.runtime()
	GameFixtures.play(r, [["look_bell", "bell"], ["ask_tomas_what", "tomas"], ["wait_watch", "tomas"]])
	return r

# A fixture sidecar that names every claim the witch holds, with the seven kinds in turn.
func _sidecar(r: MirrorRuntime) -> Dictionary:
	var claims := {}
	var i := 0
	for claim in r.engine.knowledge.all("player"):
		claims[str(claim.get("id", ""))] = {"kind": NotebookView.KINDS[i % NotebookView.KINDS.size()], "text": "note.test.claim%d" % i}
		i += 1
	return claims

func test_the_notebook_lists_what_the_witch_holds_with_a_known_kind() -> void:
	var r := _played()
	var entries := NotebookView.entries(r.engine, {}, _sidecar(r))
	ok(entries.size() > 0, "the witch holds something after a few actions (%d entries)" % entries.size())
	for entry in entries:
		ok(entry["kind"] in NotebookView.KINDS, "%s is one of the seven kinds" % entry["claim"])

func test_a_claim_no_sidecar_names_is_not_listed() -> void:
	var r := _played()
	eq(NotebookView.entries(r.engine).size(), 0, "without a sidecar the notebook lists nothing")
	eq(NotebookView.entries(r.engine, {}, {"c.not_held": {"kind": "seen", "text": "note.test.x"}}).size(), 0, "a named claim the witch does not hold is not listed")

func test_every_entry_opens_the_event_it_came_from() -> void:
	var r := _played()
	for entry in NotebookView.entries(r.engine, {}, _sidecar(r)):
		var source := NotebookView.source_event(r.engine, entry)
		ok(not source.is_empty(), "%s: its event %s is in the log" % [entry["claim"], entry["event_id"]])
		eq(str(source.get("event_id", "")), str(entry["event_id"]), "%s: and that is the event it names" % entry["claim"])

func test_an_open_question_stays_visible_and_is_untestable_whatever_its_sidecar_says() -> void:
	var r := _played()
	r.engine.record_observation("player", "bell", {"signature": ["PUZZLE"]}, {}, [], [{"id": "q.open_bell", "holder_id": "player", "proposition": {"open": "bell"}, "status": S.UNRESOLVED_BY_DESIGN, "scope": "room"}])
	var claims := {"q.open_bell": {"kind": NotebookView.SEEN, "text": "note.test.open"}}
	var found: Array = NotebookView.entries(r.engine, {}, claims).filter(func(e: Dictionary) -> bool: return e["claim"] == "q.open_bell")
	eq(found.size(), 1, "the open question is in the notebook")
	eq(str(found[0]["kind"]), NotebookView.UNTESTABLE, "untestable, though the sidecar says seen")
	eq(str(found[0]["text"]), "note.test.open", "and it carries its note key")

func test_seen_told_guessed_and_open_are_told_apart() -> void:
	eq(NotebookView.kind_of({"status": S.SUPPORTED, "source": "hearsay", "evidence": []}), NotebookView.TOLD, "hearsay is heard")
	eq(NotebookView.kind_of({"status": S.ESTABLISHED, "source": "authored", "evidence": ["e1"]}), NotebookView.SEEN, "established on evidence is seen")
	eq(NotebookView.kind_of({"status": S.POSSIBLE, "source": "authored", "evidence": []}), NotebookView.GUESSED, "a possibility is inferred")
	eq(NotebookView.kind_of({"status": S.UNRESOLVED_BY_DESIGN, "source": "hearsay", "evidence": []}), NotebookView.OPEN, "an open question wins over its source")

func test_an_authored_kind_wins_over_the_derived_one_except_for_open_questions() -> void:
	eq(NotebookView.kind_of({"status": S.POSSIBLE, "source": "authored", "evidence": []}, NotebookView.PREDICTED), NotebookView.PREDICTED, "the sidecar's predicted stands")
	eq(NotebookView.kind_of({"status": S.UNRESOLVED_BY_DESIGN, "source": "authored", "evidence": []}, NotebookView.SHOWN), NotebookView.UNTESTABLE, "but not for an open question")
	eq(NotebookView.kind_of({"status": S.POSSIBLE, "source": "authored", "evidence": []}, "guessed"), NotebookView.INFERRED, "an unknown authored word is not a kind: the derived one applies")

func test_the_notebook_interleaves_discovery_classes_so_neighbours_differ() -> void:
	var r := _played()
	var claims := _sidecar(r)
	var ids: Array = []
	for entry in NotebookView.entries(r.engine, {}, claims):
		ids.append(entry["claim"])
	var classes := {}
	for i in ids.size():
		classes[ids[i]] = "humour" if i % 2 == 0 else "lore"
	var ordered := NotebookView.entries(r.engine, classes, claims)
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
