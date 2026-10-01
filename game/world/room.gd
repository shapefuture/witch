class_name Room
extends Node3D

# A playable space. It owns its interactables, its walkable area and its spawn point; it owns
# no game meaning (that is Mirror's).

@export var room_id := ""

var interactables: Dictionary = {}
var navigator: GridNavigator
var spawn_position := Vector3.ZERO
# Default framing for the camera director when nothing is being composed.
var camera_focus := Vector3.ZERO
var camera_distance := 11.5
var camera_pitch_deg := 32.0
var camera_yaw_deg := 0.0
var camera_fov := 40.0
var camera_roll_deg := 0.0

func register_interactable(interactable: Interactable) -> void:
	interactables[interactable.target_id] = interactable

func get_interactable(target_id: String) -> Interactable:
	return interactables.get(target_id)

func framing() -> Dictionary:
	return {"focus": camera_focus, "distance": camera_distance, "pitch_deg": camera_pitch_deg, "yaw_deg": camera_yaw_deg, "fov": camera_fov, "roll_deg": camera_roll_deg}

# What the picture is about: world-space cylinders {"at", "radius", "height"} that a speech bubble
# should not cover (the light pool, the way out, a statue). Rooms override this.
func hero_regions() -> Array:
	return []

# Adds a solid obstacle: a blocking body for physics and a blocked disc for walk planning.
func add_obstacle(at: Vector3, radius: float, height: float = 1.5) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position = Vector3(0, height * 0.5, 0)
	body.add_child(shape)
	body.position = at
	add_child(body)
	if navigator != null:
		navigator.block_disc(at, radius + 0.35)
	return body

func add_interactable(target: String, display_key: String, at: Vector3, radius: float, focus_height: float, approach: Vector3, tags: PackedStringArray = PackedStringArray()) -> Interactable:
	var interactable := Interactable.new()
	interactable.name = "Interact_" + target
	interactable.target_id = target
	interactable.display_key = display_key
	interactable.focus_height = focus_height
	interactable.approach_point = approach
	interactable.causal_tags = tags
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position = Vector3(0, focus_height, 0)
	interactable.add_child(shape)
	interactable.position = at
	add_child(interactable)
	register_interactable(interactable)
	return interactable
