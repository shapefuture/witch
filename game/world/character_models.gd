class_name CharacterModels
extends RefCounted

# The real characters (built by tools/characters, committed as assets/characters/<id>.glb).
# Each is skinned, faces +Z with its feet at the origin, is modelled at game scale, and carries
# its own looping clips: idle, walk, talk, plus cast (witch), work (Tomas), watch (raccoon).
# A missing model returns null and the caller keeps its placeholder.

const PATH := "res://assets/characters/%s.glb"
const CROSSFADE := 0.18

static func exists(id: String) -> bool:
	return ResourceLoader.exists(PATH % id)

static func instantiate(id: String) -> Node3D:
	if not exists(id):
		return null
	var scene := load(PATH % id) as PackedScene
	if scene == null:
		return null
	var root := Node3D.new()
	root.name = "Visual"
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	root.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		merge_flat_surfaces(node as MeshInstance3D)
	# The models carry decals as micro-geometry a few millimetres off the cloth, so the placeholders'
	# vertex wobble (4 mm) would tear them off, and the facet-hash tone would speckle them.
	PSXActorPresenter.apply(root, 0.0)
	_calm(root)
	play(root, "idle")
	return root

static func _calm(node: Node) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material != null:
				material.set_shader_parameter("facet_tone", 0.015)
				material.set_shader_parameter("paper_grain", 0.02)
	for child in node.get_children():
		_calm(child)

static func player_of(visual: Node) -> AnimationPlayer:
	if visual == null:
		return null
	var found := visual.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null

static func has_clip(visual: Node, clip: String) -> bool:
	var player := player_of(visual)
	return player != null and player.has_animation(clip)

# Crossfades to `clip`. Returns false when the visual has no such clip (a placeholder).
static func play(visual: Node, clip: String, speed: float = 1.0) -> bool:
	var player := player_of(visual)
	if player == null or not player.has_animation(clip):
		return false
	player.speed_scale = speed
	if player.current_animation != clip:
		player.play(clip, CROSSFADE)
	return true

# The exporters write one glTF primitive per flat colour, which would cost a phone one draw call
# per colour (the Shadow has 25). Every untextured surface is folded into ONE surface whose vertex
# colour is the surface's albedo, so a character draws in one or two calls. Textured surfaces
# (faces, atlases) stay as they are.
static func merge_flat_surfaces(mesh_instance: MeshInstance3D) -> int:
	var source := mesh_instance.mesh as ArrayMesh
	if source == null or source.get_surface_count() < 2:
		return 0
	var flat: Array[int] = []
	var kept: Array[int] = []
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface) as BaseMaterial3D
		var untextured := material == null or material.albedo_texture == null
		if untextured and source.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			flat.append(surface)
		else:
			kept.append(surface)
	if flat.size() < 2:
		return 0
	var merged := _concat(source, flat)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	var base := StandardMaterial3D.new()
	base.vertex_color_use_as_albedo = true
	base.resource_name = "flat"
	out.surface_set_material(0, base)
	for surface in kept:
		var arrays := source.surface_get_arrays(surface)
		out.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
		out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(surface))
	mesh_instance.mesh = out
	return flat.size()

static func _concat(source: ArrayMesh, surfaces: Array[int]) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var skinned := true
	for surface in surfaces:
		var arrays := source.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offset := vertices.size()
		var material := source.surface_get_material(surface) as BaseMaterial3D
		var albedo := material.albedo_color if material != null else Color.WHITE
		vertices.append_array(verts)
		if arrays[Mesh.ARRAY_NORMAL] != null:
			normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		var own_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		for i in verts.size():
			colors.append(albedo * (own_colors[i] if i < own_colors.size() else Color.WHITE))
		if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null:
			bones.append_array(arrays[Mesh.ARRAY_BONES])
			weights.append_array(arrays[Mesh.ARRAY_WEIGHTS])
		else:
			skinned = false
		var surface_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if not surface_indices.is_empty():
			for index in surface_indices:
				indices.append(index + offset)
		else:
			for i in verts.size():
				indices.append(i + offset)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	if normals.size() == vertices.size():
		out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	if skinned and bones.size() == vertices.size() * 4:
		out[Mesh.ARRAY_BONES] = bones
		out[Mesh.ARRAY_WEIGHTS] = weights
	out[Mesh.ARRAY_INDEX] = indices
	return out
