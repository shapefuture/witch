class_name PaintedProp
extends Node3D

# One thing in a painted room that answers a poke (props.json, see docs/art/painted_room.md):
#   "cutout"  - a piece of the painting lifted onto a card at its own depth, cut out by a mask; at rest it lies
#               exactly over the painting, and its reactions move it (the room shows the painting without it)
#   "hotspot" - a region of the painting with no moving part: its card is the same painting, drawn only while a
#               reaction runs, and the reaction is the paint itself answering (ripple, shake, swell, flash)
# A poke never does nothing: every reaction is a move, a sound and optionally a line (a text key, never prose).
# The vocabulary below is the whole of what props.json may name, so a new toy is data, not code.

signal reacted(prop_id: String, reaction: String)
# reaction + the sound to play + the text key to show ("" when there is none)
signal answered(prop_id: String, reaction: String, sound: String, say: String)

# Every reaction name, with the sound it plays when props.json gives none (tools/painted/synth.py writes them).
const VOCABULARY := {
	"wobble": "creak", "hop": "boing", "squash": "thunk", "shiver": "rattle", "spin": "whoosh",
	"droop": "creak", "peek": "creak", "blink": "chime", "rattle": "rattle", "bob": "boing",
	"tilt_fall": "thunk", "swing": "tick", "pulse": "blip", "ripple": "sparkle", "flash": "sparkle",
}
# A hotspot has nothing to move: these are the answers it can give, and every other name maps onto one of them.
const HOTSPOT_MOVES := ["ripple", "flash", "blink", "pulse", "rattle"]
const HOTSPOT_ALIAS := {
	"wobble": "rattle", "shiver": "rattle", "squash": "pulse", "hop": "pulse", "bob": "pulse", "droop": "ripple",
	"peek": "ripple", "spin": "ripple", "swing": "ripple", "tilt_fall": "ripple",
}
const CUTOUT_ALIAS := {"ripple": "shiver", "flash": "blink"}
const GLOW := Vector3(0.1, 0.085, 0.045)

var prop_id := ""
var kind := "hotspot"
# trigger -> names (what the capture and the tests walk); voices: trigger -> [{do, sound, say}] (what plays)
var reactions: Dictionary = {}
var voices: Dictionary = {}
var rect := Rect2i()
var depth := 1.0
var last_reaction := ""
var last_sound := ""
var last_say := ""
var _mask: Image
var _polygon := PackedVector2Array()
var _card: MeshInstance3D
var _material: ShaderMaterial
var _axis := Vector3.BACK
var _up := Vector3.UP
var _toward := Vector3.BACK
var _mpp := 0.002          # metres per painting pixel at this prop's depth
var _glow := GLOW
var _flash_gain := 1.0
var _tween: Tween
var _glint: Tween
var _uses := 0

# Cutout state, applied to the card about the pivot: a turn about the view axis, a lift (metres), a squash and a
# uniform grow, a shift in painting pixels, a push towards the camera (metres).
var turn := 0.0:
	set(value):
		turn = value
		_apply()
var lift := 0.0:
	set(value):
		lift = value
		_apply()
var squash := 0.0:
	set(value):
		squash = value
		_apply()
var grow := 0.0:
	set(value):
		grow = value
		_apply()
var shift := Vector2.ZERO:
	set(value):
		shift = value
		_apply()
var push := 0.0:
	set(value):
		push = value
		_apply()
# Both kinds: how strongly the card glows (0..1), and a hotspot's ripple progress, shake (px) and swell.
var flash := 0.0:
	set(value):
		flash = value
		_apply()
var ripple := 0.0:
	set(value):
		ripple = value
		_apply()
var shake := Vector2.ZERO:
	set(value):
		shake = value
		_apply()
var zoom := 0.0:
	set(value):
		zoom = value
		_apply()

func setup(room: PaintedRoom, data: Dictionary, plate: Texture2D, plate_smooth: Texture2D) -> void:
	prop_id = str(data.get("id", "prop"))
	name = prop_id
	kind = str(data.get("kind", "hotspot"))
	_parse_reactions(data.get("reactions", {"press": ["wobble"]}))
	if data.has("glow"):
		_glow = Vector3(float(data["glow"][0]), float(data["glow"][1]), float(data["glow"][2]))
	_axis = room.view_axis()
	_up = room.view_up()
	if data.has("polygon"):
		for point in data["polygon"]:
			_polygon.append(Vector2(float(point[0]), float(point[1])))
	if data.has("mask"):
		_mask = Image.load_from_file(ProjectSettings.globalize_path(room.room_dir.path_join(str(data["mask"]))))
	if data.has("rect"):
		var r: Array = data["rect"]
		rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	elif not _polygon.is_empty():
		var bounds := Rect2(_polygon[0], Vector2.ZERO)
		for point in _polygon:
			bounds = bounds.expand(point)
		rect = Rect2i(bounds)
	var pivot_px := Vector2(rect.get_center())
	if data.has("pivot"):
		pivot_px = Vector2(float(data["pivot"][0]), float(data["pivot"][1]))
	# A cutout stands at its nearest depth (see _nearest_depth); a hotspot's card must clear everything it covers.
	depth = float(data.get("depth", _nearest_depth(room, 0.05 if kind == "cutout" else 0.0))) * 0.97
	position = room.pixel_at_depth(pivot_px, depth)
	_toward = (room.pixel_at_depth(Vector2.ZERO, 0.0) - position).normalized()
	_mpp = room.pixel_at_depth(Vector2(641.0, 360.0), depth).x - room.pixel_at_depth(Vector2(640.0, 360.0), depth).x
	if _mask != null:
		_build_card(room, plate, plate_smooth)

func _parse_reactions(raw: Dictionary) -> void:
	for trigger in raw:
		var names: Array[String] = []
		var spoken: Array[Dictionary] = []
		for entry in raw[trigger]:
			var voice: Dictionary = {"do": "", "sound": "", "say": ""}
			if entry is Dictionary:
				voice["do"] = str(entry.get("do", "wobble"))
				voice["sound"] = str(entry.get("sound", ""))
				voice["say"] = str(entry.get("say", ""))
			else:
				voice["do"] = str(entry)
			if str(voice["sound"]).is_empty():
				voice["sound"] = str(VOCABULARY.get(str(voice["do"]), "ping"))
			names.append(str(voice["do"]))
			spoken.append(voice)
		reactions[trigger] = names
		voices[trigger] = spoken

# Problems in a props.json entry, for the tests and the tools: unknown reaction names, empty lists.
static func problems(data: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var id := str(data.get("id", "?"))
	var kind_name := str(data.get("kind", "hotspot"))
	var table: Dictionary = data.get("reactions", {})
	if table.is_empty():
		found.append("%s: no reactions" % id)
	for trigger in table:
		if (table[trigger] as Array).is_empty():
			found.append("%s: %s has no reactions" % [id, trigger])
		for entry in table[trigger]:
			var move_name := str(entry.get("do", "")) if entry is Dictionary else str(entry)
			if not VOCABULARY.has(move_name):
				found.append("%s: unknown reaction '%s'" % [id, move_name])
			elif kind_name == "hotspot" and not (move_name in HOTSPOT_MOVES or HOTSPOT_ALIAS.has(move_name)):
				found.append("%s: a hotspot cannot '%s'" % [id, move_name])
	if kind_name == "hotspot" and not data.has("polygon"):
		found.append("%s: a hotspot needs a polygon" % id)
	if kind_name == "cutout" and (not data.has("mask") or not data.has("rect")):
		found.append("%s: a cutout needs a mask and a rect" % id)
	return found

# The card stands at the object's NEAREST depth (a low percentile over its pixels): at its centre depth, the
# room's own surface would poke through wherever the object comes closer (a robe's hem on the floor).
# Whatever stands nearer still passes in front of it.
func _nearest_depth(room: PaintedRoom, percentile: float) -> float:
	var depths := PackedFloat32Array()
	for y in range(rect.position.y, rect.end.y, 4):
		for x in range(rect.position.x, rect.end.x, 4):
			if contains(Vector2(x, y)):
				depths.append(room.depth_at(Vector2(x, y)))
	if depths.is_empty():
		return room.depth_at(Vector2(rect.get_center()))
	depths.sort()
	return depths[int(depths.size() * percentile)]

func _build_card(room: PaintedRoom, plate: Texture2D, plate_smooth: Texture2D) -> void:
	# A flat at the prop's depth: its corners are the rect's corners seen at that depth, so its plate UV is
	# simply each corner's screen position.
	var corners := [Vector2(rect.position), Vector2(rect.end.x, rect.position.y), Vector2(rect.end), Vector2(rect.position.x, rect.end.y)]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	for corner in corners:
		vertices.append(room.pixel_at_depth(corner, depth) - position)
		uvs.append(room.plate_uv(corner))
		uvs2.append((corner - Vector2(rect.position)) / Vector2(rect.size))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_material = ShaderMaterial.new()
	_material.shader = load("res://game/world/painted/painted_%s.gdshader" % ("cutout" if kind == "cutout" else "hotspot"))
	_material.set_shader_parameter("plate", plate)
	_material.set_shader_parameter("plate_smooth", plate_smooth)
	_material.set_shader_parameter("mask", ImageTexture.create_from_image(_mask))
	if kind != "cutout":
		_material.set_shader_parameter("plate_px", size)
		_material.set_shader_parameter("center_uv", Vector2(rect.get_center()) / size)
	_card = MeshInstance3D.new()
	_card.mesh = mesh
	_card.material_override = _material
	_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card.visible = kind == "cutout"
	add_child(_card)

func set_psx(on: bool, texel_res: Vector2, snap_res: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("psx", on)
		_material.set_shader_parameter("texel_res", texel_res)
		_material.set_shader_parameter("snap_res", snap_res)

# Whether the card is on screen: a cutout always is, a hotspot's only while it reacts.
func card_visible() -> bool:
	return _card != null and _card.visible

func set_card_hidden(hidden: bool) -> void:
	if _card != null:
		_card.visible = false if hidden else (kind == "cutout")

# True when the painting pixel `px` belongs to this prop.
func contains(px: Vector2) -> bool:
	if not Rect2(rect).has_point(px):
		return false
	if kind == "hotspot" and not _polygon.is_empty():
		return Geometry2D.is_point_in_polygon(px, _polygon)
	if _mask != null:
		var local := Vector2i(px) - rect.position
		local.x = clampi(local.x * _mask.get_width() / maxi(rect.size.x, 1), 0, _mask.get_width() - 1)
		local.y = clampi(local.y * _mask.get_height() / maxi(rect.size.y, 1), 0, _mask.get_height() - 1)
		return _mask.get_pixelv(local).r > 0.5
	if not _polygon.is_empty():
		return Geometry2D.is_point_in_polygon(px, _polygon)
	return true

# Plays the reaction for `trigger` ("press" for now). Repeated presses walk through the list, so poking the
# same thing twice can answer differently.
func react(trigger: String = "press") -> String:
	var list: Array = voices.get(trigger, [])
	if list.is_empty():
		return ""
	var voice: Dictionary = list[_uses % list.size()]
	_uses += 1
	last_reaction = str(voice["do"])
	last_sound = str(voice["sound"])
	last_say = str(voice["say"])
	play(last_reaction)
	reacted.emit(prop_id, last_reaction)
	answered.emit(prop_id, last_reaction, last_sound, last_say)
	return last_reaction

# True from the poke until the reaction has come to rest: what a player can see happening.
func reacting() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()

# True while anything about the prop is off its rest pose: it moves, glows, ripples.
func displaced() -> bool:
	return turn != 0.0 or lift != 0.0 or squash != 0.0 or grow != 0.0 or shift != Vector2.ZERO or push != 0.0 \
		or flash != 0.0 or ripple != 0.0 or shake != Vector2.ZERO or zoom != 0.0

# Back to rest at once: a cutout's card lies exactly over the painting, a hotspot's card is hidden.
func rest() -> void:
	for tween in [_tween, _glint]:
		if tween != null and (tween as Tween).is_valid():
			(tween as Tween).kill()
	_tween = null
	_glint = null
	_flash_gain = 1.0
	turn = 0.0
	lift = 0.0
	squash = 0.0
	grow = 0.0
	shift = Vector2.ZERO
	push = 0.0
	flash = 0.0
	ripple = 0.0
	shake = Vector2.ZERO
	zoom = 0.0

func play(reaction: String) -> void:
	rest()
	var move := reaction
	if not VOCABULARY.has(move):
		move = "wobble"
	if kind == "hotspot":
		move = str(HOTSPOT_ALIAS.get(move, move))
	else:
		move = str(CUTOUT_ALIAS.get(move, move))
	_tween = create_tween()
	match move:
		"wobble":
			for angle in [0.14, -0.11, 0.07, -0.04, 0.0]:
				_tween.tween_property(self, "turn", angle, 0.11).set_trans(Tween.TRANS_SINE)
		"hop":
			_tween.tween_property(self, "squash", 0.18, 0.08)
			_tween.tween_property(self, "squash", -0.12, 0.08)
			_tween.parallel().tween_property(self, "lift", 0.22, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			_tween.tween_property(self, "lift", 0.0, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			_tween.parallel().tween_property(self, "squash", 0.14, 0.16)
			_tween.tween_property(self, "squash", 0.0, 0.12).set_trans(Tween.TRANS_ELASTIC)
		"squash":
			_tween.tween_property(self, "squash", 0.25, 0.1)
			_tween.tween_property(self, "squash", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"shiver":
			for i in 8:
				_tween.tween_property(self, "turn", 0.03 if i % 2 == 0 else -0.03, 0.04)
			_tween.tween_property(self, "turn", 0.0, 0.04)
		"spin":
			_tween.tween_property(self, "turn", TAU, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"droop":
			# Leans over and sags like a toy that lost interest, holds it, then comes back slowly.
			_tween.tween_property(self, "turn", 0.2, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_tween.parallel().tween_property(self, "squash", 0.08, 0.35).set_trans(Tween.TRANS_SINE)
			_tween.tween_interval(0.25)
			_tween.tween_property(self, "turn", 0.0, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_tween.parallel().tween_property(self, "squash", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
		"peek":
			# Slides a little out towards you, looks around, slides back.
			var out := Vector2(maxf(float(rect.size.x) * 0.12, 4.0), -maxf(float(rect.size.y) * 0.04, 2.0))
			_tween.tween_property(self, "shift", out, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.parallel().tween_property(self, "push", depth * 0.1, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.tween_interval(0.3)
			_tween.tween_property(self, "shift", Vector2.ZERO, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.parallel().tween_property(self, "push", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		"blink":
			_flash_gain = 2.6
			for i in 3:
				_tween.tween_property(self, "flash", 1.0, 0.07)
				_tween.tween_property(self, "flash", 0.0, 0.09)
		"rattle":
			if kind == "hotspot":
				_flash_gain = 1.2
				_tween.tween_method(func(v: float) -> void: shake = Vector2(sin(v * TAU * 7.0) * (1.0 - v) * 4.5, 0.0), 0.0, 1.0, 0.45)
				_tween.parallel().tween_method(func(v: float) -> void: flash = v, 1.0, 0.0, 0.45)
			else:
				for i in 10:
					var decay := 1.0 - float(i) / 10.0
					var direction := 1.0 if i % 2 == 0 else -1.0
					_tween.tween_property(self, "shift", Vector2(direction * 3.5 * decay, 0.0), 0.03)
					_tween.parallel().tween_property(self, "turn", direction * 0.025 * decay, 0.03)
		"bob":
			var amplitude := clampf(float(rect.size.y) * 0.12, 5.0, 14.0)
			for i in 4:
				var decay := 1.0 - float(i) * 0.22
				var direction := -1.0 if i % 2 == 0 else 0.35
				_tween.tween_property(self, "shift", Vector2(0.0, direction * amplitude * decay), 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.tween_property(self, "shift", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_SINE)
		"tilt_fall":
			# Tips over about its foot, hangs there, and falls back with a bounce.
			_tween.tween_property(self, "turn", 0.55, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_tween.tween_interval(0.12)
			_tween.tween_property(self, "turn", 0.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_tween.parallel().tween_property(self, "squash", 0.1, 0.1).set_delay(0.38)
			_tween.tween_property(self, "squash", 0.0, 0.2).set_trans(Tween.TRANS_ELASTIC)
		"swing":
			# A pendulum about the pivot (the clock's hook): wide, then settling.
			for angle in [0.3, -0.24, 0.17, -0.1, 0.05, 0.0]:
				_tween.tween_property(self, "turn", angle, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		"pulse":
			if kind == "hotspot":
				_tween.tween_property(self, "zoom", 0.07, 0.1).set_trans(Tween.TRANS_SINE)
				_tween.parallel().tween_property(self, "flash", 0.6, 0.1)
				_tween.tween_property(self, "zoom", -0.03, 0.12).set_trans(Tween.TRANS_SINE)
				_tween.parallel().tween_property(self, "flash", 0.0, 0.2)
				_tween.tween_property(self, "zoom", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			else:
				_tween.tween_property(self, "grow", 0.14, 0.09)
				_tween.tween_property(self, "grow", -0.05, 0.1)
				_tween.tween_property(self, "grow", 0.0, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"ripple":
			_flash_gain = 1.4
			_tween.tween_property(self, "ripple", 1.0, 0.9).from(0.01)
			_tween.parallel().tween_property(self, "flash", 0.5, 0.12).from(0.0)
			_tween.parallel().tween_property(self, "flash", 0.0, 0.5).from(0.5).set_delay(0.12)
		"flash":
			_flash_gain = 3.0
			_tween.tween_property(self, "flash", 1.0, 0.06)
			_tween.tween_property(self, "flash", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if kind == "cutout" and move != "blink":
		# Every cutout reaction gets a quick glint, so even the smallest move reads as an answer.
		_glint = create_tween()
		_glint.tween_property(self, "flash", 0.0, 0.3).from(1.0)
	_tween.tween_callback(rest)

func _apply() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("flash", _glow * (flash * _flash_gain))
	if kind == "cutout":
		var scale_vector := Vector3(1.0 + squash * 0.6, 1.0 - squash, 1.0) * (1.0 + grow)
		var basis := Basis(_axis, turn) * Basis.from_scale(scale_vector)
		var offset := _up * lift + Vector3.RIGHT * (shift.x * _mpp) + _up * (-shift.y * _mpp) + _toward * push
		_card.transform = Transform3D(basis, offset)
	else:
		_material.set_shader_parameter("ripple", ripple)
		_material.set_shader_parameter("shake", shake)
		_material.set_shader_parameter("zoom", zoom)
		_card.visible = ripple > 0.0 or flash > 0.0 or zoom != 0.0 or shake != Vector2.ZERO
