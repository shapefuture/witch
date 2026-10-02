extends TestCase

# The hall's three world rules (data/mirror/minds), played through the real runtime: each is a stable relation
# with several independent surface manifestations, and they recombine.

const K := MirrorDomain.DiscrepancyKind

func _runtime() -> MirrorRuntime:
	return GameFixtures.runtime()

func _poke(r: MirrorRuntime, subject: String, reaction: String = "hop", hints: Dictionary = {}) -> Dictionary:
	return r.minds.perceive({"kind": "PROP_POKED", "actor": "player", "subject": subject, "data": {"reaction": reaction}, "hints": hints})

func _ops(result: Dictionary, op: String) -> Array:
	return result["reactions"].filter(func(x: Dictionary) -> bool: return x["op"] == op)

func _fired_kinds(result: Dictionary) -> Array:
	return result["fired"].map(func(x: Dictionary) -> String: return "%s:%s" % [x["kind"], x["subject"]])

# ---- the catalog -----------------------------------------------------------------------------------------

func test_the_minds_catalog_loads_clean_and_the_runtime_owns_a_minds_layer() -> void:
	var r := _runtime()
	eq(r.minds_report["errors"], [], "no errors")
	eq(r.minds_report["warnings"], [], "no warnings")
	ok(r.minds != null and r.minds.engine == r.engine, "Mirror.minds is built on the same engine")
	eq(r.minds.data["rules"].size(), 3, "three world rules")
	eq(r.minds.data["conventions"].size(), 2, "two customs that can form (one of them never will)")

func test_the_catalog_holds_ids_and_keys_never_prose_and_every_key_exists() -> void:
	var table := Localization.load_table()
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	var missing: Array[String] = []
	for file_name in DirAccess.get_files_at("res://data/mirror/minds"):
		if file_name.get_extension() != "json":
			continue
		var text := FileAccess.get_file_as_string("res://data/mirror/minds/" + file_name)
		ok(cyrillic.search(text) == null, "%s has no Russian prose" % file_name)
		for key in FourLawsLinter._text_keys(JSON.parse_string(text)):
			if not table.has(key):
				missing.append("%s: %s" % [file_name, key])
	eq(missing, [], "every text key the minds data refers to is in ru.json")

func test_the_engine_catalog_and_its_fingerprint_do_not_know_the_minds_exist() -> void:
	var r := _runtime()
	var before := r.engine.compute_catalog_fingerprint()
	var bare: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	eq(before, bare.compute_catalog_fingerprint(), "the minds data is outside the catalog every save is bound to: retuning a rule never invalidates a save")
	for step in [{"poke": "globe", "reaction": "hop"}, {"advance": 5}, {"poke": "statue", "reaction": "wobble"}, {"advance": 5}]:
		SimulationRunner.run_step(r, step)
	eq(r.engine.compute_catalog_fingerprint(), before, "and playing them does not change it")

func test_each_rule_has_independent_manifestations_in_different_domains() -> void:
	var by_rule: Dictionary = {}
	for rule in _runtime().minds.data["rules"]:
		by_rule[rule["id"]] = rule
	for rule_id in by_rule.keys():
		var sources: Array = []
		var domains: Array = []
		for variant in FourLawsLinter._manifestations(by_rule[rule_id]):
			if variant["source"] not in sources:
				sources.append(variant["source"])
			if variant["domain"] not in domains:
				domains.append(variant["domain"])
		ok(sources.size() >= 3, "%s: three independent sources %s" % [rule_id, sources])
		ok(domains.size() >= 2, "%s: at least two domains %s" % [rule_id, domains])

# ---- rule 1: the hall answers late -----------------------------------------------------------------------

func test_poking_one_prop_makes_the_other_answer_later_with_the_same_move() -> void:
	var r := _runtime()
	var poke := _poke(r, "globe", "spin")
	eq(r.minds.pending()[0]["event"]["subject"], "statue", "the statue will answer the globe")
	eq(r.minds.advance_time(2)["fired"].size(), 0, "not yet")
	var answered: Array = r.minds.advance_time(1)["fired"]
	eq(_fired_kinds({"fired": answered}), ["PROP_ECHOED:statue"], "three ticks later")
	eq(answered[0]["interpretations"].size(), 3, "everyone present saw the statue move")
	ok(r.engine.knowledge.has("hall_answers.globe.statue"), "the witch has direct evidence of it")
	var reverse := _poke(r, "statue", "squash")
	var echo: Dictionary = r.minds.pending()[0]["event"]
	eq([echo["subject"], echo["data"]["reaction"]], ["globe", "squash"], "and the other way round, with the move she made")
	ok(poke["ok"] and reverse["ok"], "both committed")

func test_the_raccoon_repeating_the_witchs_poke_is_the_same_rule_in_another_domain() -> void:
	var r := _runtime()
	_poke(r, "globe", "hop")
	r.minds.advance_time(5)
	ok(r.engine.knowledge.has("raccoon_repeats.globe"), "five ticks later the raccoon pokes the globe as she did: social evidence of the same relation")
	ok(r.engine.models.query_rules("", "", "player").any(func(m: Dictionary) -> bool: return m["id"] == "m.hall.every_poke_answered"), "and the witch now holds the hypothesis that every poke gets answered")

func test_the_hall_only_answers_the_latest_touch_and_the_witch_revises_instead_of_failing() -> void:
	var r := _runtime()
	_poke(r, "globe", "hop")
	r.minds.advance_time(3)
	_poke(r, "globe", "wobble")
	var second := _poke(r, "globe", "spin")
	eq(second["cancelled"].size(), 2, "the first answers are forgotten")
	eq(r.minds.pending().filter(func(c: Dictionary) -> bool: return c["slot"] == "echo").size(), 1, "one answer pending")
	var models := {}
	for rule in r.engine.models.query_rules("", "", "player"):
		models[rule["id"]] = int(rule["status"])
	eq(models["m.hall.every_poke_answered"], int(MirrorDomain.ModelStatus.REVISED), "the surface model was revised")
	eq(models["m.hall.latest_poke_answered"], int(MirrorDomain.ModelStatus.REVISED), "into a deeper one: not 'wrong', but 'refined'")
	eq(r.engine.models.query_rules("", "", "player").filter(func(m: Dictionary) -> bool: return m["id"] == "m.hall.every_poke_answered")[0]["status"], MirrorDomain.ModelStatus.REVISED, "never merely contradicted")

# ---- rule 2: everything that moves is looked at ------------------------------------------------------------

func test_whoever_sees_something_move_looks_at_it() -> void:
	var r := _runtime()
	var poke := _poke(r, "globe")
	var looks := _ops(poke, "LOOK_AT")
	eq([looks[0]["actor"], looks[0]["target"]], ["raccoon", "globe"], "the raccoon turns to the globe")
	eq(_ops(poke, "PROP_REACT")[0]["target"], "statue", "the statue leans in (a physical manifestation)")
	eq(_ops(poke, "COMMENT")[0]["actor"], "tomas", "and braced, Tomas remarks on it (a relational one)")
	eq(poke["presentation"][0]["key"], "line.hall.tomas_saw", "his remark is a line key the presentation director already understands")

func test_regard_meets_echo_the_raccoon_also_looks_where_the_echo_lands() -> void:
	var r := _runtime()
	_poke(r, "globe")
	var echo: Dictionary = r.minds.advance_time(3)["fired"][0]
	eq(_ops(echo, "LOOK_AT")[0]["target"], "statue", "regard answers to events echo schedules: the two rules recombine")

func test_what_nobody_saw_nobody_looks_at_and_that_teaches_a_deeper_rule() -> void:
	var r := _runtime()
	_poke(r, "globe")
	var unseen := _poke(r, "lamp", "wobble", {"attention": {"raccoon": "away"}})
	eq(_ops(unseen, "LOOK_AT").size(), 0, "the raccoon, looking away, hears it but does not look")
	ok(r.engine.knowledge.has("poke_unremarked.lamp"), "the witch notices that nobody looked")
	var status := -1
	for rule in r.engine.models.query_rules("", "", "player"):
		if rule["id"] == "m.hall.everything_watches":
			status = int(rule["status"])
	eq(status, int(MirrorDomain.ModelStatus.REVISED), "'everything watches' is revised to 'what is seen is watched', not discarded")

func test_a_wrong_reading_from_the_next_room_is_a_recorded_misreading() -> void:
	var r := _runtime()
	r.minds.set_presence("tomas", "back_hall")
	var poke := _poke(r, "globe")
	var tomas: Dictionary = poke["interpretations"].filter(func(x: Dictionary) -> bool: return x["holder"] == "tomas")[0]
	eq(tomas["channel"], "overheard", "he only hears it through the wall")
	ok(tomas["misread"] and int(K.ACTOR) in tomas["kinds"], "he blames the raccoon: wrong, and the engine's ACTOR discrepancy says so")
	ok(r.engine.knowledge.has("tomas_blames_the_raccoon", "tomas"), "he now holds a false belief that can later be contradicted")
	ok(not r.minds.compare_accounts(poke["event_id"], "tomas", "raccoon")["agree"], "his account and the raccoon's disagree about who did it")

# ---- rule 3: what two minds agree on becomes custom -----------------------------------------------------------

func _until_custom(r: MirrorRuntime) -> Array:
	var results: Array = []
	for i in range(4):
		results.append(_poke(r, "globe"))
	return results

func test_a_custom_forms_only_when_a_second_mind_reads_the_pokes_like_the_first() -> void:
	var r := _runtime()
	var results := _until_custom(r)
	eq(results[2]["convention_changes"].map(func(c: Dictionary) -> String: return c["change"]), ["stalled"], "after three pokes only the raccoon thinks 'play': stalled")
	ok(not results[2]["interpretations"].filter(func(x: Dictionary) -> bool: return x["holder"] == "tomas")[0]["reads"] == "play", "Tomas, braced, still reads meddling")
	eq(results[3]["convention_changes"].map(func(c: Dictionary) -> String: return c["change"]), ["adopted"], "his own model has softened (support, not a flag); now he reads play too, and it is adopted")
	ok(r.minds.is_convention_active("conv.hall.globe_is_a_toy"), "in force")
	ok(r.engine.knowledge.has("custom_needs_two"), "the stall taught the witch that one mind is not enough")
	eq(r.engine.models.query_rules("", "", "tomas")[0]["id"], "m.tomas.pokes_harmless", "Tomas's change of mind is his own model")

func test_the_statue_never_becomes_a_toy_because_tomas_will_not_agree() -> void:
	var r := _runtime()
	for i in range(6):
		_poke(r, "statue", "shiver")
	ok(not r.minds.is_convention_active("conv.hall.statue_is_a_toy"), "the raccoon alone cannot make it custom, however often")
	var state := r.minds.convention_state("conv.hall.statue_is_a_toy")
	ok(state["stalled"] and int(state["tally"]) == 6, "it keeps a tally and stays stalled")

func test_once_the_custom_holds_the_world_behaves_by_it_and_the_echo_changes() -> void:
	var r := _runtime()
	_until_custom(r)
	var before := _poke(r, "globe")
	var echo: Dictionary = r.minds.pending().filter(func(c: Dictionary) -> bool: return c["slot"] == "echo")[0]
	eq(int(echo["due"]) - int(before["time"]), 1, "the statue now answers at once instead of after three ticks: name x echo")
	eq(_ops(before, "PROP_REACT").map(func(x: Dictionary) -> String: return x["target"]), ["globe", "statue"], "the globe hops for play (physical) as well as the statue leaning in")
	ok(_ops(before, "APPROACH").size() == 1, "and the raccoon, anticipating the answer, goes to the statue")
	ok(r.engine.knowledge.has("globe_answers_as_a_toy"), "the witch has seen the globe behave by the custom")

func test_adoption_is_said_out_loud_and_the_raccoon_then_plays_alone() -> void:
	var r := _runtime()
	var results := _until_custom(r)
	eq(_ops(results[3], "COMMENT")[0]["key"], "line.hall.tomas_toy", "Tomas puts it into words (an epistemic manifestation)")
	ok(r.engine.knowledge.has("hall_custom.globe_is_a_toy"), "the witch learned the custom from him: an outsider, she is told")
	ok(not r.engine.knowledge.has("conv.hall.globe_is_a_toy", "player"), "but she does not hold it as her own: she is not of the household")
	var alone: Array = r.minds.advance_time(4)["fired"]
	ok("PROP_POKED:globe" in _fired_kinds({"fired": alone}), "four ticks later the raccoon pokes the globe by itself, unprompted: the custom acts with nobody there to cause it")
	ok(r.engine.knowledge.has("raccoon_plays_alone"), "and she saw it")

func test_the_custom_is_traceable_to_where_it_began() -> void:
	var r := _runtime()
	_until_custom(r)
	var state := r.minds.convention_state("conv.hall.globe_is_a_toy")
	ok(not (state["origin_events"] as Array).is_empty(), "origin events are recorded")
	eq(FourLawsLinter.lint_state(r.minds), [], "law 4 holds at runtime")
	for id in state["origin_events"]:
		eq(r.engine.event_store.get_by_id(id).payload["subject"], "globe", "each one is a real poke of the globe")

func test_the_whole_hall_replays_from_the_log() -> void:
	var r := _runtime()
	for step in SimulationRunner.load_script("res://data/sim/hall_rules.json")["steps"]:
		SimulationRunner.run_step(r, step)
	var live := MirrorHash.canonical_json(r.engine.projection_snapshot())
	var pending := MirrorHash.canonical_json(r.minds.pending())
	var conventions := MirrorHash.canonical_json(r.minds.state.conventions.snapshot())
	ok(r.engine.replay_all()["ok"], "replay")
	eq(MirrorHash.canonical_json(r.engine.projection_snapshot()), live, "every belief of every mind is reproduced from the log")
	r.minds.rebuild()
	eq(MirrorHash.canonical_json(r.minds.pending()), pending, "the queue is too")
	eq(MirrorHash.canonical_json(r.minds.state.conventions.snapshot()), conventions, "and the folklore")
	ok(r.engine.audit_integrity()["ok"], "the chain is intact")
