extends TestCase

# Act VII, the return: magic comes back at the jars, each wand branch calls back once, and the verdigris casts keep
# the chooser's choice open. Entry state from ActFixtures (docs/design/GAME_SPEC.md section 6, Act VII).

func _entry(fate: String = "kept") -> MirrorRuntime:
	return ActFixtures.runtime_at({"story": {"act": "act7"}, "witch": {"place": "shop", "from": ""},
		"magic": {"state": "gone"}, "wand": {"fate": fate}},
		{"raccoon": {"place": "shop", "stance": "busy"}, "miron": {"place": "fog"}}, ["act6_half_light"], [])

func _kinds(result: Dictionary) -> Array:
	var kinds: Array = []
	for entry in result.get("presentation", []):
		kinds.append(str(entry.get("kind", "")))
	return kinds

func test_the_return_is_offered_at_the_jars_and_gives_back_magic_and_verdigris() -> void:
	var r := _entry()
	ok(GameFixtures.action_ids(r, "act7_jars").has("act7_return_jars"), "the jars offer the return")
	var result: Dictionary = GameFixtures.do(r, "act7_return_jars", "act7_jars")
	ok(result.get("ok", false), "the return commits: %s" % JSON.stringify(result.get("errors", [])))
	eq(r.engine.get_world("magic", {}), {"state": "returned"}, "magic is returned")
	eq(r.engine.get_world("verdigris", {}), {"known": true}, "verdigris is known")
	ok(r.engine.knowledge.has("act7_magic_returned", "player"), "she knows she got it back")
	ok(_kinds(result).has("magic"), "the return presents the magic (constitution C1)")

func test_each_wand_branch_calls_back_on_the_return() -> void:
	for fate in ["kept", "shattered", "given", "hidden"]:
		var r := _entry(fate)
		var result: Dictionary = GameFixtures.do(r, "act7_return_jars", "act7_jars")
		ok(result.get("ok", false), "%s: the return commits" % fate)
		eq(str(result.get("response", {}).get("id", "")), "act7_return_jars.%s" % fate, "%s: its own callback responds" % fate)

func test_the_return_happens_once() -> void:
	var r := _entry()
	ok(GameFixtures.do(r, "act7_return_jars", "act7_jars").get("ok", false), "the first return commits")
	ok(not GameFixtures.action_ids(r, "act7_jars").has("act7_return_jars"), "and the jars no longer offer it")

func test_the_return_is_refused_once_magic_is_back() -> void:
	var r := _entry()
	GameFixtures.do(r, "act7_return_jars", "act7_jars")
	ok(not GameFixtures.do(r, "act7_return_jars", "act7_jars").get("ok", true), "a second return is refused")

func test_the_night_storylet_plays_while_the_jars_hum_and_before_the_return() -> void:
	var r := _entry()
	var story: Dictionary = r.next_story()
	ok(story.get("ok", false), "the night storylet is eligible")
	eq(str(story.get("storylet", {}).get("id", "")), "act7_night_jars", "and it is the one that plays")

func test_the_trapdoor_look_only_exists_for_the_hidden_wand() -> void:
	ok(GameFixtures.action_ids(_entry("hidden"), "act7_trapdoor").has("act7_trapdoor_look"), "hidden: she can look down")
	ok(not GameFixtures.action_ids(_entry("kept"), "act7_trapdoor").has("act7_trapdoor_look"), "kept: there is nothing to look at")

func test_the_return_lines_are_this_acts_own_keys() -> void:
	var r := _entry()
	var result: Dictionary = GameFixtures.do(r, "act7_return_jars", "act7_jars")
	for entry in result.get("presentation", []):
		if str(entry.get("kind", "")) == "line":
			ok(str(entry.get("key", "")).begins_with("line.act7."), "a line of this act: %s" % entry.get("key", ""))
