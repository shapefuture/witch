extends Node3D

# A stand-in for a room in the systems tests: the two methods the sight presenter reads (RoomSlot's stage_actors() and
# anchor()), with actors and anchors set by the test. Not a test: the runner only loads test_*.gd files.

var actors: Dictionary = {}
var anchors: Dictionary = {}

func stage_actors() -> Dictionary:
	return actors

func anchor(id: String) -> Variant:
	return anchors.get(id, null)
