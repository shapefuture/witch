extends TestCase

# The main menu is a stage of three plaques with no art, story or backstory. These tests pin what its
# owner relies on: it builds headless from its scene, it offers exactly three choices, Continue is dimmed
# and inert without a save, a tap and a click on one plaque mean the same thing, and every label is in
# ru.json.

const SCENE := "res://game/ui/main_menu.tscn"
const VIEWPORT := Vector2(480, 360)   # the 360-row base the plaques are sized in
const MIN_TOUCH_DP := 48.0            # NAVIGATION.md section 5
const IDS := ["new_game", "continue", "settings"]
const KEYS := ["menu.new_game", "menu.continue", "menu.settings"]

var _now := 0.0

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# The menu sits in a SubViewport with a real camera, as the other diegetic UI tests do.
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

# The menu from its scene, with a stubbed save check (never the player's real save file) and a test clock.
func _menu(stage: Dictionary, has_save: bool) -> MainMenuUI:
	var packed: PackedScene = load(SCENE)
	var menu := packed.instantiate() as MainMenuUI
	menu.save_probe = func() -> bool: return has_save
	menu.camera = stage["camera"]
	menu.pointer.clock = func() -> float: return _now
	(stage["viewport"] as SubViewport).add_child(menu)
	return menu

# Records the names of the choices the menu emits, in order.
func _record(menu: MainMenuUI) -> Array[String]:
	var chosen: Array[String] = []
	menu.new_game_requested.connect(func() -> void: chosen.append("new_game"))
	menu.continue_requested.connect(func() -> void: chosen.append("continue"))
	menu.settings_requested.connect(func() -> void: chosen.append("settings"))
	return chosen

func _center(menu: MainMenuUI, id: String) -> Vector2:
	var rects: Array[Rect2] = menu.option_rects()
	return rects[menu.option_ids().find(id)].get_center()

func _click(menu: MainMenuUI, pos: Vector2, dt: float = 0.1) -> PlayerIntent:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	menu.pointer.handle_event(down)
	_now += dt
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	return menu.pointer.handle_event(up)

func _tap(menu: MainMenuUI, pos: Vector2, dt: float = 0.1) -> PlayerIntent:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	menu.pointer.handle_event(down)
	_now += dt
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	return menu.pointer.handle_event(up)

func test_the_scene_builds_headless_and_offers_three_choices() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	ok(menu != null, "the scene's root is a MainMenuUI")
	eq(menu.option_ids(), [], "nothing is laid out until it is opened")
	menu.open()
	eq(menu.option_ids(), IDS, "three choices, top to bottom")
	eq(menu.option_rects().size(), 3, "one plaque per choice")
	ok(menu.is_open(), "open")
	menu.close()
	ok(not menu.is_open() and menu.option_ids().is_empty(), "closing clears the stage")

func test_the_empty_save_cue_is_in_the_text_table() -> void:
	ok(tr("menu.continue_empty") != "menu.continue_empty", "the empty-save cue is in ru.json")

func test_continue_is_dimmed_and_inert_without_a_save() -> void:
	var stage := await _stage()
	var menu := _menu(stage, false)
	menu.open()
	ok(menu.option_enabled("new_game") and menu.option_enabled("settings"), "new game and settings are always available")
	ok(not menu.option_enabled("continue"), "continue is disabled when there is no save")
	var chosen := _record(menu)
	_click(menu, _center(menu, "continue"))
	_tap(menu, _center(menu, "continue"))
	eq(chosen, [], "neither a click nor a tap on a disabled continue chooses anything")

func test_continue_is_enabled_when_a_save_exists() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	menu.open()
	ok(menu.option_enabled("continue"), "continue is available with a save")
	var chosen := _record(menu)
	_tap(menu, _center(menu, "continue"))
	eq(chosen, ["continue"], "and a tap chooses it")

func test_continue_checks_the_slot_the_game_saves_to() -> void:
	var root_script: GDScript = load("res://game/main/game_root.gd")
	var root_slot: int = root_script.get_script_constant_map()["SLOT"]
	eq(MainMenuUI.SAVE_SLOT, root_slot, "the same slot as game_root.gd")
	eq(MainMenuUI.SAVE_SLOT, PauseMenuUI.SLOT, "and the same slot as the pause menu")

func test_a_tap_and_a_click_on_the_same_plaque_mean_the_same_thing() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	var chosen := _record(menu)
	for id in IDS:
		menu.open()
		chosen.clear()
		var clicked := _click(menu, _center(menu, id))
		var by_click := chosen.duplicate()
		menu.open()
		chosen.clear()
		var tapped := _tap(menu, _center(menu, id))
		eq(chosen, by_click, "%s: a tap chooses what a click chooses" % id)
		eq(chosen, [id], "%s: and it is that choice" % id)
		ok(clicked != null and tapped != null, "%s: both produce an intent" % id)
		ok(clicked != null and tapped != null and clicked.same_meaning(tapped), "%s: and the same PlayerIntent" % id)
		eq(clicked.source, "mouse", "%s: provenance kept for debugging" % id)
		eq(tapped.source, "touch", "%s: provenance kept for debugging" % id)

func test_the_emulated_mouse_click_from_a_touch_never_adds_a_choice() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	menu.open()
	var chosen := _record(menu)
	var pos := _center(menu, "new_game")
	var emulated := InputEventMouseButton.new()
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.position = pos
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.pressed = true
	menu.pointer.handle_event(emulated)
	emulated.pressed = false
	menu.pointer.handle_event(emulated)
	eq(chosen, [], "an emulated click alone is not a choice")
	_tap(menu, pos)
	emulated.pressed = true
	menu.pointer.handle_event(emulated)
	emulated.pressed = false
	menu.pointer.handle_event(emulated)
	eq(chosen, ["new_game"], "one tap, one choice, even with its emulated click after it")

func test_a_choice_locks_the_menu_until_it_is_opened_again() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	menu.open()
	var chosen := _record(menu)
	_tap(menu, _center(menu, "new_game"))
	_tap(menu, _center(menu, "new_game"))
	eq(chosen, ["new_game"], "a second tap before the owner acts does not start the game again")
	ok(menu.is_open(), "the menu does not close itself: the owner decides")
	menu.open()
	_tap(menu, _center(menu, "settings"))
	eq(chosen, ["new_game", "settings"], "opening the menu again accepts input again")

func test_a_closed_menu_takes_no_taps() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	var chosen := _record(menu)
	eq(_tap(menu, Vector2(240, 180)), null, "never opened: a tap is not an intent")
	menu.open()
	var at := _center(menu, "new_game")
	menu.close()
	eq(_tap(menu, at), null, "closed: a tap where a plaque was is not an intent")
	eq(chosen, [], "and nothing is chosen")

func test_a_drag_off_a_plaque_and_a_tap_between_plaques_choose_nothing() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	menu.open()
	var chosen := _record(menu)
	var at := _center(menu, "new_game")
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = at
	menu.pointer.handle_event(down)
	_now += 0.1
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = at + Vector2(0, 80)
	eq(menu.pointer.handle_event(up), null, "a drag is not a tap")
	var rects: Array[Rect2] = menu.option_rects()
	var gap := Vector2(at.x, rects[0].end.y + (rects[1].position.y - rects[0].end.y) * 0.5)
	eq(_tap(menu, gap), null, "a tap between two plaques is not a choice")
	eq(chosen, [], "so nothing is chosen")

func test_every_menu_label_is_in_the_text_table() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	menu.open()
	var table := Localization.load_table()
	var expected: Array[String] = []
	for key in KEYS:
		ok(table.has(key), "%s is in ru.json" % key)
		var text := str(table.get(key, ""))
		ok(not text.strip_edges().is_empty(), "%s has text" % key)
		expected.append(text)
	eq(menu.option_labels(), expected, "the plaques show the table's text, not the keys")

func test_the_three_plaques_are_finger_sized_disjoint_and_on_screen() -> void:
	var stage := await _stage()
	var menu := _menu(stage, true)
	menu.open()
	var rects: Array[Rect2] = menu.option_rects()
	eq(rects.size(), 3, "three plaques")
	var safe := Diegetic.safe_rect(VIEWPORT)
	for i in range(rects.size()):
		ok(rects[i].size.y >= MIN_TOUCH_DP, "plaque %d is %.0f px tall on the 360-row base (at least 48 dp)" % [i, rects[i].size.y])
		ok(safe.grow(1.0).encloses(rects[i]), "plaque %d is inside the safe area" % i)
		for j in range(i + 1, rects.size()):
			ok(not rects[i].intersects(rects[j]), "plaques %d and %d do not overlap" % [i, j])
