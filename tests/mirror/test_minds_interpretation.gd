extends TestCase

# Per-holder interpretation: the same event is read differently by different minds, according to what each
# believes, how each stands with the actor, each one's stance, and how clearly each perceived it. A reading
# may be wrong, and a wrong one is recorded as such.

const S := MirrorDomain.EpistemicStatus
const K := MirrorDomain.DiscrepancyKind

func _reads(result: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for reading in result["interpretations"]:
		out[reading["holder"]] = reading["reads"]
	return out

func test_the_same_event_is_read_differently_by_different_holders() -> void:
	var rig := MindsFixtures.rig()
	var reads := _reads(rig.minds.perceive(MindsFixtures.knock()))
	eq(reads["ana"], "rude", "Ana takes a knock for rudeness")
	eq(reads["bo"], "game", "Bo takes the same knock for a game")
	eq(reads["player"], "noticed", "no authored reading: merely noticed")
	ok(rig.engine.knowledge.has("ana_saw.door", "ana") and rig.engine.knowledge.has("bo_saw.door", "bo"), "each learned their own version")
	eq(rig.engine.knowledge.get_claim("ana_saw.door", "ana")["proposition"], {"rude": "player"}, "Ana's claim is hers")
	eq(rig.engine.knowledge.get_claim("bo_saw.door", "bo")["proposition"], {"game": "player"}, "Bo's claim is his")
	ok(not rig.engine.knowledge.has("ana_saw.door", "bo"), "claims are holder-scoped: Bo does not hold Ana's")

func test_a_holders_stance_changes_the_reading() -> void:
	var engine := MirrorEngine.new()
	engine.set_npc_state("bo", {"stance": "grim"})
	var rig := MindsFixtures.rig({}, engine)
	eq(_reads(rig.minds.perceive(MindsFixtures.knock()))["bo"], "serious", "a grim Bo reads it as serious (stance in npc state)")
	var calm := MindsFixtures.rig()
	eq(_reads(calm.minds.perceive(MindsFixtures.knock()))["bo"], "game", "a calm one does not")

func test_a_holders_beliefs_change_the_reading() -> void:
	var data := MindsFixtures.raw()
	data["interpretations"].append({"id": "i.ana.knows_better", "event_kind": "KNOCK", "holder": "ana", "priority": 30, "min_clarity": 40, "reads": "code",
		"requires_claims": [{"id": "ana_knows_the_code", "min_status": "SUPPORTED"}]})
	data["initial_beliefs"] = []
	var rig := MindsFixtures.rig(data)
	eq(_reads(rig.minds.perceive(MindsFixtures.knock()))["ana"], "rude", "without the belief: rude")
	rig.engine.record_observation("ana", "door", {"signature": ["TOLD"]}, {}, [], [{"id": "ana_knows_the_code", "holder_id": "ana", "proposition": {"code": "knock_twice"}, "status": S.SUPPORTED, "scope": "room"}])
	eq(_reads(rig.minds.perceive(MindsFixtures.knock()))["ana"], "code", "once she believes it, the knock means something else to her")

func test_a_holders_models_change_the_reading() -> void:
	var data := MindsFixtures.raw()
	data["initial_beliefs"] = [{"holder": "bo", "model_effects": [{"type": "upsert", "rule_id": "m.bo.trusts", "subject_id": "player", "proposition": {"trusts": "witch"}, "scope": "room", "confidence": 0.3, "status": "HYPOTHESIS"}]}]
	data["interpretations"].append({"id": "i.bo.trusting", "event_kind": "KNOCK", "holder": "bo", "priority": 30, "min_clarity": 40, "reads": "friendly", "requires_models": [{"id": "m.bo.trusts", "min_confidence": 0.5}]})
	var rig := MindsFixtures.rig(data)
	eq(_reads(rig.minds.perceive(MindsFixtures.knock()))["bo"], "game", "a doubtful Bo: just a game")
	ok(rig.engine.models.support("m.bo.trusts", "test", 0.3, "bo"), "his trust grows")
	eq(_reads(rig.minds.perceive(MindsFixtures.knock()))["bo"], "friendly", "a trusting Bo reads the same knock as friendly: models are per observer")

func test_a_relationship_changes_the_reading() -> void:
	var data := MindsFixtures.raw()
	data["interpretations"].append({"id": "i.ana.grudge", "event_kind": "KNOCK", "holder": "ana", "priority": 30, "min_clarity": 40, "reads": "provocation",
		"when": {"$contains": {"relation.interpretations": "grudge"}}})
	data["interpretations"].append({"id": "i.ana.records_a_grudge", "event_kind": "ECHO", "holder": "ana", "priority": 1, "min_clarity": 40,
		"relationship_effects": [{"b": "player", "tags": ["NOTE"], "payload": {"interpretation": "grudge"}}]})
	var rig := MindsFixtures.rig(data)
	eq(_reads(rig.minds.perceive(MindsFixtures.knock()))["ana"], "rude", "no history between them: rude")
	rig.minds.perceive({"kind": "ECHO", "actor": "world", "subject": "bell"})
	eq(rig.engine.relationships.get_relation("ana", "player")["interpretations"].size(), 1, "her reading of the witch was recorded as a relationship fact")
	eq(_reads(rig.minds.perceive(MindsFixtures.knock()))["ana"], "provocation", "with that history, the same knock is a provocation")

func test_clarity_selects_the_reading() -> void:
	var rig := MindsFixtures.rig()
	var result := rig.minds.perceive(MindsFixtures.knock())
	eq(_reads(result)["cat"], "noise", "heard through a wall: only a noise")
	var near := rig.minds.perceive(MindsFixtures.knock("door", "player", {"distance": {"ana": 9.0}}))
	var ana_clarity := -1
	for reading in near["interpretations"]:
		if reading["holder"] == "ana":
			ana_clarity = 1
	eq(ana_clarity, 1, "Ana is still a witness at the edge of sight")
	eq(_reads(near)["ana"], "rude", "and still reads it (clarity 46 clears her bar of 40)")
	var dim := rig.minds.perceive(MindsFixtures.knock("door", "player", {"distance": {"ana": 9.9}, "attention": {"ana": "busy"}}))
	eq(_reads(dim)["ana"], "noticed", "half-seen at the edge of sight she only notices: no authored reading is clear enough")

func test_a_wrong_reading_is_recorded_as_a_misreading_with_the_engines_discrepancy_kinds() -> void:
	var rig := MindsFixtures.rig()
	var result := rig.minds.perceive(MindsFixtures.knock())
	var by_holder: Dictionary = {}
	for reading in result["interpretations"]:
		by_holder[reading["holder"]] = reading
	ok(not by_holder["ana"]["misread"], "Ana got it right")
	ok(by_holder["cat"]["misread"], "the cat, next door, blames Ana: wrong")
	ok(int(K.ACTOR) in by_holder["cat"]["kinds"], "an ACTOR discrepancy, the engine's own kind")
	var accounts := rig.minds.compare_accounts(result["event_id"], "cat", "ana")
	ok(accounts["ok"], "two accounts can be compared")
	ok(not accounts["agree"], "and they disagree")
	ok(accounts["vector"]["identity"], "about who did it")

func test_accounts_that_agree_have_no_discrepancy() -> void:
	var rig := MindsFixtures.rig()
	var result := rig.minds.perceive(MindsFixtures.knock())
	var accounts := rig.minds.compare_accounts(result["event_id"], "ana", "bo")
	ok(accounts["agree"], "Ana and Bo agree on what happened (they differ only on what it meant)")
	ok(not rig.minds.compare_accounts(result["event_id"], "ana", "nobody")["ok"], "a non-witness has no account")

func test_a_misreading_persists_as_a_belief_that_can_later_be_contradicted() -> void:
	var rig := MindsFixtures.rig()
	rig.minds.perceive(MindsFixtures.knock())
	var claim := rig.engine.knowledge.get_claim("cat_heard_ana", "cat")
	eq(int(claim["status"]), int(S.POSSIBLE), "the cat believes, tentatively, that Ana knocked")
	rig.engine.knowledge.mark_contradicted("cat_heard_ana", "test", "", "cat")
	eq(int(rig.engine.knowledge.get_claim("cat_heard_ana", "cat")["status"]), int(S.CONTESTED), "and a later contradiction is an ordinary revision")

func test_a_convention_biases_interpretation_for_its_community_only() -> void:
	var data := MindsFixtures.raw()
	data["conventions"] = [{
		"id": "conv.t.knock_is_rude", "label_key": "x", "community": "house", "reads": "rude", "subjects": ["door"], "event_kinds": ["KNOCK"],
		"origin": {"event_kinds": ["KNOCK"], "fed_by": ["i.ana.rude"]}, "adopt": {"threshold": 1, "min_holders": 1}, "cap": 3,
		"decay": {"every": 0, "amount": 0}, "retire_at": 0, "force": {"bias": 20},
	}]
	data["interpretations"].append({"id": "i.bo.rude", "event_kind": "KNOCK", "holder": "bo", "priority": 5, "min_clarity": 40, "reads": "rude"})
	data["interpretations"].append({"id": "i.cat.rude", "event_kind": "KNOCK", "holder": "cat", "priority": 4, "reads": "rude", "channels": ["overheard"]})
	var rig := MindsFixtures.rig(data)
	var first := rig.minds.perceive(MindsFixtures.knock())
	eq(_reads(first)["bo"], "game", "before the custom, Bo (priority 10 against 5) reads a knock as a game")
	ok(rig.minds.is_convention_active("conv.t.knock_is_rude"), "Ana's reading alone adopted it (threshold 1)")
	var second := rig.minds.perceive(MindsFixtures.knock())
	eq(_reads(second)["bo"], "rude", "afterwards the custom tips Bo's reading: a convention is a causal force")
	eq(_reads(second)["cat"], "noise", "the cat is outside the community: the custom does not tip its reading (4 + no bias against 5)")
	eq(_reads(rig.minds.perceive(MindsFixtures.knock("bell")))["bo"], "game", "and only for the door it is about")

func test_effects_default_to_the_witness_as_holder_and_templates_resolve() -> void:
	var rig := MindsFixtures.rig()
	rig.minds.perceive(MindsFixtures.knock("bell"))
	var claim := rig.engine.knowledge.get_claim("player_saw.bell", "player")
	eq(claim["proposition"], {"saw": "bell"}, "$subject resolved")
	eq(claim["holder_id"], "player", "the claim belongs to the witness, not to the default holder")
	eq(claim["scope"], "room", "scope defaults to the place")
