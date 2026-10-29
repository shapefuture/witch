class_name SaveCodec
extends RefCounted

# Envelope around the Mirror engine's own save. The save file is primarily MirrorState:
# world, knowledge, models, relationships, predictions, evidence and the full event history.
# It deliberately does NOT contain camera transforms, particles or animation frames.
#
# Version 2 seals the envelope. Its checksum covers the envelope's own fields and the engine's
# checksum (mirror_checksum), and the engine's checksum covers the mirror body. The mirror body
# is not hashed twice. Version 1 files (no checksum) still load and are reported as legacy.

const FORMAT := "witch_save"
const VERSION := 2

static func encode(engine: MirrorEngine, meta: Dictionary = {}) -> String:
	var mirror: Dictionary = JSON.parse_string(engine.save_json())
	var envelope := {
		"format": FORMAT,
		"version": VERSION,
		"engine_version": MirrorDomain.ENGINE_VERSION,
		"catalog_fingerprint": engine.catalog_fingerprint if engine.catalog_is_locked else engine.compute_catalog_fingerprint(),
		"meta": meta,
		"mirror": mirror,
	}
	return JSON.stringify(seal(envelope), "\t", true)

# Adds mirror_checksum and checksum. Tests use it to re-seal an envelope they changed on purpose.
static func seal(envelope: Dictionary) -> Dictionary:
	var mirror: Dictionary = envelope.get("mirror", {})
	envelope["mirror_checksum"] = str(mirror.get("checksum", ""))
	envelope["checksum"] = MirrorPersistence.checksum_of(_sealed_fields(envelope))
	return envelope

# Returns {"ok": bool, "error": String, "mirror_json": String, "meta": Dictionary, "legacy": bool}.
# Nothing here changes game state; the caller hands mirror_json to the engine only when it passes.
static func decode(text: String) -> Dictionary:
	if MirrorPersistence.is_oversized(text):
		return {"ok": false, "error": "oversized"}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"ok": false, "error": "invalid_json"}
	var envelope: Dictionary = json.data
	if str(envelope.get("format", "")) != FORMAT:
		return {"ok": false, "error": "not_a_witch_save"}
	var version := int(envelope.get("version", 0))
	if version < 1:
		return {"ok": false, "error": "not_a_witch_save"}
	if version > VERSION:
		return {"ok": false, "error": "future_version"}
	if not envelope.get("mirror", null) is Dictionary:
		return {"ok": false, "error": "missing_mirror_state"}
	if version >= 2:
		if not envelope.has("checksum"):
			return {"ok": false, "error": "checksum_missing"}
		if MirrorPersistence.checksum_of(_sealed_fields(envelope)) != str(envelope["checksum"]):
			return {"ok": false, "error": "checksum_mismatch"}
		if str(envelope["mirror"].get("checksum", "")) != str(envelope.get("mirror_checksum", "")):
			return {"ok": false, "error": "checksum_mismatch"}
	return {
		"ok": true,
		"mirror_json": JSON.stringify(envelope["mirror"]),
		"meta": envelope.get("meta", {}),
		"catalog_fingerprint": str(envelope.get("catalog_fingerprint", "")),
		"legacy": version < 2,
	}

# Everything the envelope checksum covers: all fields except the mirror body and the checksum.
static func _sealed_fields(envelope: Dictionary) -> Dictionary:
	var fields := envelope.duplicate(false)
	fields.erase("mirror")
	fields.erase("checksum")
	return fields
