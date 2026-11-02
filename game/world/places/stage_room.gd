class_name StageRoom
extends PlaceRoom

# A stand-in for a place whose picture is not made yet: a plain 3D set in the place's palette, so every place is
# playable before its art exists (GAME_SPEC section 4). The plate's frame maps onto the stage's floor, so a pixel in
# the place file means the same spot on the stand-in as on the painting. Each hotspot is a box named after its target.

const STAGE_W := 10.0
const STAGE_D := 6.0
const WALK_INSET := 0.4
const WALL_HEIGHT := 4.0
const PROP_SIZE := Vector3(0.7, 0.9, 0.7)
const PROP_BLOCK := 0.3
const DEFAULT_PALETTE := [Color(0.25, 0.22, 0.30), Color(0.36, 0.28, 0.42), Color(0.42, 0.50, 0.30), Color(0.72, 0.56, 0.28), Color(0.08, 0.06, 0.10)]

var _dressed: Dictionary = {}

func _ready() -> void:
	camera_focus = Vector3(0.0, 0.6, 0.2)
	camera_distance = 10.5
	camera_pitch_deg = 22.0
	camera_yaw_deg = 0.0
	camera_fov = 44.0
	camera_roll_deg = 0.0
	var colours := colours_of(place)
	navigator = GridNavigator.new(Rect2(-6.0, -4.0, 12.0, 8.0))
	var half := Vector2(STAGE_W * 0.5 - WALK_INSET, STAGE_D * 0.5 - WALK_INSET)
	navigator.block_where(func(p: Vector2) -> bool: return absf(p.x) > half.x or absf(p.y) > half.y)
	spawn_position = spot_point("default")
	_build_set(colours)
	build_ground_pick()

# The five colours of a place's stand-in: floor, back wall, side walls, props, the dark behind the set.
static func colours_of(data: PlaceData) -> Array[Color]:
	var out: Array[Color] = []
	for i in range(DEFAULT_PALETTE.size()):
		var colour: Color = DEFAULT_PALETTE[i]
		if data != null and i < data.palette.size():
			colour = data.palette[i]
		out.append(colour)
	return out

func pixel_to_floor(px: Vector2) -> Vector3:
	return Vector3((px.x / PlaceData.PLATE.x - 0.5) * STAGE_W, 0.0, (px.y / PlaceData.PLATE.y - 0.5) * STAGE_D)

# Hotspots are boxes on the floor, and each one is a small obstacle the witch walks around.
func add_hotspots(specs: Array) -> int:
	var added := super.add_hotspots(specs)
	for target in interactables.keys():
		if not _dressed.has(target):
			_dress(interactables[target] as Interactable)
	return added

func _dress(interactable: Interactable) -> void:
	var target := interactable.target_id
	_dressed[target] = true
	var at := interactable.position
	var prop := Placeholders.box(PROP_SIZE, colours_of(place)[3], Vector3(at.x, PROP_SIZE.y * 0.5, at.z))
	prop.name = "Hotspot_" + target
	add_child(prop)
	pokeable[target] = prop
	add_obstacle(Vector3(at.x, 0.0, at.z), PROP_BLOCK, PROP_SIZE.y)

func _build_set(colours: Array[Color]) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = colours[4]
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	_add_box("Floor", Vector3(STAGE_W, 0.1, STAGE_D), colours[0], Vector3(0.0, -0.05, 0.0))
	_add_box("Back", Vector3(STAGE_W + 0.6, WALL_HEIGHT, 0.3), colours[1], Vector3(0.0, WALL_HEIGHT * 0.5, -STAGE_D * 0.5 - 0.3))
	_add_box("WallLeft", Vector3(0.3, WALL_HEIGHT, STAGE_D), colours[2], Vector3(-STAGE_W * 0.5 - 0.15, WALL_HEIGHT * 0.5, 0.0))
	_add_box("WallRight", Vector3(0.3, WALL_HEIGHT, STAGE_D), colours[2], Vector3(STAGE_W * 0.5 + 0.15, WALL_HEIGHT * 0.5, 0.0))

func _add_box(node_name: String, size: Vector3, colour: Color, at: Vector3) -> void:
	var box := Placeholders.box(size, colour, at)
	box.name = node_name
	add_child(box)
