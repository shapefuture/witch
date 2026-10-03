class_name ArchiveProps
extends RefCounted

# The archive hall's LIVE props: the things that move, so they cannot be in the pre-rendered plates.
#   machine  its named parts turn (MachineView: BigGear, SmallGear and any Gear*)
#   bell     the brass bell (swings when it comes from its own prop file)
# Sources, in order: assets/archive/props/machine.glb and bell.glb (authored in world space, like the
# set), else the Machine and Bell of the old vertex-colour set, assets/archive/archive_set.glb.
# Surfaces named after a painted tile get the PSX set material; anything else is lit like an actor.

const MACHINE_PATH := "res://assets/archive/props/machine.glb"
const BELL_PATH := "res://assets/archive/props/bell.glb"
const LEGACY_PATH := "res://assets/archive/archive_set.glb"

var machine: Node3D
var bell: Node3D
# true when the bell came from its own prop file (it then swings)
var bell_is_prop := false

func load_props() -> bool:
	machine = _from_file(MACHINE_PATH)
	bell = _from_file(BELL_PATH)
	bell_is_prop = bell != null
	if machine == null or bell == null:
		var legacy := _instantiate(LEGACY_PATH)
		if legacy != null:
			if machine == null:
				machine = _take(legacy.get_node_or_null("Machine") as Node3D)
			if bell == null:
				bell = _take(legacy.get_node_or_null("Bell") as Node3D)
			legacy.free()
	for part: Node3D in [machine, bell]:
		if part != null:
			_restyle(part)
	return machine != null and bell != null

static func _instantiate(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	return packed.instantiate() as Node3D if packed != null else null

# A prop file's root: the node itself when it is the only child of the glTF scene root.
static func _from_file(path: String) -> Node3D:
	var root := _instantiate(path)
	if root == null:
		return null
	if root.get_child_count() == 1 and root.get_child(0) is Node3D:
		var only := _take(root.get_child(0) as Node3D)
		only.transform = root.transform * only.transform
		root.free()
		return only
	return root

static func _take(node: Node3D) -> Node3D:
	if node != null and node.get_parent() != null:
		node.get_parent().remove_child(node)
	return node

# Each part gets its own material copies: an outline is a next_pass on them and must stay local.
static func _restyle(node: Node) -> void:
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		for surface in range(instance.mesh.get_surface_count()):
			var source := instance.mesh.surface_get_material(surface)
			var tile := source.resource_name if source != null else ""
			var material: ShaderMaterial
			if PSXMaterials.GLOWING.has(tile) or PSXMaterials.tile_texture(tile) != null:
				material = PSXMaterials.set_material(tile).duplicate() as ShaderMaterial
			else:
				var color := (source as BaseMaterial3D).albedo_color if source is BaseMaterial3D else Color.WHITE
				material = PSXMaterials.actor(color, 0.0)
			instance.set_surface_override_material(surface, material)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_restyle(child)
