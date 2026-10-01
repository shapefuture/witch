class_name SpeechBubble
extends Node3D

# One speech (or thought) bubble, hung in the scene next to whoever is talking. A faceted
# parchment slab with a pointed tail, a brass name tab, ink text typed out by SubtitleUI, and a
# blinking "next" mark. Speech gets a tail to the speaker; narration is a scalloped cloud with a
# trail of dots to the witch. See Diegetic for how it is placed.

const PAD := 6.0
const MAX_WIDTH := 220.0
const PARCHMENT := Color(1.0, 0.97, 0.88)
const BORDER := Color(0.30, 0.21, 0.15)
const INK := Color(0.15, 0.10, 0.08)
const THOUGHT_TINT := Color(0.90, 0.86, 0.99)
const THOUGHT_BORDER := Color(0.27, 0.19, 0.38)
const THOUGHT_INK := Color(0.16, 0.11, 0.26)
const BRASS := Color(0.84, 0.66, 0.28)

var camera: Camera3D

var _rect := Rect2()   # UI pixels
var _scale := 1.0
var _pivot := Vector2.ZERO
var _label: Label3D
var _wrapped := ""
var _prompt: Label3D
var _grow := 1.0
var _clock := 0.0
var _active := false

func _ready() -> void:
	visible = false

func is_showing() -> bool:
	return _active

# Builds the bubble for one line and pops it in. `anchor_world` is where the speaker's head is.
# `avoid` is a list of screen Rect2s (the picture's focal points) the slab should not sit on.
func present(speaker: String, text: String, anchor_world: Vector3, narration: bool, avoid: Array = []) -> void:
	_clear()
	var real_size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(480, 360)
	_scale = Diegetic.ui_scale(real_size)
	var viewport_size := Diegetic.ui_size(real_size)
	var font := UIKit.font()
	var wrap := minf(MAX_WIDTH, viewport_size.x * 0.58) - PAD * 2.0
	# Lines are broken HERE, once, so the typewriter reveals characters without the text reflowing.
	var paragraph := TextParagraph.new()
	paragraph.width = wrap
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	paragraph.add_string(text, font, UIKit.FONT_SIZE)
	var lines := PackedStringArray()
	for i in range(paragraph.get_line_count()):
		var span := paragraph.get_line_range(i)
		lines.append(text.substr(span.x, span.y - span.x).strip_edges(false, true))
	_wrapped = "\n".join(lines)
	var measured := paragraph.get_size()
	var w := maxf(ceilf(measured.x) + PAD * 2.0 + 2.0, 60.0)
	var h := ceilf(measured.y) + PAD * 2.0 + 8.0
	var anchor_px := viewport_size * 0.5
	if camera != null:
		anchor_px = camera.unproject_position(anchor_world) / _scale
	var safe := Diegetic.safe_rect(viewport_size)
	var avoid_ui: Array = []
	for hero in avoid:
		avoid_ui.append(Rect2((hero as Rect2).position / _scale, (hero as Rect2).size / _scale))
	_rect = _best_rect(Vector2(w, h), anchor_px, safe, avoid_ui)
	var x := _rect.position.x
	var y := _rect.position.y
	var to_anchor := Vector2(anchor_px.x - x, -(anchor_px.y - y))
	var centre := Vector2(w * 0.5, -h * 0.5)
	var direction := (to_anchor - centre).normalized()
	var tip := to_anchor - direction * 9.0
	_pivot = tip
	var tint := THOUGHT_TINT if narration else PARCHMENT
	var border := THOUGHT_BORDER if narration else BORDER
	var ink := THOUGHT_INK if narration else INK
	var outline := SlabMesh.cloud(w, h) if narration else SlabMesh.with_tail(w, h, tip)
	add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.offset(outline, Vector2(2, -2))), Diegetic.slab_material(Color(0, 0, 0, 0.5), "", 10), -0.2))
	add_child(Diegetic.mesh_instance(SlabMesh.fill(outline), Diegetic.slab_material(border, "wood_dark", 11), -0.1))
	add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.inset(outline, 2.0)), Diegetic.slab_material(tint, "scroll", 12), 0.0))
	# a lit bevel: a lighter slab nudged up-left and a darker one down-right under the face, so the
	# bubble reads as a thick carved piece rather than a flat sticker
	add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.offset(SlabMesh.inset(outline, 2.0), Vector2(-1, 1))), Diegetic.slab_material(Color(1.0, 1.0, 0.95, 0.55), "", 12), 0.05))
	add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.offset(SlabMesh.inset(outline, 2.0), Vector2(1.5, -1.5))), Diegetic.slab_material(Color(0.25, 0.17, 0.10, 0.45), "", 12), -0.02))
	if narration:
		# the trail of thought: three shrinking dots from the cloud toward the thinker
		for k in range(3):
			var t := (k + 1.0) / 4.0
			var at := centre.lerp(tip, 0.55 + t * 0.45)
			var radius := 3.4 - k * 0.9
			add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.dot(at, radius + 1.0)), Diegetic.slab_material(border, "", 11), -0.1))
			add_child(Diegetic.mesh_instance(SlabMesh.fill(SlabMesh.dot(at, radius)), Diegetic.slab_material(tint, "scroll", 12), 0.0))
	if not speaker.is_empty():
		var tab_w := ceilf(font.get_string_size(speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FONT_SIZE).x) + 8.0
		var tab := PackedVector2Array([Vector2(5, 0), Vector2(5, 11), Vector2(9, 13), Vector2(5 + tab_w - 4, 13), Vector2(5 + tab_w, 11), Vector2(5 + tab_w, 0)])
		add_child(Diegetic.mesh_instance(SlabMesh.fill(tab), Diegetic.slab_material(BRASS, "brass", 11), -0.05))
		var name_label := Diegetic.label(speaker, INK, 13, _scale)
		name_label.position = Vector3(9, 11, 0.2)
		add_child(name_label)
	_label = Diegetic.label(_wrapped, ink, 13, _scale)
	_label.position = Vector3(PAD, -PAD, 0.2)
	add_child(_label)
	_prompt = Diegetic.label("▼", border, 13, _scale)
	_prompt.position = Vector3(w - PAD - 8.0, -(h - 10.0), 0.2)
	_prompt.visible = false
	add_child(_prompt)
	_grow = 0.35
	_clock = 0.0
	_active = true
	visible = true
	_place()

# Tries a handful of spots around the speaker's head and keeps the one that covers the least of the
# picture's focal points (the light pool, the arch, the statue) and none of the speaker.
func _best_rect(size: Vector2, anchor_px: Vector2, safe: Rect2, avoid: Array) -> Rect2:
	var body := Rect2(anchor_px.x - 16.0, anchor_px.y - 6.0, 32.0, 64.0)
	var spots := [
		Vector2(anchor_px.x - size.x * 0.35, anchor_px.y - size.y - 24.0),
		Vector2(anchor_px.x - size.x * 0.70, anchor_px.y - size.y - 24.0),
		Vector2(anchor_px.x - size.x * 0.5, anchor_px.y - size.y - 52.0),
		Vector2(anchor_px.x - size.x - 22.0, anchor_px.y - size.y * 0.7),
		Vector2(anchor_px.x + 22.0, anchor_px.y - size.y * 0.7),
		Vector2(anchor_px.x - size.x * 0.35, anchor_px.y + 34.0),
	]
	var best := Rect2()
	var best_score := INF
	for i in range(spots.size()):
		var at: Vector2 = spots[i]
		at.x = clampf(at.x, safe.position.x, maxf(safe.position.x, safe.end.x - size.x))
		at.y = clampf(at.y, safe.position.y, maxf(safe.position.y, safe.end.y - size.y))
		var candidate := Rect2(at, size)
		var score := float(i) * 25.0 + candidate.get_center().distance_to(anchor_px) * 0.5
		score += _overlap(candidate, body) * 6.0
		for hero in avoid:
			score += _overlap(candidate, hero as Rect2)
		if score < best_score:
			best_score = score
			best = candidate
	return best

static func _overlap(a: Rect2, b: Rect2) -> float:
	var common := a.intersection(b)
	return common.size.x * common.size.y if common.has_area() else 0.0

# The text as broken into lines for this bubble (what SubtitleUI types out).
func wrapped_text() -> String:
	return _wrapped

func set_shown(count: int) -> void:
	if _label != null:
		_label.text = _wrapped.substr(0, count)

func show_all() -> void:
	if _label != null:
		_label.text = _wrapped

func set_prompt(on: bool) -> void:
	if _prompt != null:
		_prompt.visible = on

func dismiss() -> void:
	_active = false
	visible = false
	_clear()

# The bubble's rectangle in viewport pixels (for tests and for keeping other UI clear of it).
func screen_rect() -> Rect2:
	return Rect2(_rect.position * _scale, _rect.size * _scale)

func _process(delta: float) -> void:
	if not _active:
		return
	_clock += delta
	_grow = minf(1.0, _grow + delta * 5.5)
	_place()
	if _prompt != null and _prompt.visible:
		_prompt.modulate.a = 1.0 if fmod(_clock, 0.9) < 0.55 else 0.25

func _place() -> void:
	if camera == null or not is_inside_tree():
		return
	var overshoot := 1.0 + sin(minf(_grow, 1.0) * PI) * 0.06 * (1.0 - _grow)
	var bob := floorf(sin(_clock * 2.4) * 0.5 + 0.5)
	global_transform = Diegetic.transform_for(camera, get_viewport().get_visible_rect().size, _rect.position + Vector2(0, bob), _grow * overshoot, _pivot, true)

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_label = null
	_prompt = null
