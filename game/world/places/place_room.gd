class_name PlaceRoom
extends Room

# A room that a place is played in. It is a Room (interactables, walk grid, framing) that also answers the room slot
# (game/world/room_slot.gd) for every kind of room: the archive hall, a painted room and a stand-in stage. The defaults
# here are the stand-in answers; a kind overrides what it has, with the same signatures.
#
# Hotspots are Interactables. A room offers one only while Mirror offers an action on it (GameRoot decides, through
# set_offered). Pixel points come from the place file (1280x720 plate); pixel_to_floor turns them into the floor.

signal walked(pixel: Vector2, world_position: Vector3)
signal prop_pressed(prop_id: String, reaction: String, world_position: Vector3)

const GROUND_RADIUS := 12.0
const POKE_HOP_HEIGHT := 0.12
const POKE_HOP_SECONDS := 0.5
# Where a stand-in tries a spot off the floor (metres) before it gives up and keeps the point as it is.
const NEAREST_STEP := 0.25
const NEAREST_REACH := 3.0

# The place this room was built for (null for a room built without one, such as the legacy hall in a test).
var place: PlaceData
# Person id -> node, for the people this room placed (the hall and painted rooms have their own; see npc_node).
var npcs: Dictionary = {}
# Prop id -> node the room hops when poked (a stand-in's objects; the hall and painted rooms have their own).
var pokeable: Dictionary = {}

static func set_offered(interactable: Interactable, on: bool) -> void:
	if interactable != null:
		interactable.collision_layer = PhysicsLayers.INTERACTABLE if on else 0

# ---- the room slot ----------------------------------------------------------------------------------------------

func mirror_room_id() -> String:
	return room_id

func is_walkable(point: Vector3) -> bool:
	return navigator != null and not navigator.is_blocked(point)

func is_occluded(_from: Vector3, _to: Vector3) -> bool:
	return false

func anchor(id: String) -> Variant:
	var interactable := get_interactable(id)
	return interactable.global_position if interactable != null else null

func stage_actors() -> Dictionary:
	return npcs.duplicate()

func request_reaction(target_id: String, _reaction: String) -> bool:
	var node: Node3D = pokeable.get(target_id)
	if node == null:
		return false
	_hop(node)
	return true

func cut_shots() -> Array[String]:
	var out: Array[String] = ["wide"]
	return out

# ---- the framing and shots the director asks for --------------------------------------------------------------

# A plate's exact pose for a shot ({} when the room has none: the director computes one).
func shot_pose(_mode: String, _focus_ids: Array, _roll_deg: float) -> Dictionary:
	return {}

func focus_node(_target_id: String) -> Node3D:
	return null

func focus_position(target_id: String) -> Variant:
	var interactable := get_interactable(target_id)
	return interactable.focus_point() if interactable != null else null

# Where the witch walks to leave the picture: off the frame, toward the camera by default.
func exit_point() -> Vector3:
	return Vector3(0.0, 0.0, 6.0)

# Makes the room look like a Mirror state (the hall reads its machine and Tomas; the others have nothing to show yet).
func apply_mirror_state(_engine: MirrorEngine) -> void:
	pass

# ---- people ---------------------------------------------------------------------------------------------------

func npc_node(id: String) -> Node3D:
	var node: Variant = npcs.get(id)
	return node as Node3D

func show_npc(id: String, on: bool) -> void:
	var node := npc_node(id)
	if node != null:
		node.visible = on

# Puts a person into the room at a world point (the presence sync does this when a person comes in).
func place_npc(id: String, node: Node3D, at: Vector3) -> void:
	node.name = "Npc_" + id
	add_child(node)
	node.position = at
	npcs[id] = node

# Where a person stands in this room, from the place file ("default" when they have no spot of their own).
func spot_point(npc_id: String) -> Vector3:
	if place == null:
		return spawn_position
	var at := pixel_to_floor(place.spot_for(npc_id))
	return at if at.is_finite() else spawn_position

# Where she appears coming from `from` (a place id): the place's arrival, else the hall's spawn.
func arrival_point(from: String) -> Vector3:
	if place != null and (place.has_arrival(from) or place.spots.has("default")):
		var px := place.arrival_for(from)
		var at := pixel_to_floor(px)
		if at.is_finite():
			return _standable_for(at, px)
	return spawn_position

# The floor point under a pixel of the place's plate. Rooms without a plate answer Vector3.INF.
func pixel_to_floor(_px: Vector2) -> Vector3:
	return Vector3.INF

# The standable floor nearest a pixel as it shows on screen (painted rooms). Rooms without a plate answer Vector3.INF.
func standable_near_pixel(_px: Vector2) -> Vector3:
	return Vector3.INF

# Where she stands for something at `at` (the floor point of plate pixel `px`): a walkable point near it, else the floor
# nearest the pixel on screen, else `at` itself.
func _standable_for(at: Vector3, px: Vector2) -> Vector3:
	var near := walkable_near(at)
	if is_walkable(near):
		return near
	var shown := standable_near_pixel(px)
	return shown if shown.is_finite() else near

# A walkable point at or near `at` (the place file may put a point just off the floor).
func walkable_near(at: Vector3) -> Vector3:
	if is_walkable(at):
		return at
	var steps := int(NEAREST_REACH / NEAREST_STEP)
	for ring in range(1, steps + 1):
		var reach := ring * NEAREST_STEP
		for k in range(8):
			var angle := TAU * k / 8.0
			var candidate := at + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
			if is_walkable(candidate):
				return candidate
	return at

# ---- hotspots -------------------------------------------------------------------------------------------------

# Adds the place's hotspots as Interactables (hidden until GameRoot offers them). A spec with an anchor takes the
# anchor's place; an anchor that is itself an interactable of this room (the hall's path_out) is shared, so the same
# spot answers to another target id too. Returns how many were added.
func add_hotspots(specs: Array) -> int:
	var added := 0
	for spec: Variant in specs:
		var entry: Dictionary = spec
		var target := str(entry.get("target", ""))
		if target.is_empty() or get_interactable(target) != null:
			continue
		var at := Vector3.INF
		var approach := Vector3.INF
		var px := Vector2(-1.0, -1.0)
		var anchor_name := str(entry.get("anchor", ""))
		if not anchor_name.is_empty():
			var source := get_interactable(anchor_name)
			var anchored: Variant = anchor(anchor_name)
			if anchored is Vector3:
				at = anchored
			if source != null:
				approach = source.approach_point
		elif entry.has("at"):
			px = entry["at"]
			at = pixel_to_floor(px)
		if not at.is_finite():
			push_warning("PlaceRoom %s: hotspot %s has no place in this room" % [room_id, target])
			continue
		if not approach.is_finite():
			approach = _approach_for(at)
			if not is_walkable(approach) and px.x >= 0.0:
				# A thing on the wall, or far off: she walks to the floor the picture shows nearest it.
				var shown := standable_near_pixel(px)
				if shown.is_finite():
					approach = shown
		add_interactable(target, "obj." + target, at, 0.6, 0.9, approach, PackedStringArray())
		added += 1
	return added

func _approach_for(at: Vector3) -> Vector3:
	var offsets: Array[Vector3] = [Vector3(0, 0, 0.9), Vector3(0, 0, -0.9), Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0), Vector3(0.9, 0, 0.9), Vector3(-0.9, 0, 0.9), Vector3(0.9, 0, -0.9), Vector3(-0.9, 0, -0.9)]
	for offset in offsets:
		if is_walkable(at + offset):
			return at + offset
	return walkable_near(at)

# The floor as a picking surface only (the witch has no gravity and does not stand on it).
func build_ground_pick() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundPick"
	floor_body.collision_layer = PhysicsLayers.GROUND
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = GROUND_RADIUS
	cylinder.height = 0.2
	shape.shape = cylinder
	shape.position = Vector3(0, -0.1, 0)
	floor_body.add_child(shape)
	add_child(floor_body)

func _hop(node: Node3D) -> void:
	var rest := node.position
	var tween := create_tween()
	tween.tween_property(node, "position", rest + Vector3(0.0, POKE_HOP_HEIGHT, 0.0), POKE_HOP_SECONDS * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position", rest, POKE_HOP_SECONDS * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
