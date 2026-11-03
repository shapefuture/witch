extends TestCase

# The whole game's content (the root files plus every area package, docs/engine/CONTENT_PACKAGES.md) loads with zero
# errors and zero warnings, like the hall's. Every content builder keeps this green.

func test_the_game_scope_catalog_loads_with_no_errors_and_no_warnings() -> void:
	var built := MirrorCatalog.build_engine(MirrorCatalog.DEFAULT_DIR, true)
	var report: Dictionary = built["report"]
	eq(report["errors"], [], "no load errors in the game scope")
	eq(report["warnings"], [], "no load warnings in the game scope")

func test_the_game_scope_minds_data_loads_with_no_errors() -> void:
	var loaded := MindsCatalog.load_dir(MindsCatalog.DEFAULT_DIR, true)
	eq(loaded["errors"], [], "no Minds errors in the game scope")

func test_a_new_game_in_the_game_scope_starts_in_the_shop_at_the_prologue() -> void:
	var r := GameFixtures.runtime(true)
	eq(r.engine.get_world("witch", {}).get("place", ""), "shop", "the witch starts in her shop")
	eq(r.engine.get_world("story", {}).get("act", ""), "prologue", "at the prologue")

func test_every_core_exit_moves_the_witch_where_it_says() -> void:
	var r := GameFixtures.runtime(true)
	var result := GameFixtures.do(r, "core_go_door_shop_street", "door_shop_street")
	ok(result.get("ok", false), "the shop door opens onto the street: %s" % JSON.stringify(result.get("errors", [])))
	eq(r.engine.get_world("witch", {}), {"place": "street", "from": "shop"}, "she is in the street, from the shop")
	result = GameFixtures.do(r, "core_go_door_street_shop", "door_street_shop")
	ok(result.get("ok", false), "and back")
	eq(r.engine.get_world("witch", {}).get("place", ""), "shop", "she is home")
