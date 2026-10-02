class_name PaintedProp
extends Node3D

# One thing in a painted room that answers a tap (props.json, see docs/art/painted_room.md):
#   "cutout"  - a piece of the painting lifted onto a card at its own depth, cut out by a mask; at rest it lies
#               exactly over the painting, and its reactions move it (the room shows the painting without it)
#   "hotspot" - a region of the painting with no moving part: its reactions are sound, speech, effects (later)
# Reactions are a small vocabulary of moves, so a new toy is data, not code.

signal reacted(prop_id: String, reaction: String)

const REACTIONS := ["wobble", "hop", "squash", "shiver", "spin"]

var prop_id := ""
var kind := "hotspot"
var reactions: Dictionary = {}
var rect := Rect2i()
var depth := 1.0
var _mask: Image
var _polygon := PackedVector2Array()
var _card: MeshInstance3D
var _material: ShaderMaterial
var _axis := Vector3.BACK
var _up := Vector3.UP
var _tween: Tween
var _uses := 0

# Wobble state, applied as a rotation about the camera's view axis at the pivot, plus a lift and a squash.
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

func setup(room: PaintedRoom, data: Dictionary, plate: Texture2D, plate_smooth: Texture2D) -> void:
	prop_id = str(data.get("id", "prop"))
	name = prop_id
	kind = str(data.get("kind", "hotspot"))
	reactions = data.get("reactions", {"press": ["wobble"]})
	_axis = room.view_axis()
	_up = room.view_up()
	if data.has("polygon"):
		for point in data["polygon"]:
			_polygon.append(Vector2(float(point[0]), float(point[1])))
	if kind == "cutout":
		_mask = Image.load_from_file(ProjectSettings.globalize_path(room.room_dir.path_join(str(data["mask"]))))
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
	depth = float(data.get("depth", _nearest_depth(room))) * 0.97
	position = room.pixel_at_depth(pivot_px, depth)
	if kind == "cutout":
		_build_card(room, plate, plate_smooth)

# The card stands at the object's NEAREST depth (a low percentile over its pixels): at its centre depth, the
# room's own surface would poke through wherever the object comes closer (a robe's hem on the floor).
# Whatever stands nearer still passes in front of it.
func _nearest_depth(room: PaintedRoom) -> float:
	var depths := PackedFloat32Array()
	for y in range(rect.position.y, rect.end.y, 4):
		for x in range(rect.position.x, rect.end.x, 4):
			if contains(Vector2(x, y)):
				depths.append(room.depth_at(Vector2(x, y)))
	if depths.is_empty():
		return room.depth_at(Vector2(rect.get_center()))
	depths.sort()
	return depths[int(depths.size() * 0.05)]

func _build_card(room: PaintedRoom, plate: Texture2D, plate_smooth: Texture2D) -> void:
	# A flat at the prop's depth: its corners are the rect's corners seen at that depth, so its plate UV is
	# simply each corner's screen position.
	var corners := [Vector2(rect.position), Vector2(rect.end.x, rect.position.y), Vector2(rect.end), Vector2(rect.position.x, rect.end.y)]
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	var size := room.image_size()
	for corner in corners:
		vertices.append(room.pixel_at_depth(corner, depth) - position)
		uvs.append(corner / size)
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
	_material.shader = load("res://game/world/painted/painted_cutout.gdshader")
	_material.set_shader_parameter("plate", plate)
	_material.set_shader_parameter("plate_smooth", plate_smooth)
	_material.set_shader_parameter("mask", ImageTexture.create_from_image(_mask))
	_card = MeshInstance3D.new()
	_card.mesh = mesh
	_card.material_override = _material
	_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_card)

func set_psx(on: bool, texel_res: Vector2, snap_res: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("psx", on)
		_material.set_shader_parameter("texel_res", texel_res)
		_material.set_shader_parameter("snap_res", snap_res)

# True when the painting pixel `px` belongs to this prop.
func contains(px: Vector2) -> bool:
	if not Rect2(rect).has_point(px):
		return false
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
	var list: Array = reactions.get(trigger, [])
	if list.is_empty():
		return ""
	var reaction := str(list[_uses % list.size()])
	_uses += 1
	play(reaction)
	reacted.emit(prop_id, reaction)
	return reaction

func play(reaction: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	turn = 0.0
	lift = 0.0
	squash = 0.0
	_tween = create_tween()
	match reaction:
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
			_tween.tween_callback(func() -> void: turn = 0.0)
	if _material != null:
		_material.set_shader_parameter("flash", Vector3(0.08, 0.07, 0.04))
		_tween.parallel().tween_method(func(v: float) -> void: _material.set_shader_parameter("flash", Vector3(0.08, 0.07, 0.04) * v), 1.0, 0.0, 0.3)

func _apply() -> void:
	if _card == null:
		return
	var b := Basis(_axis, turn)
	b = b * Basis.from_scale(Vector3(1.0 + squash * 0.6, 1.0 - squash, 1.0))
	_card.transform = Transform3D(b, _up * lift)
