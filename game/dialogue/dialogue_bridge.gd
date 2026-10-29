class_name DialogueBridge
extends RefCounted

# Runs a Dialogue Manager conversation as a pure language/runtime layer:
#
#   MirrorState -> MirrorDialogueContext -> Dialogue Manager -> presentation
#
# Dialogue Manager is stateless here. It renders the wording under a title, choosing branches
# by READING Mirror through `ctx`. It never owns relationship state, NPC memory or progress:
# when the player picks a response, that choice is committed to Mirror as a DIALOGUE_CHOICE
# action, and Mirror remains the only place anything is recorded.
#
# All wording resolves through tr() from data/text/ru.json (a line's text IS its key).

const DEFAULT_RESOURCE := "res://data/conversations/tomas.dialogue"
const CONVERSATIONS_DIR := "res://data/conversations"

# title -> the .dialogue file that defines it (titles are unique across data/conversations, one file per area).
static var _title_index: Dictionary = {}

var engine: MirrorEngine
var context: MirrorDialogueContext
var manager: Node
var _resources: Dictionary = {}
# The character id of the line currently handed to the sink ("" for narration).
var current_speaker_id := ""

func _init(p_engine: MirrorEngine, p_manager: Node = null) -> void:
	engine = p_engine
	context = MirrorDialogueContext.new(p_engine)
	manager = p_manager if p_manager != null else _find_manager()

static func _find_manager() -> Node:
	var root := (Engine.get_main_loop() as SceneTree).root
	return root.get_node_or_null("DialogueManager")

func is_ready() -> bool:
	return manager != null

func load_resource(path: String = DEFAULT_RESOURCE) -> Resource:
	if not _resources.has(path):
		_resources[path] = load(path)
	return _resources[path]

# The file that defines `title`; DEFAULT_RESOURCE for a title no file defines (Dialogue Manager then reports it).
static func resource_for_title(title: String) -> String:
	if _title_index.is_empty():
		var built := title_index()
		for duplicate: String in built["duplicates"]:
			push_error("DialogueBridge: dialogue title defined twice: %s" % duplicate)
		_title_index = built["titles"]
	return str(_title_index.get(title, DEFAULT_RESOURCE))

# Reads the titles (`~ name` lines) of every .dialogue file: {"titles": {title: path}, "duplicates": ["title (path)"]}.
# A title may be defined in one file only; the first one wins.
static func title_index(dir: String = CONVERSATIONS_DIR) -> Dictionary:
	var titles := {}
	var duplicates: Array[String] = []
	for path in ContentFiles.files_in(dir, "dialogue"):
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			var line := raw.strip_edges()
			if not line.begins_with("~ "):
				continue
			var title := line.substr(2).strip_edges()
			if titles.has(title):
				duplicates.append("%s (%s)" % [title, path])
				continue
			titles[title] = path
	return {"titles": titles, "duplicates": duplicates}

# Plays one title to its end. `sink` is called once per line and awaited:
#   func(speaker: String, text: String, responses: Array[Dictionary]) -> int
# `responses` is a list of {"id", "text", "allowed"}; the sink returns the chosen index when
# there are responses (ignored otherwise). Returns the lines that were shown, for logging/tests.
func run(title: String, sink: Callable, resource: Resource = null, npc_id: String = "tomas") -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	if manager == null:
		push_error("DialogueBridge: DialogueManager autoload not available")
		return shown
	var script := resource if resource != null else load_resource(resource_for_title(title))
	var states: Array = [{"ctx": context}]
	var line = await manager.get_next_dialogue_line(script, title, states)
	while line != null:
		var speaker := speaker_name(line.character)
		current_speaker_id = line.character
		var options: Array[Dictionary] = []
		for response in line.responses:
			options.append({"id": choice_id(response), "text": response.text, "allowed": response.is_allowed})
		shown.append({"speaker": speaker, "text": line.text, "responses": options})
		var chosen: int = int(await sink.call(speaker, line.text, options))
		var next_id: String = line.next_id
		if not line.responses.is_empty():
			chosen = clampi(chosen, 0, line.responses.size() - 1)
			record_choice(npc_id, options[chosen]["id"])
			next_id = line.responses[chosen].next_id
		line = await manager.get_next_dialogue_line(script, next_id, states)
	return shown

func speaker_name(character_id: String) -> String:
	return "" if character_id.is_empty() else TranslationServer.translate("speaker." + character_id)

# Stable identity for a response: its static [ID:...] if the author gave one.
static func choice_id(response: Object) -> String:
	var key: String = response.translation_key
	return key if not key.is_empty() else str(response.id)

# The only way dialogue changes the game: a recorded, replayable Mirror action.
func record_choice(npc_id: String, choice_id_value: String) -> Dictionary:
	return MirrorDialogueBridge.new(engine).record_choice("player", npc_id, choice_id_value)
