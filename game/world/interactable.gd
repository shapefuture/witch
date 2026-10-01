class_name Interactable
extends Area3D

# Something the player can point at. It carries NO game meaning: `target_id` is just the id
# Mirror's catalog uses for this thing. What can be done to it is decided by Mirror.

@export var target_id := ""
# Text-table key for what the thing is called ("obj.tomas").
@export var display_key := ""
# Free-form causal tags (wind, sound, attention, authorship, ...) for the debug overlay.
@export var causal_tags: PackedStringArray = PackedStringArray()
@export var focus_height := 1.0
# Where the witch stands to interact. World space; set by the room that owns the object.
@export var approach_point := Vector3.ZERO

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = PhysicsLayers.INTERACTABLE
	collision_mask = 0
	monitoring = false

func focus_point() -> Vector3:
	return global_position + Vector3.UP * focus_height

func display_name() -> String:
	return tr(display_key) if not display_key.is_empty() else target_id
