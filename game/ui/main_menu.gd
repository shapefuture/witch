class_name MainMenuUI
extends Node3D

# The title screen: three carved plaques hung in the world, and nothing else. It has no art, story or
# backstory; its owner dresses the stage around it. A choice is a signal. The menu does not close itself:
# the owner decides what a choice does, then calls close() or open() again.
#
# Pointer only. Taps and clicks go through IntentInput, the same translation the game uses, so a touch
# and a mouse on one plaque give the same intent. Continue is dimmed and does nothing while there is no
# save. After a choice the menu takes no more input until it is opened again, so a double tap cannot
# start a game twice.

signal new_game_requested
signal continue_requested
signal settings_requested

# The slot the game saves to (pause_menu_ui.gd, game_root.gd). The menu tests pin all three together.
const SAVE_SLOT := SaveGame.DEFAULT_SLOT
# One UI row is one dp on a 360-dp-tall screen, and a taller screen makes it bigger, so 52 rows clear
# the 48 dp a finger needs (NAVIGATION.md section 5).
const ROW_HEIGHT := 52.0
const GAP := 12.0
const PAD := 8.0
const MIN_WIDTH := 112.0
const PRIORITY := 40
const WOOD := Color(1.18, 1.0, 0.86)
const WOOD_BORDER := Color(0.22, 0.15, 0.11)
const CREAM := Color(1.0, 0.95, 0.80)
const DIM_WOOD := Color(0.62, 0.52, 0.46)
const DIM_CREAM := Color(0.92, 0.86, 0.70)
const DEFAULT_VIEWPORT := Vector2(480, 360)

# Answers "is there a save to continue from?". Tests replace it so they never read the player's file.
var save_probe: Callable = func() -> bool: return SaveGame.exists(SAVE_SLOT)
# The camera the plaques are placed by. Menus stay square to it.
var camera: Camera3D
# Taps and clicks become PlayerIntents here. Public so the owner (and tests) can set its clock.
var pointer: IntentInput

var _open := false
var _stage: Node3D
var _options: Array[Dictionary] = []   # {id, label, enabled, rect (UI px), node}
var _scale := 1.0

func _init() -> void:
	visible = false
	pointer = IntentInput.new()
	pointer.picker = _pick
	pointer.intent_emitted.connect(_on_intent)
	pointer.enabled = false
	add_child(pointer)

func _process(_delta: float) -> void:
	if _open:
		_place_all()

func is_open() -> bool:
	return _open

func open() -> void:
	close()
	var real_size := _viewport_size()
	_scale = Diegetic.ui_scale(real_size)
	var ui := Diegetic.ui_size(real_size)
	var rows := _rows()
	var has_save: bool = save_probe.call()
	if not has_save:
		for row in rows:
			if row["id"] == "continue":
				row["text"] = tr("menu.continue_empty")
	var font := UIKit.font()
	var widest := MIN_WIDTH
	for row in rows:
		var text: String = row["text"]
		widest = maxf(widest, ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.text_size()).x) + PAD * 2.0 + 6.0)
	var stack_h := rows.size() * ROW_HEIGHT + (rows.size() - 1) * GAP
	var safe := Diegetic.safe_rect(ui)
	var origin := Vector2((ui.x - widest) * 0.5, (ui.y - stack_h) * 0.5)
	origin.x = clampf(origin.x, safe.position.x, maxf(safe.position.x, safe.end.x - widest))
	origin.y = clampf(origin.y, safe.position.y, maxf(safe.position.y, safe.end.y - stack_h))
	_stage = Node3D.new()
	add_child(_stage)
	for i in range(rows.size()):
		var id: String = rows[i]["id"]
		var text: String = rows[i]["text"]
		var enabled := id != "continue" or has_save
		var rect := Rect2(origin.x, origin.y + i * (ROW_HEIGHT + GAP), widest, ROW_HEIGHT)
		_options.append({"id": id, "label": text, "enabled": enabled, "rect": rect, "node": _make_plaque(rect, text, enabled, i)})
	_open = true
	visible = true
	pointer.enabled = true
	_place_all()

func close() -> void:
	_open = false
	visible = false
	pointer.enabled = false
	_options.clear()
	if _stage != null:
		remove_child(_stage)
		_stage.free()
		_stage = null

func option_ids() -> Array[String]:
	var ids: Array[String] = []
	for option in _options:
		ids.append(str(option["id"]))
	return ids

func option_labels() -> Array[String]:
	var labels: Array[String] = []
	for option in _options:
		labels.append(str(option["label"]))
	return labels

func option_enabled(id: String) -> bool:
	var index := _index_of(id)
	return index >= 0 and bool(_options[index]["enabled"])

# Rectangles of the plaques, in viewport pixels.
func option_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for option in _options:
		var rect: Rect2 = option["rect"]
		out.append(Rect2(rect.position * _scale, rect.size * _scale))
	return out

# The three options, top to bottom. Each label is a literal key so the text table sees it.
func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		{"id": "new_game", "text": tr("menu.new_game")},
		{"id": "continue", "text": tr("menu.continue")},
		{"id": "settings", "text": tr("menu.settings")},
	]
	return rows

func _pick(viewport_px: Vector2) -> Dictionary:
	var index := _index_at(viewport_px)
	if index < 0:
		return {"target_id": "", "has_ground": false}
	return {"target_id": _options[index]["id"], "has_ground": false}

func _on_intent(intent: PlayerIntent) -> void:
	if not _open or intent.type != PlayerIntent.Type.INSPECT:
		return
	var index := _index_of(intent.target_id)
	if index < 0 or not bool(_options[index]["enabled"]):
		return
	pointer.enabled = false
	match intent.target_id:
		"new_game":
			new_game_requested.emit()
		"continue":
			continue_requested.emit()
		"settings":
			settings_requested.emit()

func _index_of(id: String) -> int:
	for i in range(_options.size()):
		if _options[i]["id"] == id:
			return i
	return -1

func _index_at(viewport_px: Vector2) -> int:
	var px := viewport_px / _scale
	for i in range(_options.size()):
		var rect: Rect2 = _options[i]["rect"]
		if rect.has_point(px):
			return i
	return -1

func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else DEFAULT_VIEWPORT

func _place_all() -> void:
	if camera == null or not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	for option in _options:
		var rect: Rect2 = option["rect"]
		(option["node"] as Node3D).global_transform = Diegetic.transform_for(camera, viewport_size, rect.position)

# The same carved wooden plaque as PlaqueStack, without its press animation and at the touch size.
func _make_plaque(rect: Rect2, text: String, enabled: bool, index: int) -> Node3D:
	var priority := PRIORITY + index * 4
	var tint := WOOD if enabled else DIM_WOOD
	var ink := CREAM if enabled else DIM_CREAM
	var node := Node3D.new()
	var outline := SlabMesh.chamfered(rect.size.x, rect.size.y, 3.0)
	node.add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.offset(outline, Vector2(2, -2))), Diegetic.slab_material(Color(0, 0, 0, 0.5), "", priority), -0.2))
	node.add_child(Diegetic.mesh_instance(SlabMesh.fill(outline), Diegetic.slab_material(WOOD_BORDER, "wood_dark", priority + 1), -0.1))
	node.add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.inset(outline, 2.0)), Diegetic.slab_material(tint, "wood", priority + 2), 0.0))
	var label := Diegetic.label(text, ink, priority + 3, _scale)
	label.position = Vector3(PAD, -(rect.size.y - UIKit.text_size()) * 0.5 + 1.0, 0.2)
	node.add_child(label)
	_stage.add_child(node)
	return node
