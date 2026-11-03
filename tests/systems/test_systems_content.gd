extends TestCase

# The systems cell's steps as the content writes them. Every step of a kind the cell owns has a handler once the seam is
# registered, and every magic step names a look and an effect that MagicPresentation plays: the game root hands the
# step's fields to MagicPresentation, so a misspelt look would quietly play as violet. The steps are the dictionaries
# under data/mirror that carry a "kind" (actions, storylets and responses alike).

const DATA := "res://data/mirror"
const SYSTEMS_KINDS := ["notebook", "sight", "flash"]

func test_every_systems_step_in_the_content_has_a_handler_once_the_seam_is_registered() -> void:
	var host := Node.new()
	track(host)
	var director := PresentationDirector.new()
	SystemsPresenters.register(director, host)
	var used: Dictionary = {}
	for step: Dictionary in _steps():
		var kind := str(step.get("kind", ""))
		if kind in SYSTEMS_KINDS:
			used[kind] = int(used.get(kind, 0)) + 1
	for kind in SYSTEMS_KINDS:
		ok(used.has(kind), "the content has %s steps to check" % kind)
		ok(director.handlers.has(kind), "%s steps have a handler" % kind)

func test_every_magic_step_names_a_look_and_an_effect_the_presentation_plays() -> void:
	var checked := 0
	for step: Dictionary in _steps():
		if str(step.get("kind", "")) != "magic":
			continue
		checked += 1
		var effect := str(step.get("effect", ""))
		ok(effect == "fizzle" or MagicPresentation.EFFECTS.has(effect), "magic effect '%s' is one it plays" % effect)
		var mode := str(step.get("mode", "violet"))
		ok(mode in MagicPresentation.MODES, "magic mode '%s' is one of the three looks" % mode)
	ok(checked > 0, "the content has magic steps to check")

func _steps() -> Array:
	var steps: Array = []
	for path: String in _json_files(DATA):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_collect(parsed, steps)
	return steps

func _json_files(dir_path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				found.append_array(_json_files(path))
		elif entry.ends_with(".json"):
			found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found

func _collect(node: Variant, out: Array) -> void:
	if node is Dictionary:
		var dict: Dictionary = node
		if dict.has("kind"):
			out.append(dict)
		for key in dict:
			_collect(dict[key], out)
	elif node is Array:
		for item in node:
			_collect(item, out)
