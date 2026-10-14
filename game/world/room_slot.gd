class_name RoomSlot
extends RefCounted

# The contract every room provides to the rest of the game (ArchiveHall, PaintedRoom, and any room after them).
#
# A room owns its look, its geometry and its props. It owns no game meaning: Mirror decides, and the room answers
# queries and presents what it is asked to. Rooms cannot share a base class (ArchiveHall extends Room, PaintedRoom
# extends Node3D), so the slot is a set of members that each room implements as thin adapters over its own code.
# missing() names the members a room lacks; tests/world/test_room_slot.gd runs the same checks against every room.
#
# Signals a room declares:
#   walked(pixel: Vector2, world_position: Vector3)
#       The witch arrived on the floor. `pixel` is the painting pixel she was sent to, Vector2(-1, -1) in a room
#       without a painting. PropEvents turns it into a WALKED happening.
#   prop_pressed(prop_id: String, reaction: String, world_position: Vector3)
#       The witch poked a prop, and the move it made. PropEvents turns it into a PROP_POKED happening.
#
# Methods a room declares:
#   mirror_room_id() -> String
#       The room's key in Mirror's world (a place in data/mirror/minds). Ids are data; the look of a room is not.
#   is_walkable(point: Vector3) -> bool
#       Whether the witch may stand at `point` (world space).
#   is_occluded(from: Vector3, to: Vector3) -> bool
#       Whether something solid in the room hides `to` from `from`.
#   anchor(id: String) -> Variant
#       A named place in the room, in world space, or null when the room has no place by that name.
#   stage_actors() -> Dictionary
#       {scene id: Node3D} for the characters on stage. PropEvents reads it for the perception hints.
#   request_reaction(target_id: String, reaction: String) -> bool
#       Presents a reaction on one of the room's own things. False when the room has no such thing.
#   cut_shots() -> Array[String]
#       The CameraDirector modes this room can be cut to. "wide" is always among them.

const SIGNALS := ["walked", "prop_pressed"]
const METHODS := ["mirror_room_id", "is_walkable", "is_occluded", "anchor", "stage_actors", "request_reaction", "cut_shots"]

# The members a room lacks (empty when it conforms).
static func missing(room: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for signal_name: String in SIGNALS:
		if room == null or not room.has_signal(signal_name):
			out.append(signal_name)
	for method_name: String in METHODS:
		if room == null or not room.has_method(method_name):
			out.append(method_name)
	return out

static func conforms(room: Object) -> bool:
	return room != null and missing(room).is_empty()

# The geometry of is_occluded: does the segment from -> to pass through a vertical cylinder (centre `center` in x/z,
# radius `radius`, top at `height`) at a point where the sight line is below its top?
static func segment_hits_cylinder(from: Vector3, to: Vector3, center: Vector2, radius: float, height: float) -> bool:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var closest := Geometry2D.get_closest_point_to_segment(center, a, b)
	if closest.distance_to(center) >= radius:
		return false
	var length := a.distance_to(b)
	var t := a.distance_to(closest) / length if length > 0.0001 else 0.0
	return lerpf(from.y, to.y, t) < height
