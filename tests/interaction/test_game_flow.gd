extends TestCase

# End-to-end through the REAL scene: synthetic mouse / touch input -> intent -> walk -> options
# -> Mirror commit -> presentation -> state. Headless, so physics and picking run but nothing
# is rendered.

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _boot() -> GameRoot:
	GameFixtures.ensure_localization()
	var game := GameRoot.new()
	game.runtime = track(MirrorRuntime.new())
	game.auto_advance = 0.0
	game.magic_time_scale = 0.01
	_tree().root.add_child(game)
	track(game)
	for i in 3:
		await _tree().physics_frame
	return game

func _until(condition: Callable, max_frames: int = 900) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await _tree().physics_frame
	return condition.call()

func _screen_point(game: GameRoot, target_id: String) -> Vector2:
	return game.camera.unproject_position(game.room.get_interactable(target_id).focus_point())

func _click(game: GameRoot, position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = position
	game.input.handle_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = position
	game.input.handle_event(up)

func _tap(game: GameRoot, position: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = position
	game.input.handle_event(down)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = position
	game.input.handle_event(up)

func _settled(game: GameRoot) -> bool:
	return not game.runtime.is_busy() and not game.subtitles.is_active()

func _open_surface(game: GameRoot, target_id: String, use_touch: bool = false) -> bool:
	if use_touch:
		_tap(game, _screen_point(game, target_id))
	else:
		_click(game, _screen_point(game, target_id))
	return await _until(func() -> bool: return game.surface.is_open())

func _choose(game: GameRoot, action_id: String) -> void:
	for i in range(game.surface.current_options().size()):
		if game.surface.current_options()[i].action_id == action_id:
			game.surface.choose(i)
			return
	ok(false, "option %s was not offered; offered: %s" % [action_id, game.surface.current_options().map(func(o): return o.action_id)])

func test_boot_builds_the_scene_and_plays_the_arrival_beat_from_mirror() -> void:
	var game := await _boot()
	ok(game.room != null and game.witch != null and game.camera != null, "room, witch and camera exist")
	ok(await _until(func() -> bool: return game.input.enabled and _settled(game)), "the arrival beat finished and input is live")
	var events := game.runtime.engine.event_store.get_all()
	ok(events.any(func(e): return e.event_type == "ContentConsumed" and e.payload["storylet_id"] == "story.arrival"), "the arrival was consumed from the log, not hard-coded")
	eq(game.room.tomas.pose, "braced", "Tomas is posed from Mirror state")
	ok(game.camera.current, "the authored camera is the active camera")

func test_clicking_tomas_walks_there_and_opens_russian_options() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	ok(await _open_surface(game, "tomas"), "the action surface opened")
	var approach := game.room.get_interactable("tomas").approach_point
	ok(game.witch.global_position.distance_to(approach) < 0.5, "she walked to him first (%s vs %s)" % [game.witch.global_position, approach])
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	var labels := game.surface.current_options().map(func(o): return o.label)
	ok(labels.size() >= 3, "several options")
	for label in labels:
		ok(cyrillic.search(label) != null, "Russian label: %s" % label)

func test_touch_and_mouse_open_the_same_options() -> void:
	var by_mouse := await _boot()
	await _until(func() -> bool: return by_mouse.input.enabled)
	await _open_surface(by_mouse, "tomas")
	var mouse_ids := by_mouse.surface.current_options().map(func(o): return o.option_id)
	var by_touch := await _boot()
	await _until(func() -> bool: return by_touch.input.enabled)
	await _open_surface(by_touch, "tomas", true)
	var touch_ids := by_touch.surface.current_options().map(func(o): return o.option_id)
	eq(touch_ids, mouse_ids, "identical options whichever device was used")

func test_a_tap_that_misses_but_lands_near_an_object_still_selects_it() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	var hit := game.probe.pick(_screen_point(game, "machine") + Vector2(6, 4))
	eq(hit["target_id"], "machine", "fat-finger tolerance")
	var far := game.probe.pick(Vector2(300, 20))
	ok(far["target_id"] != "machine", "but not from across the screen")

func test_clicking_empty_ground_walks_there_and_closes_the_surface() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	await _open_surface(game, "tomas")
	# any floor spot the option plaques are not hanging over (a tap on a plaque chooses it instead)
	var ground := Vector3.ZERO
	for candidate in [Vector3(-4, 0, 0.5), Vector3(3, 0, 1.5), Vector3(-1, 0, 2.5), Vector3(2, 0, -5), Vector3(-2, 0, 3)]:
		var at := game.camera.unproject_position(candidate)
		if game.surface.plaque_rects().all(func(r: Rect2) -> bool: return not r.grow(8.0).has_point(at)):
			ground = candidate
			break
	ok(ground != Vector3.ZERO, "found floor the plaques do not cover")
	_click(game, game.camera.unproject_position(ground))
	ok(not game.surface.is_open(), "surface closed")
	ok(await _until(func() -> bool: return not game.witch.is_walking()), "she arrived")
	ok(game.witch.global_position.distance_to(ground) < 1.0, "near where she was sent (%s)" % game.witch.global_position)

func test_choosing_an_option_commits_to_mirror_then_presents_then_unlocks_input() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	await _open_surface(game, "tomas")
	_choose(game, "ask_tomas_what")
	ok(game.runtime.engine.knowledge.has("tomas_explained_alignment"), "committed before it is presented")
	ok(await _until(func() -> bool: return _settled(game) and game.input.enabled), "presentation finished and input returned")
	ok(game.presentation.played.has("dialogue"), "the conversation played")
	ok(game.presentation.unhandled.is_empty(), "no presentation entry was left without a handler: %s" % [game.presentation.unhandled])

func test_input_is_ignored_while_an_action_is_presenting() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	game.subtitles.auto_advance_delay = -1.0
	await _open_surface(game, "tomas")
	_choose(game, "show_tomas_wand")
	ok(await _until(func() -> bool: return game.subtitles.is_active()), "dialogue is on screen, waiting for the player")
	var before := game.runtime.engine.event_store.size()
	_click(game, _screen_point(game, "machine"))
	await _tree().physics_frame
	ok(not game.surface.is_open(), "no new surface while presenting")
	eq(game.runtime.engine.event_store.size(), before, "nothing else committed")
	game.subtitles.auto_advance_delay = 0.0
	game.subtitles.advance()
	game.subtitles.advance()
	ok(await _until(func() -> bool: return _settled(game) and game.input.enabled), "after the dialogue the player is back in control")

func test_a_full_playthrough_driven_through_the_ui_equals_the_scripted_simulation() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	var script := SimulationRunner.load_script("res://data/sim/patient_no_bell.json")
	for step in script["steps"]:
		var target := str(step["target"])
		ok(await _open_surface(game, target), "surface for %s" % target)
		_choose(game, str(step["action"]))
		ok(await _until(func() -> bool: return _settled(game) and game.input.enabled, 3000), "step %s finished" % step["action"])
	var twin: MirrorRuntime = GameFixtures.runtime()
	twin.next_story()
	var outcome := SimulationRunner.new().run(twin, script)
	ok(outcome["ok"], "the scripted twin meets its expectations")
	eq(game.runtime.engine.event_store.head_hash(), twin.engine.event_store.head_hash(), "clicking through the UI produced the IDENTICAL event chain as the headless simulation")

func test_taking_the_path_out_freezes_the_camera_and_removes_the_witch() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	await _open_surface(game, "path_out")
	_choose(game, "go_path_out")
	ok(await _until(func() -> bool: return game.director.frozen), "the camera was told to stay")
	var frozen_pose := game.camera.current_pose()
	ok(await _until(func() -> bool: return not game.witch.visible, 2400), "the witch walked out of the frame")
	eq(game.camera.current_pose()["look_at"], frozen_pose["look_at"], "and the camera never followed her")
	eq(game.runtime.engine.get_world("clearing")["departed"], true, "Mirror recorded the departure")

func test_a_loaded_game_in_which_the_witch_has_left_has_no_witch() -> void:
	var played := GameFixtures.runtime()
	GameFixtures.do(played, "go_path_out", "path_out")
	var text := SaveCodec.encode(played.engine)
	var game := GameRoot.new()
	game.runtime = track(MirrorRuntime.new())
	game.runtime.setup()
	ok(SaveGame.load_text(game.runtime.engine, text)["ok"], "save loads")
	game.auto_advance = 0.0
	_tree().root.add_child(game)
	track(game)
	await _tree().physics_frame
	ok(not game.witch.visible, "she is gone")
	ok(game.director.frozen, "and the camera does not go looking for her")

func test_the_pause_menu_freezes_the_world_and_resumes() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	game.pause_menu.open()
	ok(_tree().paused, "the tree is paused")
	game.pause_menu.close()
	ok(not _tree().paused, "resumed")

func test_saving_and_loading_from_the_pause_menu_roundtrips_the_game() -> void:
	var game := await _boot()
	await _until(func() -> bool: return game.input.enabled)
	await _open_surface(game, "bell")
	_choose(game, "look_bell")
	await _until(func() -> bool: return _settled(game) and game.input.enabled, 3000)
	var head := game.runtime.engine.event_store.head_hash()
	game._on_save()
	GameFixtures.do(game.runtime, "look_tomas", "tomas")
	ok(game.runtime.engine.event_store.head_hash() != head, "progressed past the save")
	game._on_load()
	eq(game.runtime.engine.event_store.head_hash(), head, "loading restored the saved moment")
	DirAccess.remove_absolute(SaveGame.path_for(GameRoot.SLOT))
