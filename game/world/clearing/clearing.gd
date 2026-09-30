class_name Clearing
extends Room

# THE CLEARING: the first complete causal room. One witch, one man, one machine, one tree with
# a bell, one crooked structure, one path out, one raccoon watching. Built from placeholders.
#
# Layout (x right, z toward the camera, metres):
#     path out  (0, -8.9)            structure (-4.4, -5.0)   tree + bell (3.6, -3.2)
#     workbench (-3.2, -2.6)   machine (-1.6, -1.2)   Tomas (-0.1, -0.9)   crate (2.4, -0.4)
#     witch starts (0.4, 4.5)

const RADIUS := 9.5
const PATH_ANGLE := 180.0
const TREE_AT := Vector3(3.6, 0, -3.2)
const MACHINE_AT := Vector3(-1.6, 0, -1.2)
const STRUCTURE_AT := Vector3(-4.4, 0, -5.0)
const PATH_AT := Vector3(0, 0, -7.8)

var machine_view: MachineView
var tomas: NPC
var raccoon: Node3D
var bell: Node3D
var moon: DirectionalLight3D

func _ready() -> void:
	room_id = "clearing"
	spawn_position = Vector3(0.4, 0.0, 4.5)
	camera_focus = Vector3(0.0, 0.8, -1.2)
	navigator = GridNavigator.new(Rect2(-11.0, -11.0, 22.0, 22.0))
	navigator.block_outside(8.6, PATH_AT + Vector3(0, 0, -1.2), 1.5)
	_build_environment()
	_build_ground()
	_build_props()
	_build_tomas()
	_build_interactables()

func _build_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load("res://render/psx/sky_stars.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.25, 0.42)
	environment.ambient_light_energy = 0.75
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.07, 0.08, 0.14)
	environment.fog_density = 0.012
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	moon = DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = Palette.MOON
	moon.light_energy = 0.55
	moon.rotation_degrees = Vector3(-52, 28, 0)
	add_child(moon)
	for spec in [[MACHINE_AT + Vector3(0.6, 2.4, 1.2), 1.3, 6.0], [PATH_AT + Vector3(-1.3, 2.3, 0), 1.6, 4.5], [PATH_AT + Vector3(1.3, 2.3, 0), 1.6, 4.5]]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Palette.LAMP
		lamp.light_energy = spec[1]
		lamp.omni_range = spec[2]
		lamp.position = spec[0]
		lamp.shadow_enabled = false
		add_child(lamp)

func _build_ground() -> void:
	var ground := Placeholders.ground(RADIUS, PATH_ANGLE, 14.0)
	add_child(ground)
	var strip := Placeholders.box(Vector3(2.4, 0.02, 7.0), Palette.DIRT, Vector3(0, 0.01, -12.4))
	strip.name = "PathStrip"
	ground.add_child(strip)
	for x in [-1.3, 1.3]:
		var post := Placeholders.lantern_post()
		post.position = PATH_AT + Vector3(x, 0, 0)
		add_child(post)
	# Picking surface only: the witch has no gravity and does not stand on it.
	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundPick"
	floor_body.collision_layer = PhysicsLayers.GROUND
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS + 3.0
	cylinder.height = 0.2
	shape.shape = cylinder
	shape.position = Vector3(0, -0.1, 0)
	floor_body.add_child(shape)
	add_child(floor_body)

func _build_props() -> void:
	# MachineView animates the named gears of the machine it is attached to, so the placeholder's
	# children are moved under a MachineView root (a Node3D with the behaviour).
	var machine := Placeholders.machine()
	machine_view = MachineView.new()
	machine_view.name = "Machine"
	machine_view.position = MACHINE_AT
	for child in machine.get_children():
		machine.remove_child(child)
		machine_view.add_child(child)
	machine.free()
	add_child(machine_view)
	add_obstacle(MACHINE_AT, 1.25)

	var tree := Placeholders.tree_with_bell()
	tree.position = TREE_AT
	add_child(tree)
	bell = tree.get_node("Bell")
	add_obstacle(TREE_AT, 0.4, 3.0)

	var structure := Placeholders.structure()
	structure.position = STRUCTURE_AT
	add_child(structure)
	add_obstacle(STRUCTURE_AT, 1.7, 2.4)

	raccoon = Placeholders.raccoon()
	raccoon.position = STRUCTURE_AT + Vector3(0.4, 2.3, 0.0)
	raccoon.rotation_degrees.y = 12.0
	add_child(raccoon)

	var crate := Placeholders.crate()
	crate.position = Vector3(2.4, 0, -0.4)
	add_child(crate)
	add_obstacle(crate.position, 0.5, 0.6)

	var bench := Placeholders.workbench()
	bench.position = Vector3(-3.2, 0, -2.6)
	add_child(bench)
	add_obstacle(bench.position, 1.0, 1.0)

func _build_tomas() -> void:
	tomas = NPC.new()
	tomas.name = "Tomas"
	tomas.actor_id = "tomas"
	tomas.anchors = {
		"braced": {"position": Vector3(0.7, 0, -0.9), "yaw_deg": 12.0},
		"working": {"position": Vector3(-0.1, 0, -0.9), "yaw_deg": -85.0},
		"inviting": {"position": Vector3(-0.1, 0, -0.9), "yaw_deg": -35.0},
		"partnered": {"position": Vector3(-0.1, 0, -0.9), "yaw_deg": -85.0},
		"withdrawn": {"position": Vector3(1.7, 0, -0.4), "yaw_deg": 90.0},
		"quiet": {"position": Vector3(0.2, 0, -0.6), "yaw_deg": -55.0},
	}
	add_child(tomas)
	tomas.snap_pose("braced")
	navigator.block_disc(Vector3(-0.1, 0, -0.9), 0.85)
	navigator.block_disc(Vector3(0.7, 0, -0.9), 0.85)

func _build_interactables() -> void:
	var tomas_interactable := Interactable.new()
	tomas_interactable.name = "Interact_tomas"
	tomas_interactable.target_id = "tomas"
	tomas_interactable.display_key = "obj.tomas"
	tomas_interactable.focus_height = 1.0
	tomas_interactable.approach_point = Vector3(0.9, 0, 0.6)
	tomas_interactable.causal_tags = PackedStringArray(["attention", "authorship"])
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.95
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	tomas_interactable.add_child(shape)
	tomas.add_child(tomas_interactable)
	register_interactable(tomas_interactable)

	add_interactable("machine", "obj.machine", MACHINE_AT, 1.7, 0.8, Vector3(-0.7, 0, 0.5), PackedStringArray(["mechanism", "timing"]))
	add_interactable("bell", "obj.bell", TREE_AT + Vector3(-1.3, 2.25, 0.0), 0.8, 0.0, Vector3(2.3, 0, -1.8), PackedStringArray(["wind", "sound", "attention"]))
	add_interactable("path_out", "obj.path_out", PATH_AT, 1.3, 0.4, Vector3(0, 0, -6.6), PackedStringArray(["departure"]))

# The node that gets the focus outline when `target_id` is pointed at (null = no outline).
func focus_node(target_id: String) -> Node3D:
	match target_id:
		"tomas":
			return tomas.visual
		"machine":
			return machine_view
		"bell":
			return bell
	return null

# Where the camera should look for a focus id ("player" is resolved by the caller).
func focus_position(target_id: String) -> Variant:
	if target_id == "tomas":
		return tomas.global_position + Vector3(0, 1.0, 0)
	var interactable := get_interactable(target_id)
	return interactable.focus_point() if interactable != null else null

# Makes the room LOOK like a Mirror state (used at start and after a load). Reads only.
func apply_mirror_state(engine: MirrorEngine) -> void:
	var machine_state := str(engine.get_world("machine", {}).get("state", "jammed"))
	machine_view.apply_state(machine_state)
	tomas.snap_pose(str(engine.get_npc_state("tomas").get("stance", "braced")))
