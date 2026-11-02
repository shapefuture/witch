extends TestCase

# The prologue's puzzles, run through Mirror (docs/design/GAME_SPEC.md section 6, Prologue). Each test drives the
# real game-scope runtime; the sims in data/sim/prologue_*.json check whole routes.

func _status(r: MirrorRuntime, claim_id: String) -> int:
	var claim: Dictionary = r.engine.knowledge.get_claim(claim_id, "player")
	return int(claim.get("status", -1)) if not claim.is_empty() else -1

func _kettle(r: MirrorRuntime) -> String:
	return str(r.engine.get_world("prologue_kettle", {}).get("state", ""))

func _go_garden(r: MirrorRuntime) -> void:
	GameFixtures.do(r, "core_go_door_shop_garden", "door_shop_garden")

func test_the_kettle_stops_when_watched_and_boils_when_turned_away() -> void:
	var r := GameFixtures.runtime(true)
	eq(_kettle(r), "simmering", "the kettle starts on the flame, not boiling")
	ok(GameFixtures.do(r, "prologue_look_kettle", "prologue_kettle").get("ok", false), "she looks at it")
	eq(_kettle(r), "still", "looking stops it simmering")
	ok(GameFixtures.do(r, "prologue_wait_kettle", "prologue_kettle").get("ok", false), "she turns away to tidy")
	eq(_kettle(r), "boiled", "it boils by itself, unwatched")
	eq(_status(r, "prologue_kettle_rule"), MirrorDomain.EpistemicStatus.SUPPORTED, "the rule is an inference, SUPPORTED at most")
	ok(r.engine.operators.has("op.prologue_unwatched", "player"), "and the witch acquires op.prologue_unwatched")

func test_turning_away_before_looking_boils_it_but_teaches_no_rule() -> void:
	var r := GameFixtures.runtime(true)
	GameFixtures.do(r, "prologue_wait_kettle", "prologue_kettle")
	eq(_kettle(r), "boiled", "it still boils")
	eq(_status(r, "prologue_kettle_rule"), -1, "without looking first there is no rule to infer")
	ok(not r.engine.operators.has("op.prologue_unwatched", "player"), "and no operator")

func test_a_forced_kettle_still_leaves_the_rule_reachable() -> void:
	var r := GameFixtures.runtime(true)
	var cast := GameFixtures.do(r, "prologue_cast_kettle", "prologue_kettle")
	ok(cast.get("ok", false), "casting makes it boil at once")
	eq(_kettle(r), "thunder", "the forced kettle is thunder")
	eq(_status(r, "prologue_kettle_thunder"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the tea tastes of thunder: altered")
	eq(_status(r, "prologue_kettle_rule"), -1, "the forced result teaches nothing about why")
	eq(r.engine.get_npc_state("raccoon").get("stance", ""), "soaked", "the raccoon is sprayed")
	ok(GameFixtures.do(r, "prologue_refill_kettle", "prologue_kettle").get("ok", false), "she puts it back on")
	GameFixtures.do(r, "prologue_look_kettle", "prologue_kettle")
	GameFixtures.do(r, "prologue_wait_kettle", "prologue_kettle")
	eq(_status(r, "prologue_kettle_rule"), MirrorDomain.EpistemicStatus.SUPPORTED, "the honest route still reaches the rule")

func test_the_cast_cannot_be_repeated_once_it_has_been_used() -> void:
	var r := GameFixtures.runtime(true)
	GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street")
	ok(GameFixtures.do(r, "prologue_cast_lamp", "prologue_lamp").get("ok", false), "the lamp lights once")
	eq(r.engine.get_world("prologue_lamp", {}).get("lit", false), true, "and stays lit")
	var again := GameFixtures.do(r, "prologue_cast_lamp", "prologue_lamp")
	ok(not again.get("ok", false), "the second cast is refused (once_key)")

func test_the_lamp_look_changes_once_it_burns() -> void:
	var r := GameFixtures.runtime(true)
	GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street")
	eq(GameFixtures.do(r, "prologue_look_lamp", "prologue_lamp").get("observed", {}).get("outcome", ""), "lamp_unlit", "unlit before the cast")
	GameFixtures.do(r, "prologue_cast_lamp", "prologue_lamp")
	eq(GameFixtures.do(r, "prologue_look_lamp", "prologue_lamp").get("observed", {}).get("outcome", ""), "lamp_burns", "it burns after")

func test_two_tastes_needs_both_the_lilies_and_the_sunflowers() -> void:
	var r := GameFixtures.runtime(true)
	_go_garden(r)
	GameFixtures.do(r, "prologue_look_lilies", "prologue_lilies")
	eq(_status(r, "prologue_lilies_tidy"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the lilies are tidy: seen")
	eq(_status(r, "prologue_garden_two_tastes"), -1, "one taste is not two")
	GameFixtures.do(r, "prologue_look_sunflowers", "prologue_sunflowers")
	GameFixtures.do(r, "prologue_look_lilies", "prologue_lilies")
	eq(_status(r, "prologue_garden_two_tastes"), MirrorDomain.EpistemicStatus.SUPPORTED, "with both, the garden has two tastes")

func test_the_bench_is_crooked_by_looking_or_by_the_cast_alone() -> void:
	var by_look := GameFixtures.runtime(true)
	_go_garden(by_look)
	GameFixtures.do(by_look, "prologue_look_bench", "prologue_bench")
	eq(_status(by_look, "prologue_bench_crooked"), MirrorDomain.EpistemicStatus.ESTABLISHED, "looking shows it")
	var by_cast := GameFixtures.runtime(true)
	_go_garden(by_cast)
	ok(GameFixtures.do(by_cast, "prologue_cast_bench", "prologue_bench").get("ok", false), "the straightening cast")
	eq(_status(by_cast, "prologue_bench_crooked"), MirrorDomain.EpistemicStatus.ESTABLISHED, "and it leans back on Miron: the claim comes with the cast too")

func test_the_bed_needs_the_kettle_rule_and_every_garden_claim() -> void:
	var r := ActFixtures.runtime_at({}, {}, [])
	eq(r.engine.get_world("story", {}).get("act", ""), "prologue", "at the prologue")
	ok(not GameFixtures.do(r, "prologue_end_day", "prologue_bed").get("ok", false), "no bed before the claims")
	var knows := [
		{"id": "prologue_kettle_rule", "proposition": {"kettle": "boils_only_unwatched"}, "status": "SUPPORTED", "scope": "fixture"},
		{"id": "prologue_garden_two_tastes", "proposition": {"garden": "two_tastes"}, "status": "SUPPORTED", "scope": "fixture"},
		{"id": "prologue_bench_crooked", "proposition": {"bench": "leans"}, "status": "ESTABLISHED", "scope": "fixture"},
		{"id": "prologue_knot", "proposition": {"swing": "his_knot"}, "status": "ESTABLISHED", "scope": "fixture"},
		{"id": "prologue_sunflowers", "proposition": {"sunflowers": "crooked"}, "status": "ESTABLISHED", "scope": "fixture"},
	]
	var partial := ActFixtures.runtime_at({}, {}, knows.slice(0, 4))
	ok(not GameFixtures.do(partial, "prologue_end_day", "prologue_bed").get("ok", false), "still no bed without the sunflowers")
	var r2 := ActFixtures.runtime_at({}, {}, knows)
	ok(not GameFixtures.do(r2, "prologue_end_day", "prologue_bed").get("ok", false), "and not without Miron's evening")
	var full: Array = knows.duplicate(true)
	full.append({"id": "prologue_fog_mentioned", "proposition": {"miron_said": "quiet"}, "status": "ESTABLISHED", "scope": "fixture"})
	var r3 := ActFixtures.runtime_at({}, {}, full)
	ok(GameFixtures.do(r3, "prologue_end_day", "prologue_bed").get("ok", false), "with all of them, the day ends")
	eq(r3.engine.get_world("story", {}).get("act", ""), "act1", "and the story moves to act I")

func test_the_morning_storylet_is_eligible_in_the_shop_at_the_start() -> void:
	var r := GameFixtures.runtime(true)
	var ids: Array = []
	for definition in r.engine.select_storylets(r.context_snapshot(), "player"):
		ids.append(str(definition.get("id", "")))
	ok("prologue_morning" in ids, "the morning beat is eligible at the start")

func test_the_chuyka_on_herself_records_only_that_she_looked() -> void:
	var r := GameFixtures.runtime(true)
	ok(GameFixtures.do(r, "prologue_sight_self", "witch").get("ok", false), "she looks with her chuyka")
	eq(_status(r, "prologue_sight_used"), MirrorDomain.EpistemicStatus.ESTABLISHED, "the record says she looked, not what the ghost meant")
	eq(_status(r, "prologue_father_drawing"), -1, "and nothing else")

func test_the_raccoon_drawing_question_needs_the_drawing_seen() -> void:
	var r := GameFixtures.runtime(true)
	ok(not GameFixtures.do(r, "prologue_ask_raccoon_drawing", "raccoon").get("ok", false), "not before she has seen it")
	GameFixtures.do(r, "prologue_look_drawing", "prologue_drawing")
	ok(GameFixtures.do(r, "prologue_ask_raccoon_drawing", "raccoon").get("ok", false), "now she can ask")
	eq(_status(r, "prologue_drawing_older"), MirrorDomain.EpistemicStatus.ESTABLISHED, "he says it is older than him, and nothing more")
