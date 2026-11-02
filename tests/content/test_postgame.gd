extends TestCase

# The postgame (GAME_SPEC postgame; constitution C5, C8, C9, C10, C11): no avatar, looking and the exits are the only
# verbs, each wand branch leaves its own trace, the gift inference stays SUPPORTED at most, the truths stand side by side,
# and what happened on the last night stays unresolved. Russian strings are checked through char codes (no Cyrillic here).

const EXITS := ["postgame_exit_down", "postgame_exit_up", "postgame_exit_below", "postgame_exit_basement"]

func _house(fate: String = "kept", place: String = "shop", world_extra: Dictionary = {}, knows: Array = []) -> MirrorRuntime:
	var world := {"story": {"act": "postgame"}, "witch": {"place": place, "from": ""},
		"magic": {"state": "returned"}, "verdigris": {"known": true}, "gold": {"known": true},
		"wand": {"fate": fate}, "act2_shadow_coin": {"left": true}, "act3_shadow_key": {"left": true},
		"act6_shadow_flower": {"left": true}, "garden_below": {"state": "dust"}}
	world.merge(world_extra, true)
	var claims: Array = ["act1_key_on_hook", "prologue_knot", "act6_half_light", "act7_enabled_tomas"]
	claims.append({"id": "act9_what_happened", "proposition": {"event": "what_happened_at_dusk"},
		"status": "UNRESOLVED_BY_DESIGN", "scope": "global"})
	claims.append_array(knows)
	return ActFixtures.runtime_at(world, {"raccoon": {"place": "shop", "stance": "busy"}, "miron": {"place": "fog"}}, claims, [])

func _status(r: MirrorRuntime, claim_id: String) -> int:
	return int(r.engine.knowledge.get_claim(claim_id, "player").get("status", -1))

func _game_engine() -> MirrorEngine:
	GameFixtures.ensure_localization()
	var engine: MirrorEngine = MirrorCatalog.build_engine(MirrorCatalog.DEFAULT_DIR, true)["engine"]
	return engine

func _postgame_definitions() -> Array:
	var out: Array = []
	var engine := _game_engine()
	for id in engine.action_definitions.keys():
		if str(id).begins_with("postgame_"):
			out.append(engine.action_definitions[id])
	return out

func test_each_wand_branch_leaves_its_own_trace_and_no_other() -> void:
	var traces := [
		["kept", "shop", "postgame_look_wand_satchel", "pg_satchel", "postgame_wand_satchel"],
		["shattered", "shop", "postgame_look_wand_pieces", "pg_wand_pieces", "postgame_wand_pieces"],
		["given", "attic", "postgame_look_wand_glue", "pg_glue", "postgame_wand_glue"],
		["hidden", "basement", "postgame_look_wand_crate", "pg_crate", "postgame_wand_crate"],
	]
	for trace in traces:
		var fate: String = trace[0]
		var place: String = trace[1]
		var r := _house(fate, place)
		var result: Dictionary = GameFixtures.do(r, trace[2], trace[3])
		ok(result.get("ok", false), "%s: its trace is there to look at: %s" % [fate, JSON.stringify(result.get("errors", []))])
		ok(r.engine.knowledge.has(trace[4], "player"), "%s: the trace is recorded" % fate)
		for other in traces:
			if other[0] == fate:
				continue
			ok(not GameFixtures.action_ids(r, other[3]).has(other[2]), "%s: the %s trace is not there" % [fate, other[0]])

func test_she_knew_him_needs_three_of_the_seen_objects() -> void:
	var two := _house("kept", "shop", {"postgame_clue_knot": {"seen": true}, "postgame_clue_coin": {"seen": true}})
	ok(not GameFixtures.action_ids(two, "pg_notebook").has("postgame_think_she_knew"), "two seen objects are not enough")
	var three := _house("kept", "shop", {"postgame_clue_knot": {"seen": true}, "postgame_clue_coin": {"seen": true},
		"postgame_clue_hook": {"seen": true}})
	ok(GameFixtures.action_ids(three, "pg_notebook").has("postgame_think_she_knew"), "three seen objects give the thought")
	var result: Dictionary = GameFixtures.do(three, "postgame_think_she_knew", "pg_notebook")
	ok(result.get("ok", false), "the thought commits")
	eq(_status(three, "postgame_she_knew_him"), MirrorDomain.EpistemicStatus.SUPPORTED, "she knew him is inferred, at SUPPORTED")

func test_he_asked_her_needs_the_petal_and_the_knot_and_stays_supported() -> void:
	var one := _house("kept", "shop", {}, ["postgame_petal"])
	ok(not GameFixtures.action_ids(one, "pg_notebook").has("postgame_think_asked"), "the petal alone is not a request")
	var both := _house("kept", "shop", {}, ["postgame_petal", "postgame_knot_swing"])
	ok(GameFixtures.action_ids(both, "pg_notebook").has("postgame_think_asked"), "the petal and the knot together suggest it")
	var result: Dictionary = GameFixtures.do(both, "postgame_think_asked", "pg_notebook")
	ok(result.get("ok", false), "the thought commits")
	eq(_status(both, "postgame_he_asked_her"), MirrorDomain.EpistemicStatus.SUPPORTED, "he asked her: SUPPORTED at most (constitution C10)")
	eq(_status(both, "postgame_he_cared"), MirrorDomain.EpistemicStatus.SUPPORTED, "he cared: inferred, never established (constitution C3)")

func test_the_gift_inference_is_never_established_anywhere_in_the_game() -> void:
	var engine := _game_engine()
	var checked := 0
	for id in engine.action_definitions.keys():
		var definition: Dictionary = engine.action_definitions[id]
		for response in definition.get("response_contracts", []):
			for effect in response.get("knowledge_effects", []):
				var claim_id := str(effect.get("id", ""))
				if claim_id in ["postgame_he_asked_her", "postgame_he_cared", "postgame_she_knew_him"]:
					checked += 1
					ok(int(effect.get("status", -1)) != MirrorDomain.EpistemicStatus.ESTABLISHED,
						"%s/%s does not establish %s (constitution C10)" % [id, response["id"], claim_id])
					ok(MirrorDomain.epistemic_rank(int(effect.get("status", -1))) <= MirrorDomain.epistemic_rank(MirrorDomain.EpistemicStatus.SUPPORTED),
						"%s is at most SUPPORTED" % claim_id)
	ok(checked >= 3, "the gift claims are written by the postgame (%d writes)" % checked)

func test_he_left_and_he_chose_stay_true_beside_the_inference() -> void:
	var r := _house()
	GameFixtures.do(r, "core_go_door_shop_garden", "door_shop_garden")
	GameFixtures.do(r, "postgame_look_bench", "pg_bench")
	GameFixtures.do(r, "postgame_look_gate", "pg_gate")
	eq(_status(r, "postgame_he_left"), MirrorDomain.EpistemicStatus.ESTABLISHED, "he left is seen")
	ok(MirrorDomain.epistemic_satisfies(_status(r, "postgame_he_chose"), MirrorDomain.EpistemicStatus.SUPPORTED), "he chose stays true")

func test_the_exits_reach_the_basement_the_dust_and_come_back() -> void:
	var r := _house()
	GameFixtures.do(r, "postgame_exit_down", "pg_trapdoor")
	eq(r.engine.get_world("witch", {}).get("place", ""), "basement", "down to the basement")
	GameFixtures.do(r, "postgame_exit_below", "pg_low_door")
	eq(r.engine.get_world("witch", {}).get("place", ""), "garden_below", "through the low door to the Garden Below")
	GameFixtures.do(r, "postgame_exit_basement", "pg_below_stairs")
	eq(r.engine.get_world("witch", {}).get("place", ""), "basement", "and back to the basement")
	GameFixtures.do(r, "postgame_exit_up", "pg_stairs")
	eq(r.engine.get_world("witch", {}).get("place", ""), "shop", "and up to the shop")

func test_the_street_is_shut_in_the_postgame() -> void:
	var r := _house()
	ok(not GameFixtures.action_ids(r, "door_shop_street").has("core_go_door_shop_street"), "the shop door to the street is shut after the ending")

func test_the_house_is_only_looked_at_and_walked_through() -> void:
	var definitions := _postgame_definitions()
	ok(definitions.size() >= 20, "the postgame has its looks and exits (%d actions)" % definitions.size())
	for definition in definitions:
		var kind := int(definition.get("action_type", -1))
		ok(kind == MirrorDomain.ActionType.LOOK or kind == MirrorDomain.ActionType.GO,
			"%s is a look or an exit, never a cast, ask, show or wait" % definition["id"])

func test_the_scratch_phrase_is_written_exactly_once() -> void:
	# The phrase is built from code points: Vedj my byli zdes' (in Russian letters, as the doorframe reads).
	var phrase := char(0x0412) + char(0x0435) + char(0x0434) + char(0x044C) + " " + char(0x043C) + char(0x044B) + " " \
		+ char(0x0431) + char(0x044B) + char(0x043B) + char(0x0438) + " " + char(0x0437) + char(0x0434) + char(0x0435) \
		+ char(0x0441) + char(0x044C)
	var table := Localization.load_table()
	var found: Array = []
	for key in table.keys():
		if str(table[key]).contains(phrase):
			found.append(str(key))
	eq(found, ["line.postgame.doorframe"], "the phrase is scratched on the doorframe, and nowhere else")

func test_closing_the_notebook_is_a_presentation_step() -> void:
	var r := _house()
	var result: Dictionary = GameFixtures.do(r, "postgame_open_notebook", "pg_notebook")
	ok(result.get("ok", false), "the notebook opens")
	var kinds: Array = []
	for entry in result.get("presentation", []):
		kinds.append(str(entry.get("kind", "")))
	ok(kinds.has("notebook"), "as a notebook presentation step (the menu is the framework's)")

func test_the_garden_below_reads_dust_or_fading_and_only_dust_is_recorded() -> void:
	var dust := _house("kept", "garden_below", {"garden_below": {"state": "dust"}})
	var dust_result: Dictionary = GameFixtures.do(dust, "postgame_look_dust", "pg_dust")
	eq(str(dust_result.get("response", {}).get("id", "")), "postgame_look_dust.dust", "dust is the response when the garden is dust")
	ok(dust.engine.knowledge.has("postgame_below_dust", "player"), "and it is recorded")
	var fading := _house("kept", "garden_below", {"garden_below": {"state": "fading"}})
	var fading_result: Dictionary = GameFixtures.do(fading, "postgame_look_dust", "pg_dust")
	eq(str(fading_result.get("response", {}).get("id", "")), "postgame_look_dust.fading", "fading is the other response")
	ok(not fading.engine.knowledge.has("postgame_below_dust", "player"), "nothing is claimed about a garden that is not yet dust")

func test_every_notebook_entry_is_a_claim_the_postgame_writes() -> void:
	var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/notebook/postgame.json"))
	ok(sidecar is Dictionary, "the postgame notebook sidecar is a JSON object")
	if not sidecar is Dictionary:
		return
	var written: Dictionary = {}
	for definition in _postgame_definitions():
		for response in definition.get("response_contracts", []):
			for effect in response.get("knowledge_effects", []):
				written[str(effect.get("id", ""))] = true
	var kinds := ["seen", "heard", "shown", "inferred", "predicted", "altered", "untestable"]
	for claim_id in sidecar.keys():
		ok(written.has(str(claim_id)), "%s is written by a postgame action" % claim_id)
		ok(str(sidecar[claim_id].get("kind", "")) in kinds, "%s has a known notebook kind" % claim_id)

func test_the_postgame_text_has_no_numbers_and_fits_the_bubbles() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/text/ru/postgame.json"))
	ok(parsed is Dictionary, "the postgame text fragment is a JSON object")
	if not parsed is Dictionary:
		return
	var digits := RegEx.create_from_string("[0-9]")
	for key in parsed.keys():
		var text := str(parsed[key])
		if str(key).begins_with("_"):
			continue
		ok(digits.search(text) == null, "%s shows no number about anyone (constitution C11)" % key)
		if str(key).begins_with("line."):
			ok(text.length() <= 90, "%s fits a bubble (%d characters)" % [key, text.length()])
		if str(key).begins_with("opt."):
			ok(text.length() <= 40, "%s fits an option (%d characters)" % [key, text.length()])
