class_name PaintedWalk
extends Node

# Walking in a painted room: a tap on the painted floor sends the witch there; the raccoon keeps near her.
# PaintedRoom decides what a tap means (a prop first, then the floor, else a fallback); this node answers the
# floor. It owns the walkable floor (PaintedWalkable, from room.json) and one PaintedWalker per character.

# Her order was accepted: the tapped painting pixel and the world point she walks to.
signal walk_started(pixel: Vector2, world_position: Vector3)
# She arrived: the tapped painting pixel and where she stands (an interrupted walk never emits).
signal walked(pixel: Vector2, world_position: Vector3)

# The raccoon stays about this far (metres) behind her, comes when she is farther than FOLLOW_FAR, and gives
# her room when nearer than FOLLOW_NEAR.
const FOLLOW_DISTANCE := 1.1
const FOLLOW_FAR := 2.0
const FOLLOW_NEAR := 0.7
const FOLLOW_TICK := 0.3
const RACCOON_SPEED := 2.4

var room: PaintedRoom
var walkable: PaintedWalkable
var witch: PaintedWalker
var raccoon: PaintedWalker
var _pending_pixel := Vector2.ZERO
var _tick := 0.0

# False when the room has no walkable block (a room made before tools/painted/walkable.py).
func setup(p_room: PaintedRoom) -> bool:
	room = p_room
	walkable = PaintedWalkable.from_room(room.room)
	if walkable == null:
		set_process(false)
		return false
	witch = _walker("witch")
	raccoon = _walker("raccoon")
	if raccoon != null:
		raccoon.speed = RACCOON_SPEED
		raccoon.idle_clip = "watch" if CharacterModels.has_clip(raccoon.visual, "watch") else "idle"
	if witch != null:
		witch.walk_ended.connect(_on_witch_walk_ended)
	return witch != null

func _walker(id: String) -> PaintedWalker:
	var holder: Node3D = room.actors.get(id)
	if holder == null:
		return null
	var walker := PaintedWalker.new()
	walker.name = "%sWalker" % id.capitalize()
	add_child(walker)
	walker.setup(holder, holder.get_node_or_null("Visual") as Node3D, walkable)
	return walker

# The point of the floor a tap on painting pixel `px` means, or Vector3.INF if it is not the floor (or not
# floor she can reach).
func floor_target(px: Vector2) -> Vector3:
	if walkable == null:
		return Vector3.INF
	return walkable.floor_target(room.pixel_to_world(px))

# A tap on the floor: she walks there. False if `px` is not on the floor or there is no way.
func walk_to_pixel(px: Vector2) -> bool:
	var target := floor_target(px)
	return target != Vector3.INF and walk_to(target, px)

# She walks to a world point of the floor (the pixel it stands for rides along on the signals). False if there
# is no way there.
func walk_to(target: Vector3, px: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	if witch == null or walkable == null:
		return false
	var path := walkable.find_path(witch.body.position, target)
	if path.is_empty():
		return false
	_pending_pixel = px if px.x >= 0.0 else room.world_to_pixel(target)
	witch.walk_path(path)
	walk_started.emit(_pending_pixel, target)
	return true

func _on_witch_walk_ended(reached: bool) -> void:
	if reached:
		walked.emit(_pending_pixel, witch.body.position)

func _process(delta: float) -> void:
	step(delta)

# One tick of everyone's walking; tests call it directly to run a walk without a frame loop.
func step(delta: float) -> void:
	if witch != null:
		witch.advance(delta)
	if raccoon != null:
		_follow(delta)
		raccoon.advance(delta)

# The raccoon: trails a little behind the witch while she walks, gives her room when she comes close, and
# otherwise stands and watches her. Deterministic: it depends only on positions and the elapsed time.
func _follow(delta: float) -> void:
	_tick += delta
	var here := Vector2(witch.body.position.x, witch.body.position.z)
	var there := Vector2(raccoon.body.position.x, raccoon.body.position.z)
	if _tick >= FOLLOW_TICK:
		_tick = 0.0
		var gap := here.distance_to(there)
		if gap > FOLLOW_FAR or gap < FOLLOW_NEAR:
			var spot := _spot_behind_witch()
			if spot != Vector2.INF and spot.distance_to(Vector2(raccoon.destination().x, raccoon.destination().z)) > 0.4:
				var point := Vector3(spot.x, 0.0, spot.y)
				raccoon.walk_path(walkable.find_path(raccoon.body.position, point))
	if not raccoon.is_walking():
		raccoon.face_toward(witch.body.position)

# Where the raccoon should be: FOLLOW_DISTANCE behind her (the way she is facing), or where she is going.
func _spot_behind_witch() -> Vector2:
	var heading := Vector3(sin(witch.body.rotation.y), 0.0, cos(witch.body.rotation.y))
	var anchor := witch.destination() if witch.is_walking() else witch.body.position
	var spot := Vector2(anchor.x, anchor.z) - Vector2(heading.x, heading.z) * FOLLOW_DISTANCE
	return walkable.nearest_standable(spot.x, spot.y, 2.0)
