class_name HallAtmosphere
extends Node3D

# The air of the hall: dust drifting through the shaft of light. The shaft itself and the glow where
# it lands are baked into the pre-rendered plates now (they are light, and the plates own the light);
# only what moves is drawn live. Driven by the diorama clock (PSXGlobals.stage_time), so frames
# reproduce exactly. Positions come from anchors.json, the same numbers the plates were lit with.

const MOTE_COUNT := 150
const MOTE_COLOUR := Color(1.0, 0.86, 0.55)

var _dust_material: ShaderMaterial

func _ready() -> void:
	name = "HallAtmosphere"
	var sun := StageLight.sun_dir()
	var pool := StageLight.anchor_vector("pool", Vector3(0.5, 0, -0.5))
	var oculus := StageLight.anchor_vector("oculus", pool + sun * 16.0)
	_add_dust(oculus, pool)

# Motes glitter only in sunlight: they fade with the sun (the room ageing to dusk).
func set_sun(amount: float) -> void:
	if _dust_material != null:
		_dust_material.set_shader_parameter("colour", MOTE_COLOUR * clampf(amount, 0.0, 1.0))

func _add_dust(top: Vector3, bottom: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240611
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = QuadMesh.new()
	multimesh.instance_count = MOTE_COUNT
	for i in range(MOTE_COUNT):
		var t := rng.randf_range(0.0, 1.0)
		var along := top.lerp(bottom, t)
		var spread := rng.randf_range(0.0, 2.4) if i < MOTE_COUNT * 0.65 else rng.randf_range(2.0, 7.0)
		var angle := rng.randf_range(0.0, TAU)
		var at := along + Vector3(cos(angle) * spread, rng.randf_range(-0.5, 0.5), sin(angle) * spread)
		at.y = clampf(at.y, 0.3, 13.0)
		multimesh.set_instance_transform(i, Transform3D(Basis(), at))
	var material := ShaderMaterial.new()
	material.shader = load("res://render/psx/dust.gdshader")
	_dust_material = material
	var instance := MultiMeshInstance3D.new()
	instance.name = "Dust"
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-30, -2, -40), Vector3(60, 30, 60))
	add_child(instance)
