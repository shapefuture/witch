class_name PaintedLife
extends Node3D

# Light and life in a painted room (docs/art/painted_room.md, "Light and life"). The painting is a still; this node
# makes its own light breathe without a single Godot light, driven by assets/painted/hall_clean/life.json:
#   glow cards  - one mesh, one draw call: a flat card at every lamp's depth, additive, flickering
#   the beam    - the room's depth grid draped over the shaft and its floor pool (one mesh, one draw call): breathing,
#                 dust motes inside it, the characters' shadow along the ray to the oculus
#   the frame   - the dark foreground closing in and letting go as the beam breathes (one full-screen multiply)
#   the actors  - their light follows the beam (life_changed -> actor_light / sun colour)
# Everything moves on a clock of `fps` steps a second and every level is quantised, so it reads as hand-animated;
# the shaders band and dither with painted_screen.gdshader's 4x4 Bayer. Nothing reads the real-time clock: advance()
# (or set_clock) is the only source of time, so a capture or a test is repeatable.

signal life_changed(level: float)

const GLOW_SHADER := preload("res://game/world/painted/painted_life_glow.gdshader")
const BEAM_SHADER := preload("res://game/world/painted/painted_life_beam.gdshader")
const FRAME_SHADER := preload("res://game/world/painted/painted_life_frame.gdshader")
const MAX_SLOTS := 32
const MAX_OCCLUDERS := 8
# The beam lies 1.5 % in front of the surface it falls on (along the painting's own rays, so it does not move on screen).
const DRAPE_DEPTH := 0.985
const LEVEL_STEP := 1.0 / 16.0
# A flare keeps this share of itself every step: 0.72 at 8 steps a second is a quarter-second half-life.
const PULSE_DECAY := 0.72
const FLARE_GAIN := 0.7
const SPARK_ID := "spark_%d"

var room: PaintedRoom
var data: Dictionary = {}
var loaded := false
var fps := 8.0
# Time comes from here only; turn it off to drive the clock by hand (tests, captures).
var auto_advance := true
# Master switch, 0..1: 0 draws nothing at all (the painting as painted), 1 is the authored look.
var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		_refresh()
# How much the lights move, 0..1: 0 holds every light at its base level (the glows stay, the flicker stops).
var flicker := 1.0:
	set(value):
		flicker = clampf(value, 0.0, 1.0)
		_refresh()

var _clock := 0.0
var _step := 0
var _lights: Array[Dictionary] = []
var _glow_levels := 6.0
var _glow_depth := 0.97
var _spare := 6
var _glow_instance: MeshInstance3D
var _glow_material: ShaderMaterial
var _beam_instance: MeshInstance3D
var _beam_material: ShaderMaterial
var _frame_layer: CanvasLayer
var _frame_material: ShaderMaterial
var _beam_flicker: Dictionary = {}
var _beam_level := 1.0
var _frame_strength := 0.0
var _frame_breath := 0.0
var _occluder_config: Dictionary = {}
var _occluders := PackedVector4Array()
var _actor_materials: Array[ShaderMaterial] = []
var _actor_follow := 1.0
var _sun_base := Color.WHITE
var _reported_level := 1.0
var _sparks := 0

# ---- data ---------------------------------------------------------------------------------------------------

# Builds the nodes from `file` in the room's directory. Returns false (and builds nothing) when the room has no life.
func setup(p_room: PaintedRoom, file: String = "life.json") -> bool:
	room = p_room
	var path := room.room_dir.path_join(file)
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("PaintedLife: %s is not a JSON object" % path)
		return false
	data = parsed
	fps = maxf(float(data.get("fps", 8.0)), 1.0)
	var glow: Dictionary = data.get("glow", {})
	_glow_levels = float(glow.get("levels", 6.0))
	_glow_depth = float(glow.get("depth", 0.97))
	for entry: Dictionary in data.get("lights", []):
		if entry.has("id") and entry.has("pixel"):
			_lights.append(_light_from(entry))
		else:
			push_error("PaintedLife: a light in %s needs an id and a pixel" % path)
	_spare = clampi(int(glow.get("spare", 6)), 0, maxi(MAX_SLOTS - _lights.size(), 0))
	_occluder_config = data.get("occluders", {})
	var actors: Dictionary = data.get("actors", {})
	_actor_follow = float(actors.get("follow", 1.0))
	var sun: Array = room.room.get("sun_color", [1.0, 1.0, 1.0])
	_sun_base = Color(float(sun[0]), float(sun[1]), float(sun[2])) * room.actor_sun
	_build_glow()
	_build_beam(data.get("beam", {}) as Dictionary)
	_build_frame(data.get("frame", {}) as Dictionary)
	collect_actor_materials()
	loaded = true
	set_psx(room.psx, room.texel_res, room.snap_res)
	_tick()
	return true

func _light_from(entry: Dictionary) -> Dictionary:
	var pixel: Array = entry["pixel"]
	var flick: Dictionary = entry.get("flicker", {})
	return {
		"id": str(entry["id"]),
		"pixel": Vector2(float(pixel[0]), float(pixel[1])),
		"radius": float(entry.get("radius", 40.0)),
		"core": float(entry.get("core", 0.3)),
		"color": _color(entry.get("color", [1.0, 0.8, 0.5]), Color(1.0, 0.8, 0.5)),
		"strength": float(entry.get("strength", 0.5)),
		"depth_mode": str(entry.get("depth_mode", "at")),
		"kind": str(flick.get("kind", "none")),
		"amount": float(flick.get("amount", 0.0)),
		"seed": int(flick.get("seed", 1)),
		"shift": float(flick.get("shift", 0.0)),
		"level": 1.0,
		"pulse": 0.0,
		"pulse_color": Color.WHITE,
		"spark": false,
	}

static func _color(value: Variant, fallback: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback

# ---- time -----------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not loaded:
		return
	if auto_advance:
		advance(delta)
	_track_occluders()

# Moves the clock on. The lights change only when a whole step has passed; a flare decays one step at a time.
func advance(delta: float) -> void:
	_clock += delta
	var step := floori(_clock * fps)
	if step != _step:
		var passed := mini(absi(step - _step), 64)
		_step = step
		for light in _lights:
			var fading := float(light["pulse"]) * pow(PULSE_DECAY, passed)
			light["pulse"] = fading if fading >= 0.02 else 0.0
		_tick()

# Puts the clock at `seconds`; flares are cleared (they belong to the time they were struck).
func set_clock(seconds: float) -> void:
	_clock = seconds
	_step = floori(_clock * fps)
	for light in _lights:
		light["pulse"] = 0.0
	_tick()

func clock() -> float:
	return _clock

func step_index() -> int:
	return _step

# ---- the flicker, as a pure function ------------------------------------------------------------------------

static func hash_unit(n: int) -> float:
	var h := n & 0xffffffff
	h = ((h ^ 61) ^ (h >> 16)) & 0xffffffff
	h = (h + (h << 3)) & 0xffffffff
	h = (h ^ (h >> 4)) & 0xffffffff
	h = (h * 0x27d4eb2d) & 0xffffffff
	h = (h ^ (h >> 15)) & 0xffffffff
	return float(h & 0xffffff) / 16777216.0

# The level of a light (1 = its base brightness) at integer `step` of a clock running at `fps`: a staircase, never a
# curve. "candle" is a short-memory noise with now and then a gutter; "lamp" the same, slower and gentler; "magic" a
# slow breath; "breath" the sky behind the oculus: two slow waves. Quantised to 1/16, never below zero.
static func flicker_value(kind: String, seed_id: int, step: int, rate: float, amount: float) -> float:
	if amount <= 0.0 or kind == "none":
		return 1.0
	var t := float(step) / rate
	var base := seed_id * 7919
	var v := 0.0
	match kind:
		"candle":
			var a := hash_unit(base + step)
			var b := hash_unit(base + step - 1)
			v = (a * 0.6 + b * 0.4) * 2.0 - 1.0
			if hash_unit(base * 31 + floori(step / 3.0)) > 0.93:
				v -= 1.1
		"lamp":
			var a := hash_unit(base + floori(step / 4.0))
			var b := hash_unit(base + floori(step / 4.0) - 1)
			v = (a * 0.5 + b * 0.5) * 2.0 - 1.0
		"magic":
			var phase := hash_unit(base) * TAU
			v = sin(TAU * t / 3.4 + phase)
			if hash_unit(base * 17 + floori(t / 5.0)) > 0.9 and fposmod(t, 5.0) < 0.5:
				v = -1.0
		"breath":
			var phase := hash_unit(base) * TAU
			v = 0.65 * sin(TAU * t / 5.7 + phase) + 0.35 * sin(TAU * t / 2.1 + phase * 2.3)
	return maxf(snappedf(1.0 + amount * v, LEVEL_STEP), 0.0)

# ---- the tick -----------------------------------------------------------------------------------------------

func _refresh() -> void:
	if not loaded:
		return
	_tick()

func _tick() -> void:
	var motion := flicker
	var state := PackedVector4Array()
	state.resize(MAX_SLOTS)
	for i in _lights.size():
		var light := _lights[i]
		var level := flicker_value(str(light["kind"]), int(light["seed"]), _step, fps, float(light["amount"]) * motion)
		light["level"] = 0.0 if bool(light["spark"]) else level
		state[i] = _slot_color(light)
	_glow_material.set_shader_parameter("state", state)
	var beam: Dictionary = _beam_flicker
	_beam_level = flicker_value(str(beam.get("kind", "none")), int(beam.get("seed", 1)), _step, fps, float(beam.get("amount", 0.0)) * motion)
	_beam_material.set_shader_parameter("level", _beam_level)
	# With the flicker at zero the room holds still: the motes stop too.
	_beam_material.set_shader_parameter("clock", float(_step) / fps if motion > 0.0 else 0.0)
	_beam_material.set_shader_parameter("master", intensity)
	var frame_scale := 1.0 + _frame_breath * (_beam_level - 1.0) * 4.0
	_frame_material.set_shader_parameter("strength", _frame_strength * frame_scale * intensity)
	var visible_now := intensity > 0.0
	_glow_instance.visible = visible_now
	_beam_instance.visible = visible_now
	_frame_layer.visible = visible_now
	_track_occluders()
	_apply_actor_light()

func _slot_color(light: Dictionary) -> Vector4:
	var level := float(light["level"])
	var shift := float(light["shift"])
	var base: Color = light["color"]
	var warm := Vector3(base.r, base.g, base.b) * float(light["strength"]) * level
	warm.y *= maxf(1.0 + shift * (level - 1.0), 0.0)
	warm.z *= maxf(1.0 + 2.0 * shift * (level - 1.0), 0.0)
	var flare: Color = light["pulse_color"]
	var extra := Vector3(flare.r, flare.g, flare.b) * float(light["pulse"]) * FLARE_GAIN
	var total := (warm + extra) * intensity
	return Vector4(total.x, total.y, total.z, 0.0)

# ---- the reaction hook ----------------------------------------------------------------------------------------

# Flares the light nearest painting pixel `pixel` (within its reach), or strikes a short-lived spark there when none
# is near: a prop reaction or a tap makes the room answer with light. `strength` 1 is a flare as bright as a lit lamp;
# it fades in about a second, a step at a time. Returns the id of the light that flared ("" outside the painting).
func pulse(pixel: Vector2, color: Color = Color(1.0, 0.85, 0.55), strength: float = 1.0) -> String:
	if not loaded or strength <= 0.0:
		return ""
	var size := room.image_size()
	if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x > size.x or pixel.y > size.y:
		return ""
	var strength_now := clampf(strength, 0.0, 2.0)
	var best := -1
	var best_distance := INF
	for i in _lights.size():
		var light := _lights[i]
		if bool(light["spark"]) and float(light["pulse"]) <= 0.02:
			continue
		var reach := clampf(float(light["radius"]) * 0.7, 22.0, 70.0)
		var distance := pixel.distance_to(light["pixel"])
		if distance <= reach and distance < best_distance:
			best = i
			best_distance = distance
	if best < 0:
		best = _strike_spark(pixel, strength_now)
	if best < 0:
		return ""
	var target := _lights[best]
	var old: Color = target["pulse_color"]
	target["pulse_color"] = old.lerp(color, 0.5) if float(target["pulse"]) > 0.05 else color
	target["pulse"] = maxf(float(target["pulse"]), strength_now)
	_tick()
	return str(target["id"])

func _strike_spark(pixel: Vector2, strength: float) -> int:
	var radius := 30.0 + 20.0 * strength
	var slot := -1
	var quietest := INF
	var count := 0
	for i in _lights.size():
		if not bool(_lights[i]["spark"]):
			continue
		count += 1
		if float(_lights[i]["pulse"]) < quietest:
			quietest = float(_lights[i]["pulse"])
			slot = i
	if count >= _spare:
		if slot < 0:
			return -1
		_lights[slot]["pixel"] = pixel
		_lights[slot]["radius"] = radius
	else:
		var light := _light_from({"id": SPARK_ID % _sparks, "pixel": [pixel.x, pixel.y], "radius": radius, "core": 0.35, "strength": 0.0})
		_sparks += 1
		light["spark"] = true
		_lights.append(light)
		slot = _lights.size() - 1
	_glow_instance.mesh = _glow_mesh()
	return slot

func light_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for light in _lights:
		ids.append(str(light["id"]))
	return ids

func pixel_of(id: String) -> Vector2:
	for light in _lights:
		if str(light["id"]) == id:
			return light["pixel"]
	return Vector2(-1.0, -1.0)

# Brightness of a light now, as a multiple of its base (flicker and flare together); -1 for an unknown id.
func level_of(id: String) -> float:
	for light in _lights:
		if str(light["id"]) == id:
			return float(light["level"]) + float(light["pulse"])
	return -1.0

func flare_of(id: String) -> float:
	for light in _lights:
		if str(light["id"]) == id:
			return float(light["pulse"])
	return 0.0

# The beam's breathing level (1 = as painted).
func beam_level() -> float:
	return _beam_level

# ---- glow cards ---------------------------------------------------------------------------------------------

func _build_glow() -> void:
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GLOW_SHADER
	_glow_material.render_priority = 1
	_glow_material.set_shader_parameter("levels", _glow_levels)
	_glow_instance = MeshInstance3D.new()
	_glow_instance.name = "Glow"
	_glow_instance.material_override = _glow_material
	_glow_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_instance.mesh = _glow_mesh()
	add_child(_glow_instance)

func _card_depth(light: Dictionary) -> float:
	var pixel: Vector2 = light["pixel"]
	var depth := room.depth_at(pixel)
	if str(light["depth_mode"]) == "near":
		var reach := float(light["radius"]) * 0.6
		for k in 8:
			var angle := TAU * k / 8.0
			depth = minf(depth, room.depth_at(pixel + Vector2(cos(angle), sin(angle)) * reach))
		return depth * 0.95
	return depth * _glow_depth

func _glow_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var slots := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners := [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]
	for i in _lights.size():
		var light := _lights[i]
		var pixel: Vector2 = light["pixel"]
		var radius := float(light["radius"])
		var depth := _card_depth(light)
		var first := vertices.size()
		for corner: Vector2 in corners:
			vertices.append(room.pixel_at_depth(pixel + corner * radius, depth))
			uvs.append(corner)
			slots.append(Vector2(float(i), 0.0))
			colors.append(Color(float(light["core"]), 0.0, 0.0, 1.0))
		indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = slots
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# ---- the beam -----------------------------------------------------------------------------------------------

func _build_beam(cfg: Dictionary) -> void:
	_beam_flicker = cfg.get("flicker", {})
	var size := room.image_size()
	var step := float(room.room.get("grid_step", 8))
	var columns := int(round(size.x / step))
	var rows := int(round(size.y / step))
	var mask := _bake_mask(cfg, columns, rows, step)
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BEAM_SHADER
	_beam_material.set_shader_parameter("mask", ImageTexture.create_from_image(mask))
	_beam_material.set_shader_parameter("plate", load(room.room_dir.path_join(str(room.room.get("plate", "plate.png")))) as Texture2D)
	_beam_material.set_shader_parameter("image_size", size)
	_beam_material.set_shader_parameter("beam_color", _vec3(_color(cfg.get("color"), Color(1.0, 0.88, 0.58))))
	_beam_material.set_shader_parameter("shade_color", _vec3(_color(cfg.get("shade"), Color(0.16, 0.1, 0.2))))
	var shaft: Dictionary = cfg.get("shaft", {})
	var pool: Dictionary = cfg.get("pool", {})
	_beam_material.set_shader_parameter("shaft", Vector4(float(shaft.get("base", 0.06)), float(shaft.get("gain", 1.2)), float(shaft.get("taper", 0.5)), float(shaft.get("shadow", 0.25))))
	_beam_material.set_shader_parameter("pool", Vector4(float(pool.get("base", 0.04)), float(pool.get("gain", 1.0)), 1.0, float(pool.get("shadow", 0.4))))
	var rows_taper: Array = shaft.get("taper_rows", [40.0, 600.0])
	_beam_material.set_shader_parameter("taper_rows", Vector2(float(rows_taper[0]), float(rows_taper[1])))
	var motes: Dictionary = cfg.get("motes", {})
	_beam_material.set_shader_parameter("motes", Vector4(float(motes.get("cell", 9.0)), float(motes.get("density", 0.3)), float(motes.get("speed", 0.16)), float(motes.get("strength", 0.6))))
	_beam_material.set_shader_parameter("mote_color", _vec3(_color(motes.get("color"), Color(1.0, 0.93, 0.7))))
	_beam_material.set_shader_parameter("light_pos", _source_position(str(cfg.get("source", "oculus"))))
	_beam_instance = MeshInstance3D.new()
	_beam_instance.name = "Beam"
	_beam_instance.mesh = _beam_mesh(mask, columns, rows, step)
	_beam_instance.material_override = _beam_material
	_beam_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam_instance)

static func _vec3(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)

func _source_position(id: String) -> Vector3:
	for light in _lights:
		if str(light["id"]) == id:
			return room.pixel_at_depth(light["pixel"], _card_depth(light))
	return room.pixel_at_depth(Vector2(876.0, 54.0), 13.0)

# R: the shaft, G: the pool. 1 deep inside a polygon, 0 on its edge and outside, falling off over `feather` painting
# pixels, sampled at the grid cells' centres so the texture's texels line up with the room's depth grid.
func _bake_mask(cfg: Dictionary, columns: int, rows: int, step: float) -> Image:
	var image := Image.create(columns, rows, false, Image.FORMAT_RGB8)
	var channels := ["shaft", "pool"]
	for c in channels.size():
		var region: Dictionary = cfg.get(channels[c], {})
		var polygon := PackedVector2Array()
		for point in region.get("polygon", []):
			polygon.append(Vector2(float(point[0]), float(point[1])))
		if polygon.size() < 3:
			continue
		var feather := maxf(float(region.get("feather", 32.0)), 1.0)
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		var first := Vector2i(maxi(int(bounds.position.x / step), 0), maxi(int(bounds.position.y / step), 0))
		var last := Vector2i(mini(int(bounds.end.x / step) + 1, columns - 1), mini(int(bounds.end.y / step) + 1, rows - 1))
		for j in range(first.y, last.y + 1):
			for i in range(first.x, last.x + 1):
				var p := (Vector2(i, j) + Vector2(0.5, 0.5)) * step
				if not Geometry2D.is_point_in_polygon(p, polygon):
					continue
				var edge := INF
				for k in polygon.size():
					edge = minf(edge, p.distance_to(Geometry2D.get_closest_point_to_segment(p, polygon[k], polygon[(k + 1) % polygon.size()])))
				var value := smoothstep(0.0, 1.0, clampf(edge / feather, 0.0, 1.0))
				var pixel := image.get_pixel(i, j)
				pixel[c] = value
				image.set_pixel(i, j, pixel)
	return image

# The room's depth grid, over the cells the mask touches. Props stand in front of the room mesh, so on and just around
# them (a cell wide, so no cell straddles the silhouette) the beam follows the prop.
func _drape_depth(px: Vector2, step: float) -> float:
	var depth := room.depth_at(px)
	for prop in room.props:
		if prop.kind != "cutout":
			continue
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				if prop.contains(px + Vector2(dx, dy) * step):
					depth = minf(depth, prop.depth)
	return depth * DRAPE_DEPTH

func _beam_mesh(mask: Image, columns: int, rows: int, step: float) -> ArrayMesh:
	var size := room.image_size()
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var index_of: Dictionary = {}
	for j in rows:
		for i in columns:
			if not _touches(mask, i, j, columns, rows):
				continue
			var corners: Array[int] = []
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var key := (j + offset.y) * (columns + 1) + (i + offset.x)
				if not index_of.has(key):
					var px := Vector2(minf((i + offset.x) * step, size.x), minf((j + offset.y) * step, size.y))
					index_of[key] = vertices.size()
					vertices.append(room.pixel_at_depth(px, _drape_depth(px, step)))
					uvs.append(px / size)
				corners.append(index_of[key])
			indices.append_array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# A cell is kept when any texel its bilinear lookups can reach is lit.
func _touches(mask: Image, i: int, j: int, columns: int, rows: int) -> bool:
	for y in range(maxi(j - 1, 0), mini(j + 2, rows)):
		for x in range(maxi(i - 1, 0), mini(i + 2, columns)):
			var pixel := mask.get_pixel(x, y)
			if pixel.r > 0.001 or pixel.g > 0.001:
				return true
	return false

# ---- the frame ------------------------------------------------------------------------------------------------

func _build_frame(cfg: Dictionary) -> void:
	_frame_strength = float(cfg.get("strength", 0.0))
	_frame_breath = float(cfg.get("breath", 0.0))
	_frame_material = ShaderMaterial.new()
	_frame_material.shader = FRAME_SHADER
	_frame_material.set_shader_parameter("tint", _vec3(_color(cfg.get("tint"), Color(0.34, 0.24, 0.4))))
	# Built before the room's screen layer, so painted_screen's quantisation reads the finished frame.
	_frame_layer = CanvasLayer.new()
	_frame_layer.name = "Frame"
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _frame_material
	_frame_layer.add_child(rect)
	add_child(_frame_layer)

# ---- the characters ---------------------------------------------------------------------------------------------

# Finds the characters' shaders that take the painting's light. Call again after a character is swapped.
func collect_actor_materials() -> void:
	_actor_materials.clear()
	for id in room.actors:
		for mesh in (room.actors[id] as Node).find_children("*", "MeshInstance3D", true, false):
			var instance := mesh as MeshInstance3D
			var materials: Array[Material] = [instance.material_override]
			for surface in instance.mesh.get_surface_count():
				materials.append(instance.get_surface_override_material(surface))
			for material in materials:
				var shader_material := material as ShaderMaterial
				if shader_material != null and shader_material.shader != null and _has_uniform(shader_material.shader, "light_scale"):
					_actor_materials.append(shader_material)

static func _has_uniform(shader: Shader, uniform_name: String) -> bool:
	for uniform in shader.get_shader_uniform_list():
		if str((uniform as Dictionary).get("name", "")) == uniform_name:
			return true
	return false

# The level the characters' light follows: the beam, plus a share of any flare.
func actor_level() -> float:
	var flare := 0.0
	for light in _lights:
		flare += float(light["pulse"])
	return clampf(_beam_level + 0.1 * flare, 0.0, 2.0)

# Takes the node out of the picture: the characters are lit as the room itself lights them again.
func _exit_tree() -> void:
	if loaded and room != null:
		for material in _actor_materials:
			if is_instance_valid(material):
				material.set_shader_parameter("light_scale", room.actor_light)
				material.set_shader_parameter("sun_color", _sun_base)

func _apply_actor_light() -> void:
	var level := lerpf(1.0, actor_level(), _actor_follow * intensity)
	for material in _actor_materials:
		material.set_shader_parameter("light_scale", room.actor_light * level)
		material.set_shader_parameter("sun_color", _sun_base * level)
	if absf(level - _reported_level) >= 1.0 / 64.0:
		_reported_level = level
		life_changed.emit(level)

# Their bodies block the beam: a few spheres per character, in the beam shader's `occ` array.
func _track_occluders() -> void:
	var spheres := PackedVector4Array()
	for id in _occluder_config:
		var holder := room.actors.get(id) as Node3D
		if holder == null or not holder.is_inside_tree():
			continue
		var config: Dictionary = _occluder_config[id]
		var radius := float(config.get("radius", 0.25))
		var height := float(config.get("height", 1.0))
		var feet := holder.global_position
		for share: float in [0.3, 0.65, 0.95]:
			if spheres.size() < MAX_OCCLUDERS:
				spheres.append(Vector4(feet.x, feet.y + height * share, feet.z, radius * (0.9 if share > 0.9 else 1.0)))
	if spheres == _occluders:
		return
	_occluders = spheres
	var padded := spheres.duplicate()
	padded.resize(MAX_OCCLUDERS)
	_beam_material.set_shader_parameter("occ", padded)
	_beam_material.set_shader_parameter("occ_count", spheres.size())

func occluder_count() -> int:
	return _occluders.size()

# ---- the room's PSX switch ---------------------------------------------------------------------------------

func set_psx(on: bool, texel_res: Vector2, snap_res: Vector2) -> void:
	if _glow_material == null or _beam_material == null:
		return
	for material in [_glow_material, _beam_material]:
		material.set_shader_parameter("psx", on)
		material.set_shader_parameter("snap_res", snap_res)
	_beam_material.set_shader_parameter("texel_res", texel_res)

# ---- numbers for the budget test ---------------------------------------------------------------------------

# {"surfaces": mesh surfaces this node draws, "triangles": their triangles, "draw_calls": draws it costs a frame}.
func cost() -> Dictionary:
	var surfaces := 0
	var triangles := 0
	for instance in [_glow_instance, _beam_instance]:
		if instance != null and instance.mesh != null:
			surfaces += instance.mesh.get_surface_count()
			for surface in instance.mesh.get_surface_count():
				triangles += int((instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3.0)
	return {"surfaces": surfaces, "triangles": triangles, "draw_calls": surfaces + (1 if _frame_layer != null else 0)}
