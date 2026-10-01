class_name PlaqueStack
extends Node3D

# A column of carved wooden plaques hung in the scene: the option list for whatever you tapped, and
# the pause menu. A plaque is a faceted wood slab with cream text; a tap inside its rectangle
# chooses it (touch and mouse both come through handle_tap). The first row can be a brass title
# plaque that does nothing. Placement and pixel scale come from Diegetic.

signal chosen(index: int)

const ROW_HEIGHT := 38.0   # render pixels; about 7-9 mm on a phone held in landscape (a fingertip)
const GAP := 10.0
const TITLE_HEIGHT := 22.0  # the title is a small brass tag, visibly not a button
const TITLE_GAP := 12.0
const PAD := 8.0
const MIN_WIDTH := 112.0
const WOOD := Color(1.18, 1.0, 0.86)
const WOOD_BORDER := Color(0.22, 0.15, 0.11)
const CREAM := Color(1.0, 0.95, 0.80)
const DIM_CREAM := Color(0.92, 0.86, 0.70)
const INK := Color(0.16, 0.11, 0.08)

var camera: Camera3D
# Option plaques hang in the world (tip with the Dutch roll); menus stay square to the screen.
var upright := true

var _items: Array[Dictionary] = []
var _title_rect := Rect2()
var _dim: MeshInstance3D
var _title_node: Node3D
var _title_label: Label3D
var _hover := -1
var _pulse_index := -1
var _pulse := 0.0
var _clock := 0.0
var _open := false
var _scale := 1.0   # render pixels per UI pixel (rects below are in UI pixels)

func _ready() -> void:
	visible = false

func is_open() -> bool:
	return _open

func item_count() -> int:
	return _items.size()

# Rectangles of the choosable plaques, in viewport pixels.
func item_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for item in _items:
		var rect: Rect2 = item["rect"]
		out.append(Rect2(rect.position * _scale, rect.size * _scale))
	return out

# `labels` are already translated. `dim_background` puts a dark veil over the whole picture.
# `dim_last` draws the final plaque quieter (the "never mind" row).
func open(title: String, labels: Array[String], anchor_px: Vector2, centered: bool = false, dim_background: bool = false, dim_last: bool = false) -> void:
	close()
	var real_size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(480, 360)
	_scale = Diegetic.ui_scale(real_size)
	var viewport_size := Diegetic.ui_size(real_size)
	anchor_px /= _scale
	var font := UIKit.font()
	var widest := MIN_WIDTH
	for text in labels + [title]:
		widest = maxf(widest, ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FONT_SIZE).x) + PAD * 2.0 + 6.0)
	var rows := labels.size()
	var title_w := ceilf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FONT_SIZE).x) + 18.0
	var stack_h := rows * ROW_HEIGHT + maxi(rows - 1, 0) * GAP + (TITLE_HEIGHT + TITLE_GAP if not title.is_empty() else 0.0)
	var safe := Diegetic.safe_rect(viewport_size)
	var origin := Vector2.ZERO
	if centered:
		origin = Vector2((viewport_size.x - widest) * 0.5, (viewport_size.y - stack_h) * 0.5)
	else:
		origin.x = anchor_px.x + 30.0 if anchor_px.x < viewport_size.x * 0.5 else anchor_px.x - 30.0 - widest
		origin.y = anchor_px.y - stack_h * 0.45
	origin.x = clampf(origin.x, safe.position.x, maxf(safe.position.x, safe.end.x - widest))
	origin.y = clampf(origin.y, safe.position.y, maxf(safe.position.y, safe.end.y - stack_h))
	if dim_background:
		_dim = Diegetic.mesh_instance(SlabMesh.fill(PackedVector2Array([Vector2(0, 0), Vector2(viewport_size.x, 0), Vector2(viewport_size.x, -viewport_size.y), Vector2(0, -viewport_size.y)])), Diegetic.slab_material(Color(0.03, 0.02, 0.05, 0.66), "", 5), -0.3)
		add_child(_dim)
	var y := origin.y
	if not title.is_empty():
		_title_rect = Rect2(origin.x, y, title_w, TITLE_HEIGHT)
		var made := _make_plaque(_title_rect, title, "brass", Color(1, 1, 1), INK, Color(0.36, 0.26, 0.10), 20)
		_title_node = made["node"]
		_title_label = made["label"]
		y += TITLE_HEIGHT + TITLE_GAP
	for i in range(labels.size()):
		var rect := Rect2(origin.x, y, widest, ROW_HEIGHT)
		var quiet := dim_last and i == labels.size() - 1
		var made := _make_plaque(rect, labels[i], "wood", WOOD if not quiet else Color(0.62, 0.52, 0.46), CREAM if not quiet else DIM_CREAM, WOOD_BORDER, 30 + i * 4)
		_items.append({"index": i, "rect": rect, "node": made["node"], "material": made["material"]})
		y += ROW_HEIGHT + GAP
	_hover = -1
	_pulse_index = -1
	_clock = 0.0
	_open = true
	visible = true
	_place_all()

# Changes the title text in place (a status line, a volume read-out).
func set_title(text: String) -> void:
	if _title_label != null:
		_title_label.text = text

func close() -> void:
	_open = false
	visible = false
	_items.clear()
	for child in get_children():
		remove_child(child)
		child.free()
	_dim = null
	_title_node = null
	_title_label = null

# Returns true when the tap landed on a plaque (and chooses it, after a short press animation).
func handle_tap(px: Vector2) -> bool:
	if not _open:
		return false
	var index := _index_at(px)
	if index < 0:
		return false
	_pulse_index = index
	_pulse = 0.0
	return true

func hover(px: Vector2) -> void:
	if not _open:
		return
	var index := _index_at(px)
	if index != _hover:
		_hover = index
		for item in _items:
			_set_highlight(item, item["index"] == _hover)

func _index_at(viewport_px: Vector2) -> int:
	var px := viewport_px / _scale
	for item in _items:
		if (item["rect"] as Rect2).grow(3.0).has_point(px):
			return item["index"]
	return -1

func _process(delta: float) -> void:
	if not _open:
		return
	_clock += delta
	if _pulse_index >= 0:
		_pulse += delta
		if _pulse >= 0.14:
			var picked := _pulse_index
			_pulse_index = -1
			chosen.emit(picked)
			return
	_place_all()

func _make_plaque(rect: Rect2, text: String, tile: String, tint: Color, ink: Color, border: Color, priority: int) -> Dictionary:
	var node := Node3D.new()
	var outline := SlabMesh.chamfered(rect.size.x, rect.size.y, 3.0)
	node.add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.offset(outline, Vector2(2, -2))), Diegetic.slab_material(Color(0, 0, 0, 0.5), "", priority), -0.2))
	node.add_child(Diegetic.mesh_instance(SlabMesh.fill(outline), Diegetic.slab_material(border, "wood_dark", priority + 1), -0.1))
	var fill_material := Diegetic.slab_material(tint, tile, priority + 2)
	node.add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.inset(outline, 2.0)), fill_material, 0.0))
	var label := Diegetic.label(text, ink, priority + 3, _scale)
	label.position = Vector3(PAD, -(rect.size.y - UIKit.FONT_SIZE) * 0.5 + 1.0, 0.2)
	node.add_child(label)
	add_child(node)
	return {"node": node, "material": fill_material, "label": label}

func _set_highlight(item: Dictionary, on: bool) -> void:
	(item["material"] as ShaderMaterial).set_shader_parameter("highlight", 1.0 if on else 0.0)

func _place_all() -> void:
	if camera == null or not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if _dim != null:
		_dim.global_transform = Diegetic.transform_for(camera, viewport_size, Vector2.ZERO)
	if _title_node != null:
		_title_node.global_transform = Diegetic.transform_for(camera, viewport_size, _title_rect.position, _pop(0), _title_rect.size * Vector2(0.5, -0.5), upright)
	for k in range(_items.size()):
		var item: Dictionary = _items[k]
		var rect: Rect2 = item["rect"]
		var grow := _pop(k + 1)
		if item["index"] == _pulse_index:
			grow *= 1.0 + 0.1 * sin(clampf(_pulse / 0.14, 0.0, 1.0) * PI) - 0.06 * clampf(_pulse / 0.14, 0.0, 1.0)
		(item["node"] as Node3D).global_transform = Diegetic.transform_for(camera, viewport_size, rect.position, grow, rect.size * Vector2(0.5, -0.5), upright)

# Each plaque pops in a beat after the one above it.
func _pop(row: int) -> float:
	var t := clampf((_clock - row * 0.035) / 0.14, 0.0, 1.0)
	return lerpf(0.4, 1.0, t) + sin(t * PI) * 0.07
