class_name ArchiveSet
extends RefCounted

# Loads the hand-made, light-baked set (assets/archive/archive_set.glb, produced by
# tools/blender/build_hall.py) and hands the ArchiveHall its parts:
#   batch    one static mesh: hall, shelves, towers, statue, corridor (a handful of draw calls)
#   machine  the machine with its named, animatable parts (BigGear, SmallGear, Lever, Cam, ...)
#   bell     the brass bell on its yoke (a separate node so it can swing and be outlined)
# Every surface gets the PSX set material for its painted tile; the glTF's own materials are
# only used for their NAMES.

const SCENE_PATH := "res://assets/archive/archive_set.glb"

var root: Node3D
var batch: MeshInstance3D
var machine: Node3D
var bell: MeshInstance3D

static func available() -> bool:
	return ResourceLoader.exists(SCENE_PATH)

func load_set() -> bool:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		return false
	root = packed.instantiate() as Node3D
	batch = root.get_node_or_null("StaticSet") as MeshInstance3D
	machine = root.get_node_or_null("Machine") as Node3D
	bell = root.get_node_or_null("Bell") as MeshInstance3D
	_restyle(root)
	return batch != null and machine != null and bell != null

# Detaches a named part so the owner can place it in its own tree.
func take(node: Node3D) -> Node3D:
	node.get_parent().remove_child(node)
	return node

# The static batch shares one material per tile (few draw calls); every other part gets its own
# copies, because an outline is a `next_pass` on the material and must not light up the whole set.
func _restyle(node: Node) -> void:
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		for surface in range(instance.mesh.get_surface_count()):
			var source := instance.mesh.surface_get_material(surface)
			var tile := source.resource_name if source != null else ""
			var material := PSXMaterials.set_material(tile)
			if instance != batch:
				material = material.duplicate() as ShaderMaterial
			instance.set_surface_override_material(surface, material)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_restyle(child)
