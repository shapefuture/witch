class_name LookAtPresenter
extends Node

# Presents Mirror's LOOK_AT reactions (rule.hall.regard: "whatever moves is looked at") as head turns. It decides
# nothing: who looks and at what come committed from the Minds layer through PropEvents.reaction_requested; this
# finds the looker on the room's stage and the thing in the room, and turns the looker's head (LookAtHead).
#
#   var gaze := LookAtPresenter.attach(bridge)   # LiveHallCoordinator does this when it attaches a room
#   add_child(gaze)
#   gaze.gaze_presented.connect(...)             # (reaction, presented): false when the room cannot show it

signal gaze_presented(reaction: Dictionary, presented: bool)

# Height of a look aimed at a character with no head bone (a placeholder), above its feet.
const PLACEHOLDER_EYE_HEIGHT := 1.0

var room: Object
# Scene id -> Mirror holder (PropEvents.actor_map: the scene's "witch" is Mirror's "player").
var actor_map: Dictionary = {"witch": "player"}
var hold_time := 1.6
var bridge: PropEvents

static func attach(to_bridge: PropEvents) -> LookAtPresenter:
	var gaze := LookAtPresenter.new()
	gaze.name = "LookAtPresenter"
	gaze.bridge = to_bridge
	gaze.room = to_bridge.room
	gaze.actor_map = to_bridge.actor_map
	to_bridge.reaction_requested.connect(gaze.present)
	return gaze

func detach() -> void:
	if bridge != null and is_instance_valid(bridge) and bridge.reaction_requested.is_connected(present):
		bridge.reaction_requested.disconnect(present)
	bridge = null
	room = null

# Plays one reaction. True when a head was turned; anything but a LOOK_AT is not this presenter's and is ignored.
func present(reaction: Dictionary) -> bool:
	if str(reaction.get("op", "")) != "LOOK_AT":
		return false
	var gaze := gaze_of(str(reaction.get("actor", "")))
	var point := target_point(str(reaction.get("target", "")))
	var shown := gaze != null and point.is_finite()
	if shown:
		gaze.look_at_point(point, hold_time)
	gaze_presented.emit(reaction, shown)
	return shown

func gaze_of(holder: String) -> LookAtHead:
	return LookAtHead.of(actor_node(holder))

# The node on stage for a Mirror holder (or a scene id), or null.
func actor_node(holder: String) -> Node3D:
	var stage := _stage()
	var scene_id := _scene_id(holder)
	var node: Variant = stage.get(scene_id, stage.get(holder))
	return node as Node3D if node is Node3D else null

# Where to look for a thing called `id`: a character's head, or the room's anchor of that name. INF if unknown.
func target_point(id: String) -> Vector3:
	var actor := actor_node(id)
	if actor != null:
		var head := LookAtHead.of(actor)
		var at := head.head_world_position() if head != null else Vector3.INF
		return at if at.is_finite() else actor.global_position + Vector3.UP * PLACEHOLDER_EYE_HEIGHT
	if room != null and room.has_method("anchor"):
		var anchor: Variant = room.call("anchor", id)
		if anchor is Vector3:
			return anchor as Vector3
	return Vector3.INF

func _scene_id(holder: String) -> String:
	for scene_id: Variant in actor_map.keys():
		if str(actor_map[scene_id]) == holder:
			return str(scene_id)
	return holder

func _stage() -> Dictionary:
	if room == null:
		return {}
	if room.has_method("stage_actors"):
		var stage: Variant = room.call("stage_actors")
		return stage as Dictionary if stage is Dictionary else {}
	var legacy: Variant = room.get("actors")
	return legacy as Dictionary if legacy is Dictionary else {}
