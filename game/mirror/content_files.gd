class_name ContentFiles
extends RefCounted

# Authored content is split into area packages so parallel authors never edit the same file
# (docs/engine/CONTENT_PACKAGES.md). A root file such as data/mirror/storylets.json keeps working; each area adds
# data/mirror/areas/<area>/storylets.json, and the loaders read the root first, then the areas in name order.
# Merging never overrides: an id, a world entity or a text key may be defined once across the root and every area,
# and the loaders report a second definition as an error.

const AREAS := "areas"

# The area files named `name` (without .json) under `areas_dir`, sorted by area. Empty when there are none.
static func area_paths(areas_dir: String, name: String) -> Array[String]:
	var out: Array[String] = []
	if areas_dir.is_empty() or not DirAccess.dir_exists_absolute(areas_dir):
		return out
	var areas := Array(DirAccess.get_directories_at(areas_dir))
	areas.sort()
	for area: String in areas:
		var path := areas_dir.path_join(area).path_join(name + ".json")
		if FileAccess.file_exists(path):
			out.append(path)
	return out

# The JSON files in `dir` with the given extension, sorted (an absent directory is empty).
static func files_in(dir: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var names := Array(DirAccess.get_files_at(dir))
	names.sort()
	for file_name: String in names:
		if file_name.get_extension() == extension:
			out.append(dir.path_join(file_name))
	return out

# Adds `incoming`'s keys to `target`, refusing a key that is already there. `label` names what the keys are
# ("world entity", "Minds place") and `where` the file, for the error.
static func merge_unique(target: Dictionary, incoming: Dictionary, label: String, where: String, errors: Array) -> void:
	for key in incoming.keys():
		if str(key).begins_with("_"):
			continue
		if target.has(key):
			errors.append("%s: %s '%s' is already defined" % [where, label, key])
			continue
		target[key] = incoming[key]
