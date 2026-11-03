extends TestCase

# Negative emergence: shared meaning needs evidence from two minds. For every convention in
# data/mirror/minds/conventions.json, one mind repeating the reading that feeds it, well past the adoption
# threshold, must never form it; and, as a control, two minds sharing that reading must form it, so the
# negative cannot pass merely because the setup feeds nothing.
#
# Driven through the real runtime (Mirror.minds.perceive, the authored interpretations and world rules), with
# the scenarios written as sim steps (SimulationRunner.run_step). They live here rather than in data/sim
# because every file there must have a golden transcript.

const REPEATS := 12

func _poke(subject: String, hints: Dictionary = {}) -> Dictionary:
	return {"poke": subject, "reaction": "hop", "hints": hints}

# REPEATS pokes, one tick apart (well inside every convention's decay window).
func _pokes(subject: String, setup: Array = [], hints: Dictionary = {}, times: int = REPEATS) -> Array:
	var steps: Array = setup.duplicate(true)
	for i in range(times):
		steps.append(_poke(subject, hints))
		steps.append({"advance": 1})
	return steps

# Every convention in the catalog needs an entry here; test_every_convention_has_a_negative_and_a_control
# fails otherwise. `mind` is the only member that may ever hold the feeding reading in a negative.
func _cases() -> Dictionary:
	return {
		"conv.hall.globe_is_a_toy": {
			"negatives": [
				{"name": "the raccoon alone (Tomas in the next room)", "mind": "raccoon",
					"steps": _pokes("globe", [{"presence": {"holder": "tomas", "place": "back_hall"}}])},
				{"name": "the raccoon alone (Tomas off stage)", "mind": "raccoon",
					"steps": _pokes("globe", [], {"absent": ["tomas"]})},
				{"name": "Tomas alone (the raccoon looking away)", "mind": "tomas",
					"steps": _pokes("globe", [], {"attention": {"raccoon": "away"}})},
			],
			"positive": {"steps": _pokes("globe", [], {}, 4)},
		},
		"conv.hall.statue_is_a_toy": {
			"negatives": [
				{"name": "the raccoon alone (Tomas present, reverent)", "mind": "raccoon",
					"steps": _pokes("statue")},
				{"name": "the raccoon alone (Tomas in the next room)", "mind": "raccoon",
					"steps": _pokes("statue", [{"presence": {"holder": "tomas", "place": "back_hall"}}])},
				{"name": "the raccoon alone (Tomas off stage)", "mind": "raccoon",
					"steps": _pokes("statue", [], {"absent": ["tomas"]})},
			],
			# The catalog never lets a second mind read the statue as play (that is the counterexample), so the
			# control takes away Tomas's reverence: once softened he reads it as play too, and it must form.
			"positive": {"steps": _pokes("statue", [], {}, 6), "drop_interpretations": ["interp.tomas.statue_is_revered"]},
		},
	}

func _definition(r: MirrorRuntime, id: String) -> Dictionary:
	for definition in r.minds.data["conventions"]:
		if str(definition["id"]) == id:
			return definition
	return {}

func _members(r: MirrorRuntime, definition: Dictionary) -> Array:
	return r.minds.data["communities"][str(definition["community"])]["members"]

func _run(steps: Array, drop: Array = []) -> Dictionary:
	var r := GameFixtures.runtime()
	if not drop.is_empty():
		r.minds.data["interpretations"] = r.minds.data["interpretations"].filter(func(x: Dictionary) -> bool: return str(x["id"]) not in drop)
	var results: Array = []
	for step in steps:
		results.append(SimulationRunner.run_step(r, step))
	return {"runtime": r, "results": results}

# Who, per committed poke, read it the way the convention is fed: [{holder: true}, ...] for feeding events only.
func _feeding(r: MirrorRuntime, definition: Dictionary, results: Array) -> Array:
	var out: Array = []
	var members := _members(r, definition)
	for result in _flatten(results):
		if str(result.get("kind", "")) not in definition["event_kinds"]:
			continue
		var holders: Dictionary = {}
		for reading in result.get("interpretations", []):
			if str(reading.get("holder", "")) in members and str(reading.get("reads", "")) == str(definition["reads"]) and str(reading.get("subject", result.get("subject", ""))) in definition["subjects"]:
				holders[str(reading["holder"])] = true
		if not holders.is_empty():
			out.append(holders)
	return out

# Each step's result and every consequence that fell due during it (the raccoon's own pokes, echoes).
func _flatten(results: Array) -> Array:
	var out: Array = []
	for result in results:
		out.append(result)
		out.append_array(result.get("fired", []))
	return out

func _changes(results: Array, id: String) -> Array:
	var out: Array = []
	for result in _flatten(results):
		for change in result.get("convention_changes", []):
			if str(change["id"]) == id:
				out.append(str(change["change"]))
	return out

# ---- coverage ----------------------------------------------------------------------------------------------

func test_every_convention_has_a_negative_and_a_control() -> void:
	var r := GameFixtures.runtime()
	var cases := _cases()
	ok(not r.minds.data["conventions"].is_empty(), "the catalog has conventions to test")
	for definition in r.minds.data["conventions"]:
		var id := str(definition["id"])
		ok(cases.has(id), "%s has a one-mind negative and a two-mind control in this file" % id)
		if cases.has(id):
			ok(not (cases[id]["negatives"] as Array).is_empty(), "%s: at least one negative" % id)
			ok(cases[id].has("positive"), "%s: a positive control" % id)
			ok(int(definition["adopt"]["min_holders"]) >= 2, "%s: a custom needs at least two minds (min_holders)" % id)

# ---- through the real runtime -----------------------------------------------------------------------------

func test_one_mind_repeating_a_reading_past_the_threshold_never_forms_a_convention() -> void:
	var cases := _cases()
	for id in cases.keys():
		for negative in cases[id]["negatives"]:
			var label := "%s, %s" % [id, negative["name"]]
			var run := _run(negative["steps"])
			var r: MirrorRuntime = run["runtime"]
			var results: Array = run["results"]
			var definition := _definition(r, id)
			var threshold := int(definition["adopt"]["threshold"])
			ok(results.all(func(x: Dictionary) -> bool: return x.get("ok", false)), "%s: every step committed" % label)
			var feeding := _feeding(r, definition, results)
			var minds: Dictionary = {}
			for holders in feeding:
				minds.merge(holders)
			eq(minds.keys(), [negative["mind"]], "%s: only one mind ever held the reading" % label)
			ok(feeding.size() >= 3 * threshold, "%s: fed %d times, well past the threshold of %d" % [label, feeding.size(), threshold])
			var state := r.minds.convention_state(id)
			ok(int(state["tally"]) >= threshold, "%s: the tally reached the threshold (%d)" % [label, int(state["tally"])])
			eq((state["holders"] as Dictionary).keys(), [negative["mind"]], "%s: the book counts one holder" % label)
			ok(not r.minds.is_convention_active(id), "%s: not adopted" % label)
			ok(bool(state["stalled"]) and not bool(state["adopted"]) and str(state["adopted_event"]).is_empty(), "%s: stalled, never adopted" % label)
			ok("adopted" not in _changes(results, id), "%s: no step ever announced an adoption" % label)
			for member in _members(r, definition):
				ok(not r.engine.knowledge.has(id, member), "%s: %s does not hold the custom" % [label, member])
			eq(FourLawsLinter.lint_state(r.minds), [], "%s: law 4 holds at runtime" % label)

func test_two_minds_sharing_the_reading_do_form_each_convention() -> void:
	var cases := _cases()
	for id in cases.keys():
		var positive: Dictionary = cases[id]["positive"]
		var run := _run(positive["steps"], positive.get("drop_interpretations", []))
		var r: MirrorRuntime = run["runtime"]
		var results: Array = run["results"]
		var definition := _definition(r, id)
		ok(results.all(func(x: Dictionary) -> bool: return x.get("ok", false)), "%s: every step committed" % id)
		var minds: Dictionary = {}
		for holders in _feeding(r, definition, results):
			minds.merge(holders)
		ok(minds.size() >= 2, "%s: two minds held the reading %s" % [id, minds.keys()])
		ok(r.minds.is_convention_active(id), "%s: adopted once two minds share it" % id)
		eq(_changes(results, id).count("adopted"), 1, "%s: adopted exactly once" % id)
		ok((r.minds.convention_state(id)["holders"] as Dictionary).size() >= int(definition["adopt"]["min_holders"]), "%s: the book counts both" % id)

# ---- the book itself, for every convention and every lone member -----------------------------------------

func _reading(definition: Dictionary, holder: String) -> Dictionary:
	var subjects: Array = definition.get("subjects", [])
	return {"holder": holder, "reads": str(definition["reads"]), "subject": str(subjects[0]) if not subjects.is_empty() else "", "kind": str(definition["event_kinds"][0])}

func _feed(r: MirrorRuntime, definition: Dictionary, holders_per_event: Array) -> Dictionary:
	var book := ConventionBook.new()
	var changes: Array = []
	var now := 0
	for holders in holders_per_event:
		var readings: Array = []
		for holder in holders:
			readings.append(_reading(definition, holder))
		var evaluation := ConventionBook.evaluate([definition], book, r.minds.data["communities"], readings, "e%d" % now, str(definition["event_kinds"][0]), now, definition.get("subject_tags", []), r.minds.data["limits"])
		book.apply_updates(evaluation["updates"])
		for change in evaluation["changes"]:
			changes.append(str(change["change"]))
		now += 1
	return {"book": book, "changes": changes}

func test_the_book_never_adopts_from_any_single_member_of_any_convention() -> void:
	var r := GameFixtures.runtime()
	for definition in r.minds.data["conventions"]:
		var id := str(definition["id"])
		var members := _members(r, definition)
		var times := 3 * int(definition["adopt"]["threshold"]) + int(definition["cap"])
		for member in members:
			var events: Array = []
			for i in range(times):
				events.append([member])
			var fed := _feed(r, definition, events)
			ok(not (fed["book"] as ConventionBook).is_active(id), "%s: %s alone, %d times, never forms it" % [id, member, times])
			ok("adopted" not in fed["changes"], "%s: %s alone: no adoption announced" % [id, member])
		ok(members.size() >= 2, "%s: its community has two minds to agree" % id)
		var both: Array = []
		for i in range(int(definition["adopt"]["threshold"])):
			both.append(members.slice(0, 2))
		var shared := _feed(r, definition, both)
		ok((shared["book"] as ConventionBook).is_active(id), "%s: two members sharing it %d times form it (control)" % [id, both.size()])
