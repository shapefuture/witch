extends TestCase

# Act IX, the invitation (GAME_SPEC act IX; constitution C9, C10): three readings of the impossible dusk, each held by an
# object; what happened stays untestable; the shadow says her two lines at the open door, and the only way on is to go
# with her. The Russian lines are written as Unicode escapes here, because no Cyrillic may live outside the text table.

static func _hello() -> String:
	return char(0x041F) + char(0x0440) + char(0x0438) + char(0x0432) + char(0x0435) + char(0x0442) + "."

static func _come() -> String:
	return char(0x041F) + char(0x043E) + char(0x0439) + char(0x0434) + char(0x0451) + char(0x043C) + "."

func _shop() -> MirrorRuntime:
	return ActFixtures.runtime_at({"story": {"act": "act9"}, "witch": {"place": "shop", "from": "street"},
		"magic": {"state": "returned"}, "verdigris": {"known": true}, "wand": {"fate": "kept"}},
		{"raccoon": {"place": "shop", "stance": "busy"}, "miron": {"place": "fog"}}, [], [])

func _status(r: MirrorRuntime, claim_id: String) -> int:
	return int(r.engine.knowledge.get_claim(claim_id, "player").get("status", -1))

func _titles(result: Dictionary) -> Array:
	var titles: Array = []
	for entry in result.get("presentation", []):
		if str(entry.get("kind", "")) == "dialogue":
			titles.append(str(entry.get("title", "")))
	return titles

func test_the_act_opens_on_the_clocks_stopping() -> void:
	var r := _shop()
	var story: Dictionary = r.next_story()
	ok(story.get("ok", false), "the act's opening storylet is eligible")
	eq(str(story.get("storylet", {}).get("id", "")), "act9_event", "it is the clocks, the glow and the bell")

func test_each_evidence_object_records_a_seen_claim() -> void:
	var r := _shop()
	ok(GameFixtures.do(r, "act9_look_bell_rope", "act9_bell_rope").get("ok", false), "the knot is looked at")
	eq(_status(r, "act9_shadow_knot"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the knot is seen")
	ok(GameFixtures.do(r, "act9_listen_jars", "act7_jars").get("ok", false), "the jars are listened to")
	eq(_status(r, "act9_jars_in_tune"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the jars are heard in tune")
	ok(GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street").get("ok", false), "she steps out to the street")
	ok(GameFixtures.do(r, "act9_look_step", "act9_step").get("ok", false), "the step is looked at")
	eq(_status(r, "act9_fog_dew"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the fog-dew is seen")
	ok(GameFixtures.do(r, "act9_look_clocks", "act9_clocks").get("ok", false), "the clocks are looked at")
	eq(_status(r, "act9_clocks_stopped"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the clocks are seen stopped")

func test_the_three_readings_are_inferred_never_established() -> void:
	var r := _shop()
	GameFixtures.do(r, "act9_look_bell_rope", "act9_bell_rope")
	GameFixtures.do(r, "act9_listen_jars", "act7_jars")
	GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street")
	GameFixtures.do(r, "act9_look_step", "act9_step")
	for reading in ["act9_reading_fog", "act9_reading_shadow", "act9_reading_magic"]:
		eq(_status(r, reading), MirrorDomain.EpistemicStatus.SUPPORTED, "%s is supported, never established" % reading)

func test_the_doorway_leaves_what_happened_unresolved() -> void:
	var r := _shop()
	var result: Dictionary = GameFixtures.do(r, "act9_look_doorway", "act9_doorway")
	ok(result.get("ok", false), "the empty doorway is looked at")
	eq(_status(r, "act9_what_happened"), MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "what happened is unresolved by design")
	eq(_status(r, "act9_bell_rang"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the bell rang: that is seen")

func test_the_shadow_comes_to_the_open_door_and_says_hello() -> void:
	var r := _shop()
	ok(not GameFixtures.action_ids(r, "shadow").has("act9_go_with_shadow"), "before she comes, there is no way on")
	var result: Dictionary = GameFixtures.do(r, "act9_wait_at_door", "act9_doorway")
	ok(result.get("ok", false), "waiting at the door commits")
	eq(r.engine.get_npc_state("shadow").get("place", ""), "shop", "the shadow is in the doorway")
	ok(_titles(result).has("act9_shadow_hi"), "and she says her first line")

func test_the_only_way_on_is_to_go_with_her_and_the_ending_leaves_the_question_open() -> void:
	var r := _shop()
	GameFixtures.do(r, "act9_wait_at_door", "act9_doorway")
	GameFixtures.do(r, "act9_look_doorway", "act9_doorway")
	var result: Dictionary = GameFixtures.do(r, "act9_go_with_shadow", "shadow")
	ok(result.get("ok", false), "going with her commits: %s" % JSON.stringify(result.get("errors", [])))
	eq(r.engine.get_world("story", {}).get("act", ""), "postgame", "the story moves to the postgame")
	eq(r.engine.get_world("witch", {}).get("place", ""), "shop", "she stays in the shop as the viewpoint")
	eq(_status(r, "act9_what_happened"), MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN, "the ending reaches postgame with the question still open (constitution C9)")
	var presentation: Array = result.get("presentation", [])
	ok(not presentation.is_empty(), "the ending has a presentation")
	eq(str(presentation.back().get("kind", "")), "ending", "the ending is the last step: the witch walks out and the camera stays")

func test_the_pair_of_shadow_lines_is_written_once_in_the_whole_table() -> void:
	var table := Localization.load_table()
	var hellos := 0
	var comes := 0
	for key in table.keys():
		if str(table[key]) == _hello():
			hellos += 1
		if str(table[key]) == _come():
			comes += 1
	eq(hellos, 1, "the greeting is written once in the whole table")
	eq(comes, 1, "the invitation is written once in the whole table")

func test_the_lines_of_the_act_are_its_own_keys() -> void:
	var r := _shop()
	var result: Dictionary = GameFixtures.do(r, "act9_look_doorway", "act9_doorway")
	for entry in result.get("presentation", []):
		if str(entry.get("kind", "")) == "line":
			ok(str(entry.get("key", "")).begins_with("line.act9."), "a line of act nine: %s" % entry.get("key", ""))
