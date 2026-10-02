extends TestCase

# Deferred consequences: a queue consumed by the Mirror clock, in a deterministic order, derived from the
# event log (so it survives save/load and replay) and outside the catalog fingerprint.

func _rig(delay: int = 3, policy: String = "replace") -> MindsFixtures.Rig:
	var data := MindsFixtures.raw()
	data["rules"] = [MindsFixtures.echo_rule(delay, policy)]
	return MindsFixtures.rig(data)

func _fired_summary(results: Array) -> Array:
	var out: Array = []
	for result in results:
		out.append("%s:%s@%d" % [result["kind"], result["subject"], int(result["time"])])
	return out

func test_a_trigger_schedules_a_consequence_with_a_due_time_and_an_origin() -> void:
	var rig := _rig()
	var result := rig.minds.perceive(MindsFixtures.knock())
	eq(result["scheduled"], ["c1"], "one consequence scheduled")
	var pending := rig.minds.pending()
	eq(pending.size(), 1, "pending")
	eq(int(pending[0]["due"]), 3, "due is now (0) plus the delay")
	eq(pending[0]["event"]["subject"], "bell", "what will happen")
	eq(pending[0]["event"]["data"]["reaction"], "hop", "the move is copied from the poke: same kind of answer")
	eq(pending[0]["origin"]["variant"], "t.door_bell", "and why: the variant that scheduled it")

func test_nothing_happens_before_it_is_due_and_it_happens_when_it_is() -> void:
	var rig := _rig()
	rig.minds.perceive(MindsFixtures.knock())
	var early := rig.minds.advance_time(2)
	eq(early["fired"].size(), 0, "not yet")
	eq(rig.minds.pending().size(), 1, "still pending")
	var due := rig.minds.advance_time(1)
	eq(_fired_summary(due["fired"]), ["ECHO:bell@3"], "now")
	eq(rig.minds.pending().size(), 0, "consumed")
	ok(rig.engine.knowledge.has("echo.door", "player"), "and the witch, who was there, saw it: evidence at the consequence")

func test_consequences_fall_due_in_due_then_id_order() -> void:
	var data := MindsFixtures.raw()
	var rule := MindsFixtures.echo_rule(5, "stack")
	rule["variants"].append({
		"id": "t.bell_second", "domain": "physical", "form": "direct", "source": "bell",
		"relation": {"id": "answers_later", "polarity": "+", "bindings": {"q": "bell", "a": "door"}},
		"trigger": {"event_kind": "KNOCK", "subject": "bell"},
		"transformation": {"schedule": [{"delay": 2, "event": {"kind": "ECHO", "actor": "world", "subject": "door", "data": {"reaction": "$reaction", "answers": "$subject"}}}]},
		"evidence": {"holders": ["player"], "at": "consequence"},
	})
	data["rules"] = [rule]
	var rig := MindsFixtures.rig(data)
	rig.minds.perceive(MindsFixtures.knock("door"))
	rig.minds.perceive(MindsFixtures.knock("bell"))
	rig.minds.perceive(MindsFixtures.knock("door"))
	var summary := _fired_summary(rig.minds.advance_time(10)["fired"])
	eq(summary, ["ECHO:door@2", "ECHO:bell@5", "ECHO:bell@5"], "earliest first; ties in the order they were scheduled")

func test_advancing_time_in_one_step_or_many_fires_the_same_things_in_the_same_order() -> void:
	var whole := _rig()
	var chunked := _rig()
	for rig in [whole, chunked]:
		rig.minds.perceive(MindsFixtures.knock("door"))
	var once := _fired_summary(whole.minds.advance_time(10)["fired"])
	var many: Array = []
	for i in range(10):
		many.append_array(_fired_summary(chunked.minds.advance_time(1)["fired"]))
	eq(many, once, "chunking time does not change what happens or when")
	eq(chunked.engine.get_time(), whole.engine.get_time(), "and both clocks agree")

func test_an_action_that_costs_time_pumps_the_queue_too() -> void:
	var data := MindsFixtures.raw()
	data["rules"] = [MindsFixtures.echo_rule(3)]
	var engine := MirrorFixtures.engine()
	var rig := MindsFixtures.rig(data, engine)
	rig.minds.perceive(MindsFixtures.knock())
	var waited := engine.resolve_action(MirrorFixtures.act("wait", "", MirrorDomain.ActionType.WAIT))
	ok(waited["ok"], "the player waits (an ordinary action with a time cost of 8)")
	eq(rig.minds.pending().size(), 0, "the world did its thing while she waited")
	eq(_fired_summary(rig.minds.take_fired()), ["ECHO:bell@3"], "and the result is there for whoever presents it")
	eq(rig.minds.take_fired().size(), 0, "read once")

func test_a_pending_entry_with_the_same_key_is_replaced() -> void:
	var rig := _rig(3, "replace")
	rig.minds.perceive(MindsFixtures.knock("door", "player", {}, "hop"))
	var second := rig.minds.perceive(MindsFixtures.knock("door", "player", {}, "spin"))
	eq(second["cancelled"], ["c1"], "the first answer is forgotten")
	var pending := rig.minds.pending()
	eq(pending.size(), 1, "one answer pending")
	eq(pending[0]["event"]["data"]["reaction"], "spin", "the latest")

func test_skip_keeps_the_first_and_stack_keeps_both() -> void:
	var skip := _rig(3, "skip")
	skip.minds.perceive(MindsFixtures.knock("door", "player", {}, "hop"))
	var second := skip.minds.perceive(MindsFixtures.knock("door", "player", {}, "spin"))
	eq(second["dropped"][0]["why"], "already_pending", "the second is dropped, and says why")
	eq(skip.minds.pending()[0]["event"]["data"]["reaction"], "hop", "the first stands")
	var stack := _rig(3, "stack")
	stack.minds.perceive(MindsFixtures.knock())
	stack.minds.perceive(MindsFixtures.knock())
	eq(stack.minds.pending().size(), 2, "stacked")

func test_a_condition_checked_at_the_time_can_cancel_a_consequence() -> void:
	var data := MindsFixtures.raw()
	var rule := MindsFixtures.echo_rule(3)
	rule["variants"][0]["transformation"]["schedule"][0]["when"] = {"world.bell_taken": false}
	data["rules"] = [rule]
	var engine := MirrorEngine.new()
	engine.set_world("world", {"bell_taken": false})
	var rig := MindsFixtures.rig(data, engine)
	rig.minds.perceive(MindsFixtures.knock())
	engine.world_state["world"] = {"bell_taken": true}
	var fired: Array = rig.minds.advance_time(3)["fired"]
	eq(fired[0]["kind"], "consequence.fizzled", "the bell was taken: nothing to answer with")
	eq(rig.minds.pending().size(), 0, "and the entry is gone")

func test_a_consequence_whose_kind_has_left_the_data_is_dropped_on_record_not_retried_forever() -> void:
	var rig := _rig()
	rig.minds.perceive(MindsFixtures.knock())
	rig.minds.data["event_kinds"].erase("ECHO")
	var fired: Array = rig.minds.advance_time(3)["fired"]
	eq(fired[0]["kind"], "consequence.fizzled", "recorded as fizzled")
	eq(rig.minds.pending().size(), 0, "and gone from the queue")

func test_the_queue_is_bounded_and_so_is_a_chain_of_consequences() -> void:
	var data := MindsFixtures.raw()
	var rule := MindsFixtures.echo_rule(1, "stack")
	rule["variants"][0]["trigger"] = {"event_kind": ["KNOCK", "ECHO"], "subject": ["door", "bell"]}
	rule["variants"][0]["transformation"]["schedule"][0]["event"]["subject"] = "bell"
	data["rules"] = [rule]
	var rig := MindsFixtures.rig(data)
	rig.minds.perceive(MindsFixtures.knock())
	var fired: Array = rig.minds.advance_time(20)["fired"]
	eq(fired.size(), 3, "a consequence of a consequence of a consequence, then it stops (max_chain_depth 3)")
	var last: Dictionary = fired[fired.size() - 1]
	eq(last["dropped"][0]["why"], "chain_depth", "and the cut-off is recorded, not silent")
	var full := _rig(50, "stack")
	var dropped := 0
	for i in range(12):
		var result := full.minds.perceive(MindsFixtures.knock())
		dropped += result["dropped"].size()
	eq(full.minds.pending().size(), 8, "the queue holds at most max_pending entries")
	eq(dropped, 4, "the rest were dropped, each one recorded")

# ---- persistence ---------------------------------------------------------------------------------------

func test_the_queue_survives_save_and_load_and_the_run_continues_identically() -> void:
	var live := _rig()
	live.minds.perceive(MindsFixtures.knock())
	live.minds.advance_time(1)
	var json := live.engine.save_json()
	var loaded := _rig()
	var res := loaded.engine.load_json(json)
	ok(res.get("ok", false), "load: %s" % JSON.stringify(res))
	eq(MirrorHash.canonical_json(loaded.minds.pending()), MirrorHash.canonical_json(live.minds.pending()), "the pending queue is exactly what it was, rebuilt from the log")
	var a := live.minds.advance_time(5)
	var b := loaded.minds.advance_time(5)
	eq(_fired_summary(a["fired"]), _fired_summary(b["fired"]), "it fires the same things")
	eq(loaded.engine.event_store.head_hash(), live.engine.event_store.head_hash(), "and writes the identical history")

func test_replaying_the_log_reproduces_the_projection_and_the_queue() -> void:
	var rig := _rig()
	rig.minds.perceive(MindsFixtures.knock())
	rig.minds.perceive(MindsFixtures.knock())
	rig.minds.advance_time(1)
	var live := MirrorHash.canonical_json(rig.engine.projection_snapshot())
	var pending_before := rig.minds.pending()
	ok(rig.engine.replay_all()["ok"], "replay")
	eq(MirrorHash.canonical_json(rig.engine.projection_snapshot()), live, "every engine projection is reproduced from the log, witness beliefs included")
	rig.minds.rebuild()
	eq(rig.minds.pending(), pending_before, "and so is the queue")

func test_scheduling_and_firing_never_touch_the_catalog_fingerprint() -> void:
	var rig := _rig()
	var before := rig.engine.compute_catalog_fingerprint()
	rig.minds.perceive(MindsFixtures.knock())
	rig.minds.advance_time(5)
	eq(rig.engine.compute_catalog_fingerprint(), before, "the fingerprint a save is bound to is unchanged by the queue")
	eq(rig.engine.catalog_fingerprint, before, "the locked fingerprint too")
	for event in rig.engine.event_store.get_all():
		eq(event.catalog_fingerprint, before, "every event, including consequences, carries it")

func test_the_same_inputs_always_write_the_same_history() -> void:
	var heads: Array = []
	for i in range(2):
		var rig := _rig()
		rig.minds.perceive(MindsFixtures.knock("door", "player", {"attention": {"ana": "busy"}, "distance": {"bo": 3.0}}))
		rig.minds.perceive(MindsFixtures.knock("bell"))
		rig.minds.advance_time(4)
		heads.append(rig.engine.event_store.head_hash())
	eq(heads[0], heads[1], "no randomness anywhere: two runs, one chain")

func test_a_previewed_action_leaves_the_minds_consistent() -> void:
	var data := MindsFixtures.raw()
	data["rules"] = [MindsFixtures.echo_rule(3)]
	var engine := MirrorFixtures.engine()
	var rig := MindsFixtures.rig(data, engine)
	rig.minds.perceive(MindsFixtures.knock())
	var preview := engine.preview_action(MirrorFixtures.act("wait", "", MirrorDomain.ActionType.WAIT))
	ok(preview["ok"], "a speculative wait")
	eq(rig.minds.pending().size(), 1, "it fired nothing: speculation is not history")
	eq(engine.get_time(), 0, "the clock did not move")
