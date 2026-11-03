extends TestCase

# The diegetic notebook (GAME_SPEC section 4): the slab builds headless from the witch's pages, opens at the page of a
# claim, turns by tap (forward on the right two thirds, back on the left third), closes by its plaque or by a forward
# tap on the last page, ignores taps that miss it, and its close plaque is a 48 pixel target at 960x540.

const VIEWPORT := Vector2i(960, 540)

# A picture with a camera that looks at the slab's place (the slab is placed by the camera, as in the game).
func _stage() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT
	var camera := Camera3D.new()
	camera.name = "Camera"
	viewport.add_child(camera)
	Engine.get_main_loop().root.add_child(viewport)
	track(viewport)
	camera.make_current()
	return viewport

func _entries(count: int, kind: String, prefix: String) -> Array:
	var out: Array = []
	for i in count:
		out.append({"claim": "%s.%d" % [prefix, i], "kind": kind, "text": "note.fixture.%s_%d" % [prefix, i]})
	return out

# Four pages: seen on two (three and one), heard, and untestable.
func _page_list() -> Array:
	var entries := _entries(4, "seen", "s")
	entries.append_array(_entries(1, "heard", "h"))
	entries.append_array(_entries(1, "untestable", "u"))
	return NotebookView.pages(entries, 3)

func _slab(viewport: SubViewport) -> NotebookSlab:
	var slab := NotebookSlab.new()
	slab.name = "Slab"
	slab.camera = viewport.get_camera_3d()
	viewport.add_child(slab)
	return slab

func test_the_slab_builds_headless_and_shows_the_first_page() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	slab.open(_page_list(), 0)
	ok(slab.is_open(), "the notebook is open")
	eq(slab.page_count(), 4, "four pages: seen twice, heard, untestable")
	eq(slab.shown_claims(), ["s.0", "s.1", "s.2"], "the first page shows the first three seen entries")

func test_it_opens_at_the_page_of_the_claim_it_names() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	var page_list := _page_list()
	slab.open(page_list, NotebookView.page_of(page_list, "h.0"))
	eq(slab.page_index(), 2, "the heard page")
	eq(slab.shown_claims(), ["h.0"], "and it shows the heard claim")

func test_taps_turn_pages_forward_and_back_and_stop_at_the_first() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	slab.open(_page_list(), 0)
	ok(slab.handle_tap(slab.forward_point()), "a tap on the right two thirds is used by the notebook")
	eq(slab.page_index(), 1, "it turns forward")
	slab.handle_tap(slab.back_point())
	eq(slab.page_index(), 0, "a tap on the left third turns back")
	slab.handle_tap(slab.back_point())
	eq(slab.page_index(), 0, "and the first page does not turn further back")

func test_a_forward_tap_on_the_last_page_closes_the_notebook() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	slab.open(_page_list(), 3)
	slab.handle_tap(slab.forward_point())
	ok(not slab.is_open(), "the last page's forward tap closes it")

func test_the_close_plaque_closes_it_on_any_page_and_says_so_once_after_the_input() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	var closes: Array = []
	slab.closed.connect(func() -> void: closes.append(true))
	slab.open(_page_list(), 1)
	slab.handle_tap(slab.close_point())
	ok(not slab.is_open(), "the plaque closes it")
	eq(closes.size(), 0, "closed is emitted after the tap, not inside it")
	await Engine.get_main_loop().process_frame
	eq(closes.size(), 1, "and once afterwards")

func test_taps_that_miss_the_slab_are_not_used() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	slab.open(_page_list(), 0)
	ok(not slab.handle_tap(Vector2(4, 4)), "a tap in the corner of the picture is not the notebook's")
	ok(slab.is_open() and slab.page_index() == 0, "and it changes nothing")

func test_the_close_plaque_is_a_48_pixel_target_at_960_by_540_and_the_slab_fits() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	slab.open(_page_list(), 0)
	var close := slab.close_rect_px()
	ok(close.size.y >= 48.0, "the close plaque is at least 48 pixels tall (%s)" % str(close.size))
	ok(close.size.x >= 48.0, "and at least 48 wide")
	var picture := Rect2(Vector2.ZERO, Vector2(VIEWPORT))
	ok(picture.encloses(slab.screen_rect()), "the slab lies inside the picture (%s)" % str(slab.screen_rect()))

func test_space_turns_the_page_as_it_advances_a_line() -> void:
	var viewport := _stage()
	var slab := _slab(viewport)
	slab.open(_page_list(), 0)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	slab._unhandled_input(key)
	eq(slab.page_index(), 1, "space turns to the next page")
	slab.close()
