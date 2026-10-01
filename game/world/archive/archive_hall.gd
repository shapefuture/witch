class_name ArchiveHall
extends Room

# THE ARCHIVE HALL: the first complete causal room. One witch, one man, one brass machine, one
# bell on its wooden mount, one crooked bookcase tower with a raccoon on a shelf, one pointed
# arch out. A gothic chamber of tall shelves, an eye on the wall, a hooded statue and a single
# shaft of late light on a spiral-painted floor.
#
# The set is PRE-RENDERED (docs/art/PLATE_CONTRACT.md): plates projected onto proxy geometry by
# PlateStage. Only what moves is drawn live: the machine and the bell (ArchiveProps), the people,
# the dust. The layout (spawn, Tomas, interactables, the walkable floor, obstacles, the picture's
# focal regions, the master framing) comes from assets/archive/anchors.json, written by the same
# build that renders the plates, so art and play agree; the constants below are only fallbacks.
#
# `room_id` stays "clearing": it is the key of this place in Mirror's world catalog (ids are
# stable data; the look of the place is not).

const RADIUS := 9.5
const FALLBACK_SPAWN := Vector3(1.0, 0.0, 0.3)
const FALLBACK_TOMAS_AT := Vector3(0.7, 0.0, -0.9)
const FALLBACK_TOMAS_YAW := 12.0
const FALLBACK_FRAMING := {"focus": Vector3(0.2, 3.3, -2.2), "distance": 11.0, "pitch_deg": -14.0, "yaw_deg": 24.0, "fov": 52.0, "roll_deg": 3.5}
const FALLBACK_INTERACTABLES := {
	"machine": {"at": Vector3(-1.6, 0, -1.2), "radius": 1.7, "height": 0.8, "approach": Vector3(-0.7, 0, 0.5)},
	"bell": {"at": Vector3(4.3, 2.25, -3.0), "radius": 0.8, "height": 0.0, "approach": Vector3(4.3, 0, -1.4)},
	"path_out": {"at": Vector3(-4.2, 0, -9.4), "radius": 2.6, "height": 3.2, "approach": Vector3(-3.6, 0, -6.4)},
}
# The open floor between the shelves, trimmed so the bolted wide shot sees her at 4:3, plus the way
# out under the arch (x, z).
const FALLBACK_WALKABLE := [[0.55, 4.3], [-4.4, 1.0], [-6.8, -0.6], [-6.8, -5.27], [-5.7, -6.44], [-5.7, -10.4], [-2.7, -10.4],
	[-2.7, -8.17], [0.0, -8.6], [3.0, -8.06], [6.4, -5.74], [6.4, -3.0], [0.56, 4.3]]
const FALLBACK_OBSTACLES := [
	{"at": [-1.6, -1.2], "radius": 1.25, "height": 1.5}, {"at": [5.6, -3.0], "radius": 0.95, "height": 3.0},
	{"at": [-6.2, -5.4], "radius": 1.7, "height": 2.4}, {"at": [5.4, -8.0], "radius": 1.3, "height": 3.0},
	{"at": [-6.4, -7.7], "radius": 1.3, "height": 3.0}, {"at": [2.6, -3.0], "radius": 1.3, "height": 3.0},
	{"at": [2.4, -0.4], "radius": 0.5, "height": 0.6}, {"at": [-3.2, -2.6], "radius": 1.0, "height": 1.0},
]
const BELL_TILT_DEG := 24.0
const BELL_SWING_DEG := 3.0
# Gameplay data that is not geometry: what each interactable is about.
const TAGS := {"machine": ["mechanism", "timing"], "bell": ["wind", "sound", "attention"], "path_out": ["departure"]}
# Tomas's stances relative to where he first stands (anchors.json tomas_at / tomas_yaw_deg).
const STANCES := {
	"braced": {"offset": Vector3(0.0, 0, 0.0), "yaw": 0.0},
	"working": {"offset": Vector3(-0.8, 0, 0.0), "yaw": -97.0},
	"inviting": {"offset": Vector3(-0.8, 0, 0.0), "yaw": -47.0},
	"partnered": {"offset": Vector3(-0.8, 0, 0.0), "yaw": -97.0},
	"withdrawn": {"offset": Vector3(1.0, 0, 0.5), "yaw": 78.0},
	"quiet": {"offset": Vector3(-0.5, 0, 0.3), "yaw": -67.0},
}

# Capture aid (--no-fx): leave out the dust to see the bare plates.
static var atmosphere_enabled := true
static var _walkable_cache := PackedVector2Array()

var machine_view: MachineView
var tomas: NPC
var raccoon: Node3D
var bell: Node3D
var plates: PlateStage
var atmosphere: HallAtmosphere
var sky: MeshInstance3D

func _ready() -> void:
	room_id = "clearing"
	spawn_position = anchor_point("spawn", FALLBACK_SPAWN)
	var wide := wide_framing()
	camera_focus = wide["focus"]
	camera_distance = wide["distance"]
	camera_pitch_deg = wide["pitch_deg"]
	camera_yaw_deg = wide["yaw_deg"]
	camera_fov = wide["fov"]
	camera_roll_deg = wide["roll_deg"]
	var bounds := Rect2(-11.0, -11.0, 22.0, 22.0)
	for p in walkable_polygon():
		bounds = bounds.expand(p)
	navigator = GridNavigator.new(bounds.grow(1.0))
	# The camera never follows her, so she may only stand where the bolted frame shows her.
	navigator.block_where(func(p: Vector2) -> bool: return not stage_allows(p.x, p.y))
	PSXGlobals.set_fog(PSXGlobals.FOG_COLOR, PSXGlobals.FOG_DENSITY)
	_build_environment()
	_build_ground_pick()
	plates = PlateStage.new()
	add_child(plates)
	BlobShadow.light_probe = plates.key_at
	_build_props()
	if atmosphere_enabled:
		atmosphere = HallAtmosphere.new()
		add_child(atmosphere)
	plates.variant_changed.connect(func(_variant: String) -> void: _sync_sun())
	_build_tomas()
	_build_interactables()

func _exit_tree() -> void:
	if plates != null and BlobShadow.light_probe == Callable(plates, "key_at"):
		BlobShadow.light_probe = Callable()

# ---- layout from anchors.json ------------------------------------------------------------------------

static func anchors() -> Dictionary:
	return StageLight.anchors()

static func _v3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

static func anchor_point(key: String, fallback: Vector3) -> Vector3:
	return _v3(anchors().get(key), fallback)

# The bolted master shot's framing (also the base for every computed shot).
static func wide_framing() -> Dictionary:
	var value: Variant = anchors().get("framing")
	if not value is Dictionary:
		return FALLBACK_FRAMING.duplicate()
	var f: Dictionary = value
	return {"focus": _v3(f.get("focus"), FALLBACK_FRAMING["focus"]), "distance": float(f.get("distance", FALLBACK_FRAMING["distance"])),
		"pitch_deg": float(f.get("pitch_deg", FALLBACK_FRAMING["pitch_deg"])), "yaw_deg": float(f.get("yaw_deg", FALLBACK_FRAMING["yaw_deg"])),
		"fov": float(f.get("fov", FALLBACK_FRAMING["fov"])), "roll_deg": float(f.get("roll_deg", FALLBACK_FRAMING["roll_deg"]))}

# Where the witch may stand: a closed polygon of the floor in world (x, z).
static func walkable_polygon() -> PackedVector2Array:
	if _walkable_cache.is_empty():
		var value: Variant = anchors().get("walkable")
		var source: Array = value if value is Array and (value as Array).size() >= 3 else FALLBACK_WALKABLE
		for p: Variant in source:
			_walkable_cache.append(Vector2(float(p[0]), float(p[1])))
	return _walkable_cache

static func stage_allows(x: float, z: float) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(x, z), walkable_polygon())

static func interactable_spec(id: String) -> Dictionary:
	var fallback: Dictionary = FALLBACK_INTERACTABLES[id]
	var all: Variant = anchors().get("interactables")
	var value: Variant = (all as Dictionary).get(id) if all is Dictionary else null
	if not value is Dictionary:
		return fallback.duplicate()
	var spec: Dictionary = value
	return {"at": _v3(spec.get("at"), fallback["at"]), "radius": float(spec.get("radius", fallback["radius"])),
		"height": float(spec.get("height", fallback["height"])), "approach": _v3(spec.get("approach"), fallback["approach"])}

static func obstacles() -> Array:
	var value: Variant = anchors().get("obstacles")
	return value if value is Array else FALLBACK_OBSTACLES

# Where the witch walks to when she leaves: straight on through the arch, out of the picture.
func exit_point() -> Vector3:
	var arch: Vector3 = interactable_spec("path_out")["at"]
	return Vector3(arch.x, 0.0, arch.z - 6.6)

func hero_regions() -> Array:
	var value: Variant = anchors().get("hero_regions")
	if value is Array:
		var out: Array = []
		for region: Variant in value:
			if region is Dictionary:
				var r := {"at": _v3(region.get("at"), Vector3.ZERO), "radius": float(region.get("radius", 1.0)), "height": float(region.get("height", 0.0))}
				if region.has("to"):
					r["to"] = _v3(region["to"], r["at"])
				out.append(r)
		return out
	var pool := StageLight.anchor_vector("pool", Vector3(1.0, 0.0, -0.2))
	var sun := StageLight.sun_dir()
	return [
		{"at": pool, "radius": 2.0, "height": 0.3},
		{"at": pool + sun * 1.5, "to": pool + sun * 12.0, "radius": 1.4, "height": 0.0},
		{"at": Vector3(-4.2, 0.0, -9.4), "radius": 2.2, "height": 5.0},
		{"at": Vector3(2.6, 0.0, -3.0), "radius": 0.7, "height": 3.0},
	]

# A plate rendered for this beat, as an exact camera pose with the beat's roll ({} if none).
func shot_pose(mode: String, focus_ids: Array, roll_deg: float) -> Dictionary:
	if plates == null or plates.plates == null:
		return {}
	var plate := plates.plates.shot_for(mode, focus_ids)
	return PlateSet.pose_of(plate, roll_deg) if not plate.is_empty() else {}

# ---- the room ages (presentation only) -------------------------------------------------------------

func set_room_variant(variant: String, seconds: float = PlateStage.CROSSFADE_SECONDS) -> void:
	if plates != null:
		await plates.crossfade_to(variant, seconds)

func _sync_sun() -> void:
	if atmosphere != null and plates != null:
		atmosphere.set_sun(1.0 if plates.variant.is_empty() else 0.35)

# ---- construction -------------------------------------------------------------------------------------

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = PSXGlobals.FOG_COLOR
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	# What shows through the hole in the vault (the proxy has the same hole as the plates).
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
	var props := ArchiveProps.new()
	if not props.load_props():
		push_warning("ArchiveHall: no machine/bell props (assets/archive/props/*.glb or archive_set.glb)")
	if props.machine != null:
		var machine := props.machine
		machine.set_script(MachineView)
		machine.name = "Machine"
		add_child(machine)
		machine_view = machine as MachineView
	if props.bell != null:
		var swing := props.bell
		swing.set_script(BellView)
		(swing as BellView).tilt_deg = BELL_TILT_DEG   # hangs tilted into the draught, on purpose
		(swing as BellView).swing_deg = BELL_SWING_DEG if props.bell_is_prop else 0.0
		swing.name = "Bell"
		add_child(swing)
		bell = swing
	for obstacle: Variant in obstacles():
		var at: Array = obstacle["at"]
		add_obstacle(Vector3(float(at[0]), 0, float(at[1])), float(obstacle["radius"]), float(obstacle.get("height", 1.5)))
	raccoon = Placeholders.raccoon()
	raccoon.position = StageLight.anchor_vector("raccoon_perch", Vector3(-3.8, 2.2, -4.5))
	raccoon.rotation_degrees.y = 12.0
	add_child(raccoon)
	BlobShadow.attach(raccoon, 0.26, 0.5)

func _build_tomas() -> void:
	var home := anchor_point("tomas_at", FALLBACK_TOMAS_AT)
	var yaw := float(anchors().get("tomas_yaw_deg", FALLBACK_TOMAS_YAW))
	tomas = NPC.new()
	tomas.name = "Tomas"
	tomas.actor_id = "tomas"
	var stances := {}
	for stance: String in STANCES:
		stances[stance] = {"position": home + STANCES[stance]["offset"], "yaw_deg": yaw + float(STANCES[stance]["yaw"])}
	tomas.anchors = stances
	add_child(tomas)
	tomas.snap_pose("braced")
	navigator.block_disc(stances["working"]["position"], 0.85)
	navigator.block_disc(stances["braced"]["position"], 0.85)

func _build_interactables() -> void:
	var tomas_interactable := Interactable.new()
	tomas_interactable.name = "Interact_tomas"
	tomas_interactable.target_id = "tomas"
	tomas_interactable.display_key = "obj.tomas"
	tomas_interactable.focus_height = 1.0
	tomas_interactable.approach_point = anchor_point("tomas_at", FALLBACK_TOMAS_AT) + Vector3(0.2, 0, 1.5)
	tomas_interactable.causal_tags = PackedStringArray(["attention", "authorship"])
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.95
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	tomas_interactable.add_child(shape)
	tomas.add_child(tomas_interactable)
	register_interactable(tomas_interactable)
	# The arch is a tall volume in the wall, so a low camera can still point at it over people's heads.
	for id: String in ["machine", "bell", "path_out"]:
		var spec := interactable_spec(id)
		add_interactable(id, "obj." + id, spec["at"], spec["radius"], spec["height"], spec["approach"], PackedStringArray(TAGS[id]))

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
