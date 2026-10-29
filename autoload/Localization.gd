extends Node

# The game is Russian-only. The text table is loaded into a Translation and the locale is pinned to "ru". Game
# content refers to text by KEY (e.g. "opt.look_machine"), never by prose, so rewording a line does not change the
# Mirror catalog fingerprint and therefore never invalidates a save.
#
# The table is data/text/ru.json plus one fragment per content area in data/text/ru/*.json
# (docs/engine/CONTENT_PACKAGES.md), so parallel authors never edit the same file. A key may be defined once across
# all of them; a second definition is reported as an error and the first one is kept.

const LOCALE := "ru"
const TABLE_PATH := "res://data/text/ru.json"
const FRAGMENTS_DIR := "res://data/text/ru"

func _ready() -> void:
	register()

func register() -> int:
	var loaded := load_tables()
	for duplicate: String in loaded["duplicates"]:
		push_error("Localization: text key defined twice: %s" % duplicate)
	var table: Dictionary = loaded["table"]
	var translation := Translation.new()
	translation.locale = LOCALE
	for key: String in table:
		translation.add_message(key, table[key])
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale(LOCALE)
	return table.size()

# The merged table. A custom `path` reads that one file only (fixtures); the default reads the fragments too.
static func load_table(path: String = TABLE_PATH) -> Dictionary:
	return load_tables(path, FRAGMENTS_DIR if path == TABLE_PATH else "")["table"]

# {"table": merged keys, "files": the files read, "duplicates": "key (file)" for each key defined twice}. Duplicates
# are returned, not raised: register() reports them at boot and tests/mirror/test_text_single_source.gd fails on them.
static func load_tables(path: String = TABLE_PATH, fragments_dir: String = FRAGMENTS_DIR) -> Dictionary:
	var files: Array[String] = [path]
	if not fragments_dir.is_empty():
		files.append_array(ContentFiles.files_in(fragments_dir, "json"))
	var table := {}
	var duplicates: Array[String] = []
	for file in files:
		if not FileAccess.file_exists(file):
			push_error("Localization: %s not found" % file)
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not parsed is Dictionary:
			push_error("Localization: %s is not a JSON object" % file)
			continue
		for key in parsed.keys():
			if str(key).begins_with("_"):
				continue
			if table.has(str(key)):
				duplicates.append("%s (%s)" % [key, file])
				continue
			table[str(key)] = str(parsed[key])
	return {"table": table, "files": files, "duplicates": duplicates}
