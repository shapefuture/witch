class_name PlaceCatalog
extends RefCounted

# Loads the places (data/world/places/<place>.json) and the hotspots (data/world/hotspots/<area>.json, one file per
# content area, merged). Nothing is cached: a read is a few small files, and a test or a save can change the data.
#
# A hotspot is {"place", "target", "at": Vector2 (pixels) or "anchor": name, "radius"}. Its target is an id Mirror's
# actions use; the room offers it only while Mirror offers an action on it (see GameRoot).

const PLACES_DIR := "res://data/world/places"
const HOTSPOTS_DIR := "res://data/world/hotspots"
const DEFAULT_RADIUS := 48.0

static func place_ids(dir: String = PLACES_DIR) -> PackedStringArray:
	var out := PackedStringArray()
	for file in _json_files(dir):
		out.append(file.get_basename())
	return out

# The place with `id`, or null (and `error` in load_report). Problems are reported by load_report.
static func load_place(id: String, dir: String = PLACES_DIR) -> PlaceData:
	var data := _read(dir.path_join(id + ".json"))
	if data.is_empty():
		return null
	var place := PlaceData.from_dict(data)
	return place if place.problems().is_empty() else null

# Every place file: {"places": {id: PlaceData}, "errors": PackedStringArray}. A file whose id does not match its name
# is an error, as is any problem PlaceData reports.
static func load_all(dir: String = PLACES_DIR) -> Dictionary:
	var places: Dictionary = {}
	var errors := PackedStringArray()
	for file in _json_files(dir):
		var data := _read(dir.path_join(file))
		if data.is_empty():
			errors.append("%s: not a JSON object" % file)
			continue
		var place := PlaceData.from_dict(data)
		if place.id != file.get_basename():
			errors.append("%s: id '%s' does not match the file name" % [file, place.id])
		for problem in place.problems():
			errors.append("%s: %s" % [file, problem])
		if place.problems().is_empty():
			places[place.id] = place
	return {"places": places, "errors": errors}

# Every hotspot file merged: {"hotspots": Array[Dictionary], "errors": PackedStringArray}. A second hotspot for the
# same (place, target) is an error and is dropped. An entry without a target is a note and is skipped.
static func load_hotspots(dir: String = HOTSPOTS_DIR) -> Dictionary:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var errors := PackedStringArray()
	for file in _json_files(dir):
		var parsed: Variant = _read_any(dir.path_join(file))
		if not parsed is Array:
			errors.append("%s: hotspots are a JSON array" % file)
			continue
		for entry: Variant in parsed:
			if not entry is Dictionary or not (entry as Dictionary).has("target"):
				continue
			var spec := _spec(entry as Dictionary)
			var key := "%s/%s" % [spec["place"], spec["target"]]
			if spec["place"].is_empty() or spec["target"].is_empty():
				errors.append("%s: a hotspot needs place and target (%s)" % [file, key])
			elif not spec.has("at") and str(spec["anchor"]).is_empty():
				errors.append("%s: hotspot %s needs at or anchor" % [file, key])
			elif seen.has(key):
				errors.append("%s: hotspot %s is defined twice" % [file, key])
			else:
				seen[key] = true
				out.append(spec)
	return {"hotspots": out, "errors": errors}

# The hotspots of one place, merged from every file.
static func hotspots_for(place_id: String, dir: String = HOTSPOTS_DIR) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec: Dictionary in load_hotspots(dir)["hotspots"]:
		if str(spec["place"]) == place_id:
			out.append(spec)
	return out

static func _spec(entry: Dictionary) -> Dictionary:
	var spec := {
		"place": str(entry.get("place", "")),
		"target": str(entry.get("target", "")),
		"anchor": str(entry.get("anchor", "")),
		"radius": float(entry.get("radius", DEFAULT_RADIUS)),
	}
	var at: Variant = entry.get("at")
	if at is Array and (at as Array).size() >= 2:
		spec["at"] = Vector2(float(at[0]), float(at[1]))
	return spec

static func _json_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var access := DirAccess.open(dir)
	if access == null:
		return out
	access.list_dir_begin()
	var name := access.get_next()
	while not name.is_empty():
		if not access.current_is_dir() and name.ends_with(".json") and not name.begins_with("_"):
			out.append(name)
		name = access.get_next()
	access.list_dir_end()
	out.sort()
	return out

static func _read(path: String) -> Dictionary:
	var parsed: Variant = _read_any(path)
	return parsed if parsed is Dictionary else {}

static func _read_any(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
