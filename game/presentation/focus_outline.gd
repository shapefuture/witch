class_name FocusOutline
extends RefCounted

# The white focus outline (an inverted-hull pass), applied as `next_pass` on an actor's
# materials while it is the pointed-at thing. Independent of the actor's behaviour.

static func set_focus(root: Node, focused: bool) -> void:
	for mesh in _meshes(root):
		var material := mesh.material_override as ShaderMaterial
		if material == null:
			continue
		material.next_pass = PSXMaterials.outline() if focused else null

static func is_focused(root: Node) -> bool:
	for mesh in _meshes(root):
		var material := mesh.material_override as ShaderMaterial
		if material != null and material.next_pass != null:
			return true
	return false

static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
