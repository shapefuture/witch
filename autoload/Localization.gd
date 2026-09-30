extends Node

# The game is Russian-only. data/text/ru.json is loaded into a Translation and the locale is
# pinned to "ru". Game content refers to text by KEY (e.g. "opt.look_machine"), never by
# prose, so rewording a line does not change the Mirror catalog fingerprint and therefore
# never invalidates a save.

const LOCALE := "ru"
const TABLE_PATH := "res://data/text/ru.json"

func _ready() -> void:
	register()

func register() -> int:
	var table := load_table()
	var translation := Translation.new()
	translation.locale = LOCALE
	for key: String in table:
		translation.add_message(key, table[key])
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale(LOCALE)
	return table.size()

static func load_table(path: String = TABLE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Localization: %s not found" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Localization: %s is not a JSON object" % path)
		return {}
	var out := {}
	for key in parsed.keys():
		if not str(key).begins_with("_"):
			out[str(key)] = str(parsed[key])
	return out
