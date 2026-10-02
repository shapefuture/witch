extends TestCase

# game/world/painted: walking on the painted floor (PaintedWalkable, PaintedWalker, PaintedWalk) and the order a
# tap is understood in (a prop, then the floor, then a fallback). Headless; pixels are in painted_walk_render.gd.

const STATUE_AT := Vector2(2.081, -7.199)
const BEHIND_STATUE := Vector3(2.1, 0.0, -8.6)
const FRAME := 1.0 / 30.0

func _room() -> PaintedRoom:
	# A frame first: a node added to the root inside the very first tick of the runner is not in the tree yet.
	await (Engine.get_main_loop() as SceneTree).process_frame
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	(Engine.get_main_loop() as SceneTree).root.add_child(room)
	room.walk.set_process(false)
	return room

# Runs the walk with a fixed tick, so a test is the same on every machine. Returns the seconds it took.
func _finish_walk(room: PaintedRoom, limit: float = 30.0) -> float:
	var t := 0.0
	while room.walk.witch.is_walking() and t < limit:
		room.walk.step(FRAME)
		t += FRAME
	return t

func _feet(room: PaintedRoom) -> Vector3:
	return (room.actors["witch"] as Node3D).position - Vector3(0.0, PaintedWalker.FOOT_LIFT, 0.0)

func test_the_floor_is_derived_from_the_depth_and_holds_the_actors() -> void:
	var room := await _room()
	var w := room.walk.walkable
	ok(w != null and w.standable_count() > 400, "a walkable floor of some size (%d cells)" % (w.standable_count() if w != null else 0))
	for id in ["witch", "raccoon"]:
		var p: Array = room.room["actors"][id]["position"]
		ok(w.is_standable(float(p[0]), float(p[2])), "%s starts on standable floor" % id)
	ok(not w.is_floor(STATUE_AT.x, STATUE_AT.y), "the statue's own footprint is not floor")
	ok(not w.is_standable(STATUE_AT.x, STATUE_AT.y + 0.6), "and she keeps her body's width away from it")
	ok(w.is_standable(BEHIND_STATUE.x, BEHIND_STATUE.z), "there is floor behind the statue, on the dais")
	var dais := w.height_at(BEHIND_STATUE.x, BEHIND_STATUE.z)
	ok(dais > 0.1 and dais < 0.4, "the dais is a step up (%.2f m)" % dais)
	ok(absf(w.height_at(0.75, -5.76)) < 0.08, "the carpet is at the floor plane")
	ok(not w.is_floor(0.0, -2.0), "the strip nearest the camera, outside the frame, is not floor")
	room.queue_free()

func test_a_path_goes_around_the_statue_and_stays_on_the_floor() -> void:
	var room := await _room()
	var w := room.walk.walkable
	var from := Vector3(0.754, 0.0, -5.761)
	var path := w.find_path(from, Vector3(BEHIND_STATUE.x, w.height_at(BEHIND_STATUE.x, BEHIND_STATUE.z), BEHIND_STATUE.z))
	ok(path.size() >= 2, "a path exists (%d points)" % path.size())
	var length := 0.0
	var nearest := 100.0
	var previous := from
	for p in path:
		length += Vector2(p.x - previous.x, p.z - previous.z).length()
		previous = p
	for i in path.size() - 1:
		var steps := 40
		for s in steps + 1:
			var at := path[i].lerp(path[i + 1], float(s) / steps)
			ok(w.is_floor(at.x, at.z), "every step of the path is floor (%.2f, %.2f)" % [at.x, at.z])
			nearest = minf(nearest, Vector2(at.x, at.z).distance_to(STATUE_AT))
	ok(nearest > 0.6, "she gives the statue room (%.2f m)" % nearest)
	ok(length > Vector2(BEHIND_STATUE.x - from.x, BEHIND_STATUE.z - from.z).length(), "and goes round it, not through it")
	eq(Vector2(path[path.size() - 1].x, path[path.size() - 1].z), Vector2(BEHIND_STATUE.x, BEHIND_STATUE.z), "to exactly where she was sent")
	room.queue_free()

func test_a_tap_goes_to_a_prop_then_the_floor_then_the_fallback() -> void:
	var room := await _room()
	var walked_to: Array = []
	room.walked.connect(func(pixel: Vector2, _at: Vector3) -> void: walked_to.append(pixel))
	var pressed: Array = []
	room.prop_pressed.connect(func(id: String, _reaction: String, _at: Vector3) -> void: pressed.append(id))
	eq(room.tap(Vector2(845, 450)), "prop", "the statue answers a tap on it")
	ok(not room.walk.witch.is_walking(), "and she does not walk to it")
	eq(pressed, ["statue"], "prop_pressed still fires")
	eq(room.tap(Vector2(640, 660)), "walk", "the carpet is a walk")
	ok(room.walk.witch.is_walking(), "she is walking")
	eq(room.tap(Vector2(640, 40)), "fallback", "the ceiling is neither")
	eq(room.tap(Vector2(660, 500)), "fallback", "nor is the foot of the shelf")
	eq(room.tap(Vector2(1150, 620)), "fallback", "nor is the rock in the right foreground")
	_finish_walk(room)
	eq(walked_to, [Vector2(640, 660)], "walked fires once, on arrival, with the tapped pixel")
	room.queue_free()

func test_she_walks_to_the_tapped_pixel_on_the_painted_floor() -> void:
	var room := await _room()
	var witch := room.walk.witch
	var tapped := Vector2(430, 660)
	eq(room.tap(tapped), "walk", "tap")
	var player := CharacterModels.player_of(witch.visual)
	var seen_walk := false
	var worst := 0.0
	var started_yaw := (room.actors["witch"] as Node3D).rotation.y
	var heading := started_yaw
	var t := 0.0
	while witch.is_walking() and t < 20.0:
		var before := (room.actors["witch"] as Node3D).position
		room.walk.step(FRAME)
		var after := (room.actors["witch"] as Node3D).position
		if Vector2(after.x - before.x, after.z - before.z).length() > 0.005:
			heading = atan2(after.x - before.x, after.z - before.z)
		t += FRAME
		seen_walk = seen_walk or player.current_animation == "walk"
		# Every step she is on the painted surface: the mesh under her feet's pixel is at her feet's height.
		var feet := _feet(room)
		var surface := room.pixel_to_world(room.world_to_pixel(feet))
		worst = maxf(worst, absf(surface.y - feet.y))
	ok(t < 20.0, "she arrives (%.1f s)" % t)
	ok(seen_walk, "with the walk clip playing")
	eq(str(player.current_animation), "idle", "and the idle clip once there")
	ok(worst < 0.08, "she keeps to the painted floor all the way (worst %.3f m off the surface)" % worst)
	var landed := room.world_to_pixel(_feet(room))
	ok(landed.distance_to(tapped) < 2.0, "her feet land on the tapped pixel (%s vs %s)" % [landed, tapped])
	var yaw := (room.actors["witch"] as Node3D).rotation.y
	ok(absf(angle_difference(yaw, started_yaw)) > 0.5 and absf(angle_difference(yaw, heading)) < 0.35, "she turned to face where she went")
	room.queue_free()

func test_a_newer_tap_replaces_the_walk() -> void:
	var room := await _room()
	var walked_to: Array = []
	room.walked.connect(func(pixel: Vector2, _at: Vector3) -> void: walked_to.append(pixel))
	room.tap(Vector2(300, 650))
	for i in 10:
		room.walk.step(FRAME)
	room.tap(Vector2(900, 680))
	_finish_walk(room)
	eq(walked_to, [Vector2(900, 680)], "only the last order arrives")
	room.queue_free()

func test_mouse_and_touch_taps_are_the_same_intent() -> void:
	var room := await _room()
	var screen := room.camera.unproject_position(room.pixel_to_world(Vector2(640, 660)))
	ok(room.screen_to_pixel(screen).distance_to(Vector2(640, 660)) < 1.0, "screen -> painting pixel round-trips")
	var now := 0.0
	room.input.clock = func() -> float: return now
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT
	mouse_down.position = screen
	mouse_down.pressed = true
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.position = screen
	mouse_up.pressed = false
	eq(room.input.handle_event(mouse_down), null, "a mouse press is not yet a tap")
	now = 0.1
	var from_mouse := room.input.handle_event(mouse_up)
	ok(from_mouse != null and from_mouse.type == PlayerIntent.Type.MOVE_TO, "a mouse click on the floor is a move")
	ok(room.walk.witch.is_walking(), "and she walks")
	room.walk.witch.stop()
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 0
	touch_down.position = screen
	touch_down.pressed = true
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 0
	touch_up.position = screen
	touch_up.pressed = false
	now = 1.0
	room.input.handle_event(touch_down)
	now = 1.1
	var from_touch := room.input.handle_event(touch_up)
	ok(from_touch != null and from_touch.same_meaning(from_mouse), "a touch is the same intent as the click")
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.position = screen
	emulated.pressed = false
	eq(room.input.handle_event(emulated), null, "the mouse event a touch also sends is ignored")
	var statue_screen := room.camera.unproject_position(room.pixel_to_world(Vector2(845, 450)))
	now = 2.0
	touch_down.position = statue_screen
	touch_up.position = statue_screen
	room.input.handle_event(touch_down)
	now = 2.1
	var on_prop := room.input.handle_event(touch_up)
	ok(on_prop != null and on_prop.type == PlayerIntent.Type.INSPECT and on_prop.target_id == "statue", "a touch on the statue is an inspect of it")
	room.queue_free()

func test_the_raccoon_trails_her_and_watches_deterministically() -> void:
	var finals: Array[Vector3] = []
	for run in 2:
		var room := await _room()
		var w := room.walk.walkable
		var far := Vector3(-2.5, w.height_at(-2.5, -9.0), -9.0)
		ok(room.walk.walk_to(far), "she is sent to the far left")
		var seen_moving := false
		for i in int(14.0 / FRAME):
			room.walk.step(FRAME)
			seen_moving = seen_moving or room.walk.raccoon.is_walking()
		var witch_at := (room.actors["witch"] as Node3D).position
		var raccoon_at := (room.actors["raccoon"] as Node3D).position
		var gap := Vector2(witch_at.x - raccoon_at.x, witch_at.z - raccoon_at.z).length()
		ok(seen_moving, "the raccoon walked")
		ok(gap > PaintedWalk.FOLLOW_NEAR - 0.05 and gap < PaintedWalk.FOLLOW_FAR + 0.05, "and is near her, not on her (%.2f m)" % gap)
		ok(w.is_floor(raccoon_at.x, raccoon_at.z), "on the floor")
		ok(not room.walk.raccoon.is_walking(), "standing")
		eq(str(CharacterModels.player_of(room.walk.raccoon.visual).current_animation), "watch", "and watching her")
		var facing := Vector2(sin((room.actors["raccoon"] as Node3D).rotation.y), cos((room.actors["raccoon"] as Node3D).rotation.y))
		var toward := Vector2(witch_at.x - raccoon_at.x, witch_at.z - raccoon_at.z).normalized()
		ok(facing.dot(toward) > 0.95, "turned toward her (%.2f)" % facing.dot(toward))
		finals.append(raccoon_at)
		room.queue_free()
	eq(finals[0], finals[1], "the same walk gives the same raccoon")

func test_a_room_made_before_the_walkable_block_still_loads() -> void:
	ok(PaintedWalkable.from_room({}) == null, "no block, no walkable floor")
	ok(PaintedWalkable.from_room({"walkable": {"cell": 0.25, "origin": [0, 0], "size": [1, 1], "rows": ["#"], "heights_cm": [0]}}) != null, "a block loads")
	var walk := PaintedWalk.new()
	eq(walk.floor_target(Vector2(640, 600)), Vector3.INF, "without a floor nothing is a floor tap")
	ok(not walk.walk_to(Vector3.ZERO), "and there is nowhere to walk")
	walk.free()
