extends TestCase

const MODELS := {
	"witch": ["idle", "walk", "talk", "cast"],
	"witch_antler": ["idle", "walk", "talk", "cast"],
	"tomas": ["idle", "walk", "talk", "work"],
	"raccoon": ["idle", "walk", "talk", "watch"],
	"shadow": ["idle", "walk", "talk"],
	"shadow_lady": ["idle", "walk", "talk"],
}
# Game scale in metres, feet on the floor (tools/characters exports at this size).
const HEIGHTS := {"witch": 1.3, "witch_antler": 1.3, "tomas": 1.55, "raccoon": 0.7, "shadow": 1.7, "shadow_lady": 1.65}

func test_every_character_loads_with_its_clips_at_game_scale() -> void:
	for id in MODELS:
		var visual := _spawn(id)
		ok(visual != null, "%s loads" % id)
		if visual == null:
			continue
		for clip in MODELS[id]:
			ok(CharacterModels.has_clip(visual, clip), "%s has %s" % [id, clip])
		var top := 0.0
		var bottom := 1e9
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var aabb := (node as MeshInstance3D).get_aabb()
			top = maxf(top, aabb.end.y)
			bottom = minf(bottom, aabb.position.y)
		ok(absf(top - float(HEIGHTS[id])) < 0.08, "%s is %.2f m tall (%.2f)" % [id, float(HEIGHTS[id]), top])
		ok(absf(bottom) < 0.03, "%s stands on the floor" % id)
		visual.queue_free()

func test_characters_cost_at_most_two_draw_calls_and_fit_the_triangle_budget() -> void:
	for id in MODELS:
		var visual := _spawn(id)
		if visual == null:
			continue
		var surfaces := 0
		var triangles := 0
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			surfaces += mesh.get_surface_count()
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				triangles += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		ok(surfaces <= 2, "%s draws in %d surfaces" % [id, surfaces])
		ok(triangles <= 9000, "%s has %d triangles" % [id, triangles])
		visual.queue_free()

func test_every_surface_is_psx_actor_shaded_and_textures_are_used() -> void:
	for id in MODELS:
		var visual := _spawn(id)
		if visual == null:
			continue
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface) as ShaderMaterial
				ok(material != null and material.shader.resource_path.ends_with("psx_lit_actor.gdshader"), "%s surface %d is PSX-lit" % [id, surface])
				var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null and source != null and source.albedo_texture != null:
					ok(bool(material.get_shader_parameter("use_texture")), "%s surface %d samples its texture" % [id, surface])
		visual.queue_free()

# The witch and the raccoon were rebuilt to look like the painting (docs/art/characters_painted.md); the
# skeletons keep the names the clips and any later game code address.
const SKELETONS := {
	"witch": ["root", "hips", "spine", "neck", "head", "cape", "arm_upper.L", "arm_lower.L", "hand.L", "leg.L", "foot.L",
		"hairB.L", "hairT.L", "arm_upper.R", "arm_lower.R", "hand.R", "leg.R", "foot.R", "hairB.R", "hairT.R", "bird"],
	"raccoon": ["root", "hips", "spine", "chest", "head", "hat", "hat_tip", "ear.L", "upper_arm.L", "forearm.L", "hand.L",
		"leg.L", "foot.L", "ear.R", "upper_arm.R", "forearm.R", "hand.R", "leg.R", "foot.R", "tail1", "tail2", "tail3"],
}

func test_the_painted_characters_keep_their_bone_names() -> void:
	for id in SKELETONS:
		var visual := _spawn(id)
		if visual == null:
			ok(false, "%s loads" % id)
			continue
		var skeletons := visual.find_children("*", "Skeleton3D", true, false)
		ok(skeletons.size() == 1, "%s has one skeleton" % id)
		if skeletons.size() == 1:
			var skeleton := skeletons[0] as Skeleton3D
			for bone in SKELETONS[id]:
				ok(skeleton.find_bone(bone) >= 0, "%s keeps bone %s" % [id, bone])
		visual.queue_free()

# In the tree like in the game: freeing an orphan skinned instance trips a dummy-renderer
# material lookup (headless only) once the full suite has run.
func _spawn(id: String) -> Node3D:
	var visual := CharacterModels.instantiate(id)
	if visual != null:
		(Engine.get_main_loop() as SceneTree).root.add_child(visual)
	return visual
