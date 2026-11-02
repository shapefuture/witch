extends TestCase

# The `notebook` presentation step (GAME_SPEC section 4): it opens the witch's notebook at the page of the claim the
# step names, holds the presentation until she closes it, and reads only what she holds. The systems seam registers it.

const FIXTURES := "res://tests/systems/fixtures"
const S := MirrorDomain.EpistemicStatus

func _held(r: MirrorRuntime, claim_id: String, status: int) -> void:
	r.engine.record_observation("player", "bell", {"signature": ["FIXTURE", claim_id]}, {}, [], [{"id": claim_id, "holder_id": "player", "proposition": {"fixture": claim_id}, "status": status, "scope": "room"}])

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

func test_the_step_opens_at_the_named_claim_and_waits_until_she_closes_it() -> void:
	var r := GameFixtures.runtime()
	for claim_id in ["c.seen", "c.heard", "c.shown", "c.inferred", "c.predicted", "c.altered", "c.untestable"]:
		_held(r, claim_id, S.SUPPORTED)
	var viewport := _stage()
	var presenter := NotebookPresenter.new()
	presenter.sidecar_dir = FIXTURES + "/notebook_good"
	presenter.runtime_provider = func() -> MirrorRuntime: return r
	viewport.add_child(presenter)
	var finished: Array = []
	presenter.finished.connect(func() -> void: finished.append(true))
	presenter.play_entry({"kind": "notebook", "claim": "c.altered"})
	var slab := presenter.find_child("Notebook", false, false) as NotebookSlab
	ok(slab != null and slab.is_open(), "the notebook is open")
	eq(slab.shown_claims(), ["c.altered"], "at the page of the claim it names (one page a kind here)")
	eq(finished.size(), 0, "the presentation waits while she reads")
	slab.close()
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	eq(finished.size(), 1, "the step finishes when she closes it")

func test_with_no_claim_named_it_opens_at_the_first_page() -> void:
	var r := GameFixtures.runtime()
	_held(r, "c.seen", S.SUPPORTED)
	_held(r, "c.untestable", S.SUPPORTED)
	var viewport := _stage()
	var presenter := NotebookPresenter.new()
	presenter.sidecar_dir = FIXTURES + "/notebook_good"
	presenter.runtime_provider = func() -> MirrorRuntime: return r
	viewport.add_child(presenter)
	presenter.play_entry({"kind": "notebook"})
	var slab := presenter.find_child("Notebook", false, false) as NotebookSlab
	eq(slab.page_index(), 0, "the first page")
	eq(slab.shown_claims(), ["c.seen"], "the first kind she holds")
	slab.close()
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	ok(not slab.is_open(), "closed")

func test_a_claim_nobody_sidecar_names_is_never_listed() -> void:
	var r := GameFixtures.runtime()
	_held(r, "c.not_in_any_sidecar", S.SUPPORTED)
	var viewport := _stage()
	var presenter := NotebookPresenter.new()
	presenter.sidecar_dir = FIXTURES + "/notebook_good"
	presenter.runtime_provider = func() -> MirrorRuntime: return r
	viewport.add_child(presenter)
	presenter.play_entry({"kind": "notebook"})
	var slab := presenter.find_child("Notebook", false, false) as NotebookSlab
	eq(slab.page_count(), 0, "the witch holds it, but no sidecar names it: no page")
	slab.close()
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
