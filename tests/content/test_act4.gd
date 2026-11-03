extends TestCase

# Act IV: the wand and the choice (docs/design/GAME_SPEC.md section 6). Four branches on the witch, exclusive through
# wand.fate. None is the right answer: each leaves its own trace and sends the story on to act five.

const BRANCHES := {
	"act4_wand_break": ["act4_wand_shattered", "shattered"],
	"act4_wand_keep": ["act4_wand_kept", "kept"],
	"act4_wand_give": ["act4_wand_given", "given"],
	"act4_wand_hide": ["act4_wand_hidden", "hidden"],
}


func _at(place: String = "garden_below") -> MirrorRuntime:
	return ActFixtures.runtime_at({"story": {"act": "act4"}, "witch": {"place": place, "from": "clocktower"},
			"magic": {"state": "below"}, "wand": {"fate": "held"}}, {"raccoon": {"place": "with_witch"}}, [], [])


func _can(r: MirrorRuntime, action_id: String) -> bool:
	return bool(r.engine.explain_action(r.make_action(action_id, "witch")).get("available", false))


func _do(r: MirrorRuntime, action_id: String) -> bool:
	return bool(GameFixtures.do(r, action_id, "witch").get("ok", false))


func test_the_four_wand_branches_are_open_while_the_wand_is_held() -> void:
	var r: MirrorRuntime = _at()
	for branch in BRANCHES.keys():
		ok(_can(r, str(branch)), "%s is open while the wand is held" % str(branch))


func test_the_four_wand_branches_are_mutually_exclusive() -> void:
	for chosen in BRANCHES.keys():
		var r: MirrorRuntime = _at()
		ok(_do(r, str(chosen)), "%s is taken" % str(chosen))
		for other in BRANCHES.keys():
			if str(other) != str(chosen):
				ok(not _can(r, str(other)), "after %s, %s is closed" % [str(chosen), str(other)])


func test_each_branch_leaves_only_its_own_altered_note() -> void:
	for chosen in BRANCHES.keys():
		var r: MirrorRuntime = _at()
		ok(_do(r, str(chosen)), "%s is taken" % str(chosen))
		var own: String = BRANCHES[chosen][0]
		eq(int(r.engine.knowledge.get_claim(own, "player").get("status", -1)), MirrorDomain.EpistemicStatus.ESTABLISHED,
				"%s is altered and recorded" % own)
		for other in BRANCHES.keys():
			var claim: String = BRANCHES[other][0]
			if claim != own:
				ok(not r.engine.knowledge.has(claim, "player"), "and %s is not" % claim)


func test_each_branch_sets_the_wand_fate_and_passes_the_story_to_act_five() -> void:
	for chosen in BRANCHES.keys():
		var r: MirrorRuntime = _at()
		ok(_do(r, str(chosen)), "%s is taken" % str(chosen))
		eq(r.engine.get_world("wand", {}).get("fate", ""), BRANCHES[chosen][1], "the wand's fate is %s" % BRANCHES[chosen][1])
		eq(r.engine.get_world("story", {}).get("act", ""), "act5", "and act five begins")


func test_hiding_the_wand_takes_the_witch_down_to_the_basement() -> void:
	var r: MirrorRuntime = _at()
	ok(_do(r, "act4_wand_hide"), "she hides it")
	eq(r.engine.get_world("witch", {}).get("place", ""), "basement", "the crate is in the basement")


func test_the_wand_glows_as_a_beat_in_the_garden_until_it_is_decided() -> void:
	var r: MirrorRuntime = _at()
	var ids: Array = []
	for storylet in r.engine.select_storylets(r.context_snapshot(), "player"):
		ids.append(str(storylet.get("id", "")))
	ok("act4_wand_glows" in ids, "the glow is eligible in the garden with the wand held")
	ok(_do(r, "act4_wand_keep"), "she keeps the wand")
	var after: Array = []
	for storylet in r.engine.select_storylets(r.context_snapshot(), "player"):
		after.append(str(storylet.get("id", "")))
	ok(not ("act4_wand_glows" in after), "and the glow is not eligible once act four is over")


func test_the_act_four_simulation_passes() -> void:
	var script: Dictionary = SimulationRunner.load_script("res://data/sim_pending/act4_main.json")
	var outcome: Dictionary = SimulationRunner.new().run(_at(), script)
	ok(outcome.get("ok", false), "act4_main passes: failed step %d, expectations %s"
			% [int(outcome.get("failed_step", -1)), str(outcome.get("expect_failures", []))])
