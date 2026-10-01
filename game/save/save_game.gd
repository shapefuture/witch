class_name SaveGame
extends RefCounted

const DIR := "user://saves"

static func path_for(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]

static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))

static func save(engine: MirrorEngine, slot: int, meta: Dictionary = {}) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	# Write to a temp file and rename, so a crash mid-write can never leave a half-written save
	# in the slot.
	var final_path := path_for(slot)
	var temp_path := final_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(SaveCodec.encode(engine, meta))
	file.close()
	return DirAccess.rename_absolute(temp_path, final_path)

# Loads into an engine that already has the catalog registered. Atomic: a rejected save leaves
# the engine exactly as it was (MirrorPersistence.load_json restores its own pre-load snapshot).
static func load_into(engine: MirrorEngine, slot: int) -> Dictionary:
	if not exists(slot):
		return {"ok": false, "error": "no_save"}
	return load_text(engine, FileAccess.get_file_as_string(path_for(slot)))

static func load_text(engine: MirrorEngine, text: String) -> Dictionary:
	var decoded := SaveCodec.decode(text)
	if not decoded.get("ok", false):
		return decoded
	var result := engine.load_json(decoded["mirror_json"])
	if result.get("ok", false):
		result["meta"] = decoded["meta"]
	return result
