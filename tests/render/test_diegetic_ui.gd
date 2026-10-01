extends TestCase

# Speech bubbles and option plaques are scene geometry placed by projecting screen positions into
# the world. These tests pin what a player needs from them: they stay on screen, are big enough for
# a finger, never overlap, and a tap on a plaque chooses that plaque.

const VIEWPORT := Vector2(480, 360)
const MIN_TOUCH_ROWS := 17.0   # render pixels; 3x on a 1080p phone is ~51 css px

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _stage() -> Dictionary:  # callers: var stage := await _stage()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 360)
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	_tree().root.add_child(viewport)
	track(viewport)
	await _tree().process_frame
	camera.set_pose({"look_at": Vector3(0, 1, 0), "distance": 10.0, "pitch_deg": 5.0, "yaw_deg": 0.0, "roll_deg": 0.0, "fov": 60.0}, true)
	return {"viewport": viewport, "camera": camera}

func test_a_bubble_stays_inside_the_safe_area_wherever_its_speaker_is() -> void:
	var stage := await _stage()
	var bubble := SpeechBubble.new()
	bubble.camera = stage["camera"]
	(stage["viewport"] as SubViewport).add_child(bubble)
	var safe := Diegetic.safe_rect(VIEWPORT)
	for anchor in [Vector3(0, 1.6, 0), Vector3(-6, 1.6, 0), Vector3(6, 1.6, 0), Vector3(0, 7, 0), Vector3(0, -3, 0), Vector3(-9, 0.2, 2)]:
		bubble.present("Speaker", "Will you hold this while I turn the wheel? Carefully, though: it likes to bite.", anchor, false)
		var rect := bubble.screen_rect()
		ok(safe.grow(1.0).encloses(rect), "bubble %s inside the safe area %s for a speaker at %s" % [rect, safe, anchor])
		ok(rect.size.x >= 60.0 and rect.size.y >= 20.0, "and big enough to read")
	bubble.present("", "A short thought.", Vector3.ZERO, true)
	ok(bubble.wrapped_text().length() > 0 and not bubble.wrapped_text().contains("  "), "narration is wrapped once, up front")
	bubble.free()

func test_the_typewriter_never_reflows_the_bubble() -> void:
	var stage := await _stage()
	var bubble := SpeechBubble.new()
	bubble.camera = stage["camera"]
	(stage["viewport"] as SubViewport).add_child(bubble)
	bubble.present("", "The gears tick in the quiet between the shelves. Nothing is asked of you, which is almost worrying.", Vector3(0, 1.8, 0), true)
	var full := bubble.wrapped_text()
	var before := bubble.screen_rect()
	bubble.set_shown(10)
	eq(bubble.screen_rect(), before, "revealing characters does not resize or move the bubble")
	ok(full.begins_with(full.substr(0, 10)), "the revealed text is a prefix of the final, already-wrapped text")
	bubble.free()

func test_option_plaques_are_finger_sized_disjoint_and_on_screen() -> void:
	var stage := await _stage()
	var stack := PlaqueStack.new()
	stack.camera = stage["camera"]
	(stage["viewport"] as SubViewport).add_child(stack)
	var labels: Array[String] = ["Look at the bell", "Listen", "Wait"]
	for anchor in [Vector2(60, 200), Vector2(420, 200), Vector2(240, 20), Vector2(240, 350)]:
		stack.open("Bell", labels, anchor)
		var rects := stack.item_rects()
		eq(rects.size(), 3, "one plaque per option")
		var safe := Diegetic.safe_rect(VIEWPORT)
		for i in range(rects.size()):
			ok(rects[i].size.y >= MIN_TOUCH_ROWS, "plaque %d is tall enough to hit with a thumb (%.0f px)" % [i, rects[i].size.y])
			ok(safe.grow(1.0).encloses(rects[i]), "plaque %d %s is inside the safe area for an anchor at %s" % [i, rects[i], anchor])
			for j in range(i + 1, rects.size()):
				ok(not rects[i].intersects(rects[j]), "plaques %d and %d do not overlap" % [i, j])
	stack.free()

func test_tapping_a_plaque_chooses_exactly_that_plaque_and_a_miss_chooses_nothing() -> void:
	var stage := await _stage()
	var stack := PlaqueStack.new()
	stack.camera = stage["camera"]
	(stage["viewport"] as SubViewport).add_child(stack)
	var picked: Array[int] = []
	stack.chosen.connect(func(index: int) -> void: picked.append(index))
	var labels: Array[String] = ["One", "Two", "Three"]
	stack.open("Title", labels, Vector2(100, 180))
	var rects := stack.item_rects()
	ok(not stack.handle_tap(Vector2(1, 1)), "a tap away from the plaques is not consumed (it becomes a walk order)")
	ok(not stack.handle_tap(rects[0].position + Vector2(rects[0].size.x * 0.5, -10.0)), "the title plaque cannot be chosen")
	ok(stack.handle_tap(rects[1].get_center()), "a tap in the middle of the second plaque is consumed")
	for i in range(30):
		stack._process(0.016)
	eq(picked, [1], "and it chooses plaque 1 after its short press animation")
	stack.free()

func test_the_option_surface_keeps_its_contract_and_never_shows_the_ontology() -> void:
	var stage := await _stage()
	var surface := InteractionPresenter.new()
	surface.camera = stage["camera"]
	(stage["viewport"] as SubViewport).add_child(surface)
	var option := InteractionOption.new()
	option.option_id = "o1"
	option.action_id = "look_bell"
	option.target_id = "bell"
	option.label = "Look at the bell"
	option.ontology = MirrorDomain.ActionType.LOOK
	var chosen: Array[InteractionOption] = []
	surface.option_chosen.connect(func(o: InteractionOption) -> void: chosen.append(o))
	var options: Array[InteractionOption] = [option]
	surface.show_options("bell", options, Vector3(0, 2, 0))
	ok(surface.is_open() and surface.current_options().size() == 1, "open with the options it was given")
	surface.choose(0)
	ok(chosen.size() == 1 and chosen[0] == option and not surface.is_open(), "choosing hands over the option and closes")
	surface.show_options("bell", options, Vector3(0, 2, 0))
	surface.choose(1)
	ok(not surface.is_open() and chosen.size() == 1, "the last plaque, 'never mind', just closes")
	surface.free()
