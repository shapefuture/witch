class_name VoiceLint
extends RefCounted

# VOICES.md "Form", the glossary, the reserved phrases and the caption register, as a lint over every line of the
# Russian text table: the root table and every area fragment. check() returns one failure per broken rule, as
# "key | rule | text". The Russian words are written as \u escapes (a post-processing step converts them): the
# single-source test forbids Cyrillic in any file but the table.
#
# A bubble line is at most 90 characters, an option (`opt.` keys) at most 40. Captions (a line only the narrator
# speaks, see usage()) and the designer-facing Minds texts (`rule.`, `conv.`: read by the four-laws linter, never
# shown in a bubble) have no length limit. A caption an area wrote (not the root table, whose lines stay as they are)
# is in the third person: no second-person pronoun, and no mental verb with a person as its subject. An untestable
# note (a notebook entry the game shows as an open question) ends with a question mark. Every other rule applies to
# every line.

const DATA_MIRROR := "res://data/mirror"
const DATA_CONVERSATIONS := "res://data/conversations"
const DATA_NOTEBOOK := "res://data/notebook"
const ROOT_TABLE := "res://data/text/ru.json"
const MAX_BUBBLE := 90
const MAX_OPTION := 40
const DESIGNER_PREFIXES := ["rule.", "conv."]
const QUOTE_MARKS := ["\"", "“", "”", "„"]
const SMILEYS := [":)", ";)", "=)"]

# System words (event, task, reward) by stem; the noun forms of trust and relationships, exactly.
const SYSTEM_PREFIXES := ["\u0441\u043e\u0431\u044b\u0442\u0438", "\u0437\u0430\u0434\u0430\u043d\u0438", "\u043d\u0430\u0433\u0440\u0430\u0434"]
const SYSTEM_EXACT := ["\u0434\u043e\u0432\u0435\u0440\u0438\u0435", "\u0434\u043e\u0432\u0435\u0440\u0438\u044f", "\u0434\u043e\u0432\u0435\u0440\u0438\u044e", "\u0434\u043e\u0432\u0435\u0440\u0438\u0435\u043c", "\u0434\u043e\u0432\u0435\u0440\u0438\u0438", "\u043e\u0442\u043d\u043e\u0448\u0435\u043d\u0438\u044f", "\u043e\u0442\u043d\u043e\u0448\u0435\u043d\u0438\u0439", "\u043e\u0442\u043d\u043e\u0448\u0435\u043d\u0438\u044f\u043c", "\u043e\u0442\u043d\u043e\u0448\u0435\u043d\u0438\u044f\u043c\u0438", "\u043e\u0442\u043d\u043e\u0448\u0435\u043d\u0438\u044f\u0445"]
# The concessions: the witch never gives up a point.
const CONCESSIONS := ["\u0442\u044b \u043f\u0440\u0430\u0432\u0430", "\u043f\u0440\u0438\u0437\u043d\u0430\u044e", "\u0441\u0434\u0430\u044e\u0441\u044c", "\u0442\u0432\u043e\u044f \u0432\u0437\u044f\u043b\u0430"]
# The glossary's never-words: the Fog's other names, the Basement's depths, the old Town name.
const NEVER_EXACT := ["\u043c\u043e\u0440\u043e\u043a", "\u043f\u043e\u0441\u0430\u0434"]
const NEVER_PREFIX := ["\u043c\u0433\u043b", "\u0438\u0437\u043d\u0430\u043d\u043a", "\u043a\u043e\u043b\u0434\u043e\u0432\u0441\u0442\u0432"]
const NEVER_PHRASES := ["\u043f\u0435\u0440\u0432\u044b\u0439 \u0441\u0430\u0434", "\u0432\u0442\u043e\u0440\u043e\u0439 \u0441\u0430\u0434", "\u0434\u043e\u043c \u0432\u0435\u0434\u044c\u043c\u044b", "\u0437\u0440\u0435\u043d\u0438\u0435 \u043e\u0436\u0438\u0434\u0430\u043d\u0438\u0439"]
# The mode labels never use the two old words (checked on ui.magic.* only: the verb is ordinary prose).
const NEVER_IN_MODES := ["\u0434\u0435\u0440\u0436\u0443", "\u0437\u043b\u0430\u0442\u043e"]
# The notebook kind label is never the old word (checked on ui.notebook.kind.* only).
const NEVER_NOTEBOOK := ["\u0438\u0437\u043c\u0435\u043d\u0438\u043b\u0430"]
# The hotel has one name: its old name (a phrase together with the word for hotel) is refused.
const HOTEL_PHRASE := "\u043f\u043e \u0442\u0443 \u0441\u0442\u043e\u0440\u043e\u043d\u0443"
const HOTEL_WORD := "\u043e\u0442\u0435\u043b"
# Words whose spelling with the plain letter e (never the letter with the diaeresis) is never right.
const NO_YO := ["\u0435\u0449\u0435", "\u0435\u0435", "\u043f\u043e\u0439\u0434\u0435\u043c", "\u043f\u043e\u0439\u0434\u0435\u043c\u0442\u0435", "\u0438\u0434\u0435\u043c", "\u0438\u0434\u0435\u0442", "\u0438\u0434\u0435\u0448\u044c", "\u0447\u044c\u0435", "\u043f\u043e\u0448\u0435\u043b", "\u0436\u0434\u0435\u0442", "\u043f\u0440\u0438\u0434\u0435\u0442", "\u0436\u0438\u0432\u0435\u0442", "\u0431\u0435\u0440\u0435\u0442", "\u0437\u043e\u0432\u0435\u0442", "\u0432\u0435\u0434\u0435\u0442", "\u043f\u043e\u0435\u0442", "\u043f\u044c\u0435\u0442", "\u0432\u0435\u0437\u0435\u0442", "\u043d\u0435\u0441\u0435\u0442"]
# Intent words need a hedge.
const INTENT := ["\u043d\u0430\u0440\u043e\u0447\u043d\u043e", "\u0441\u043f\u0435\u0446\u0438\u0430\u043b\u044c\u043d\u043e"]
const HEDGES := ["\u0431\u0443\u0434\u0442\u043e", "\u043a\u0430\u0436\u0435\u0442\u0441\u044f", "\u043f\u043e\u0445\u043e\u0436\u0435"]
# Budgets across the whole game: phrase -> the most times it may appear over all the table's lines (lowercase).
const BUDGETS := {
	"\u043d\u0443 \u0438 \u043d\u0435 \u043d\u0430\u0434\u043e.": 4,
	"\u043f\u0440\u0438\u0432\u0435\u0442.": 1,
	"\u043f\u043e\u0439\u0434\u0451\u043c.": 1,
	"\u0432\u0435\u0434\u044c \u043c\u044b \u0431\u044b\u043b\u0438 \u0437\u0434\u0435\u0441\u044c": 1,
}
# The caption register (areas only): second-person words; mental verbs; the words that make a person the subject.
const SECOND_PERSON := ["\u0442\u044b", "\u0442\u0435\u0431\u044f", "\u0442\u0435\u0431\u0435", "\u0442\u043e\u0431\u043e\u0439", "\u0442\u043e\u0431\u043e\u044e", "\u0442\u0432\u043e\u0439", "\u0442\u0432\u043e\u044f", "\u0442\u0432\u043e\u0451", "\u0442\u0432\u043e\u0438", "\u0442\u0432\u043e\u0438\u0445", "\u0442\u0432\u043e\u0438\u043c", "\u0442\u0432\u043e\u0435\u0439", "\u0442\u0432\u043e\u0435\u0433\u043e", "\u0432\u044b", "\u0432\u0430\u0441", "\u0432\u0430\u043c", "\u0432\u0430\u043c\u0438", "\u0432\u0430\u0448", "\u0432\u0430\u0448\u0430", "\u0432\u0430\u0448\u0435", "\u0432\u0430\u0448\u0438", "\u0432\u0430\u0448\u0435\u0433\u043e", "\u0432\u0430\u0448\u0435\u0439", "\u0432\u0430\u0448\u0438\u043c"]
const MENTAL_PREFIXES := ["\u0445\u043e\u0447", "\u0445\u043e\u0442\u0435\u043b", "\u0431\u043e\u0438\u0442", "\u0431\u043e\u044f\u0442\u044c\u0441\u044f", "\u0431\u043e\u044f\u0437", "\u0431\u043e\u044e\u0441\u044c", "\u0436\u0434", "\u043f\u043e\u043d\u0438\u043c\u0430"]
const PERSON_WORDS := ["\u043e\u043d", "\u043e\u043d\u0430", "\u043e\u043d\u0438", "\u043e\u043d\u043e", "\u043c\u0438\u0440\u043e\u043d", "\u0432\u0435\u0440\u0430", "\u0438\u043b\u044c\u044f", "\u044d\u043b\u0438\u0430\u043d", "\u0442\u0435\u043d\u044c", "\u0442\u043e\u043c\u0430\u0441", "\u0433\u0430\u0432\u0440\u0438\u043b\u0430", "\u0433\u0430\u0432\u0440\u0438\u043a", "\u0434\u0432\u043e\u0440\u043d\u0438\u043a", "\u043f\u043e\u0440\u0442\u044c\u0435", "\u043d\u0438\u043a\u0442\u043e"]
const DIALOGUE_LINE := "^(?:[a-z_][a-z0-9_]*:\\s+)?([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)$"

# The rules over the merged table. `usage` is usage(): the caption and untestable-note keys and the root table's keys.
static func check(table: Dictionary, usage: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	var keys: Array = table.keys()
	keys.sort()
	for key in keys:
		failures.append_array(check_line(str(key), str(table[key]), usage))
	var untestable: Dictionary = usage.get("untestable", {})
	for note_key in untestable.keys():
		if table.has(note_key) and not str(table[note_key]).strip_edges().ends_with("?"):
			failures.append(_failure(str(note_key), "an untestable note ends with «?»", str(table[note_key])))
	return failures

static func check_line(key: String, text: String, usage: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	var limit := _limit(key, usage)
	if limit > 0 and text.length() > limit:
		failures.append(_failure(key, "over %d characters" % limit, text))
	for mark in QUOTE_MARKS:
		if text.contains(str(mark)):
			failures.append(_failure(key, "quotes are «»: no straight or curly double quote marks", text))
			break
	if text.contains(" - "):
		failures.append(_failure(key, "the dash is «—», never a spaced hyphen", text))
	if text.count("!") > 1:
		failures.append(_failure(key, "at most one «!» per line", text))
	var words := _words(text)
	for word in words:
		if word.length() >= 3 and word == word.to_upper():
			failures.append(_failure(key, "all-caps word '%s'" % word, text))
	if _smiley(text):
		failures.append(_failure(key, "no «)» smiley", text))
	var lower := text.to_lower()
	for word in words:
		var lowered := word.to_lower()
		if _is_system_word(lowered):
			failures.append(_failure(key, "system word '%s'" % word, text))
		if _any_prefix(lowered, NEVER_PREFIX) or lowered in NEVER_EXACT:
			failures.append(_failure(key, "glossary's never word '%s'" % word, text))
		if lowered in NO_YO:
			failures.append(_failure(key, "missing \u0451 in '%s'" % word, text))
		if key.begins_with("ui.magic.") and lowered in NEVER_IN_MODES:
			failures.append(_failure(key, "a mode is never called '%s'" % word, text))
	for phrase in CONCESSIONS:
		if lower.contains(str(phrase)):
			failures.append(_failure(key, "concession '%s'" % phrase, text))
	for phrase in NEVER_PHRASES:
		if lower.contains(str(phrase)):
			failures.append(_failure(key, "glossary's never phrase '%s'" % phrase, text))
	if lower.contains(HOTEL_PHRASE) and lower.contains(HOTEL_WORD):
		failures.append(_failure(key, "the hotel is \u0417\u0430\u043f\u0440\u0435\u0434\u0435\u043b\u044c\u0435, not its old name", text))
	if key.begins_with("ui.notebook.kind.") and lower.strip_edges() in NEVER_NOTEBOOK:
		failures.append(_failure(key, "the notebook kind is never \u0418\u0437\u043c\u0435\u043d\u0438\u043b\u0430", text))
	if _has_any(words, INTENT) and not _has_any(words, HEDGES):
		failures.append(_failure(key, "an intent word needs a hedge (\u0431\u0443\u0434\u0442\u043e, \u043a\u0430\u0436\u0435\u0442\u0441\u044f, \u043f\u043e\u0445\u043e\u0436\u0435)", text))
	var captions: Dictionary = usage.get("captions", {})
	var root: Dictionary = usage.get("root_keys", {})
	if captions.has(key) and not root.has(key):
		failures.append_array(_caption_failures(key, words, text))
	return failures

# Reserved phrases counted over every line of the table (each occurrence counts, lowercase).
static func budget_failures(table: Dictionary) -> Array[String]:
	var failures: Array[String] = []
	var keys: Array = table.keys()
	keys.sort()
	for phrase in BUDGETS.keys():
		var total := 0
		var where: Array[String] = []
		for key in keys:
			var count := str(table[key]).to_lower().count(str(phrase))
			if count > 0:
				total += count
				where.append(str(key))
		var cap := int(BUDGETS[phrase])
		if total > cap:
			failures.append("budget | %s appears %d times, the budget is %d | %s" % [phrase, total, cap, ", ".join(PackedStringArray(where))])
	return failures

# Which keys are captions (a line only the narrator speaks) and which are spoken (a bubble), read from the Mirror data
# and the dialogue files; a key a dialogue file speaks is always a bubble. Also: the root table's keys (the hall's own
# lines) and the notebook's untestable notes (the text keys of entries the game shows as open questions).
static func usage() -> Dictionary:
	var captions: Dictionary = {}
	var bubbles: Dictionary = {}
	for path in _files(DATA_MIRROR, "json"):
		_walk_steps(JSON.parse_string(FileAccess.get_file_as_string(path)), captions, bubbles)
	var dialogue := RegEx.create_from_string(DIALOGUE_LINE)
	for path in _files(DATA_CONVERSATIONS, "dialogue"):
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			var found := dialogue.search(raw.strip_edges())
			if found != null:
				bubbles[found.get_string(1)] = true
	var caption_keys: Dictionary = {}
	for key in captions.keys():
		if not bubbles.has(key):
			caption_keys[key] = true
	var root: Dictionary = {}
	var root_table: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT_TABLE))
	if root_table is Dictionary:
		for key in root_table.keys():
			root[str(key)] = true
	var untestable: Dictionary = {}
	for path in _files(DATA_NOTEBOOK, "json"):
		var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if sidecar is Dictionary:
			for claim in sidecar.keys():
				var entry: Variant = sidecar[claim]
				if entry is Dictionary and str(entry.get("kind", "")) == "untestable":
					untestable[str(entry.get("text", ""))] = true
	return {"captions": caption_keys, "bubbles": bubbles, "root_keys": root, "untestable": untestable}

# One violation and its clean twin per rule. "rule" is a substring of the failure the bad text must raise; the clean
# text must raise nothing. "usage" (bad) and "clean_usage" carry the caption, root and untestable keys of the fixture.
static func fixtures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"rule": "over 90", "key": "line.fx.bubble", "bad": "".lpad(91, "a"), "clean": "".lpad(90, "a")})
	out.append({"rule": "over 40", "key": "opt.fx", "bad": "".lpad(41, "a"), "clean": "".lpad(40, "a")})
	out.append({"rule": "over 90", "key": "line.fx.caption", "bad": "".lpad(150, "a"), "clean": "".lpad(150, "a"), "clean_usage": {"captions": {"line.fx.caption": true}}})
	out.append({"rule": "over 90", "key": "line.fx.bubble_long", "bad": "".lpad(150, "a"), "clean": "".lpad(150, "a"), "clean_key": "rule.fx.statement"})
	out.append({"rule": "quotes", "key": "line.fx.quote", "bad": "say \"yes\" now", "clean": "say «yes» now"})
	out.append({"rule": "spaced hyphen", "key": "line.fx.dash", "bad": "one - two", "clean": "one — two"})
	out.append({"rule": "at most one", "key": "line.fx.bang", "bad": "Hey! Wait!", "clean": "Hey! Wait."})
	out.append({"rule": "all-caps", "key": "line.fx.caps", "bad": "\u0421\u041b\u041e\u0412\u041e here", "clean": "\u0422\u0435\u043d\u044c here"})
	out.append({"rule": "all-caps", "key": "line.fx.caps_latin", "bad": "WAY out", "clean": "Way out"})
	out.append({"rule": "smiley", "key": "line.fx.smiley", "bad": "okay :)", "clean": "okay (later)"})
	out.append({"rule": "smiley", "key": "line.fx.stray", "bad": "okay)", "clean": "(okay)"})
	out.append({"rule": "system word", "key": "line.fx.system", "bad": "x " + SYSTEM_PREFIXES[0] + "\u0435 y", "clean": "x y"})
	out.append({"rule": "system word", "key": "line.fx.system_exact", "bad": "x " + SYSTEM_EXACT[0] + " y", "clean": "x y"})
	out.append({"rule": "concession", "key": "line.fx.concede", "bad": CONCESSIONS[1], "clean": "\u043b\u0430\u0434\u043d\u043e"})
	out.append({"rule": "never word", "key": "line.fx.never", "bad": "x " + NEVER_PREFIX[0] + "\u0430 y", "clean": "x fog y"})
	out.append({"rule": "never word", "key": "line.fx.never_exact", "bad": "x " + NEVER_EXACT[0] + " y", "clean": "x y"})
	out.append({"rule": "never phrase", "key": "line.fx.never_phrase", "bad": "x " + NEVER_PHRASES[0] + " y", "clean": "x y"})
	out.append({"rule": "a mode is never", "key": "ui.magic.fx", "bad": NEVER_IN_MODES[0], "clean": "fx"})
	out.append({"rule": "not its old name", "key": "line.fx.hotel", "bad": HOTEL_WORD + " " + HOTEL_PHRASE, "clean": HOTEL_WORD})
	out.append({"rule": "notebook kind is never", "key": "ui.notebook.kind.fx", "bad": NEVER_NOTEBOOK[0], "clean": "fx"})
	out.append({"rule": "missing \u0451", "key": "line.fx.yo", "bad": "x " + NO_YO[0] + " y", "clean": "x \u0435\u0449\u0451 y"})
	out.append({"rule": "intent word", "key": "line.fx.intent", "bad": INTENT[0] + " turned", "clean": HEDGES[0] + " " + INTENT[0] + " turned"})
	out.append({"rule": "second person", "key": "line.fx.caption_you", "bad": "\u0422\u044b \u0442\u0438\u043a\u0430\u0435\u0448\u044c.", "clean": "\u0428\u0435\u0441\u0442\u0435\u0440\u043d\u0438 \u0442\u0438\u043a\u0430\u044e\u0442.", "usage": {"captions": {"line.fx.caption_you": true}}, "clean_usage": {"captions": {"line.fx.caption_you": true}}})
	out.append({"rule": "second person", "key": "line.fx.caption_hall", "bad": "\u0422\u044b \u0442\u0438\u043a\u0430\u0435\u0448\u044c.", "clean": "\u0422\u044b \u0442\u0438\u043a\u0430\u0435\u0448\u044c.", "usage": {"captions": {"line.fx.caption_hall": true}}, "clean_usage": {"captions": {"line.fx.caption_hall": true}, "root_keys": {"line.fx.caption_hall": true}}})
	out.append({"rule": "mental verb", "key": "line.fx.caption_mind", "bad": "\u041e\u043d \u0436\u0434\u0451\u0442.", "clean": "\u0428\u0435\u0441\u0442\u0435\u0440\u043d\u0438 \u0442\u0438\u043a\u0430\u044e\u0442.", "usage": {"captions": {"line.fx.caption_mind": true}}, "clean_usage": {"captions": {"line.fx.caption_mind": true}}})
	out.append({"rule": "untestable note", "key": "note.fx.open", "bad": "\u042d\u0442\u043e \u0431\u044b\u043b\u043e.", "clean": "\u042d\u0442\u043e \u0431\u044b\u043b\u043e?", "usage": {"untestable": {"note.fx.open": true}}, "clean_usage": {"untestable": {"note.fx.open": true}}})
	return out

# ---- helpers ----------------------------------------------------------------------------------

static func _failure(key: String, rule: String, text: String) -> String:
	return "%s | %s | %s" % [key, rule, text]

# The longest a line may be (0 = no limit): an option 40, a bubble 90, a caption or a designer text none.
static func _limit(key: String, usage: Dictionary) -> int:
	if key.begins_with("opt."):
		return MAX_OPTION
	for prefix in DESIGNER_PREFIXES:
		if key.begins_with(str(prefix)):
			return 0
	var captions: Dictionary = usage.get("captions", {})
	if captions.has(key):
		return 0
	return MAX_BUBBLE

# The caption register: no second person, and no mental verb with a person as the subject.
static func _caption_failures(key: String, words: Array[String], text: String) -> Array[String]:
	var failures: Array[String] = []
	var person := false
	var mental := false
	for word in words:
		var lowered := word.to_lower()
		if lowered in SECOND_PERSON:
			failures.append(_failure(key, "caption in the third person: second person '%s'" % word, text))
		if _any_prefix(lowered, MENTAL_PREFIXES):
			mental = true
		if lowered in PERSON_WORDS:
			person = true
	if mental and person:
		failures.append(_failure(key, "caption: a mental verb with a person as the subject", text))
	return failures

# The words of a line: each run of cased letters (Latin or Cyrillic). Digits, marks and spaces separate them.
static func _words(text: String) -> Array[String]:
	var out: Array[String] = []
	var current := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch.to_lower() != ch.to_upper():
			current += ch
		elif not current.is_empty():
			out.append(current)
			current = ""
	if not current.is_empty():
		out.append(current)
	return out

static func _smiley(text: String) -> bool:
	for smiley in SMILEYS:
		if text.contains(str(smiley)):
			return true
	var depth := 0
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == "(":
			depth += 1
		elif ch == ")":
			if depth == 0:
				return true
			depth -= 1
	return false

static func _is_system_word(lowered: String) -> bool:
	return _any_prefix(lowered, SYSTEM_PREFIXES) or lowered in SYSTEM_EXACT

static func _any_prefix(text: String, prefixes: Array) -> bool:
	for prefix in prefixes:
		if text.begins_with(str(prefix)):
			return true
	return false

static func _has_any(words: Array[String], wanted: Array) -> bool:
	for word in words:
		if word.to_lower() in wanted:
			return true
	return false

static func _files(dir_path: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub), extension))
	for file_name in dir.get_files():
		if file_name.get_extension() == extension:
			out.append(dir_path.path_join(file_name))
	return out

static func _walk_steps(node: Variant, captions: Dictionary, bubbles: Dictionary) -> void:
	if node is Dictionary:
		var dict: Dictionary = node
		if str(dict.get("kind", "")) == "line" and dict.get("key") is String:
			var key := str(dict["key"])
			if str(dict.get("speaker", "")) == "narrator":
				captions[key] = true
			else:
				bubbles[key] = true
		for value in dict.values():
			_walk_steps(value, captions, bubbles)
	elif node is Array:
		for item in node:
			_walk_steps(item, captions, bubbles)
