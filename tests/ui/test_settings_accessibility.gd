extends TestCase

# Accessibility settings (text size, reduced effects): they persist with the volume, reduced effects
# really zero the wobble and the screen pass, the text size really changes the drawn text, and the
# settings plaques stay finger-sized at every text size. Every test writes to its own settings file
# (never the player's) and puts the real settings back when it is done.

const TEST_PATH := "user://test_settings_accessibility.cfg"
const VIEWPORT := Vector2(480, 360)
const MIN_TOUCH_DP := 48.0            # NAVIGATION.md section 5

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _isolate() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SettingsState.save_path = TEST_PATH
	SettingsState.reload()

func _restore() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	SettingsState.save_path = SettingsState.SAVE_PATH
	SettingsState.reload()

func _stage() -> Dictionary:  # callers: var stage := await _stage()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(VIEWPORT)
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	_tree().root.add_child(viewport)
	track(viewport)
	await _tree().process_frame
	camera.set_pose({"look_at": Vector3(0, 1, 0), "distance": 10.0, "pitch_deg": 5.0, "yaw_deg": 0.0, "roll_deg": 0.0, "fov": 60.0}, true)
	return {"viewport": viewport, "camera": camera}

func _menu(stage: Dictionary) -> SettingsMenuUI:
	var menu := SettingsMenuUI.new()
	menu.camera = stage["camera"]
	(stage["viewport"] as SubViewport).add_child(menu)
	return menu

func test_defaults_are_the_full_look_at_the_designed_size() -> void:
	_isolate()
	eq(SettingsState.text_scale, 1.0, "designed text size")
	eq(SettingsState.reduced_effects, false, "all effects on (SC6)")
	eq(UIKit.text_size(), UIKit.FONT_SIZE, "text drawn at the designed size")
	eq(PSXGlobals.reduced_effects(), false, "renderer has every effect")
	_restore()

func test_settings_persist_and_reload() -> void:
	_isolate()
	SettingsState.set_master_volume(0.5)
	SettingsState.set_text_scale(1.25)
	SettingsState.set_reduced_effects(true)
	var cfg := ConfigFile.new()
	eq(cfg.load(TEST_PATH), OK, "the settings file was written")
	eq(float(cfg.get_value("settings", "text_scale", 0.0)), 1.25, "text size saved")
	eq(bool(cfg.get_value("settings", "reduced_effects", false)), true, "reduced effects saved")
	# forget everything in memory, then read it back the way the game starts
	SettingsState.master_volume = 1.0
	SettingsState.text_scale = 1.0
	SettingsState.reduced_effects = false
	UIKit.text_scale = 1.0
	PSXGlobals.set_reduced_effects(false)
	SettingsState.reload()
	ok(is_equal_approx(SettingsState.master_volume, 0.5), "volume reloads")
	eq(SettingsState.text_scale, 1.25, "text size reloads")
	eq(SettingsState.reduced_effects, true, "reduced effects reload")
	eq(UIKit.text_scale, 1.25, "and is applied to the text")
	eq(PSXGlobals.reduced_effects(), true, "and to the renderer")
	_restore()

func test_text_size_steps_cycle_and_snap_to_the_table() -> void:
	_isolate()
	var seen: Array[float] = []
	for i in range(UIKit.TEXT_SCALES.size()):
		SettingsState.cycle_text_scale()
		seen.append(SettingsState.text_scale)
	eq(seen, [1.25, 1.5, 1.0] as Array[float], "100 -> 125 -> 150 -> 100")
	SettingsState.set_text_scale(9.0)
	eq(SettingsState.text_scale, 1.5, "an odd value snaps to the nearest step")
	_restore()

func test_reduced_effects_zero_wobble_jitter_and_the_screen_pass() -> void:
	_isolate()
	PSXGlobals.set_render_size(VIEWPORT)
	PSXGlobals.set_lens(0.7)
	var actor := PSXMaterials.actor(Palette.COAT, 0.004)
	var screen := PSXMaterials.screen()
	eq(actor.get_shader_parameter("wobble_amount"), 0.004, "authored wobble while effects are on")
	eq(screen.get_shader_parameter("glow_amount"), 0.4, "authored glow")
	eq(screen.get_shader_parameter("vignette"), 0.5, "authored vignette")
	eq(screen.get_shader_parameter("grain_amount"), 0.016, "authored grain")
	eq(PSXGlobals.pushed_snap_grid(), PSXGlobals.snap_grid(), "the coarse PS1 lattice")
	ok(is_equal_approx(PSXGlobals.pushed_lens(), 0.7), "the spell's lens swing")

	SettingsState.set_reduced_effects(true)
	eq(actor.get_shader_parameter("wobble_amount"), 0.0, "no vertex wobble on actors")
	eq(screen.get_shader_parameter("glow_amount"), 0.0, "no glow")
	eq(screen.get_shader_parameter("vignette"), 0.0, "no vignette")
	eq(screen.get_shader_parameter("grain_amount"), 0.0, "no flickering grain")
	eq(PSXGlobals.pushed_snap_grid(), PSXGlobals.snap_grid() * PSXGlobals.REDUCED_GRID_SCALE, "snap lattice far finer than the pixels: no jitter")
	eq(PSXGlobals.pushed_lens(), 0.0, "no fisheye swing")
	eq(PSXMaterials.actor(Palette.COAT, 0.004).get_shader_parameter("wobble_amount"), 0.0, "a material made later is calm too")
	eq(PSXMaterials.screen().get_shader_parameter("vignette"), 0.0, "and a screen pass made later")
	var code := (load(PSXMaterials.SCREEN) as Shader).code
	ok(code.contains("uniform float grain_amount") and code.contains("grain * grain_amount"), "the grain is driven by the switch")

	SettingsState.set_reduced_effects(false)
	eq(actor.get_shader_parameter("wobble_amount"), 0.004, "wobble restored, nothing deleted")
	eq(screen.get_shader_parameter("glow_amount"), 0.4, "glow restored")
	eq(screen.get_shader_parameter("vignette"), 0.5, "vignette restored")
	eq(screen.get_shader_parameter("grain_amount"), 0.016, "grain restored")
	ok(is_equal_approx(PSXGlobals.pushed_lens(), 0.7), "lens swing restored")
	PSXGlobals.set_lens(0.0)
	_restore()

func test_text_size_changes_the_drawn_text() -> void:
	_isolate()
	for scale in UIKit.TEXT_SCALES:
		SettingsState.set_text_scale(scale)
		for render_scale in [1.0, 1.5]:
			var label := Diegetic.label("x", Color.WHITE, 0, render_scale)
			ok(is_equal_approx(label.font_size * label.pixel_size, UIKit.FONT_SIZE * scale), "text %d%% is %.1f UI px tall at render scale %.1f" % [roundi(scale * 100.0), UIKit.FONT_SIZE * scale, render_scale])
			label.free()
	_restore()

func test_settings_plaques_stay_finger_sized_at_every_text_size() -> void:
	_isolate()
	var stage := await _stage()
	var safe := Diegetic.safe_rect(VIEWPORT)
	for scale in UIKit.TEXT_SCALES:
		SettingsState.set_text_scale(scale)
		var menu := _menu(stage)
		for which in [SettingsMenuUI.Page.MAIN, SettingsMenuUI.Page.VOLUME]:
			if which == SettingsMenuUI.Page.VOLUME:
				menu.stack().chosen.emit(0)
			eq(menu.page(), which, "on the expected page")
			var rects: Array[Rect2] = menu.stack().item_rects()
			eq(rects.size(), 4 if which == SettingsMenuUI.Page.MAIN else 3, "row count")
			for i in range(rects.size()):
				ok(rects[i].size.y >= MIN_TOUCH_DP, "text %d%%: row %d is %.0f px tall (at least 48 dp)" % [roundi(scale * 100.0), i, rects[i].size.y])
				ok(safe.grow(1.0).encloses(rects[i]), "text %d%%: row %d is inside the safe area" % [roundi(scale * 100.0), i])
				for j in range(i + 1, rects.size()):
					ok(not rects[i].intersects(rects[j]), "rows %d and %d do not overlap" % [i, j])
		menu.free()
	_restore()

func test_the_menu_rows_change_the_settings() -> void:
	_isolate()
	var stage := await _stage()
	var menu := _menu(stage)
	var closed: Array[bool] = []
	menu.closed.connect(func() -> void: closed.append(true))
	menu.stack().chosen.emit(1)
	eq(SettingsState.text_scale, 1.25, "the text row steps the size")
	eq(UIKit.text_size(), roundi(UIKit.FONT_SIZE * 1.25), "and the text grows")
	menu.stack().chosen.emit(2)
	eq(SettingsState.reduced_effects, true, "the effects row turns effects down")
	menu.stack().chosen.emit(2)
	eq(SettingsState.reduced_effects, false, "and back up")
	menu.stack().chosen.emit(0)
	eq(menu.page(), SettingsMenuUI.Page.VOLUME, "the sound row opens the volume page")
	menu.stack().chosen.emit(0)
	ok(is_equal_approx(SettingsState.master_volume, 0.9), "quieter")
	menu.stack().chosen.emit(2)
	eq(menu.page(), SettingsMenuUI.Page.MAIN, "back to the main page")
	menu.stack().chosen.emit(3)
	eq(closed, [true] as Array[bool], "back closes the menu")
	_restore()
