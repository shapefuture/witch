extends TestCase

# Convention clocks (TONE_MAPPING section 4, rule 1): a clocked custom that nobody feeds for its dormancy fades,
# and one that was in force may come back once, at the next matching reading, with no origin replayed. Once its
# revival is spent it stays faded. Every step is an event in the log, so a replay reproduces it exactly.

const S := MirrorDomain.EpistemicStatus
const CONVENTION := "conv.t.door_is_a_game"
const DORMANCY := 40

func _data() -> Dictionary:
	var data := MindsFixtures.raw()
	var convention := MindsFixtures.door_convention()
	convention["cadence"] = "sprint"
	# Slow decay: the clock, not the decay, is what fades the custom in these tests.
	convention["decay"] = {"every": 1000, "amount": 1}
	data["conventions"] = [convention]
	data["clocks"] = {"cadences": {"sprint": {"dormancy": DORMANCY, "revivals": 1}}}
	# Ana reads a knock as a game only once she is in the mood (a belief of hers, not a flag).
	data["interpretations"].append({"id": "i.ana.game", "event_kind": "KNOCK", "holder": "ana", "priority": 30, "min_clarity": 40, "reads": "game", "perceived": {"actor_id": "$actor", "outcome": "knocked"},
		"requires_claims": [{"id": "ana_in_the_mood"}]})
	return data

func _in_the_mood(rig: MindsFixtures.Rig) -> void:
	rig.engine.record_observation("ana", "door", {"signature": ["MOOD"]}, {}, [], [{"id": "ana_in_the_mood", "holder_id": "ana", "proposition": {"mood": "playful"}, "status": S.SUPPORTED, "scope": "room"}])

func _changes(results: Array) -> Array:
	var out: Array = []
	for result in results:
		for change in result["convention_changes"]:
			out.append(change["change"])
	return out

func _dormant_fade(results: Array) -> bool:
	for result in results:
		for change in result["convention_changes"]:
			if change["change"] == "forgotten" and str(change.get("cause", "")) == "dormant":
				return true
	return false

func _adopt(rig: MindsFixtures.Rig) -> void:
	_in_the_mood(rig)
	for i in range(4):
		rig.minds.perceive(MindsFixtures.knock("door"))
	ok(rig.minds.is_convention_active(CONVENTION), "adopted: a sprint custom, in force")

func test_a_clocked_custom_fades_once_nobody_has_fed_it_for_its_dormancy() -> void:
	var rig := MindsFixtures.rig(_data())
	_adopt(rig)
	rig.minds.advance_time(DORMANCY - 10)
	ok(not _dormant_fade([rig.minds.perceive(MindsFixtures.knock("bell"))]), "still within its dormancy: no fade")
	ok(rig.minds.is_convention_active(CONVENTION), "still in force")
	rig.minds.advance_time(20)
	var results := [rig.minds.perceive(MindsFixtures.knock("bell"))]
	ok(_dormant_fade(results), "past its dormancy the next event lets it fade, with the cause named")
	ok(not rig.minds.is_convention_active(CONVENTION), "no longer in force")
	ok(not ("adopted" in _changes(results)), "a fade never announces an adoption")

func test_a_faded_custom_comes_back_once_at_a_matching_reading_and_its_origin_is_not_replayed() -> void:
	var rig := MindsFixtures.rig(_data())
	_adopt(rig)
	var origins_before: Array = rig.minds.convention_state(CONVENTION)["origin_events"].duplicate()
	rig.minds.advance_time(DORMANCY + 20)
	rig.minds.perceive(MindsFixtures.knock("bell"))
	var results := [rig.minds.perceive(MindsFixtures.knock("door"))]
	var changes := _changes(results)
	ok("revived" in changes, "a matching reading brings it back")
	var revival: Dictionary = {}
	for change in results[0]["convention_changes"]:
		if change["change"] == "revived":
			revival = change
	eq(revival.keys().size(), 2, "the revival carries only its id and its kind: no text, so nothing explains it (TONE 4.2)")
	ok(not ("adopted" in changes), "and says nothing that explains it: no adoption is announced again")
	ok(rig.minds.is_convention_active(CONVENTION), "in force again")
	eq(rig.minds.convention_state(CONVENTION)["origin_events"], origins_before, "its origin events are kept, not re-announced")
	eq(int(rig.minds.convention_state(CONVENTION)["revivals"]), 1, "one revival is spent")

func test_once_its_revival_is_spent_a_second_lapse_leaves_it_faded_for_good() -> void:
	var rig := MindsFixtures.rig(_data())
	_adopt(rig)
	rig.minds.advance_time(DORMANCY + 20)
	rig.minds.perceive(MindsFixtures.knock("bell"))
	rig.minds.perceive(MindsFixtures.knock("door"))
	rig.minds.advance_time(DORMANCY + 20)
	ok(_dormant_fade([rig.minds.perceive(MindsFixtures.knock("bell"))]), "the second lapse fades it again")
	var results := [rig.minds.perceive(MindsFixtures.knock("door"))]
	ok(not ("revived" in _changes(results)), "no third life: the spent revival is not granted again")
	ok(not rig.minds.is_convention_active(CONVENTION), "it stays faded")

func test_replaying_the_log_reproduces_the_fade_and_the_revival() -> void:
	var rig := MindsFixtures.rig(_data())
	_adopt(rig)
	rig.minds.advance_time(DORMANCY + 20)
	rig.minds.perceive(MindsFixtures.knock("bell"))
	rig.minds.perceive(MindsFixtures.knock("door"))
	var live := rig.minds.convention_state(CONVENTION).duplicate(true)
	var live_projection := MirrorHash.canonical_json(rig.engine.projection_snapshot())
	ok(rig.engine.replay_all()["ok"], "replay")
	rig.minds.rebuild()
	eq(rig.minds.convention_state(CONVENTION), live, "the folklore book is rebuilt from the log exactly")
	eq(MirrorHash.canonical_json(rig.engine.projection_snapshot()), live_projection, "and so is every projection")

func test_the_four_laws_linter_checks_the_clock_fields() -> void:
	var data := _data()
	var convention: Dictionary = data["conventions"][0]
	convention["cadence"] = "fortnight"
	var codes := _codes(FourLawsLinter.lint(MindsCatalog.build(data.duplicate(true))["data"]))
	ok("unknown_cadence" in codes, "a cadence minds.json does not define is an error")
	convention["cadence"] = "sprint"
	convention["revivals"] = 3
	codes = _codes(FourLawsLinter.lint(MindsCatalog.build(data.duplicate(true))["data"]))
	ok("revivals_over_limit" in codes, "more revivals than the engine allows is an error")
	convention["revivals"] = 1
	data["clocks"] = {"cadences": {"sprint": {"dormancy": 0, "revivals": 1}}}
	codes = _codes(FourLawsLinter.lint(MindsCatalog.build(data.duplicate(true))["data"]))
	ok("clock_without_dormancy" in codes, "a clock that never runs out is an error")

func _codes(findings: Array) -> Array:
	var out: Array = []
	for finding in findings:
		out.append(str(finding["code"]))
	return out
