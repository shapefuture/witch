extends TestCase

# The notebook's seven kinds (GAME_SPEC section 4; BIBLE section 9), from fixture sidecars: a claim shows the kind its
# sidecar gives it, an open question shows untestable whatever its sidecar says, the sidecars are validated, and the
# notebook's groups are the seven kinds in their order.

const FIXTURES := "res://tests/systems/fixtures"
const S := MirrorDomain.EpistemicStatus

# The witch comes to hold a claim with this status (a fixture observation, not a game action).
func _held(r: MirrorRuntime, claim_id: String, status: int) -> void:
	r.engine.record_observation("player", "bell", {"signature": ["FIXTURE", claim_id]}, {}, [], [{"id": claim_id, "holder_id": "player", "proposition": {"fixture": claim_id}, "status": status, "scope": "room"}])

func test_the_seven_kinds_are_the_notebook_groups_in_order() -> void:
	eq(NotebookView.KINDS, ["seen", "heard", "shown", "inferred", "predicted", "altered", "untestable"], "the notebook's groups, in order")

func test_each_claim_shows_the_kind_its_sidecar_gives() -> void:
	var r := GameFixtures.runtime()
	var claims: Dictionary = NotebookView.load_claims(FIXTURES + "/notebook_good")["claims"]
	for claim_id in claims.keys():
		_held(r, str(claim_id), S.SUPPORTED)
	var entries := NotebookView.entries(r.engine, {}, claims)
	eq(entries.size(), 7, "all seven fixture claims are held and listed")
	for entry in entries:
		eq(entry["kind"], claims[entry["claim"]]["kind"], "%s shows the kind its sidecar gives" % entry["claim"])

func test_an_open_question_is_untestable_whatever_kind_its_sidecar_gives() -> void:
	var r := GameFixtures.runtime()
	_held(r, "c.open", S.UNRESOLVED_BY_DESIGN)
	var entries := NotebookView.entries(r.engine, {}, {"c.open": {"kind": "seen", "text": "note.fixture.open"}})
	eq(entries.size(), 1, "the open question is listed")
	eq(entries[0]["kind"], "untestable", "as untestable, though its sidecar says seen")

func test_the_pages_group_entries_by_kind_and_never_mix_two_kinds() -> void:
	var entries := [
		{"claim": "a", "kind": "seen"}, {"claim": "b", "kind": "seen"}, {"claim": "c", "kind": "seen"},
		{"claim": "d", "kind": "untestable"}, {"claim": "e", "kind": "heard"},
	]
	var page_list := NotebookView.pages(entries, 2)
	eq(page_list.size(), 4, "seen on two pages (two and one), then heard, then untestable")
	eq(page_list[0]["kind"], "seen", "seen comes first")
	eq(page_list[0]["entries"].size(), 2, "at most two entries a page")
	eq(page_list[2]["kind"], "heard", "heard follows, in the notebook's order")
	eq(page_list[3]["kind"], "untestable", "untestable comes last")
	eq(NotebookView.page_of(page_list, "c"), 1, "the page that shows c is the second seen page")
	eq(NotebookView.page_of(page_list, "zzz"), 0, "a claim no page shows opens the first page")

func test_the_sidecars_load_and_their_errors_are_reported() -> void:
	var good := NotebookView.load_claims(FIXTURES + "/notebook_good")
	eq(good["errors"], [], "the good sidecar loads with no errors")
	eq(good["claims"].size(), 7, "seven claims")
	var bad := NotebookView.load_claims(FIXTURES + "/notebook_bad")
	eq(bad["errors"].size(), 3, "a wrong kind, a text that is not a note key, and a claim named by two sidecars")
	ok(bad["claims"].has("c.twice"), "the first definition of a claim is kept")
	eq(bad["claims"]["c.twice"]["kind"], "seen", "and it is the first file's")

func test_the_game_has_no_notebook_sidecar_errors_and_the_classes_are_read() -> void:
	eq(NotebookView.load_claims()["errors"], [], "data/notebook loads with no errors (no sidecars yet is fine)")
	eq(NotebookView.discovery_classes().get("h.authorship_not_trust", ""), "relationship", "a classed claim keeps its class")
