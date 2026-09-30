class_name Placeholders
extends RefCounted

# Everything in the diorama is built from primitives until real models arrive. Each builder
# returns a Node3D whose named children (Body, Hat, BigGear, ...) are the handles animation
# code uses, so replacing one with a GLB later means re-creating those named nodes, not
# rewriting behaviour. All meshes use the project's PSX materials.

const SEGMENTS := 8

static func box(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO, actor: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, color, pos, actor)

static func cylinder(radius: float, height: float, color: Color, pos: Vector3 = Vector3.ZERO, top_radius: float = -1.0, actor: bool = false, segments: int = SEGMENTS) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _instance(mesh, color, pos, actor)

static func sphere(radius: float, color: Color, pos: Vector3 = Vector3.ZERO, actor: bool = false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = SEGMENTS
	mesh.rings = 4
	return _instance(mesh, color, pos, actor)

static func glow(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = PSXMaterials.unlit(color)
	instance.position = pos
	return instance

static func _instance(mesh: Mesh, color: Color, pos: Vector3, actor: bool) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = PSXMaterials.actor(color) if actor else PSXMaterials.lit(color)
	instance.position = pos
	return instance

static func _named(node: Node3D, node_name: String) -> Node3D:
	node.name = node_name
	return node

static func _add(parent: Node3D, child: Node3D, child_name: String) -> Node3D:
	child.name = child_name
	parent.add_child(child)
	return child

# ---- characters ---------------------------------------------------------------------------------

static func witch() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	_add(root, cylinder(0.42, 1.0, Palette.CLOAK, Vector3(0, 0.5, 0), 0.18, true), "Body")
	_add(root, sphere(0.2, Palette.SKIN, Vector3(0, 1.17, 0), true), "Head")
	var hat := _add(root, Node3D.new(), "Hat") as Node3D
	hat.position = Vector3(0, 1.3, 0)
	hat.add_child(cylinder(0.44, 0.05, Palette.HAT, Vector3.ZERO, -1.0, true))
	hat.add_child(cylinder(0.26, 0.6, Palette.HAT, Vector3(0, 0.32, 0), 0.0, true))
	hat.rotation_degrees = Vector3(0, 0, -6)
	var arm := _add(root, Node3D.new(), "ArmR") as Node3D
	arm.position = Vector3(0.3, 0.95, 0.0)
	arm.add_child(cylinder(0.06, 0.5, Palette.CLOAK, Vector3(0, -0.22, 0), -1.0, true, 6))
	var wand := _add(arm, Node3D.new(), "Wand") as Node3D
	wand.position = Vector3(0, -0.46, 0.0)
	wand.add_child(cylinder(0.02, 0.6, Palette.WOOD_DARK, Vector3(0, 0, 0.3), -1.0, false, 5))
	(wand.get_child(0) as Node3D).rotation_degrees = Vector3(90, 0, 0)
	wand.add_child(glow(Vector3(0.07, 0.07, 0.07), Palette.MAGIC_GOLD, Vector3(0, 0, 0.62)))
	# Anchor for the raccoon's tele-somatic link (a later milestone); intentionally empty.
	_add(root, Node3D.new(), "RaccoonLink")
	return root

static func tomas() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	_add(root, cylinder(0.3, 0.9, Palette.COAT, Vector3(0, 0.45, 0), 0.22, true), "Body")
	_add(root, sphere(0.18, Palette.SKIN, Vector3(0, 1.08, 0), true), "Head")
	_add(root, cylinder(0.21, 0.1, Palette.WOOD_DARK, Vector3(0, 1.25, 0), -1.0, true), "Cap")
	_add(root, cylinder(0.25, 0.08, Palette.SCARF, Vector3(0, 0.92, 0), -1.0, true), "Scarf")
	var left := _add(root, Node3D.new(), "ArmL") as Node3D
	left.position = Vector3(-0.28, 0.85, 0)
	left.add_child(cylinder(0.06, 0.48, Palette.COAT, Vector3(0, -0.2, 0), -1.0, true, 6))
	var right := _add(root, Node3D.new(), "ArmR") as Node3D
	right.position = Vector3(0.28, 0.85, 0)
	right.add_child(cylinder(0.06, 0.48, Palette.COAT, Vector3(0, -0.2, 0), -1.0, true, 6))
	var tool := _add(right, Node3D.new(), "Tool") as Node3D
	tool.position = Vector3(0, -0.46, 0)
	tool.add_child(box(Vector3(0.07, 0.07, 0.22), Palette.BRASS_DARK, Vector3.ZERO, true))
	return root

static func raccoon() -> Node3D:
	# A dark silhouette, watching. Deliberately flat in colour: it reads as a shape, not a creature.
	var root := Node3D.new()
	root.name = "Raccoon"
	_add(root, sphere(0.2, Palette.SILHOUETTE, Vector3(0, 0.2, 0), true), "Body").scale = Vector3(1.0, 0.9, 1.5)
	_add(root, sphere(0.13, Palette.SILHOUETTE, Vector3(0, 0.36, 0.3), true), "Head")
	_add(root, cylinder(0.05, 0.1, Palette.SILHOUETTE, Vector3(-0.08, 0.5, 0.3), 0.0, true, 4), "EarL")
	_add(root, cylinder(0.05, 0.1, Palette.SILHOUETTE, Vector3(0.08, 0.5, 0.3), 0.0, true, 4), "EarR")
	var tail := _add(root, cylinder(0.06, 0.45, Palette.SILHOUETTE, Vector3(0, 0.22, -0.42), -1.0, true, 6), "Tail")
	tail.rotation_degrees = Vector3(70, 0, 0)
	_add(root, glow(Vector3(0.04, 0.04, 0.02), Color.WHITE, Vector3(-0.05, 0.38, 0.42)), "EyeL")
	_add(root, glow(Vector3(0.04, 0.04, 0.02), Color.WHITE, Vector3(0.05, 0.38, 0.42)), "EyeR")
	return root

# ---- the machine, the tree, the bell --------------------------------------------------------------

static func machine() -> Node3D:
	var root := Node3D.new()
	root.name = "Machine"
	_add(root, box(Vector3(2.2, 0.25, 1.4), Palette.WOOD_DARK, Vector3(0, 0.125, 0)), "Base")
	# Gears stand on edge, face toward the camera. Each is a dark disc with lighter teeth around
	# the rim and iron spokes, so it reads as a gear (and as turning) rather than a coin.
	var big := _add(root, cylinder(0.62, 0.12, Palette.BRASS_DARK, Vector3(-0.35, 0.78, 0), -1.0, false, 10), "BigGear") as Node3D
	big.rotation_degrees = Vector3(90, 0, 0)
	_gear_details(big, 0.62, 10, Palette.BRASS)
	var small := _add(root, cylinder(0.3, 0.12, Palette.BRASS_DARK, Vector3(0.45, 0.6, 0), -1.0, false, 8), "SmallGear") as Node3D
	small.rotation_degrees = Vector3(90, 0, 0)
	_gear_details(small, 0.3, 8, Palette.BRASS)
	_add(root, cylinder(0.1, 1.1, Palette.IRON, Vector3(-0.95, 0.8, -0.4), -1.0, false, 6), "Pipe")
	var lever := _add(root, box(Vector3(0.08, 0.7, 0.08), Palette.IRON, Vector3(0.95, 0.6, 0.3)), "Lever")
	lever.rotation_degrees = Vector3(0, 0, -20)
	# The small piece that has to be held while the big wheel turns.
	_add(root, box(Vector3(0.16, 0.16, 0.16), Palette.BRASS, Vector3(0.1, 0.98, 0.2)), "Cam")
	# Lit from within once it runs (off at first).
	var lamp := glow(Vector3(0.12, 0.12, 0.12), Palette.LAMP, Vector3(-0.95, 1.4, -0.4))
	lamp.visible = false
	_add(root, lamp, "Indicator")
	return root

# Teeth around the rim and two crossing spokes, in the gear's local XZ plane (its axis is Y).
static func _gear_details(gear: Node3D, radius: float, teeth: int, tooth_color: Color) -> void:
	for i in range(teeth):
		var angle := TAU * i / teeth
		var tooth := box(Vector3(0.16, 0.14, 0.12), tooth_color, Vector3(cos(angle) * radius, 0, sin(angle) * radius))
		tooth.rotation.y = -angle
		gear.add_child(tooth)
	gear.add_child(box(Vector3(radius * 1.7, 0.16, 0.1), Palette.IRON, Vector3(0, 0.02, 0)))
	gear.add_child(box(Vector3(0.1, 0.16, radius * 1.7), Palette.IRON, Vector3(0, 0.02, 0)))

static func tree_with_bell() -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	_add(root, cylinder(0.35, 3.0, Palette.WOOD, Vector3(0, 1.5, 0), 0.22, false, 6), "Trunk")
	_add(root, sphere(1.3, Palette.CANOPY, Vector3(0, 3.4, 0)), "CanopyA")
	_add(root, sphere(1.0, Palette.CANOPY, Vector3(0.9, 3.0, 0.4)), "CanopyB")
	_add(root, sphere(0.9, Palette.CANOPY, Vector3(-0.8, 3.1, -0.3)), "CanopyC")
	var branch := _add(root, cylinder(0.07, 1.4, Palette.WOOD, Vector3(-0.75, 2.4, 0), -1.0, false, 5), "Branch")
	branch.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(_bell())
	return root

static func _bell() -> Node3D:
	# Hangs from the branch tilted into the wind, on purpose: the detail a player who looks
	# closely can notice, and the clearing's one epistemic affordance.
	var bell := Node3D.new()
	bell.name = "Bell"
	bell.position = Vector3(-1.3, 2.25, 0)
	bell.add_child(cylinder(0.01, 0.3, Palette.IRON, Vector3(0, 0.15, 0), -1.0, false, 4))
	var body := cylinder(0.2, 0.3, Palette.BRASS, Vector3(0, -0.12, 0), 0.06, false, 8)
	body.name = "BellBody"
	bell.add_child(body)
	bell.rotation_degrees = Vector3(0, 0, 24)
	return bell

static func structure() -> Node3D:
	# The crooked structure: a lean-to that has leaned for years.
	var root := Node3D.new()
	root.name = "Structure"
	var post_a := _add(root, box(Vector3(0.22, 2.4, 0.22), Palette.WOOD, Vector3(-1.2, 1.2, 0)), "PostA")
	post_a.rotation_degrees = Vector3(0, 0, 7)
	_add(root, box(Vector3(0.22, 2.0, 0.22), Palette.WOOD, Vector3(1.2, 1.0, 0)), "PostB")
	var roof := _add(root, box(Vector3(3.2, 0.12, 1.8), Palette.WOOD_DARK, Vector3(0, 2.25, 0)), "Roof")
	roof.rotation_degrees = Vector3(0, 0, -8)
	_add(root, box(Vector3(2.6, 1.6, 0.1), Palette.WOOD, Vector3(0, 0.9, -0.8)), "BackWall")
	return root

static func crate() -> Node3D:
	var root := Node3D.new()
	root.name = "Crate"
	_add(root, box(Vector3(0.8, 0.6, 0.6), Palette.WOOD, Vector3(0, 0.3, 0)), "Box")
	return root

static func workbench() -> Node3D:
	var root := Node3D.new()
	root.name = "Workbench"
	_add(root, box(Vector3(1.8, 0.1, 0.8), Palette.WOOD, Vector3(0, 0.9, 0)), "Top")
	for x in [-0.8, 0.8]:
		_add(root, box(Vector3(0.12, 0.9, 0.12), Palette.WOOD_DARK, Vector3(x, 0.45, 0)), "Leg%s" % ("L" if x < 0 else "R"))
	_add(root, box(Vector3(0.25, 0.12, 0.2), Palette.BRASS_DARK, Vector3(-0.4, 1.01, 0.05)), "Parts")
	return root

# ---- the ground -----------------------------------------------------------------------------------

static func ground(radius: float, path_angle_deg: float, path_gap_deg: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Ground"
	_add(root, cylinder(radius, 0.2, Palette.GRASS, Vector3(0, -0.1, 0), -1.0, false, 20), "Grass")
	_add(root, cylinder(3.4, 0.02, Palette.DIRT, Vector3(0, 0.01, -0.6), -1.0, false, 14), "WornEarth")
	var stones := Node3D.new()
	stones.name = "StoneRing"
	root.add_child(stones)
	var count := 28
	for i in range(count):
		var degrees := 360.0 * i / count
		if absf(wrapf(degrees - path_angle_deg, -180.0, 180.0)) < path_gap_deg:
			continue
		var angle := deg_to_rad(degrees)
		var stone := box(Vector3(0.55, 0.35, 0.4), Palette.STONE, Vector3(sin(angle) * (radius - 0.6), 0.17, cos(angle) * (radius - 0.6)))
		stone.rotation.y = angle
		stones.add_child(stone)
	return root

static func lantern_post() -> Node3D:
	var root := Node3D.new()
	root.name = "LanternPost"
	_add(root, cylinder(0.07, 2.2, Palette.IRON, Vector3(0, 1.1, 0), -1.0, false, 5), "Pole")
	_add(root, glow(Vector3(0.25, 0.3, 0.25), Palette.LAMP, Vector3(0, 2.3, 0)), "Lantern")
	return root
