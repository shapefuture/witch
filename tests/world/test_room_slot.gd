extends TestCase

# The room slot (game/world/room_slot.gd): the same checks run against every room. Each room is built the way the
# game builds it (headless, in the tree), and each must provide every member the slot names and answer it sensibly.

func _first_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

func _in_tree(node: Node) -> Node:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	return track(node)

func _hall() -> ArchiveHall:
	GameFixtures.ensure_localization()
	return _in_tree(ArchiveHall.new()) as ArchiveHall

func _painted() -> PaintedRoom:
	return _in_tree((load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate()) as PaintedRoom

func _arg_count(room: Object, signal_name: String) -> int:
	for entry: Dictionary in room.get_signal_list():
		if entry["name"] == signal_name:
			return (entry["args"] as Array).size()
	return -1

# What the same checks ask of a room. `stand` is the name of a place the witch starts on, `anchors` named places,
# `blocked` a sight line through something solid, `clear` one that misses everything, `stage` the characters on
# stage and `target` a thing the room can move.
func _check_slot(room: Object, label: String, spec: Dictionary) -> void:
	eq(RoomSlot.missing(room), PackedStringArray(), "%s provides every member of the slot" % label)
	ok(RoomSlot.conforms(room), "%s conforms" % label)

	var mirror_id: String = room.call("mirror_room_id")
	var places: Dictionary = GameFixtures.runtime().minds.data["places"]
	ok(places.has(mirror_id), "%s's Mirror id (%s) is a place Mirror knows" % [label, mirror_id])

	var shots: Array = room.call("cut_shots")
	ok("wide" in shots, "%s can be cut to a wide shot" % label)
	for mode in shots:
		ok(mode in CameraDirector.MODES, "%s: %s is a camera mode" % [label, mode])

	var stand: Variant = room.call("anchor", spec["stand"])
	ok(stand is Vector3, "%s: where the witch starts is a point" % label)
	ok(room.call("is_walkable", stand), "%s: she can stand where she starts" % label)
	ok(not room.call("is_walkable", Vector3(60.0, 0.0, 60.0)), "%s: nowhere far off is walkable" % label)

	for id in spec["anchors"]:
		ok(room.call("anchor", id) is Vector3, "%s: %s is a named place" % [label, id])
	eq(room.call("anchor", "no_such_place"), null, "%s: an unknown name is no place" % label)

	var blocked: Array = spec["blocked"]
	var clear: Array = spec["clear"]
	ok(room.call("is_occluded", blocked[0], blocked[1]), "%s: a sight line through something solid is occluded" % label)
	ok(not room.call("is_occluded", clear[0], clear[1]), "%s: a sight line that misses everything is not" % label)

	var stage: Dictionary = room.call("stage_actors")
	for id in spec["stage"]:
		ok(stage.has(id) and stage[id] is Node3D, "%s: %s is on stage" % [label, id])

	eq(room.call("request_reaction", "no_such_thing", "hop"), false, "%s: it has no thing of that name to move" % label)
	ok(room.call("request_reaction", spec["target"], "hop"), "%s: it presents a reaction on %s" % [label, spec["target"]])

	eq(_arg_count(room, "walked"), 2, "%s: walked(pixel, world_position)" % label)
	eq(_arg_count(room, "prop_pressed"), 3, "%s: prop_pressed(prop_id, reaction, world_position)" % label)

func test_both_rooms_provide_every_member_of_the_slot_and_answer_the_same_questions() -> void:
	await _first_frame()
	_check_slot(_hall(), "the archive hall", {
		"stand": "spawn",
		"anchors": ["spawn", "tomas", "raccoon", "bell", "machine", "path_out"],
		"blocked": [Vector3(0.2, 0.5, -6.0), Vector3(0.2, 0.5, 2.0)],
		"clear": [Vector3(5.0, 0.5, 5.0), Vector3(6.0, 0.5, 6.0)],
		"stage": ["tomas", "raccoon"],
		"target": "bell",
	})
	_check_slot(_painted(), "the painted room", {
		"stand": "witch",
		"anchors": ["witch", "raccoon", "globe", "statue", "lamp"],
		"blocked": [Vector3(2.081, 1.3, -10.0), Vector3(2.081, 1.3, -4.0)],
		"clear": [Vector3(-10.0, 1.3, 5.0), Vector3(-9.0, 1.3, 5.0)],
		"stage": ["witch", "raccoon"],
		"target": "globe",
	})

func test_a_node_that_is_not_a_room_provides_none_of_it() -> void:
	var stranger: Node = track(Node.new())
	eq(RoomSlot.missing(stranger).size(), RoomSlot.SIGNALS.size() + RoomSlot.METHODS.size(), "a plain node lacks every member")
	ok(not RoomSlot.conforms(stranger), "and does not conform")
	ok(not RoomSlot.conforms(null), "and nothing does not conform either")

func test_the_hall_reports_an_arrival_as_a_walk_with_no_painting_pixel() -> void:
	await _first_frame()
	var hall := _hall()
	var got: Array = []
	hall.walked.connect(func(pixel: Vector2, world: Vector3) -> void: got.append([pixel, world]))
	hall.arrived(Vector3(1.0, 0.0, 1.0))
	eq(got, [[Vector2(-1.0, -1.0), Vector3(1.0, 0.0, 1.0)]], "walked(-1, -1, where she stopped): a room with no painting has no pixel")

func test_a_sight_line_is_occluded_only_where_it_passes_inside_the_solid_below_its_top() -> void:
	var centre := Vector2(0.0, 0.0)
	ok(RoomSlot.segment_hits_cylinder(Vector3(-3.0, 0.5, 0.0), Vector3(3.0, 0.5, 0.0), centre, 1.0, 1.5), "through it, below its top")
	ok(not RoomSlot.segment_hits_cylinder(Vector3(-3.0, 2.0, 0.0), Vector3(3.0, 2.0, 0.0), centre, 1.0, 1.5), "over its top")
	ok(not RoomSlot.segment_hits_cylinder(Vector3(-3.0, 0.5, 1.2), Vector3(3.0, 0.5, 1.2), centre, 1.0, 1.5), "beside it")
	ok(not RoomSlot.segment_hits_cylinder(Vector3(-3.0, 0.5, 0.0), Vector3(-2.0, 0.5, 0.0), centre, 1.0, 1.5), "short of it")
	ok(RoomSlot.segment_hits_cylinder(Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.5, 0.0), centre, 1.0, 1.5), "a point inside it is hidden at that height")
	ok(not RoomSlot.segment_hits_cylinder(Vector3(-3.0, 0.5, 0.0), Vector3(3.0, 2.5, 0.0), centre, 1.0, 1.5), "a sight line exactly at its top where it passes is not")
