extends TestCase

# Folklore: repeated readings of the same kind can become a convention, bounded (threshold, minimum holders,
# cap, decay), recorded with their origin events, and acting as a causal force. share_claim is separate and
# stays word for word.

const S := MirrorDomain.EpistemicStatus
const CONVENTION := "conv.t.door_is_a_game"

func _data(extra_force: Dictionary = {}) -> Dictionary:
	var data := MindsFixtures.raw()
	data["conventions"] = [MindsFixtures.door_convention(extra_force)]
	# Ana reads a knock as a game only once she is in the mood (a belief of hers, not a flag).
	data["interpretations"].append({"id": "i.ana.game", "event_kind": "KNOCK", "holder": "ana", "priority": 30, "min_clarity": 40, "reads": "game", "perceived": {"actor_id": "$actor", "outcome": "knocked"},
		"requires_claims": [{"id": "ana_in_the_mood"}]})
	return data

func _in_the_mood(rig: MindsFixtures.Rig) -> void:
	rig.engine.record_observation("ana", "door", {"signature": ["MOOD"]}, {}, [], [{"id": "ana_in_the_mood", "holder_id": "ana", "proposition": {"mood": "playful"}, "status": S.SUPPORTED, "scope": "room"}])

func _knock(rig: MindsFixtures.Rig, times: int, subject: String = "door") -> Array:
	var out: Array = []
	for i in range(times):
		out.append(rig.minds.perceive(MindsFixtures.knock(subject)))
	return out

func _changes(results: Array) -> Array:
	var out: Array = []
	for result in results:
		for change in result["convention_changes"]:
			out.append(change["change"])
	return out

func test_one_mind_repeating_a_reading_never_makes_a_custom() -> void:
	var rig := MindsFixtures.rig(_data())
	var results := _knock(rig, 5)
	eq(_changes(results), ["stalled"], "Bo alone reads it as a game: the convention stalls, once, and says so")
	ok(not rig.minds.is_convention_active(CONVENTION), "no custom: a custom needs more than one mind")
	eq(int(rig.minds.convention_state(CONVENTION)["tally"]), 5, "the tally still counts")

func test_two_minds_reading_alike_enough_times_adopt_it_and_the_members_learn_it() -> void:
	var rig := MindsFixtures.rig(_data())
	_in_the_mood(rig)
	var results := _knock(rig, 3)
	eq(_changes(results), ["adopted"], "adopted on the third shared reading, not before")
	ok(rig.minds.is_convention_active(CONVENTION), "active")
	for member in ["ana", "bo"]:
		eq(int(rig.engine.knowledge.get_claim(CONVENTION, member)["status"]), int(S.ESTABLISHED), "%s knows the custom" % member)
	ok(not rig.engine.knowledge.has(CONVENTION, "player"), "the witch is an outsider: she has to work it out")
	ok(not rig.engine.knowledge.has(CONVENTION, "cat"), "so is the cat")

func test_origin_events_are_recorded_real_and_bounded() -> void:
	var rig := MindsFixtures.rig(_data())
	_in_the_mood(rig)
	_knock(rig, 5)
	var origins: Array = rig.minds.convention_state(CONVENTION)["origin_events"]
	eq(origins.size(), 3, "only the first max_origin_events (3) are kept")
	for id in origins:
		var event := rig.engine.event_store.get_by_id(str(id))
		ok(event != null and event.event_type == "WorldEventHappened" and event.payload["kind"] == "KNOCK", "%s is a real KNOCK in the log" % id)

func test_the_tally_is_capped() -> void:
	var rig := MindsFixtures.rig(_data())
	_in_the_mood(rig)
	_knock(rig, 9)
	eq(int(rig.minds.convention_state(CONVENTION)["tally"]), 5, "a custom does not grow without bound")

func test_a_custom_nobody_feeds_decays_and_retires() -> void:
	var rig := MindsFixtures.rig(_data())
	_in_the_mood(rig)
	_knock(rig, 4)
	ok(rig.minds.is_convention_active(CONVENTION), "adopted")
	var definition: Dictionary = rig.minds.data["conventions"][0]
	rig.minds.advance_time(40)
	eq(rig.minds.state.conventions.effective_tally(definition, rig.engine.get_time()), 2, "forty quiet ticks cost two points (one per 20)")
	ok(rig.minds.is_convention_active(CONVENTION), "still a custom")
	rig.minds.advance_time(100)
	var result := rig.minds.perceive(MindsFixtures.knock("bell"))
	ok("retired" in _changes([result]), "the next thing that happens notices it has lapsed")
	ok(not rig.minds.is_convention_active(CONVENTION), "no longer a custom")
	eq(int(rig.engine.knowledge.get_claim(CONVENTION, "ana")["status"]), int(S.CONTESTED), "and its members only half remember it")

func test_a_lapsed_custom_can_form_again() -> void:
	var rig := MindsFixtures.rig(_data())
	_in_the_mood(rig)
	_knock(rig, 4)
	rig.minds.advance_time(200)
	rig.minds.perceive(MindsFixtures.knock("bell"))
	ok(not rig.minds.is_convention_active(CONVENTION), "lapsed")
	var again := _knock(rig, 3)
	ok("adopted" in _changes(again), "fed again by two minds, it forms again")

func test_the_number_of_live_customs_is_capped() -> void:
	var data := _data()
	data["limits"]["max_active_conventions"] = 1
	var second := MindsFixtures.door_convention()
	second["id"] = "conv.t.bell_is_a_game"
	second["subjects"] = ["bell"]
	data["conventions"].append(second)
	var rig := MindsFixtures.rig(data)
	_in_the_mood(rig)
	_knock(rig, 3)
	var changes := _changes(_knock(rig, 3, "bell"))
	ok("capped" in changes, "a second custom is refused when the hall already holds its limit")
	ok(not rig.minds.is_convention_active("conv.t.bell_is_a_game"), "and does not form")

func test_a_convention_can_enable_and_a_lapse_can_revoke_an_operator() -> void:
	var engine := MirrorEngine.new()
	engine.register_operator({"id": "op.t.play"})
	var rig := MindsFixtures.rig(_data({"enables_operators": ["op.t.play"]}), engine)
	_in_the_mood(rig)
	ok(not engine.operators.has("op.t.play", "ana"), "not yet")
	_knock(rig, 3)
	ok(engine.operators.has("op.t.play", "ana") and engine.operators.has("op.t.play", "bo"), "adoption grants the operator to its members: folklore as a causal force")
	ok(not engine.operators.has("op.t.play", "player"), "and only to them")
	rig.minds.advance_time(200)
	rig.minds.perceive(MindsFixtures.knock("bell"))
	ok(not engine.operators.has("op.t.play", "ana"), "when the custom lapses the operator goes with it")

func test_a_convention_alters_what_a_world_rule_does() -> void:
	var data := _data()
	var rule := MindsFixtures.echo_rule(3)
	rule["variants"][0]["conventions"] = {CONVENTION: {"patch": {"set": {"schedule.0.delay": 1, "schedule.0.event.data.reaction": "spin"}}}}
	data["rules"] = [rule]
	var rig := MindsFixtures.rig(data)
	_in_the_mood(rig)
	var before := rig.minds.perceive(MindsFixtures.knock())
	var pending_before: Array = rig.minds.pending()
	eq(int(pending_before[0]["due"]) - int(before["time"]), 3, "before the custom: the bell answers after 3, in kind")
	_knock(rig, 2)
	var after := rig.minds.perceive(MindsFixtures.knock())
	ok(rig.minds.is_convention_active(CONVENTION), "the custom is in force")
	var latest: Dictionary = rig.minds.pending()[rig.minds.pending().size() - 1]
	eq(int(latest["due"]) - int(after["time"]), 1, "afterwards it answers at once")
	eq(latest["event"]["data"]["reaction"], "spin", "and with a different move: the same rule, altered by folklore")

func test_a_variant_can_exist_only_while_a_convention_does() -> void:
	var data := _data()
	data["rules"] = [{
		"id": "rule.t.custom", "label_key": "x", "domain": "cultural", "learnable": true,
		"invariant": {"relation": "custom_acts", "polarity": "+", "roles": ["c"], "constraints": {}},
		"variants": [{"id": "t.custom_acts", "domain": "physical", "form": "direct", "source": "door", "relation": {"id": "custom_acts", "polarity": "+", "bindings": {"c": "door"}},
			"trigger": {"event_kind": "KNOCK", "subject": "door", "requires_convention": CONVENTION},
			"transformation": {"reactions": [{"op": "PROP_REACT", "target": "door", "reaction": "hop"}]}}],
	}]
	var rig := MindsFixtures.rig(data)
	_in_the_mood(rig)
	eq(rig.minds.perceive(MindsFixtures.knock())["reactions"].size(), 0, "no custom, no behaviour")
	_knock(rig, 2)
	eq(rig.minds.perceive(MindsFixtures.knock())["reactions"].size(), 1, "with the custom in force the door behaves by it")

func test_share_claim_stays_word_for_word_and_is_not_how_conventions_form() -> void:
	var rig := MindsFixtures.rig(_data())
	rig.minds.perceive(MindsFixtures.knock())
	var before := rig.minds.convention_state(CONVENTION)
	var said := rig.engine.knowledge.get_claim("ana_saw.door", "ana")
	var shared := rig.engine.share_claim("ana", "bo", "ana_saw.door")
	ok(shared["ok"], "Ana tells Bo what she saw")
	var heard := rig.engine.knowledge.get_claim("ana_saw.door", "bo")
	eq(heard["proposition"], said["proposition"], "Bo holds exactly what Ana said, word for word")
	eq(int(heard["status"]), int(S.POSSIBLE), "as hearsay")
	eq(heard["source"], "hearsay", "marked so")
	eq(MirrorHash.canonical_json(rig.minds.convention_state(CONVENTION)), MirrorHash.canonical_json(before), "and telling someone something does not touch the folklore")
	rig.minds.perceive(MindsFixtures.knock())
	eq(rig.engine.knowledge.get_claim("ana_saw.door", "bo")["proposition"], said["proposition"], "nor does a convention rewrite a claim already passed on")
