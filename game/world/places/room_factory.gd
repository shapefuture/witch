class_name RoomFactory
extends RefCounted

# Builds the room a place is played in. The place file decides the kind: "hall" is the archive, "painted" is a picture
# with a room.json, and anything else (a painting not made yet, or "stage") is the stand-in. Nothing here names a
# place: a new place file with a new dir is picked up without code.
#
# Build, then add to the tree, then dress: `dress` adds the hotspots once the room's walk grid and ground exist.

static func build(place: PlaceData, variant: String = "") -> PlaceRoom:
	var dir := place.dir_for(variant)
	var room: PlaceRoom
	if place.kind == "hall":
		room = ArchiveHall.new()
	elif place.kind == "painted" and has_painting(dir):
		var painted := PaintedRoom.new()
		painted.room_dir = dir
		painted.own_input = false
		painted.skip_actors = PackedStringArray(["witch"])
		room = painted
	else:
		room = StageRoom.new()
	room.place = place
	room.room_id = place.id
	room.name = "Room_" + place.id
	return room

# Whether a painting exists in `dir` (a dir with a room.json is a painted room; without one the stand-in is used).
static func has_painting(dir: String) -> bool:
	return FileAccess.file_exists(dir.path_join("room.json"))

# Adds the place's hotspots from every area file. Call after the room is in the tree.
static func dress(room: PlaceRoom, place: PlaceData) -> int:
	return room.add_hotspots(PlaceCatalog.hotspots_for(place.id))
