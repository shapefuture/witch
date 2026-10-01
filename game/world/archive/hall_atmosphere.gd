class_name HallAtmosphere
extends Node3D

# The air of the hall: one slanted shaft of light from the hole in the vault to the floor, a warm
# bloom where it lands, and dust drifting through it. None of it touches Mirror or physics; it is
# decoration driven by the diorama clock (PSXGlobals.stage_time), so frames reproduce exactly.
#
# Positions come from the Blender bake's anchors.json (the same numbers the light was baked with),
# so the shaft is exactly where the baked pool of light is.

const SHAFT_SEGMENTS := 20
const SHAFT_RINGS := 10
const MOTE_COUNT := 150

func _ready() -> void:
	name = "HallAtmosphere"
	var sun := StageLight.sun_dir()
	var pool := StageLight.anchor_vector("pool", Vector3(0.5, 0, -0.5))
	var oculus := StageLight.anchor_vector("oculus", pool + sun * 16.0)
	_add_shaft(oculus, pool, 1.7, 0.34, 0.3)
	_add_pool_glow(pool, sun)
	_add_dust(oculus, pool)

# A tube from `top` to `bottom` whose UV runs u = around, v = along (0 at the hole).
func _add_shaft(top: Vector3, bottom: Vector3, radius: float, strength: float, streaks: float) -> void:
	var axis := (bottom - top).normalized()
	var side := axis.cross(Vector3.UP).normalized()
	var up := axis.cross(side).normalized()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in range(SHAFT_RINGS + 1):
		var t := float(ring) / SHAFT_RINGS
		var centre := top.lerp(bottom, t)
		var r := radius * lerpf(0.85, 1.25, t)
		for k in range(SHAFT_SEGMENTS + 1):
			var a := TAU * float(k) / SHAFT_SEGMENTS
			var n := side * cos(a) + up * sin(a)
			vertices.append(centre + n * r)
			normals.append(n)
			uvs.append(Vector2(float(k) / SHAFT_SEGMENTS, t))
	for ring in range(SHAFT_RINGS):
		for k in range(SHAFT_SEGMENTS):
			var a0 := ring * (SHAFT_SEGMENTS + 1) + k
			var b0 := a0 + SHAFT_SEGMENTS + 1
			indices.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://render/psx/shaft.gdshader")
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("streaks", streaks)
	var instance := MeshInstance3D.new()
	instance.name = "Shaft"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-30, -2, -40), Vector3(60, 30, 60))
	add_child(instance)

func _add_pool_glow(pool: Vector3, sun: Vector3) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.2, 4.6)
	var material := ShaderMaterial.new()
	material.shader = load("res://render/psx/pool_glow.gdshader")
	var instance := MeshInstance3D.new()
	instance.name = "PoolGlow"
	instance.mesh = plane
	instance.material_override = material
	instance.position = Vector3(pool.x, 0.04, pool.z)
	instance.rotation.y = atan2(-sun.x, -sun.z)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

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
	var instance := MultiMeshInstance3D.new()
	instance.name = "Dust"
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-30, -2, -40), Vector3(60, 30, 60))
	add_child(instance)
