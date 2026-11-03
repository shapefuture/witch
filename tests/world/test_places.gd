extends TestCase

# Every place of GAME_SPEC section 2 loads, builds a room that answers the room slot (a stand-in where its picture
# is not made yet), and takes its hotspots. Painted places use their picture; the rest use the stand-in.

const PLACES := ["shop", "window", "garden", "street", "clearing", "observatory", "attic", "fog_edge", "basement", "hotel", "clocktower", "garden_below", "threshold"]

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# Builds a place's room, puts it in the tree for a frame, dresses it, and hands it back (the caller frees it).
func _built(place: PlaceData) -> PlaceRoom:
	var room := RoomFactory.build(place)
	_tree().root.add_child(room)
	RoomFactory.dress(room, place)
	return room

func _release(room: Node) -> void:
	if room.get_parent() != null:
		room.get_parent().remove_child(room)
	room.free()

func test_the_thirteen_place_files_load_with_no_problems() -> void:
	var loaded := PlaceCatalog.load_all()
	eq(loaded["errors"], PackedStringArray(), "every place file is valid")
	var ids: Array = (loaded["places"] as Dictionary).keys()
	ids.sort()
	var expected: Array = PLACES.duplicate()
	expected.sort()
	eq(ids, expected, "exactly the thirteen places of GAME_SPEC section 2")

func test_a_place_file_with_a_bad_kind_or_no_palette_is_refused() -> void:
	var bad := PlaceData.from_dict({"id": "nowhere", "room": {"kind": "castle"}})
	ok(not bad.problems().is_empty(), "an unknown kind is reported")
	var stage := PlaceData.from_dict({"id": "nowhere", "room": {"kind": "stage"}})
	ok(not stage.problems().is_empty(), "a stage with no palette is reported")
	var painted := PlaceData.from_dict({"id": "Nowhere", "room": {"kind": "painted"}})
	ok(painted.problems().size() >= 2, "a capital id and a painted place with no dir are both reported")

func test_every_place_builds_a_room_that_conforms_to_the_room_slot() -> void:
	for id in PLACES:
		var place := PlaceCatalog.load_place(id)
		ok(place != null, "%s loads" % id)
		if place == null:
			continue
		var room := _built(place)
		await _tree().process_frame
		eq(RoomSlot.missing(room), PackedStringArray(), "%s conforms to the room slot" % id)
		eq(room.mirror_room_id(), id, "%s is Mirror's room of its own id" % id)
		_release(room)
		await _tree().process_frame

func test_painted_places_use_their_picture_and_the_rest_the_stand_in() -> void:
	var painted := _built(PlaceCatalog.load_place("garden"))
	ok(painted is PaintedRoom, "garden has a room.json, so it is the painted room")
	_release(painted)
	var hall := _built(PlaceCatalog.load_place("clearing"))
	ok(hall is ArchiveHall, "clearing is the archive hall")
	_release(hall)
	var attic := _built(PlaceCatalog.load_place("attic"))
	ok(attic is StageRoom, "attic has no picture yet, so it is the stand-in stage")
	_release(attic)
	await _tree().process_frame

func test_the_hotspot_files_merge_with_no_errors_and_the_core_exits_are_there() -> void:
	var merged := PlaceCatalog.load_hotspots()
	eq(merged["errors"], PackedStringArray(), "every hotspot file is valid and no (place, target) is defined twice")
	var shop_targets: Array = []
	for spec: Dictionary in PlaceCatalog.hotspots_for("shop"):
		shop_targets.append(spec["target"])
	in_array("door_shop_street", shop_targets, "the shop has the street door")
	in_array("ladder_shop_attic", shop_targets, "the shop has the ladder to the attic")
	var clearing: Array = []
	for spec: Dictionary in PlaceCatalog.hotspots_for("clearing"):
		clearing.append(spec["target"])
	in_array("door_archive_street", clearing, "the archive's arch is the way out to the street")

# The prologue's and act I's painted rooms, reached as a player reaches them: every hotspot a tap can open has an approach
# the witch can walk to from where she appears (the floor the picture shows nearest a thing on the wall or far off), and
# every arrival stands on the floor. The window has no walk grid: its taps are taken where she stands.
func test_the_act_one_rooms_are_reachable_as_a_player_reaches_them() -> void:
	for id in ["shop", "street", "garden", "fog_edge", "window"]:
		var place := PlaceCatalog.load_place(id)
		var room := _built(place)
		await _tree().process_frame
		ok(room is PaintedRoom, "%s is a painted room: its picture is the room" % id)
		var start: Vector3 = room.arrival_point("default")
		for spec: Dictionary in PlaceCatalog.hotspots_for(id):
			if not spec.has("at"):
				continue
			var target := str(spec["target"])
			var interactable: Interactable = room.get_interactable(target)
			ok(interactable != null, "%s: %s is an interactable" % [id, target])
			if interactable == null:
				continue
			var approach: Vector3 = interactable.approach_point
			if id == "window":
				ok(approach.is_finite(), "%s: %s keeps its place (no floor to walk)" % [id, target])
				continue
			ok(room.is_walkable(approach), "%s: %s has a standable approach" % [id, target])
			ok(not room.navigator.find_path(start, approach).is_empty(), "%s: she can walk from her arrival to %s" % [id, target])
		for from: String in place.arrive.keys():
			var arrival: Vector3 = room.arrival_point(from)
			if id != "window":
				ok(room.is_walkable(arrival), "%s: an arrival from %s stands on the floor" % [id, from])
		_release(room)
		await _tree().process_frame
