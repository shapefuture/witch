class_name ArchiveHall
extends Room

# THE ARCHIVE HALL: the first complete causal room. One witch, one man, one brass machine, one
# bell on its wooden mount, one crooked bookcase tower with a raccoon on a shelf, one pointed
# arch out. A gothic chamber of tall shelves, an eye on the wall, a hooded statue and a single
# shaft of late light on a spiral-painted floor.
#
# Visual direction comes from the user's reference still: faceted, mottled, olive-and-purple, lit
# by one beam through the vault. The SET is authored and light-baked in Blender
# (tools/blender/build_hall.py) and loaded by ArchiveSet; characters stay placeholders.
# Gameplay anchors below are shared with the build script, so art and interactables agree.
#
# `room_id` stays "clearing": it is the key of this place in Mirror's world catalog (ids are
# stable data; the look of the place is not).
#
# Layout (x right, z toward the camera, metres):
#     arch out (-4.2, -10)    tower + raccoon (-6.2, -5.4)      bell post (5.6, -3.0)
#     bench (-3.2, -2.6)   machine (-1.6, -1.2)   Tomas (-0.1, -0.9)   crate (2.4, -0.4)
#     witch starts (1.0, 0.3)           statue (2.6, -3.0)      light pool (0.8, -1.5)

const RADIUS := 9.5
const BELL_POST_AT := Vector3(5.6, 0, -3.0)
const MACHINE_AT := Vector3(-1.6, 0, -1.2)
const TOWER_AT := Vector3(-6.2, 0, -5.4)
const ARCH_X := -4.2   # the way out is back-left (tools/blender/kit/props_hall.py ARCH_X)
const PATH_AT := Vector3(ARCH_X, 0, -7.8)
const BELL_TILT_DEG := 24.0

# Capture aid (--no-fx): leave out the shaft, dust and glow to see the bare baked set.
static var atmosphere_enabled := true

var machine_view: MachineView
var tomas: NPC
var raccoon: Node3D
var bell: Node3D
var set_parts := ArchiveSet.new()
var sky: MeshInstance3D
# Camera-space frame pieces (see ArchiveSet). GameRoot parents them to the camera.
var foreground: Node3D

func _ready() -> void:
	room_id = "clearing"
	spawn_position = Vector3(1.0, 0.0, 0.3)
	# Low and wide, looking up a little: tall shelves become cliffs, the witch is small among them.
	var wide := wide_framing()
	camera_focus = wide["focus"]
	camera_distance = wide["distance"]
	camera_pitch_deg = wide["pitch_deg"]
	camera_yaw_deg = wide["yaw_deg"]
	camera_fov = wide["fov"]
	camera_roll_deg = wide["roll_deg"]
	navigator = GridNavigator.new(Rect2(-11.0, -11.0, 22.0, 22.0))
	navigator.block_outside(8.6, PATH_AT + Vector3(0, 0, -1.2), 1.5)
	# The camera never follows her, so she must stay where the frame shows her (4:3 is the tightest).
	navigator.block_where(func(p: Vector2) -> bool: return not stage_allows(p.x, p.y) and not (p.y < -6.0 and absf(p.x - ARCH_X) < 1.5))
	PSXGlobals.set_fog(PSXGlobals.FOG_COLOR, PSXGlobals.FOG_DENSITY)
	_build_environment()
	_build_ground_pick()
	_build_props()
	if atmosphere_enabled:
		add_child(HallAtmosphere.new())
	_build_tomas()
	_build_interactables()

func hero_regions() -> Array:
	var pool := StageLight.anchor_vector("pool", Vector3(1.0, 0.0, -0.2))
	var sun := StageLight.anchor_vector("sun_dir", Vector3(0.25, 0.91, -0.33))
	return [
		{"at": pool, "radius": 2.0, "height": 0.3},
		{"at": pool + sun * 1.5, "to": pool + sun * 12.0, "radius": 1.4, "height": 0.0},
		{"at": Vector3(ARCH_X, 0.0, -9.4), "radius": 2.2, "height": 5.0},
		{"at": Vector3(2.6, 0.0, -3.0), "radius": 0.7, "height": 3.0},
	]

# The bolted master shot. tools/blender/build_hall.py bakes the camera-space foreground frame for
# exactly this pose (CAMERA_AT / CAMERA_DISTANCE / CAMERA_PITCH / CAMERA_YAW): change both together.
static func wide_framing() -> Dictionary:
	return {"focus": Vector3(0.2, 3.3, -2.2), "distance": 11.0, "pitch_deg": -14.0, "yaw_deg": 24.0, "fov": 52.0, "roll_deg": 3.5}

# Where the witch may walk: the open floor between the shelves, trimmed so that she is always inside
# the frame of the bolted wide shot at 4:3 (the tightest aspect). The camera sits to the right, so
# the near-left and near-right corners of the floor fall outside the picture and are not walkable.
# tests/render/test_archive_hall.gd checks this against the real camera.
static func stage_allows(x: float, z: float) -> bool:
	if z > 4.3:
		return false
	var left := maxf(-6.8, -4.4 + (z - 1.0) * 1.5)
	var right := 6.4 if z <= -3.0 else 6.4 - (z + 3.0) * 0.8
	return x >= left and x <= right

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = PSXGlobals.FOG_COLOR
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	# What shows through the hole in the vault.
	var dome_material := ShaderMaterial.new()
	dome_material.shader = load("res://render/psx/sky_dome.gdshader")
	dome_material.set_shader_parameter("sun_dir", StageLight.sun_dir())
	var dome := SphereMesh.new()
	dome.radius = 100.0
	dome.height = 200.0
	dome.radial_segments = 32
	dome.rings = 16
	sky = MeshInstance3D.new()
	sky.name = "Sky"
	sky.mesh = dome
	sky.material_override = dome_material
	sky.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)

func _build_ground_pick() -> void:
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
	var loaded := set_parts.load_set()
	if not loaded:
		push_warning("ArchiveHall: assets/archive/archive_set.glb missing or incomplete; run tools/blender/build_hall.py")
		return
	set_parts.root.name = "Set"
	set_parts.batch.name = "StaticSet"
	add_child(set_parts.root)
	# The machine keeps its named parts; MachineView turns them.
	var machine := set_parts.take(set_parts.machine)
	machine.set_script(MachineView)
	machine.name = "Machine"
	add_child(machine)
	machine_view = machine as MachineView
	var swing := set_parts.take(set_parts.bell)
	swing.name = "Bell"
	add_child(swing)
	swing.rotation_degrees = Vector3(0, 0, BELL_TILT_DEG)   # hangs tilted into the draught, on purpose
	bell = swing
	if set_parts.foreground != null:
		foreground = set_parts.take(set_parts.foreground)
		foreground.name = "Foreground"
		add_child(foreground)
	add_obstacle(MACHINE_AT, 1.25)
	add_obstacle(BELL_POST_AT, 0.95, 3.0)
	add_obstacle(TOWER_AT, 1.7, 2.4)
	add_obstacle(Vector3(5.4, 0, -8.0), 1.3, 3.0)
	add_obstacle(Vector3(-6.4, 0, -7.7), 1.3, 3.0)
	add_obstacle(Vector3(2.6, 0, -3.0), 1.3, 3.0)
	add_obstacle(Vector3(2.4, 0, -0.4), 0.5, 0.6)
	add_obstacle(Vector3(-3.2, 0, -2.6), 1.0, 1.0)
	raccoon = CharacterModels.instantiate("raccoon")
	if raccoon == null:
		raccoon = Placeholders.raccoon()
	else:
		CharacterModels.play(raccoon, "watch", 0.7)
	raccoon.position = StageLight.anchor_vector("raccoon_perch", Vector3(-3.8, 2.2, -4.5))
	raccoon.rotation_degrees.y = 12.0
	add_child(raccoon)
	BlobShadow.attach(raccoon, 0.26, 0.5)

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
	add_interactable("bell", "obj.bell", BELL_POST_AT + Vector3(-1.3, 2.25, 0.0), 0.8, 0.0, BELL_POST_AT + Vector3(-1.3, 0, 1.6), PackedStringArray(["wind", "sound", "attention"]))
	# The whole pointed arch is the target: a tall volume in the wall, so a low camera can still
	# point at it over the heads of the people standing in front.
	add_interactable("path_out", "obj.path_out", Vector3(ARCH_X, 0, -9.4), 2.6, 3.2, Vector3(ARCH_X + 0.6, 0, -6.4), PackedStringArray(["departure"]))

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
	if machine_view != null:
		machine_view.apply_state(machine_state)
	tomas.snap_pose(str(engine.get_npc_state("tomas").get("stance", "braced")))
