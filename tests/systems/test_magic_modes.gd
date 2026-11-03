extends TestCase

# The magic modes' looks (BIBLE section 8; GAME_SPEC section 4): violet breaks the rules; verdigris opens a ring that frames
# and changes nothing; gold is a warm glow that moves nothing else; the fizzle is a misfire that is clearly magic failing.
# Every look flashes at most three times a second, and only violet touches the palette and the lens.

func _stage() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	var camera := Camera3D.new()
	camera.name = "Camera"
	viewport.add_child(camera)
	Engine.get_main_loop().root.add_child(viewport)
	track(viewport)
	camera.make_current()
	return viewport

func _magic(viewport: SubViewport) -> MagicPresentation:
	var magic := MagicPresentation.new()
	magic.time_scale = 0.02
	viewport.add_child(magic)
	return magic

# How many nodes of this name are in the picture (the looks name the nodes they add).
func _named(viewport: SubViewport, node_name: String) -> int:
	return viewport.find_children(node_name, "", true, false).size()

func _settle(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(seconds).timeout
	await tree.process_frame

func test_no_look_flashes_more_than_three_times_a_second() -> void:
	ok(MagicPresentation.max_flicker_hz() <= 3.0, "the fizzle's sputters come at %.1f a second at most" % MagicPresentation.max_flicker_hz())

func test_the_fizzle_sputters_three_times_in_order_and_no_faster_than_twice_a_second() -> void:
	var viewport := _stage()
	var magic := _magic(viewport)
	var sputters: Array = []
	magic.sputtered.connect(func(index: int) -> void: sputters.append(index))
	magic.play("fizzle", Vector3.ZERO)
	await _settle(0.3)
	eq(sputters, [0, 1, 2], "the fizzle sputters three times, in order")
	var beats: Array = MagicPresentation.FIZZLE_BEATS
	var closest := 1.0e9
	for i in range(1, beats.size()):
		closest = minf(closest, float(beats[i]) - float(beats[i - 1]))
	ok(closest >= 0.5 - 0.0001, "the sputters are half a second apart at the least (%.2f s)" % closest)
	ok(MagicPresentation.max_flicker_hz() <= 2.0 + 0.0001, "so the fizzle flashes at most twice a second")

func test_verdigris_opens_a_ring_and_leaves_the_palette_and_the_lens_alone() -> void:
	var viewport := _stage()
	var magic := _magic(viewport)
	var before := PSXGlobals.magic()
	var finished: Array = []
	magic.finished.connect(func(effect: String) -> void: finished.append(effect))
	magic.play("repair", Vector3.ZERO, "verdigris")
	eq(_named(viewport, "VerdigrisRing"), 1, "a ring of light is there while it plays")
	await _settle(0.3)
	eq(PSXGlobals.magic(), before, "the palette is not broken: verdigris frames, it does not change")
	eq(finished, ["repair"], "and it finishes once")
	eq(_named(viewport, "VerdigrisRing"), 0, "the ring is gone afterwards")

func test_gold_is_a_warm_glow_at_her_face_and_nothing_else_moves() -> void:
	var viewport := _stage()
	var magic := _magic(viewport)
	var before := PSXGlobals.magic()
	var finished: Array = []
	magic.finished.connect(func(effect: String) -> void: finished.append(effect))
	magic.play("repair", Vector3.ZERO, "gold")
	eq(_named(viewport, "GoldHalo"), 1, "a soft disc of gold is there while it plays")
	eq(_named(viewport, "MagicColumn"), 0, "and no column of light rises")
	await _settle(0.3)
	eq(PSXGlobals.magic(), before, "the world does not change")
	eq(finished, ["repair"], "and it finishes once")
	eq(_named(viewport, "GoldHalo"), 0, "the glow is gone afterwards")

func test_the_fizzle_sputters_and_goes_out_without_breaking_anything() -> void:
	var viewport := _stage()
	var magic := _magic(viewport)
	var before := PSXGlobals.magic()
	var peaks: Array = []
	var finished: Array = []
	magic.peaked.connect(func(effect: String) -> void: peaks.append(effect))
	magic.finished.connect(func(effect: String) -> void: finished.append(effect))
	magic.play("fizzle", Vector3.ZERO)
	eq(_named(viewport, "FizzleCore"), 1, "a small ball of violet is there while the magic fizzles")
	await _settle(0.3)
	eq(peaks, ["fizzle"], "the fizzle peaks once, so the room's state is shown")
	eq(finished, ["fizzle"], "and then it finishes")
	eq(PSXGlobals.magic(), before, "a misfire does not break the world")
	eq(_named(viewport, "FizzleCore"), 0, "the ball is gone afterwards")

func test_violet_still_breaks_the_world_and_settles() -> void:
	var viewport := _stage()
	var magic := _magic(viewport)
	var finished: Array = []
	magic.finished.connect(func(effect: String) -> void: finished.append(effect))
	magic.play("flourish", Vector3.ZERO)
	eq(_named(viewport, "MagicColumn"), 1, "violet rises as a column of light, as it always did")
	await _settle(0.3)
	eq(finished, ["flourish"], "and it finishes")
	eq(_named(viewport, "MagicColumn"), 0, "the column is gone afterwards")
	eq(PSXGlobals.magic(), 0.0, "and the world is back to mundane")
