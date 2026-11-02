class_name NotebookSlab
extends Node3D

# The diegetic notebook (GAME_SPEC section 4): one carved slab hung in the picture, showing one page of the witch's
# entries at a time, grouped by kind (the kind is a brass tab, in her words). A tap on the right two thirds turns the
# page forward (on the last page it closes), a tap on the left third turns it back, and the plaque in the corner
# closes it. Space and Enter advance, as they do for lines. It takes its own taps through an IntentInput child, as the
# main menu does: the presentation holds the root's input while it plays, and the notebook is open during that time.

signal closed

const WIDTH := 300.0          # UI pixels: the 360-row picture the plaques are sized in
const PAD := 14.0
const LINE_GAP := 2.0
const ENTRY_GAP := 8.0
const TAB_TOP := 12.0
const TAB_HEIGHT := 16.0
const BODY_TOP := 40.0
const FOOT_HEIGHT := 40.0     # the close plaque is 32 UI pixels tall: 48 render pixels at 540 rows (NAVIGATION.md)
const CLOSE_WIDTH := 96.0
const CLOSE_HEIGHT := 32.0
const TURN_SPLIT := 1.0 / 3.0
const PARCHMENT := Color(1.0, 0.97, 0.88)
const BORDER := Color(0.30, 0.21, 0.15)
const INK := Color(0.15, 0.10, 0.08)
const BRASS := Color(0.84, 0.66, 0.28)
const PLAQUE := Color(1.18, 1.0, 0.86)
const PRIORITY := 40

var camera: Camera3D

var _pages: Array = []
var _index := 0
var _shown: Array[String] = []
var _height := 0.0
var _rect := Rect2()   # UI pixels, centred in the picture
var _scale := 1.0
var _grow := 1.0
var _open := false
var _input: IntentInput

func _init() -> void:
	_input = IntentInput.new()
	_input.name = "NotebookInput"
	_input.picker = func(_px: Vector2) -> Dictionary: return {"target_id": "", "has_ground": false}
	_input.intercept = func(px: Vector2) -> bool: return handle_tap(px)
	_input.enabled = false
	add_child(_input)
	visible = false

# The text as lines that fit `width` UI pixels. Laid out once, so typed text never reflows.
static func wrap(text: String, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	if text.is_empty():
		return lines
	var paragraph := TextParagraph.new()
	paragraph.width = width
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	paragraph.add_string(text, UIKit.font(), UIKit.text_size())
	for i in range(paragraph.get_line_count()):
		var span := paragraph.get_line_range(i)
		lines.append(text.substr(span.x, span.y - span.x).strip_edges(false, true))
	return lines

# Opens the notebook at `start` (a page index from NotebookView.page_of). `page_list` is NotebookView.pages(...).
func open(page_list: Array, start: int = 0) -> void:
	_pages = page_list.duplicate()
	_index = clampi(start, 0, maxi(_pages.size() - 1, 0))
	_layout()
	_open = true
	_grow = 0.4
	visible = true
	_input.enabled = true
	_build()
	_place()

func is_open() -> bool:
	return _open

func page_index() -> int:
	return _index

func page_count() -> int:
	return _pages.size()

# The claim ids on the page now showing, in order.
func shown_claims() -> Array[String]:
	return _shown.duplicate()

func turn(step: int) -> void:
	if not _open or _pages.is_empty():
		return
	var target := clampi(_index + step, 0, _pages.size() - 1)
	if target == _index:
		return
	_index = target
	_build()

# Closes the notebook. `closed` is emitted after the current input event, so the presentation that waits on it resumes
# outside the tap that closed it.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_input.enabled = false
	_clear()
	call_deferred("emit_signal", "closed")

# Returns true when the tap landed on the notebook (and so was used by it).
func handle_tap(px: Vector2) -> bool:
	if not _open:
		return false
	var ui := px / _scale
	if not _rect.grow(2.0).has_point(ui):
		return false
	if _close_ui().has_point(ui):
		close()
	elif ui.x < _rect.position.x + WIDTH * TURN_SPLIT:
		turn(-1)
	else:
		_advance()
	return true

func screen_rect() -> Rect2:
	return Rect2(_rect.position * _scale, _rect.size * _scale)

# Viewport pixels, for tests and for keeping other UI clear of the slab.
func close_point() -> Vector2:
	return _close_ui().get_center() * _scale

func close_rect_px() -> Rect2:
	return Rect2(_close_ui().position * _scale, _close_ui().size * _scale)

func forward_point() -> Vector2:
	return Vector2(_rect.position.x + WIDTH * 0.8, _rect.get_center().y) * _scale

func back_point() -> Vector2:
	return Vector2(_rect.position.x + WIDTH * 0.12, _rect.get_center().y) * _scale

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_SPACE or key.keycode == KEY_ENTER):
		_advance()
		get_viewport().set_input_as_handled()

func _advance() -> void:
	if _index >= _pages.size() - 1:
		close()
	else:
		turn(1)

func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(480, 360)

func _line_height() -> float:
	return ceilf(UIKit.font().get_height(float(UIKit.text_size()))) + LINE_GAP

# The slab is as tall as its tallest page, so turning a page never resizes it.
func _layout() -> void:
	var line_height := _line_height()
	var tallest := line_height
	for page: Dictionary in _pages:
		tallest = maxf(tallest, _body_height(page, line_height))
	_height = BODY_TOP + tallest + FOOT_HEIGHT
	var real := _viewport_size()
	_scale = Diegetic.ui_scale(real)
	var ui := Diegetic.ui_size(real)
	_rect = Rect2(Vector2(roundf((ui.x - WIDTH) * 0.5), roundf((ui.y - _height) * 0.5)), Vector2(WIDTH, _height))

func _body_height(page: Dictionary, line_height: float) -> float:
	var total := 0.0
	var items: Array = page.get("entries", [])
	for i in items.size():
		total += float(_lines(items[i]).size()) * line_height
		if i < items.size() - 1:
			total += ENTRY_GAP
	return total

func _lines(entry: Dictionary) -> PackedStringArray:
	return NotebookSlab.wrap(tr(str(entry.get("text", ""))), WIDTH - PAD * 2.0)

func _build() -> void:
	_clear()
	_shown.clear()
	var outline := SlabMesh.chamfered(WIDTH, _height, 3.0)
	add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.offset(outline, Vector2(2, -2))), Diegetic.slab_material(Color(0, 0, 0, 0.5), "", PRIORITY), -0.2))
	add_child(Diegetic.mesh_instance(SlabMesh.fill(outline), Diegetic.slab_material(BORDER, "wood_dark", PRIORITY + 1), -0.1))
	add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.inset(outline, 2.0)), Diegetic.slab_material(PARCHMENT, "scroll", PRIORITY + 2), 0.0))
	if _pages.is_empty():
		_add_text(tr("ui.systems.notebook_empty"), Vector2(PAD, BODY_TOP))
	else:
		var page: Dictionary = _pages[_index]
		_add_tab(tr("ui.notebook.kind.%s" % str(page["kind"])))
		var y := BODY_TOP
		var items: Array = page["entries"]
		for i in items.size():
			var entry: Dictionary = items[i]
			_shown.append(str(entry["claim"]))
			for line in _lines(entry):
				_add_text(line, Vector2(PAD, y))
				y += _line_height()
			if i < items.size() - 1:
				y += ENTRY_GAP
	_add_footer()

func _add_tab(text: String) -> void:
	var tab_width := ceilf(UIKit.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.text_size()).x) + 12.0
	var tab := SlabMesh.offset(SlabMesh.chamfered(tab_width, TAB_HEIGHT, 2.0), Vector2(PAD, -TAB_TOP))
	add_child(Diegetic.mesh_instance(SlabMesh.fill(tab), Diegetic.slab_material(BRASS, "brass", PRIORITY + 3), -0.05))
	var label := Diegetic.label(text, INK, PRIORITY + 4, _scale)
	label.position = Vector3(PAD + 6.0, -TAB_TOP - 2.0, 0.2)
	add_child(label)

func _add_text(text: String, top_left: Vector2) -> void:
	var label := Diegetic.label(text, INK, PRIORITY + 3, _scale)
	label.position = Vector3(top_left.x, -top_left.y, 0.2)
	add_child(label)

func _add_footer() -> void:
	var middle := _height - FOOT_HEIGHT * 0.5
	if _pages.size() > 1:
		for i in _pages.size():
			var colour := INK if i == _index else Color(BORDER.r, BORDER.g, BORDER.b, 0.35)
			var at := Vector2(PAD + 3.0 + float(i) * 9.0, -middle)
			add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.dot(at, 2.5)), Diegetic.slab_material(colour, "", PRIORITY + 3), -0.05))
	var plaque := SlabMesh.offset(SlabMesh.chamfered(CLOSE_WIDTH, CLOSE_HEIGHT, 3.0), Vector2(WIDTH - PAD - CLOSE_WIDTH, -(_height - FOOT_HEIGHT + 4.0)))
	add_child(Diegetic.mesh_instance(SlabMesh.fill(plaque), Diegetic.slab_material(PLAQUE, "wood", PRIORITY + 3), -0.05))
	var text := tr("ui.systems.notebook_close")
	var text_width := UIKit.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.text_size()).x
	var label := Diegetic.label(text, INK, PRIORITY + 4, _scale)
	label.position = Vector3(WIDTH - PAD - CLOSE_WIDTH + (CLOSE_WIDTH - text_width) * 0.5, -(_height - FOOT_HEIGHT + 4.0 + (CLOSE_HEIGHT - UIKit.text_size()) * 0.5), 0.2)
	add_child(label)

# The close plaque in UI pixels (the slab's own top-left is `_rect.position`).
func _close_ui() -> Rect2:
	return Rect2(_rect.position + Vector2(WIDTH - PAD - CLOSE_WIDTH, _height - FOOT_HEIGHT + 4.0), Vector2(CLOSE_WIDTH, CLOSE_HEIGHT))

func _clear() -> void:
	for child in get_children():
		if child != _input:
			remove_child(child)
			child.free()

func _process(delta: float) -> void:
	if not _open:
		return
	_grow = minf(1.0, _grow + delta * 5.0)
	_place()

func _place() -> void:
	if camera == null or not is_inside_tree():
		return
	var overshoot := 1.0 + sin(minf(_grow, 1.0) * PI) * 0.05 * (1.0 - _grow)
	global_transform = Diegetic.transform_for(camera, _viewport_size(), _rect.position, _grow * overshoot, Vector2(WIDTH * 0.5, -_height * 0.5), true)
