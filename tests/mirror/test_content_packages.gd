extends TestCase

# The area-package contract (docs/engine/CONTENT_PACKAGES.md): every loader reads its root files, then each
# data/mirror/areas/<area>/ fragment (and data/text/ru/*.json, data/conversations/*.dialogue), and a second
# definition of the same entity, id, place, key or title is reported instead of silently overriding the first.

const SOURCE := "res://data/mirror"
const WORK := "user://content_packages"

func _write(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value, "\t"))
	file.close()

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)

# WORK/catalog: a copy of the shipped catalog's root files and actions, without any area package.
func _fresh_catalog() -> String:
	_remove_tree(WORK)
	var dir := WORK.path_join("catalog")
	for file_name in ["world.json", "operators.json", "storylets.json", "hypotheses.json", "prologue.json"]:
		_write(dir.path_join(file_name), FileAccess.get_file_as_string(SOURCE.path_join(file_name)))
	for sub in ["actions", "minds"]:
		for file_name in DirAccess.get_files_at(SOURCE.path_join(sub)):
			if file_name.ends_with(".json"):
				_write(dir.path_join(sub).path_join(file_name), FileAccess.get_file_as_string(SOURCE.path_join(sub).path_join(file_name)))
	return dir

func _lamp_action() -> Dictionary:
	return {
		"id": "look_fixture_lamp", "action_type": "LOOK", "affordance_group": "observe", "label_key": "opt.look_bell",
		"valid_targets": ["fixture_lamp"], "prediction_signature": ["LOOK", "EXPECT_CURIOSITY"],
		"response_contracts": [{
			"id": "look_fixture_lamp.seen", "observed": {"outcome": "observed_fixture_lamp"},
			"presentation": [{"kind": "line", "speaker": "narrator", "key": "line.bell.tilted"}],
		}],
	}

func _containing(lines: Array, needle: String) -> Array:
	return lines.filter(func(line: Variant) -> bool: return str(line).contains(needle))

func test_the_hall_scope_ignores_area_packages() -> void:
	var dir := _fresh_catalog()
	_write(dir.path_join("areas/a_lamp/world.json"), {"world": {"fixture_lamp": {"lit": false}}})
	_write(dir.path_join("areas/a_lamp/actions.json"), [_lamp_action()])
	var engine := MirrorEngine.new()
	eq(MirrorCatalog.load_into(engine, dir)["errors"], [], "the root files load on their own")
	ok(not engine.action_definitions.has("look_fixture_lamp"), "and the default (hall) scope leaves the areas out")
	_remove_tree(WORK)

func test_an_area_adds_world_entities_and_actions_to_the_catalog() -> void:
	var dir := _fresh_catalog()
	_write(dir.path_join("areas/a_lamp/world.json"), {"world": {"fixture_lamp": {"lit": false}}})
	_write(dir.path_join("areas/a_lamp/actions.json"), [_lamp_action()])
	var engine := MirrorEngine.new()
	var report := MirrorCatalog.load_into(engine, dir, true)
	eq(report["errors"], [], "the catalog with one area loads")
	ok(engine.action_definitions.has("look_fixture_lamp"), "the area's action is registered")
	eq(engine.get_world("fixture_lamp", {}), {"lit": false}, "the area's world entity is set")
	ok(engine.action_definitions.has("look_machine"), "and the root actions are still there")
	ok(AlivenessLint.load_catalog(dir, true)["actions"].any(func(a: Variant) -> bool: return a.get("id", "") == "look_fixture_lamp"),
		"the aliveness lint reads the area's actions too")
	_remove_tree(WORK)

func test_a_world_entity_defined_twice_is_refused() -> void:
	var dir := _fresh_catalog()
	_write(dir.path_join("areas/a_lamp/world.json"), {"world": {"fixture_lamp": {"lit": false}}})
	_write(dir.path_join("areas/b_lamp/world.json"), {"world": {"fixture_lamp": {"lit": true}}})
	_write(dir.path_join("areas/c_machine/world.json"), {"world": {"machine": {"state": "fine"}}})
	_write(dir.path_join("areas/d_odd/world.json"), {"weather": {"rain": true}})
	var report := MirrorCatalog.load_into(MirrorEngine.new(), dir, true)
	ok(not report["ok"], "refused")
	eq(_containing(report["errors"], "world entity 'fixture_lamp' is already defined").size(), 1, "the entity two areas define")
	eq(_containing(report["errors"], "world entity 'machine' is already defined").size(), 1, "an area cannot redefine a root entity")
	eq(_containing(report["errors"], "unknown section 'weather'").size(), 1, "an unknown section is named")
	_remove_tree(WORK)

func test_an_action_id_defined_in_two_areas_is_refused() -> void:
	var dir := _fresh_catalog()
	_write(dir.path_join("areas/a_lamp/world.json"), {"world": {"fixture_lamp": {"lit": false}}})
	_write(dir.path_join("areas/a_lamp/actions.json"), [_lamp_action()])
	_write(dir.path_join("areas/b_lamp/actions.json"), [_lamp_action()])
	var report := MirrorCatalog.load_into(MirrorEngine.new(), dir, true)
	ok(not report["ok"], "refused")
	eq(_containing(report["errors"], "areas/b_lamp/actions.json: could not register action 'look_fixture_lamp'").size(), 1,
		"the second definition is named with its file")
	_remove_tree(WORK)

func test_minds_areas_add_places_and_holders_and_refuse_duplicates_and_tuning() -> void:
	_remove_tree(WORK)
	var areas := WORK.path_join("areas")
	_write(areas.path_join("a_garden/minds.json"), {
		"places": {"garden": {"adjacent": ["clearing"], "subjects": {}}},
		"holders": {"elian": {"tags": ["person"], "place": "garden"}},
		"routines": [{"id": "fixture_routine", "every": 10, "event": {"kind": "WALKED"}}],
	})
	_write(areas.path_join("a_garden/conventions.json"), [{"id": "fixture_convention"}])
	_write(areas.path_join("b_garden/minds.json"), {"places": {"garden": {"adjacent": [], "subjects": {}}}, "limits": {"max_pending": 1}})
	var raw := {"places": {"clearing": {"adjacent": [], "subjects": {}}}, "holders": {}, "conventions": []}
	var errors: Array = []
	MindsCatalog.merge_areas(raw, areas, errors)
	ok(raw["places"].has("garden") and raw["holders"].has("elian"), "an area adds a place and a holder")
	eq(raw["routines"].size(), 1, "and appends to the routines")
	eq(raw["conventions"].size(), 1, "and to the conventions")
	eq(_containing(errors, "place 'garden' is already defined").size(), 1, "a place defined twice is refused")
	eq(_containing(errors, "may not set 'limits'").size(), 1, "tuning stays in the root minds.json")
	_remove_tree(WORK)

func test_the_shipped_minds_catalog_loads_with_its_areas() -> void:
	eq(MindsCatalog.load_dir(MindsCatalog.DEFAULT_DIR, true)["errors"], [], "data/mirror/minds plus every area package loads cleanly")

func test_text_fragments_merge_and_a_key_defined_twice_is_reported() -> void:
	_remove_tree(WORK)
	_write(WORK.path_join("text/ru.json"), {"_about": "fixture", "fx.one": "one"})
	_write(WORK.path_join("text/ru/a_area.json"), {"fx.two": "two"})
	_write(WORK.path_join("text/ru/b_area.json"), {"fx.one": "again"})
	var loaded := Localization.load_tables(WORK.path_join("text/ru.json"), WORK.path_join("text/ru"))
	eq(loaded["table"], {"fx.one": "one", "fx.two": "two"}, "fragments merge; the first definition is kept")
	eq(loaded["duplicates"].size(), 1, "the second definition is reported")
	ok(str(loaded["duplicates"][0]).contains("b_area.json"), "with the file that repeated it")
	_remove_tree(WORK)

func test_dialogue_titles_resolve_to_their_file_and_duplicates_are_reported() -> void:
	_remove_tree(WORK)
	_write(WORK.path_join("conversations/a_area.dialogue"), "~ fixture_start\nnarrator: line.bell.tilted\n=> END\n")
	_write(WORK.path_join("conversations/b_area.dialogue"), "~ fixture_other\nnarrator: line.bell.tilted\n=> END\n~ fixture_start\n=> END\n")
	var index := DialogueBridge.title_index(WORK.path_join("conversations"))
	eq(index["titles"]["fixture_start"], WORK.path_join("conversations/a_area.dialogue"), "a title maps to the file that defines it first")
	eq(index["titles"]["fixture_other"], WORK.path_join("conversations/b_area.dialogue"), "titles from every file are indexed")
	eq(index["duplicates"].size(), 1, "a title defined twice is reported")
	eq(DialogueBridge.title_index()["duplicates"], [], "the shipped conversations define each title once")
	_remove_tree(WORK)
