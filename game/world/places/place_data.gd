class_name PlaceData
extends RefCounted

# One place as data/world/places/<id>.json describes it (docs/design/GAME_SPEC.md section 4). A place is presentation:
# which room it is played in, where people stand and where she appears. Mirror holds the place's meaning (the world
# value witch.place); nothing here decides anything.
#
# Points are pixels on the 1280x720 plate. A kind of "painted" with a dir that has no room.json, and "stage", are
# played on the stand-in stage in `stage.palette`.

const PLATE := Vector2(1280.0, 720.0)
const DEFAULT_PIXEL := Vector2(640.0, 600.0)

var id := ""
# "painted" (a picture with a room.json, or a stand-in), "hall" (the archive) or "stage" (a stand-in by design).
var kind := "stage"
var dir := ""
var variants: Dictionary = {}          # variant name -> res:// dir
var palette: Array[Color] = []
var spots: Dictionary = {}             # npc id or "default" -> Vector2 (pixels)
var arrive: Dictionary = {}            # place id she comes from, or "default" -> Vector2 (pixels)

# The place file parsed to a PlaceData, or null with `error` set (the caller reports it).
static func from_dict(data: Dictionary) -> PlaceData:
	var place := PlaceData.new()
	place.id = str(data.get("id", ""))
	var room: Dictionary = data.get("room", {}) if data.get("room") is Dictionary else {}
	place.kind = str(room.get("kind", "stage"))
	place.dir = str(room.get("dir", ""))
	var variant_data: Variant = data.get("variants", {})
	if variant_data is Dictionary:
		for name: Variant in variant_data:
			place.variants[str(name)] = str(variant_data[name])
	var stage: Variant = data.get("stage", {})
	if stage is Dictionary:
		for hex: Variant in (stage as Dictionary).get("palette", []):
			place.palette.append(Color.from_string(str(hex), Color.DIM_GRAY))
	place.spots = _points(data.get("spots", {}))
	place.arrive = _points(data.get("arrive", {}))
	return place

# Problems with the parsed place, empty when it is usable. A painted place needs a dir; a stage needs a palette.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if id.is_empty() or not id.is_valid_filename() or id.to_lower() != id:
		out.append("place id '%s' must be lowercase, with no spaces" % id)
	if kind not in ["painted", "hall", "stage"]:
		out.append("%s: unknown room kind '%s'" % [id, kind])
	if kind == "painted" and dir.is_empty():
		out.append("%s: a painted room needs room.dir" % id)
	if kind == "stage" and palette.is_empty():
		out.append("%s: a stage needs stage.palette" % id)
	return out

# Where a person stands: their own spot, else the default one.
func spot_for(npc_id: String) -> Vector2:
	if spots.has(npc_id):
		return spots[npc_id]
	return spots.get("default", DEFAULT_PIXEL)

# Where she appears coming from `from` (a place id), else the default arrival, else the default spot.
func arrival_for(from: String) -> Vector2:
	if not from.is_empty() and arrive.has(from):
		return arrive[from]
	if arrive.has("default"):
		return arrive["default"]
	return spot_for("default")

func has_arrival(from: String) -> bool:
	return (not from.is_empty() and arrive.has(from)) or arrive.has("default")

# The dir a variant is painted in, or the place's own dir when the variant is unknown or empty.
func dir_for(variant: String) -> String:
	if not variant.is_empty() and variants.has(variant):
		return str(variants[variant])
	return dir

static func _points(data: Variant) -> Dictionary:
	var out := {}
	if not data is Dictionary:
		return out
	for key: Variant in data:
		var value: Variant = data[key]
		if value is Array and (value as Array).size() >= 2:
			out[str(key)] = Vector2(float(value[0]), float(value[1]))
	return out
