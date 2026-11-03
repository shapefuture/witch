extends TestCase

# Every deferred consequence carries a cue naming the event that set it going (ALIVENESS 3, rule 5): the cue resolves
# to a real event in the log, and the log says which consequence fell due. Audio (the motif) is not built yet; the cue
# is the data a presenter needs, and it is in every result and every payload.

func test_a_consequence_names_the_knock_that_set_it_going() -> void:
	var data := MindsFixtures.raw()
	data["rules"] = [MindsFixtures.echo_rule(3, "stack")]
	var rig := MindsFixtures.rig(data)
	var knock := rig.minds.perceive(MindsFixtures.knock("door"))
	var fired: Array = rig.minds.advance_time(3)["fired"]
	eq(fired.size(), 1, "the echo fell due")
	var cue: Dictionary = fired[0]["cue"]
	eq(str(cue["origin_event"]), str(knock["event_id"]), "the cue names the knock that set it going")
	ok(rig.engine.event_store.get_by_id(str(cue["origin_event"])) != null, "and that knock is in the log")
	ok(str(cue["consequence"]) != "", "the cue says which consequence it is")

func test_every_consequence_in_the_hall_sim_names_a_cause_in_the_log() -> void:
	var runtime := MirrorRuntime.new()
	runtime.new_game()
	SimulationRunner.new().run(runtime, SimulationRunner.load_script("res://data/sim/hall_rules.json"))
	var fell_due := 0
	for event in runtime.engine.event_store.get_all():
		var origin: Dictionary = event.payload.get("origin", {})
		if not origin.has("consequence"):
			continue
		fell_due += 1
		var cause := str(origin.get("from", ""))
		ok(not cause.is_empty() and runtime.engine.event_store.get_by_id(cause) != null, "%s names its cause in the log" % event.event_id)
	ok(fell_due > 0, "the hall sim does let consequences fall due (%d)" % fell_due)
	runtime.free()
