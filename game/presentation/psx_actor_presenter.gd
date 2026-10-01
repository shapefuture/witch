class_name PSXActorPresenter
extends RefCounted

# Makes ANY imported model look like the project's characters: PSX-lit, with the small
# per-vertex wobble, keeping each surface's albedo colour/texture. Placeholders are already
# built with these materials; this is what real models run through when they replace them.

static func apply(root: Node, wobble: float = 0.004) -> int:
	var converted := 0
	for mesh in _meshes(root):
		if mesh.material_override is ShaderMaterial:
			continue
		var surfaces := mesh.mesh.get_surface_count() if mesh.mesh != null else 0
		if mesh.material_override != null or surfaces <= 1:
			mesh.material_override = _convert(mesh.get_active_material(0), wobble)
			converted += 1
			continue
		# One material per surface: a model may mix a vertex-coloured body with a textured face.
		for surface in surfaces:
			if mesh.get_surface_override_material(surface) is ShaderMaterial:
				continue
			mesh.set_surface_override_material(surface, _convert(mesh.get_active_material(surface), wobble))
			converted += 1
	return converted

static func _convert(source: Material, wobble: float) -> ShaderMaterial:
	var color := Color.WHITE
	var texture: Texture2D = null
	if source is BaseMaterial3D:
		color = source.albedo_color
		texture = source.albedo_texture
	var material := PSXMaterials.actor(color, wobble)
	if texture != null:
		material.set_shader_parameter("albedoTex", texture)
		material.set_shader_parameter("use_texture", true)
	return material

static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
