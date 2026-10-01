class_name BlobShadow
extends Node3D

# The contact shadow of a standing thing, in two parts laid on the floor:
#   Contact  a small dark blob right under its feet, always (it is standing ON something)
#   Sun      a long soft shadow thrown away from the key light (StageLight.sun_dir), as strong as the
#            sunlight at its feet: `light_probe` (the room's key plate) says how much sun falls there.
# It follows its target in world space, so turning the target does not turn the shadow.

const SHADER := "res://render/psx/blob_shadow.gdshader"
const CONTACT_STRENGTH := 0.55
const SUN_STRENGTH := 0.8

# func(world: Vector3) -> float  the sun's share of the light at a point (0 = shade). Set by the room.
static var light_probe: Callable

var target: Node3D
var contact: MeshInstance3D
var sun_shadow: MeshInstance3D
var _radius := 0.4
var _length := 1.0
var _sun_material: ShaderMaterial
var _in_sun := 0.0

# `length` is how far the sun shadow reaches beyond the feet.
static func attach(owner_node: Node3D, radius: float, length: float) -> BlobShadow:
	var shadow := BlobShadow.new()
	shadow.target = owner_node
	shadow._radius = radius
	shadow._length = length
	owner_node.add_child(shadow)
	return shadow

func _ready() -> void:
	top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	contact = _layer(plane, CONTACT_STRENGTH, "Contact")
	contact.scale = Vector3(_radius * 0.85, 1.0, _radius * 0.85)
	sun_shadow = _layer(plane, 0.0, "Sun")
	_sun_material = sun_shadow.material_override as ShaderMaterial
	var away := ground_away()
	sun_shadow.rotation.y = atan2(away.x, away.y)
	sun_shadow.scale = Vector3(_radius * 0.9, 1.0, (_length + _radius) * 0.5)
	_follow()

func _layer(plane: Mesh, strength: float, node_name: String) -> MeshInstance3D:
	var layer := MeshInstance3D.new()
	layer.name = node_name
	layer.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	material.set_shader_parameter("strength", strength)
	layer.material_override = material
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(layer)
	return layer

# The key light's direction across the floor, pointing away from the sun.
static func ground_away() -> Vector2:
	var away := Vector2(-StageLight.sun_dir().x, -StageLight.sun_dir().z)
	return away.normalized() if away.length() > 0.01 else Vector2(0, 1)

func _process(_delta: float) -> void:
	_follow()

func in_sun() -> float:
	return _in_sun

func _follow() -> void:
	if target == null or not is_instance_valid(target):
		return
	var at := target.global_position
	global_position = Vector3(at.x, at.y + 0.03, at.z)
	visible = target.is_visible_in_tree()
	var away := ground_away()
	var reach := (_length + _radius) * 0.5
	sun_shadow.position = Vector3(away.x * (reach - _radius * 0.5), 0.005, away.y * (reach - _radius * 0.5))
	_in_sun = clampf(float(light_probe.call(at)), 0.0, 1.0) if light_probe.is_valid() else 0.0
	_sun_material.set_shader_parameter("strength", SUN_STRENGTH * _in_sun)
