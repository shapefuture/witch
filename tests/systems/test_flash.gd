extends TestCase

# The flash (GAME_SPEC section 4; BIBLE section 6): a place's plate seen through a soft card in front of the camera for
# about two seconds, with a sound cue and no caption. The step's sensation is an image, never a sentence, so it is not
# shown. The plate comes from the place file when there is one, else from the painted directory of the same name.

const FIXTURES := "res://tests/systems/fixtures"
const PLATE := "res://assets/painted/fog_edge/plate.png"

func test_the_plate_of_a_place_comes_from_its_room_then_from_its_painted_dir() -> void:
	eq(FlashPresenter.plate_path("fixture_room", FIXTURES + "/places"), PLATE, "the place file names the painted room's directory")
	eq(FlashPresenter.plate_path("fog_edge", FIXTURES + "/places"), PLATE, "a place with no file falls back to the painted directory of its name")
	eq(FlashPresenter.plate_path("stage_room", FIXTURES + "/places"), "", "a stage has no plate, so the card is a stand-in")
	eq(FlashPresenter.plate_path("nowhere", FIXTURES + "/places"), "", "and an image nobody made has none either")
	eq(FlashPresenter.plate_path(""), "", "an empty image has no plate")

func test_the_card_fills_the_picture_at_its_depth_with_a_margin_for_the_warp() -> void:
	var size := FlashPresenter.card_size(60.0, 16.0 / 9.0, 1.0)
	ok(size.y > 2.0 * tan(deg_to_rad(30.0)), "taller than the picture is at one metre")
	ok(absf(size.x / size.y - 16.0 / 9.0) < 0.0001, "and as wide as the picture's shape")

func test_a_flash_hangs_a_card_on_the_camera_with_no_caption_and_a_sound_cue() -> void:
	var viewport := _stage()
	var camera := viewport.get_camera_3d()
	var presenter := FlashPresenter.new()
	presenter.time_scale = 0.05
	viewport.add_child(presenter)
	presenter.play_entry({"kind": "flash", "image": "fog_edge", "sensation": "note.fixture.cold"})
	ok(presenter.card() != null and presenter.card().get_parent() == camera, "the card hangs on the camera, in front of it")
	eq(camera.find_children("*", "Label3D", true, false).size(), 0, "no caption is drawn: no label under the camera")
	await _settle(0.4)
	ok(presenter.card() == null, "the card is gone when the flash has played (about two seconds at full length)")
	eq(presenter.last_cue(), "chime", "with the painted rooms' chime as its sound cue")

func test_a_flash_with_no_plate_is_a_stand_in_card_and_still_plays() -> void:
	var viewport := _stage()
	var presenter := FlashPresenter.new()
	presenter.time_scale = 0.05
	viewport.add_child(presenter)
	presenter.play_entry({"kind": "flash", "image": "a_place_with_no_plate"})
	ok(presenter.card() != null, "the card is there, flat and violet")
	await _settle(0.4)
	ok(presenter.card() == null, "and it ends like the others")

func test_reduced_effects_take_the_warp_out_of_the_flash() -> void:
	var viewport := _stage()
	var presenter := FlashPresenter.new()
	presenter.time_scale = 0.05
	viewport.add_child(presenter)
	PSXGlobals.set_reduced_effects(true)
	presenter.play_entry({"kind": "flash", "image": "fog_edge"})
	var warp := float((presenter.card().material_override as ShaderMaterial).get_shader_parameter("warp"))
	PSXGlobals.set_reduced_effects(false)
	eq(warp, 0.0, "a player who is sensitive to motion sees the plate without the wobble")
	await _settle(0.4)

func test_a_flash_step_plays_through_the_registered_seam_and_takes_its_card_away() -> void:
	var viewport := _stage()
	var host := Node.new()
	viewport.add_child(host)
	var director := PresentationDirector.new()
	SystemsPresenters.register(director, host)
	var flash := host.find_child("FlashPresenter", false, false) as FlashPresenter
	flash.time_scale = 0.05
	await director.play([{"kind": "flash", "image": "fog_edge", "sensation": "note.fixture.cold"}])
	eq(director.played, ["flash"], "the director played the flash step through its handler")
	eq(director.unhandled, [], "and no kind was left without a handler")
	ok(flash.card() == null, "the card is gone when the step ends")
	await _cue_played_out(flash)

func test_a_flash_brightens_once_over_its_two_seconds_and_never_flickers() -> void:
	var viewport := _stage()
	var presenter := FlashPresenter.new()
	viewport.add_child(presenter)
	presenter.play_entry({"kind": "flash", "image": "fog_edge", "sensation": "note.fixture.cold"})
	ok(presenter.card() != null and presenter.card().get_parent() == viewport.get_camera_3d(), "the card hangs on the camera, in front of it")
	var tree := Engine.get_main_loop() as SceneTree
	var seconds := 0.0
	var rises := 0
	var bright := false
	while presenter.card() != null and seconds < 4.0:
		var strength := float((presenter.card().material_override as ShaderMaterial).get_shader_parameter("strength"))
		if strength > 0.5 and not bright:
			rises += 1
		bright = strength > 0.5
		await tree.process_frame
		# The tween runs on the engine's clock, so the length is counted on that clock too.
		seconds += tree.root.get_process_delta_time()
	eq(rises, 1, "the card brightens once: one flash, not a flicker")
	ok(seconds >= 1.8 and seconds <= 2.4, "and the flash lasts about two seconds on the engine clock (%.2f s)" % seconds)
	await _cue_played_out(presenter)

# The cue is a 0.7 second chime. A test waits for it to play out, so no playback is still running when the run ends.
func _cue_played_out(presenter: FlashPresenter) -> void:
	var cue := presenter.find_child("Cue", false, false)
	var tree := Engine.get_main_loop() as SceneTree
	var waited := 0.0
	while cue != null and _any_voice_playing(cue) and waited < 3.0:
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
	ok(cue == null or not _any_voice_playing(cue), "the chime has played out")

func _any_voice_playing(cue: Node) -> bool:
	for voice in cue.get_children():
		if (voice as AudioStreamPlayer).playing:
			return true
	return false

# A picture with a camera made current, as the game has one.
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

func _settle(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(seconds).timeout
	await tree.process_frame
