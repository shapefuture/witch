extends TestCase

# Ambient routines (ALIVENESS rule 4, the engine side only; the routines themselves are content): a routine
# happens once per `every` ticks of the Mirror clock. WAIT is what makes a quiet room show them. A long wait
# writes one occurrence, the latest, never a burst, and the log says which occurrence it was.

func _data(every: int = 10) -> Dictionary:
	var data := MindsFixtures.raw()
	data["routines"] = [{"id": "routine.t.hum", "every": every, "event": {"kind": "QUIET", "actor": "world", "subject": "door"}}]
	return data

func _routine_events(rig: MindsFixtures.Rig) -> Array:
	var out: Array = []
	for event in rig.engine.event_store.get_all():
		if event.event_type == "WorldEventHappened" and (event.payload.get("origin", {}) as Dictionary).has("routine"):
			out.append(event)
	return out

func test_wait_is_what_makes_a_routine_happen() -> void:
	var rig := MindsFixtures.rig(_data(10))
	rig.minds.advance_time(9)
	eq(_routine_events(rig).size(), 0, "before its first occurrence nothing happens")
	rig.minds.advance_time(1)
	eq(_routine_events(rig).size(), 1, "at tick 10 the routine happens once")
	rig.minds.advance_time(9)
	eq(_routine_events(rig).size(), 1, "and not again before its next occurrence")

func test_a_long_wait_writes_the_latest_occurrence_once() -> void:
	var rig := MindsFixtures.rig(_data(10))
	rig.minds.advance_time(35)
	var events := _routine_events(rig)
	eq(events.size(), 1, "one event for the three occurrences that passed")
	eq(int((events[0].payload["origin"] as Dictionary)["n"]), 3, "it says which occurrence it is: the third")
	rig.minds.advance_time(5)
	eq(_routine_events(rig).size(), 2, "the next occurrence (t=40) happens when it is due")

func test_a_bad_routine_is_refused_by_the_catalog() -> void:
	var data := _data(0)
	var built := MindsCatalog.build(data)
	ok(not (built["errors"] as Array).is_empty(), "a routine with no period is an error")
	data = _data(10)
	data["routines"][0]["event"] = {"kind": "NOT_A_KIND", "actor": "world", "subject": "door"}
	built = MindsCatalog.build(data)
	ok(not (built["errors"] as Array).is_empty(), "a routine naming an event kind the catalog does not define is an error")

func test_routines_are_replayed_exactly() -> void:
	var rig := MindsFixtures.rig(_data(10))
	rig.minds.advance_time(25)
	var live := MirrorHash.canonical_json(rig.engine.projection_snapshot())
	ok(rig.engine.replay_all()["ok"], "replay")
	rig.minds.rebuild()
	eq(int(rig.minds.state.routines["routine.t.hum"]), 2, "the routine's last occurrence is rebuilt from the log")
	eq(MirrorHash.canonical_json(rig.engine.projection_snapshot()), live, "and so is every projection")
	rig.minds.advance_time(5)
	eq(_routine_events(rig).size(), 2, "after the rebuild the routine carries on from where it was, once per occurrence")
