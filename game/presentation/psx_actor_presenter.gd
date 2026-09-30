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
		var color := Color.WHITE
		var texture: Texture2D = null
		var source: Material = mesh.get_active_material(0)
		if source is BaseMaterial3D:
			color = source.albedo_color
			texture = source.albedo_texture
		var material := PSXMaterials.actor(color, wobble)
		if texture != null:
			material.set_shader_parameter("albedoTex", texture)
		mesh.material_override = material
		converted += 1
	return converted

static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
