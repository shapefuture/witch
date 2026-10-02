extends TestCase

# game/world/painted: a painted still as a room, with props that answer a tap.

# A frame has to pass before a node added to the root counts as inside the tree (the first test of a run).
func _first_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

func _room() -> PaintedRoom:
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	(Engine.get_main_loop() as SceneTree).root.add_child(room)
	return room

func test_the_room_loads_its_camera_depth_actors_and_props() -> void:
	await _first_frame()
	var room := _room()
	ok(room.camera != null, "the painting's camera exists")
	ok(room.actors.has("witch") and room.actors.has("raccoon"), "the witch and the raccoon stand in it")
	eq(room.props.size(), 14, "the toy box: globe, statue and twelve more")
	var px := Vector2(640, 500)
	var back := room.world_to_pixel(room.pixel_to_world(px))
	ok(back.distance_to(px) < 0.5, "pixel -> world -> pixel round-trips (%s)" % back)
	var feet := room.world_to_pixel(room.actors["witch"].position)
	ok(feet.distance_to(Vector2(735, 634)) < 1.0, "the witch's feet are where the painting had them (%s)" % feet)
	room.queue_free()

func test_a_tap_finds_the_nearest_prop_and_walks_its_reactions() -> void:
	await _first_frame()
	var room := _room()
	eq(room.press(Vector2(90, 400)), "globe", "a tap on the globe pokes the globe")
	eq(room.press(Vector2(845, 450)), "statue", "a tap on the statue pokes the statue")
	eq(room.press(Vector2(640, 40)), "", "a tap on bare painting pokes nothing")
	var globe: PaintedProp = room.props.filter(func(p: PaintedProp) -> bool: return p.prop_id == "globe")[0]
	eq(globe.react("press"), "hop", "the second poke answers differently")
	room.queue_free()
