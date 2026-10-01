class_name StageLight
extends RefCounted

# The lighting the set was BAKED with (tools/blender/build_clearing.py), made available to things
# that are not baked: characters and moving props. It is the key light's direction and colour plus
# a top-down "light map" of the playing floor, so an actor standing in the golden shaft is lit by
# it and one in the hall's shade is purple. Values come from assets/archive/anchors.json.

const ANCHORS_PATH := "res://assets/archive/anchors.json"
const LIGHT_MAP_PATH := "res://assets/archive/light_map.png"

static var _anchors: Dictionary = {}
static var _map: Texture2D

static func anchors() -> Dictionary:
	if _anchors.is_empty() and FileAccess.file_exists(ANCHORS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ANCHORS_PATH))
		if parsed is Dictionary:
			_anchors = parsed
	return _anchors

static func anchor_vector(key: String, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var value: Variant = anchors().get(key)
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

static func sun_dir() -> Vector3:
	return anchor_vector("sun_dir", Vector3(-0.36, 0.64, -0.68)).normalized()

static func light_map() -> Texture2D:
	if _map == null and ResourceLoader.exists(LIGHT_MAP_PATH):
		_map = load(LIGHT_MAP_PATH) as Texture2D
	return _map

# Points an actor material at the baked light.
static func apply(material: ShaderMaterial) -> void:
	var rect: Variant = anchors().get("light_map")
	if rect is Dictionary:
		material.set_shader_parameter("light_rect", Vector4(rect["x0"], rect["z0"], rect["x1"], rect["z1"]))
		material.set_shader_parameter("light_scale", float(rect.get("scale", 1.4)))
		var range_value: Variant = rect.get("lit_range")
		if range_value is Array:
			material.set_shader_parameter("lit_range", Vector2(range_value[0], range_value[1]))
	var map := light_map()
	if map != null:
		material.set_shader_parameter("light_map", map)
	material.set_shader_parameter("sun_dir", sun_dir())
