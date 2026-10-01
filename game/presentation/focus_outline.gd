class_name FocusOutline
extends RefCounted

# The warm outline (an inverted-hull pass), applied as `next_pass` on an object's materials while
# it is the pointed-at thing. Works on meshes with a material override (the placeholder characters)
# and on multi-surface imported meshes (the set's machine and bell). Independent of behaviour.

static func set_focus(root: Node, focused: bool) -> void:
	for mesh in _meshes(root):
		for material in _materials(mesh):
			material.next_pass = PSXMaterials.outline() if focused else null

static func is_focused(root: Node) -> bool:
	for mesh in _meshes(root):
		for material in _materials(mesh):
			if material.next_pass != null:
				return true
	return false

# The ShaderMaterials a mesh is drawn with: its override, or each surface's override.
static func _materials(mesh: MeshInstance3D) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var override := mesh.material_override as ShaderMaterial
	if override != null:
		out.append(override)
		return out
	if mesh.mesh != null:
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_surface_override_material(surface) as ShaderMaterial
			if material != null:
				out.append(material)
	return out

static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
