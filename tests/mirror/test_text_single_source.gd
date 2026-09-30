extends TestCase

# All player-visible Russian lives in data/text/ru.json and nowhere else, so text can be
# edited by hand or by tool in one file. These tests enforce it; tools/text_tool.py is the
# same check plus sort / CSV round-tripping.

const SCAN_ROOTS := ["res://game", "res://autoload", "res://render", "res://data", "res://tests"]
const SCAN_EXTENSIONS := ["gd", "json", "dialogue", "tscn", "gdshader"]
const TABLE := "res://data/text/ru.json"

func _files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_files(dir_path.path_join(sub), out)
	for file_name in dir.get_files():
		if file_name.get_extension() in SCAN_EXTENSIONS:
			out.append(dir_path.path_join(file_name))

func test_no_russian_prose_outside_the_text_table() -> void:
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	var files: Array[String] = []
	for root in SCAN_ROOTS:
		_files(root, files)
	var offenders: Array[String] = []
	for path in files:
		if path == TABLE:
			continue
		if cyrillic.search(FileAccess.get_file_as_string(path)) != null:
			offenders.append(path)
	eq(offenders, [], "Russian text must live only in data/text/ru.json")

func test_table_is_a_flat_object_of_nonempty_strings() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	ok(parsed is Dictionary, "a JSON object")
	var empty: Array[String] = []
	for key in parsed.keys():
		if str(key).begins_with("_"):
			continue
		ok(parsed[key] is String, "%s is a string" % key)
		if str(parsed[key]).strip_edges().is_empty():
			empty.append(str(key))
	eq(empty, [], "no empty strings")

func test_every_key_used_by_code_dialogue_and_data_exists() -> void:
	var table := Localization.load_table()
	var missing: Array[String] = []
	var code_files: Array[String] = []
	_files("res://game", code_files)
	_files("res://autoload", code_files)
	var call_pattern := RegEx.create_from_string("\\btr\\(\"([^\"]+)\"\\)")
	for path in code_files:
		if path.get_extension() != "gd":
			continue
		for match in call_pattern.search_all(FileAccess.get_file_as_string(path)):
			if not table.has(match.get_string(1)):
				missing.append("%s: %s" % [path, match.get_string(1)])
	var dialogue_key := RegEx.create_from_string("^(?:[a-z_][a-z0-9_]*:\\s+)?([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)$")
	var speaker := RegEx.create_from_string("^([a-z_][a-z0-9_]*):\\s")
	for file_name in DirAccess.get_files_at("res://data/conversations"):
		if file_name.get_extension() != "dialogue":
			continue
		for raw in FileAccess.get_file_as_string("res://data/conversations/" + file_name).split("\n"):
			var line := raw.strip_edges()
			if line.begins_with("#") or line.begins_with("~") or line.is_empty():
				continue
			var key_match := dialogue_key.search(line)
			if key_match != null and not table.has(key_match.get_string(1)):
				missing.append("%s: %s" % [file_name, key_match.get_string(1)])
			var speaker_match := speaker.search(line)
			if speaker_match != null and not table.has("speaker." + speaker_match.get_string(1)):
				missing.append("%s: speaker.%s" % [file_name, speaker_match.get_string(1)])
	eq(missing, [], "keys referenced but absent from ru.json")

func test_dialogue_files_contain_no_prose_only_keys_and_structure() -> void:
	# A line that is not a title, condition, jump, comment or blank must be `speaker: key` or `key`.
	var allowed := RegEx.create_from_string("^(?:[a-z_][a-z0-9_]*:\\s+)?[a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+$")
	var prose: Array[String] = []
	for file_name in DirAccess.get_files_at("res://data/conversations"):
		if file_name.get_extension() != "dialogue":
			continue
		for raw in FileAccess.get_file_as_string("res://data/conversations/" + file_name).split("\n"):
			var line := raw.strip_edges()
			if line.is_empty() or line.begins_with("#") or line.begins_with("~") or line.begins_with("=>") or line.begins_with("if ") or line.begins_with("elif ") or line == "else" or line.begins_with("do ") or line.begins_with("set "):
				continue
			if allowed.search(line) == null:
				prose.append("%s: %s" % [file_name, line])
	eq(prose, [], "dialogue lines must be keys, not prose")

func test_the_translation_actually_resolves_keys_to_russian() -> void:
	GameFixtures.ensure_localization()
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	for key in ["opt.look_machine", "dlg.tomas_ask_what.1", "speaker.tomas", "line.arrival.1", "ui.paused"]:
		var text := TranslationServer.translate(key)
		ok(text != key and cyrillic.search(text) != null, "%s -> %s" % [key, text])
	eq(TranslationServer.get_locale().left(2), "ru", "the locale is pinned to Russian")
