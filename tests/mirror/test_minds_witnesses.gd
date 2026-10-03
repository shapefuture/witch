extends TestCase

# Witness selection: who perceives an event is a deterministic function of presence and perception hints, and
# whoever is not chosen learns nothing from it.

const T := MirrorDomain.EvidenceType

func _kind() -> Dictionary:
	return {"channels": {"sight": {"range": 10}, "sound": {"range": 8, "carries": true}}}

func _event(hints: Dictionary = {}) -> Dictionary:
	return {"kind": "KNOCK", "actor": "player", "subject": "door", "place": "room", "hints": hints}

func _around(extra: Array = []) -> Array:
	var out: Array = [{"id": "player", "place": "room"}, {"id": "ana", "place": "room"}, {"id": "bo", "place": "room"}, {"id": "cat", "place": "hall"}]
	out.append_array(extra)
	return out

func _by_holder(picked: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for witness in picked["witnesses"]:
		out[witness["holder"]] = witness
	return out

func _why(picked: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for item in picked["unaware"]:
		out[item["holder"]] = item["why"]
	return out

func test_the_room_sees_and_the_actor_always_perceives_her_own_act() -> void:
	var picked := WitnessSelector.select(_event(), _kind(), _around(), {"adjacent": ["hall"]})
	var seen := _by_holder(picked)
	eq(seen["player"]["channel"], "direct", "the actor perceives directly")
	eq(seen["ana"]["channel"], "sight", "people in the room see it")
	eq(seen["bo"]["clarity"], 100, "at no stated distance: clear")

func test_witnesses_come_in_a_fixed_order_whatever_order_the_candidates_arrive_in() -> void:
	var a := WitnessSelector.select(_event(), _kind(), _around(), {"adjacent": ["hall"]})
	var shuffled := _around()
	shuffled.reverse()
	var b := WitnessSelector.select(_event(), _kind(), shuffled, {"adjacent": ["hall"]})
	eq(MirrorHash.canonical_json(a), MirrorHash.canonical_json(b), "same inputs, same witnesses, same order")
	var ids: Array = a["witnesses"].map(func(w: Dictionary) -> String: return w["holder"])
	eq(ids, ["ana", "bo", "cat", "player"], "sorted by holder id")

func test_distance_dims_clarity_and_range_excludes() -> void:
	var picked := WitnessSelector.select(_event({"distance": {"ana": 2.0, "bo": 9.0}}), _kind(), _around(), {})
	var seen := _by_holder(picked)
	ok(int(seen["ana"]["clarity"]) > int(seen["bo"]["clarity"]), "the nearer one sees more clearly")
	var far := WitnessSelector.select(_event({"distance": {"ana": 30.0}}), _kind(), _around(), {})
	eq(_why(far)["ana"], "out_of_range", "beyond both ranges: perceives nothing")

func test_line_of_sight_blocks_sight_but_not_sound() -> void:
	var picked := WitnessSelector.select(_event({"los": {"ana": false}}), _kind(), _around(), {})
	var ana: Dictionary = _by_holder(picked)["ana"]
	eq(ana["channel"], "sound", "behind a wall she still hears it")
	var silent := WitnessSelector.select(_event({"los": {"ana": false}}), {"channels": {"sight": {"range": 10}}}, _around(), {})
	eq(_why(silent)["ana"], "no_line_of_sight", "a silent event behind a wall is not perceived at all")

func test_attention_shapes_what_is_perceived() -> void:
	var table := WitnessSelector.DEFAULT_ATTENTION
	var picked := WitnessSelector.select(_event({"attention": {"ana": "busy", "bo": "away"}}), {"channels": {"sight": {"range": 10}}}, _around(), {"attention": table})
	eq(int(_by_holder(picked)["ana"]["clarity"]), 55, "busy: half-seen")
	eq(_why(picked)["bo"], "not_attending", "looking the other way: not seen")
	var loud := WitnessSelector.select(_event({"attention": {"bo": "asleep"}}), _kind(), _around(), {"attention": table})
	ok(int(_by_holder(loud)["bo"]["clarity"]) < 100, "asleep, a loud thing is still dimly heard")

func test_the_scene_says_who_is_on_stage() -> void:
	var picked := WitnessSelector.select(_event({"present": ["player", "ana"]}), _kind(), _around(), {})
	eq(_why(picked)["bo"], "off_stage", "Mirror may place Bo in the room, but the scene does not show him: he is not part of the event")
	var excluded := WitnessSelector.select(_event({"absent": ["ana"]}), _kind(), _around(), {})
	eq(_why(excluded)["ana"], "off_stage", "and the scene can name who is out of it")

func test_a_sound_that_carries_is_overheard_next_door_and_nothing_else_is() -> void:
	var picked := WitnessSelector.select(_event(), _kind(), _around(), {"adjacent": ["hall"], "overheard_clarity": 35})
	var cat: Dictionary = _by_holder(picked)["cat"]
	eq(cat["channel"], "overheard", "next door: overheard")
	eq(cat["clarity"], 35, "faint")
	var shut := WitnessSelector.select(_event(), {"channels": {"sight": {"range": 10}, "sound": {"range": 8, "carries": false}}}, _around(), {"adjacent": ["hall"]})
	eq(_why(shut)["cat"], "absent", "a sound that does not carry stays in its room")
	var far_room := WitnessSelector.select(_event(), _kind(), _around([{"id": "owl", "place": "attic"}]), {"adjacent": ["hall"]})
	eq(_why(far_room)["owl"], "absent", "two rooms away: nothing")

# ---- through Mirror ------------------------------------------------------------------------------------

func test_a_witness_gets_a_typed_observation_and_a_non_witness_learns_nothing() -> void:
	var rig := MindsFixtures.rig()
	var result := rig.minds.perceive(MindsFixtures.knock("door", "player", {"absent": ["bo"]}))
	ok(result["ok"], "committed: %s" % JSON.stringify(result))
	in_array("ana", result["witnesses"], "Ana saw")
	not_in_array("bo", result["witnesses"], "Bo was not there")
	ok(rig.engine.knowledge.has("ana_saw.door", "ana"), "Ana learned it")
	ok(not rig.engine.knowledge.has("bo_saw.door", "bo"), "Bo learned nothing")
	var observed: Array = []
	for event in rig.engine.event_store.get_all():
		if event.event_type == "ObservationRecorded":
			observed.append(event.actor_id)
	not_in_array("bo", observed, "no observation was even recorded for Bo")
	in_array("cat", observed, "the cat next door heard it")

func test_evidence_is_typed_by_how_it_was_perceived() -> void:
	var rig := MindsFixtures.rig()
	rig.minds.perceive(MindsFixtures.knock())
	var by_holder: Dictionary = {}
	for item in rig.engine.evidence.all():
		by_holder[item["holder_id"]] = int(item["type"])
	eq(by_holder["player"], int(T.DIRECT), "her own act: direct")
	eq(by_holder["ana"], int(T.DIRECT), "seen: direct")
	eq(by_holder["cat"], int(T.AMBIGUOUS), "overheard: ambiguous")

func test_presence_is_mirrors_truth_and_changes_who_witnesses() -> void:
	var rig := MindsFixtures.rig()
	eq(rig.minds.presence_of("ana"), "room", "starts where the data puts her")
	ok(rig.minds.set_presence("ana", "hall")["ok"], "she walks next door")
	eq(rig.minds.presence_of("ana"), "hall", "and is there")
	var result := rig.minds.perceive(MindsFixtures.knock())
	var channel := ""
	for reading in result["interpretations"]:
		if reading["holder"] == "ana":
			channel = reading["channel"]
	eq(channel, "overheard", "she can only overhear it from the hall now")
	ok(not rig.engine.knowledge.has("ana_saw.door", "ana"), "and she cannot read it as someone in the room would")
	ok(not rig.minds.set_presence("nobody", "hall")["ok"], "an unknown holder is refused")
	ok(not rig.minds.set_presence("ana", "moon")["ok"], "an unknown place is refused")

func test_preview_reports_witnesses_without_committing() -> void:
	var rig := MindsFixtures.rig()
	var before := rig.engine.event_store.size()
	var picked := rig.minds.preview_witnesses(MindsFixtures.knock())
	eq(picked["witnesses"].size(), 4, "everyone would perceive it")
	eq(rig.engine.event_store.size(), before, "nothing was written")

func test_a_quiet_kind_is_written_only_when_somebody_reacts() -> void:
	var data := MindsFixtures.raw()
	var rig := MindsFixtures.rig(data)
	var before := rig.engine.event_store.size()
	var silent := rig.minds.perceive({"kind": "QUIET", "actor": "player", "subject": "door"})
	ok(silent["ok"] and not silent["recorded"], "nobody reacted: not recorded")
	eq(rig.engine.event_store.size(), before, "the log is untouched")
	data["interpretations"].append({"id": "i.ana.stirs", "event_kind": "QUIET", "holder": "ana", "knowledge_effects": [{"id": "ana_noticed", "proposition": {"x": 1}, "status": "POSSIBLE"}]})
	var loud := MindsFixtures.rig(data).minds.perceive({"kind": "QUIET", "actor": "player", "subject": "door"})
	ok(loud["recorded"], "once someone reacts to it, it is recorded")

func test_an_unknown_event_kind_is_refused_not_ignored() -> void:
	var rig := MindsFixtures.rig()
	var result := rig.minds.perceive({"kind": "NOPE", "actor": "player", "subject": "door"})
	ok(not result["ok"], "refused")
	eq(result["error"], "unknown_event_kind", "with a reason")
