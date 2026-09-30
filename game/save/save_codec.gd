class_name SaveCodec
extends RefCounted

# Envelope around the Mirror engine's own save. The save file is primarily MirrorState:
# world, knowledge, models, relationships, predictions, evidence and the full event history.
# It deliberately does NOT contain camera transforms, particles or animation frames.

const FORMAT := "witch_save"
const VERSION := 1

static func encode(engine: MirrorEngine, meta: Dictionary = {}) -> String:
	var mirror: Variant = JSON.parse_string(engine.save_json())
	var envelope := {
		"format": FORMAT,
		"version": VERSION,
		"engine_version": MirrorDomain.ENGINE_VERSION,
		"catalog_fingerprint": engine.catalog_fingerprint if engine.catalog_is_locked else engine.compute_catalog_fingerprint(),
		"meta": meta,
		"mirror": mirror,
	}
	return JSON.stringify(envelope, "\t", true)

# Returns {"ok": bool, "error": String, "mirror_json": String, "meta": Dictionary}.
static func decode(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"ok": false, "error": "invalid_json"}
	var envelope: Dictionary = json.data
	if str(envelope.get("format", "")) != FORMAT:
		return {"ok": false, "error": "not_a_witch_save"}
	if int(envelope.get("version", 0)) > VERSION:
		return {"ok": false, "error": "future_version"}
	if not envelope.get("mirror", null) is Dictionary:
		return {"ok": false, "error": "missing_mirror_state"}
	return {
		"ok": true,
		"mirror_json": JSON.stringify(envelope["mirror"]),
		"meta": envelope.get("meta", {}),
		"catalog_fingerprint": str(envelope.get("catalog_fingerprint", "")),
	}
