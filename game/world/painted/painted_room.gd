class_name PaintedRoom
extends Node3D

# An experiment (docs/art/painted_room.md): a painted still made into a room. tools/painted/build_painted.py
# writes room.json (the painting's camera, a grid of depths in metres, the light the characters stand in);
# props.json, written by hand or by tools/painted/lift_prop.py, lifts parts of the painting into things that
# answer a tap. From the painting's camera the frame is the painting; characters stand in it, lit by it.

signal prop_pressed(prop_id: String, reaction: String, world_position: Vector3)

const PLATE_SHADER := preload("res://game/world/painted/painted_plate.gdshader")
const SHADOW_SHADER := preload("res://game/world/painted/painted_shadow.gdshader")
const SCREEN_SHADER := preload("res://game/world/painted/painted_screen.gdshader")
# Where each character looks: away from the camera, into the hall, as in the painting.
const FACING := {"witch": PI, "raccoon": PI * 0.92}
const SHADOW_RADIUS := {"witch": 0.32, "raccoon": 0.28}

@export var room_dir := "res://assets/painted/hall_clean"
@export var psx := true
@export var texel_res := Vector2(640, 360)
@export var snap_res := Vector2(480, 270)
# How strongly the painting's floor light and its beam reach the characters (they are mostly backlit here).
@export var actor_light := 1.0
@export var actor_sun := 0.4
@export var actor_rim := 0.25
# Use the room's margin (overscan.json, see PaintedOverscan) when it has one; false = the painting as it was,
# zooming in to hide its edges.
@export var overscan := true

var room: Dictionary = {}
var camera: Camera3D
var actors: Dictionary = {}
var props: Array[PaintedProp] = []
var _focal := 1.0
var _pitch := 0.0
var _eye := 1.3
var _size := Vector2(1280, 720)
var _grid_w := 0
var _grid_h := 0
var _grid := PackedFloat32Array()
var _step := 8.0
var _margin := Vector2.ZERO
var _grid_origin := Vector2.ZERO
var _offset := Vector3.ZERO
var _roll_deg := 0.0
var _plate_material: ShaderMaterial
var _screen_material: ShaderMaterial
var _plate: Texture2D
var _plate_smooth: Texture2D

func _ready() -> void:
	var text := FileAccess.get_file_as_string(room_dir.path_join("room.json"))
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("PaintedRoom: no room.json in %s" % room_dir)
		return
	room = parsed
	_size = Vector2(float(room["image_size"][0]), float(room["image_size"][1]))
	_eye = float(room["eye_height"])
	_pitch = deg_to_rad(float(room["pitch_deg"]))
	_focal = (_size.y * 0.5) / tan(deg_to_rad(float(room["fov_v"])) * 0.5)
	_grid_w = int(room["grid_size"][0])
	_grid_h = int(room["grid_size"][1])
	_step = float(room["grid_step"])
	_grid = PackedFloat32Array(room["depth_grid"])
	var props_data := _load_props()
	var plate_file := str(room.get("plate", "plate.png"))
	var empty_file := str(props_data.get("plate_empty", ""))
	var margin_data: Dictionary = PaintedOverscan.load_for(room, room_dir) if overscan else {}
	if not margin_data.is_empty():
		_margin = PaintedOverscan.margin_of(margin_data)
		_grid_origin = Vector2(float(margin_data["grid_origin"][0]), float(margin_data["grid_origin"][1]))
		_grid_w = int(margin_data["grid_size"][0])
		_grid_h = int(margin_data["grid_size"][1])
		_grid = PackedFloat32Array(margin_data["depth_grid"])
		plate_file = str(margin_data.get("plate", plate_file))
		empty_file = str(margin_data.get("plate_empty", plate_file)) if empty_file != "" else ""
	_plate = _texture(plate_file)
	# With lifted props the room shows the painting without them; the props put them back.
	var behind := _plate
	if empty_file != "":
		behind = _texture(empty_file)
	_plate_smooth = _plate
	_build_camera()
	_build_room(behind)
	for id in room.get("actors", {}):
		_spawn_actor(str(id), room["actors"][id])
	for data in props_data.get("props", []):
		var prop := PaintedProp.new()
		add_child(prop)
		prop.setup(self, data, _plate, _plate_smooth)
		props.append(prop)
	_build_screen()
	set_psx(psx)

func _load_props() -> Dictionary:
	var path := room_dir.path_join("props.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _texture(file: String) -> Texture2D:
	return load(room_dir.path_join(file)) as Texture2D

# ---- the painting's camera ---------------------------------------------------------------------------

func image_size() -> Vector2:
	return _size

func view_axis() -> Vector3:
	return Vector3(0.0, sin(_pitch), -cos(_pitch))

func view_up() -> Vector3:
	return Vector3(0.0, cos(_pitch), sin(_pitch))

# Extra painting (pixels of the plate) on each side of the frame; zero without overscan.
func margin() -> Vector2:
	return _margin

# Where painting pixel `px` sits in the plate texture (0..1), margin included.
func plate_uv(px: Vector2) -> Vector2:
	return PaintedOverscan.plate_uv(px, _size, _margin)

# The shape of the view the camera has to cover: the window's, once there is a margin to cover it with (the
# painting's own shape otherwise, as before the margin existed).
func view_aspect() -> float:
	if _margin == Vector2.ZERO or camera == null or not camera.is_inside_tree():
		return _size.x / _size.y
	var view := camera.get_viewport().get_visible_rect().size
	return view.x / maxf(view.y, 1.0)

# The world direction through painting pixel `px`, scaled so its component along the view axis is 1:
# the point at camera depth z is eye + ray * z.
func ray(px: Vector2) -> Vector3:
	var dx := (px.x - _size.x * 0.5) / _focal
	var dy := -(px.y - _size.y * 0.5) / _focal
	return Vector3.RIGHT * dx + view_up() * dy + view_axis()

func pixel_at_depth(px: Vector2, depth: float) -> Vector3:
	return Vector3(0.0, _eye, 0.0) + ray(px) * depth

# Camera depth (metres) of the painting at pixel `px`, bilinear in the depth grid.
func depth_at(px: Vector2) -> float:
	var gx := clampf((px.x - _grid_origin.x) / _step, 0.0, _grid_w - 1.001)
	var gy := clampf((px.y - _grid_origin.y) / _step, 0.0, _grid_h - 1.001)
	var x0 := int(gx)
	var y0 := int(gy)
	var fx := gx - x0
	var fy := gy - y0
	var a := lerpf(_grid[y0 * _grid_w + x0], _grid[y0 * _grid_w + x0 + 1], fx)
	var b := lerpf(_grid[(y0 + 1) * _grid_w + x0], _grid[(y0 + 1) * _grid_w + x0 + 1], fx)
	return lerpf(a, b, fy)

# The surface of the painted room under pixel `px`.
func pixel_to_world(px: Vector2) -> Vector3:
	return pixel_at_depth(px, depth_at(px))

# The point on the floor (y = 0) under pixel `px`; for placing characters and props that stand.
func floor_at(px: Vector2) -> Vector3:
	var r := ray(px)
	return Vector3(0.0, _eye, 0.0) + r * (_eye / -r.y) if r.y < -0.0001 else pixel_to_world(px)

func world_to_pixel(point: Vector3) -> Vector2:
	var rel := point - Vector3(0.0, _eye, 0.0)
	var depth := rel.dot(view_axis())
	return Vector2(_size.x * 0.5 + _focal * rel.x / depth, _size.y * 0.5 - _focal * rel.dot(view_up()) / depth)

# The painting pixel under a point of the screen, whatever the window's shape or the camera's roll.
func screen_to_pixel(screen: Vector2) -> Vector2:
	var direction := camera.project_ray_normal(screen)
	var depth := direction.dot(view_axis())
	if depth <= 0.0:
		return Vector2(-1, -1)
	return Vector2(_size.x * 0.5 + _focal * direction.x / depth, _size.y * 0.5 - _focal * direction.dot(view_up()) / depth)

# ---- building ------------------------------------------------------------------------------------------

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(room["fov_v"])
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = 120.0
	add_child(camera)
	set_camera_offset(Vector3.ZERO, 0.0)
	camera.make_current()
	camera.get_viewport().size_changed.connect(_refresh_camera)

func _refresh_camera() -> void:
	set_camera_offset(_offset, _roll_deg)

# Moves the camera off the painting's viewpoint (metres, in the camera's frame) and rolls it (degrees):
# a held shot's breathing, the Dutch tilt, or a test of how far the painting holds up.
func set_camera_offset(offset: Vector3, roll_deg: float) -> void:
	_offset = offset
	_roll_deg = roll_deg
	var roll := deg_to_rad(roll_deg)
	var basis := Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, roll)
	camera.transform = Transform3D(basis, Vector3(0.0, _eye, 0.0) + basis * offset)
	# A rolled or wider-than-painted frame zooms in only as far as its corners need to stay inside the painting
	# and its margin (none: the painting's own shape and the roll alone decide, as before the margin existed).
	camera.fov = PaintedOverscan.fov_for(float(room["fov_v"]), _size, _margin, view_aspect(), roll)

func _build_room(texture: Texture2D) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in _grid_h:
		for i in _grid_w:
			var px := PaintedOverscan.vertex_pixel(i, j, _grid_origin, _step, _size, _margin)
			vertices.append(pixel_at_depth(px, _grid[j * _grid_w + i]))
			uvs.append(plate_uv(px))
	var indices := PackedInt32Array()
	for j in _grid_h - 1:
		for i in _grid_w - 1:
			var a := j * _grid_w + i
			indices.append_array([a, a + 1, a + _grid_w + 1, a, a + _grid_w + 1, a + _grid_w])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_plate_material = ShaderMaterial.new()
	_plate_material.shader = PLATE_SHADER
	_plate_material.set_shader_parameter("plate", texture)
	_plate_material.set_shader_parameter("plate_smooth", texture)
	var instance := MeshInstance3D.new()
	instance.name = "Painting"
	instance.mesh = mesh
	instance.material_override = _plate_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _spawn_actor(id: String, data: Dictionary) -> void:
	var visual := CharacterModels.instantiate(id)
	if visual == null:
		return
	var holder := Node3D.new()
	holder.name = id.capitalize()
	var p: Array = data["position"]
	holder.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	holder.rotation.y = float(FACING.get(id, PI))
	add_child(holder)
	holder.add_child(visual)
	_light_actor(visual)
	CharacterModels.play(visual, "watch" if CharacterModels.has_clip(visual, "watch") else "idle")
	_add_shadow(holder, float(SHADOW_RADIUS.get(id, 0.3)))
	actors[id] = holder

# The characters stand in the painting's light: its floor seen from above (light_map.png) and the beam.
func relight_actors() -> void:
	for id in actors:
		_light_actor(actors[id])

func _light_actor(node: Node) -> void:
	var light_map := _texture("light_map.png")
	var r: Array = room["light_rect"]
	var sun: Array = room["sun_dir"]
	var sun_color: Array = room["sun_color"]
	var lit: Array = room["lit_range"]
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		var materials: Array[Material] = [instance.material_override]
		for surface in instance.mesh.get_surface_count():
			materials.append(instance.get_surface_override_material(surface))
		for material in materials:
			var shader_material := material as ShaderMaterial
			if shader_material == null:
				continue
			shader_material.set_shader_parameter("light_map", light_map)
			shader_material.set_shader_parameter("light_rect", Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
			shader_material.set_shader_parameter("sun_dir", Vector3(float(sun[0]), float(sun[1]), float(sun[2])))
			shader_material.set_shader_parameter("sun_color", Color(float(sun_color[0]), float(sun_color[1]), float(sun_color[2])) * actor_sun)
			shader_material.set_shader_parameter("lit_range", Vector2(float(lit[0]), float(lit[1])))
			shader_material.set_shader_parameter("light_scale", actor_light)
			shader_material.set_shader_parameter("rim_strength", actor_rim)

func _add_shadow(holder: Node3D, radius: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var material := ShaderMaterial.new()
	material.shader = SHADOW_SHADER
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = quad
	shadow.material_override = material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Flat on the floor, pushed a little away from the sun (the holder turns with the character).
	var sun: Array = room["sun_dir"]
	var away := -Vector3(float(sun[0]), 0.0, float(sun[2])).normalized() * radius * 0.35
	shadow.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), holder.basis.inverse() * away + Vector3(0.0, 0.01, 0.0))
	holder.add_child(shadow)

func _build_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Screen"
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_material = ShaderMaterial.new()
	_screen_material.shader = SCREEN_SHADER
	rect.material = _screen_material
	layer.add_child(rect)
	add_child(layer)

# PSX on: coarse texels, snapped vertices, affine mapping, 15-bit colour. Off: the painting as painted.
func set_psx(on: bool) -> void:
	psx = on
	# The texture covers the margin too: more texels, so each stays the size it has without one.
	var texels := texel_res * (_size + _margin * 2.0) / _size
	_plate_material.set_shader_parameter("psx", on)
	_plate_material.set_shader_parameter("texel_res", texels)
	_plate_material.set_shader_parameter("snap_res", snap_res)
	_screen_material.set_shader_parameter("enabled", on)
	for prop in props:
		prop.set_psx(on, texels, snap_res)

# ---- taps ----------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if press(screen_to_pixel(button.position)) != "":
			get_viewport().set_input_as_handled()

# Pokes whatever is at painting pixel `px` (the nearest prop that contains it). Returns the prop's id.
func press(px: Vector2) -> String:
	var best: PaintedProp = null
	for prop in props:
		if prop.contains(px) and (best == null or prop.depth < best.depth):
			best = prop
	if best == null:
		return ""
	var reaction := best.react("press")
	prop_pressed.emit(best.prop_id, reaction, pixel_to_world(px))
	return best.prop_id
