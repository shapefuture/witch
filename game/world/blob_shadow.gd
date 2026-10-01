class_name BlobShadow
extends MeshInstance3D

# The contact shadow of a standing thing, laid on the floor under it and stretched away from the
# key light (StageLight.sun_dir). It follows its target in world space, so turning the target does
# not turn the shadow.

var target: Node3D
var _radius := 0.4
var _length := 1.0

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
	mesh = plane
	var material := ShaderMaterial.new()
	material.shader = load("res://render/psx/blob_shadow.gdshader")
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var away := Vector2(-StageLight.sun_dir().x, -StageLight.sun_dir().z)
	if away.length() < 0.01:
		away = Vector2(0, 1)
	away = away.normalized()
	rotation.y = atan2(away.x, away.y)
	scale = Vector3(_radius, 1.0, _length)
	_follow()

func _process(_delta: float) -> void:
	_follow()

func _follow() -> void:
	if target == null or not is_instance_valid(target):
		return
	var away := Vector2(-StageLight.sun_dir().x, -StageLight.sun_dir().z).normalized()
	var at := target.global_position
	global_position = Vector3(at.x + away.x * _length * 0.55, at.y + 0.03, at.z + away.y * _length * 0.55)
	visible = target.is_visible_in_tree()
