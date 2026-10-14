class_name SaveGame
extends RefCounted

# Slot files: slot_N.json is the current save, slot_N.json.bak the one before it. A write goes to
# slot_N.json.tmp first, is read back and compared, and only then replaces the slot. The .bak is a
# copy made before the replace, so a failed write never leaves the slot without a complete save.

const DIR := "user://saves"

static func path_for(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]

static func backup_path_for(slot: int) -> String:
	return path_for(slot) + ".bak"

static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))

static func save(engine: MirrorEngine, slot: int, meta: Dictionary = {}) -> Error:
	DirAccess.make_dir_recursive_absolute(DIR)
	var final_path := path_for(slot)
	var temp_path := final_path + ".tmp"
	var text := SaveCodec.encode(engine, meta)
	# A save over the size limit could never be loaded, so refuse it here instead of writing it.
	if MirrorPersistence.is_oversized(text):
		return ERR_INVALID_DATA
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(temp_path) != text:
		DirAccess.remove_absolute(temp_path)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(final_path):
		var backup_error := DirAccess.copy_absolute(final_path, backup_path_for(slot))
		if backup_error != OK:
			DirAccess.remove_absolute(temp_path)
			return backup_error
	var rename_error := DirAccess.rename_absolute(temp_path, final_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
	return rename_error

# Loads into an engine that already has the catalog registered. Atomic: a rejected save leaves
# the engine exactly as it was (MirrorPersistence.load_json restores its own pre-load snapshot).
static func load_into(engine: MirrorEngine, slot: int) -> Dictionary:
	if not exists(slot):
		return {"ok": false, "error": "no_save"}
	var file := FileAccess.open(path_for(slot), FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "unreadable"}
	# Checked before the file is read into memory, not after.
	if file.get_length() > MirrorPersistence.max_save_bytes:
		file.close()
		return {"ok": false, "error": "oversized"}
	var text := file.get_as_text()
	file.close()
	return load_text(engine, text)

static func load_text(engine: MirrorEngine, text: String) -> Dictionary:
	var decoded := SaveCodec.decode(text)
	if not decoded.get("ok", false):
		return decoded
	var result := engine.load_json(decoded["mirror_json"])
	if result.get("ok", false):
		result["meta"] = decoded["meta"]
		result["legacy"] = bool(result.get("legacy", false)) or bool(decoded.get("legacy", false))
	return result
