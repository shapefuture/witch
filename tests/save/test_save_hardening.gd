extends TestCase

# Save hardening: every rejected save leaves the engine exactly as it was, the slot keeps a .bak
# of the previous save, a round trip is identical, and older saves still load.

const SLOT := 97

func _cleanup() -> void:
	for path in [SaveGame.path_for(SLOT), SaveGame.backup_path_for(SLOT), SaveGame.path_for(SLOT) + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _played() -> MirrorRuntime:
	var r := GameFixtures.runtime()
	GameFixtures.play(r, [["look_bell", "bell"], ["ask_tomas_what", "tomas"], ["wait_watch", "tomas"]])
	return r

func _fresh() -> MirrorRuntime:
	var r: MirrorRuntime = track(MirrorRuntime.new())
	r.setup()
	return r

func _state(engine: MirrorEngine) -> String:
	return "%s|%s|%d|%s" % [MirrorHash.canonical_json(engine.projection_snapshot()), engine.event_store.head_hash(), engine.event_store.size(), str(engine.catalog_is_locked)]

func _envelope(text: String) -> Dictionary:
	return JSON.parse_string(text)

func _mirror_of(envelope: Dictionary) -> Dictionary:
	return envelope["mirror"]

# Writes the envelope back out after editing and re-sealing it, as an attacker who knows the format would.
func _resealed(envelope: Dictionary) -> String:
	var mirror: Dictionary = _mirror_of(envelope)
	MirrorPersistence.seal(mirror)
	return JSON.stringify(SaveCodec.seal(envelope), "\t", true)

func test_a_tampered_body_is_rejected_and_the_engine_is_untouched() -> void:
	var text := SaveCodec.encode(_played().engine)
	var envelope := _envelope(text)
	_mirror_of(envelope)["world_state"]["machine"]["state"] = "running_by_magic"
	var target := _fresh()
	var before := _state(target.engine)
	var result := SaveGame.load_text(target.engine, JSON.stringify(envelope, "\t", true))
	ok(not result["ok"], "a body edited without re-sealing is rejected")
	eq(result["error"], "checksum_mismatch", "reported as a checksum mismatch")
	eq(_state(target.engine), before, "the engine is unchanged")

func test_tampered_meta_is_rejected_by_the_envelope_checksum() -> void:
	var text := SaveCodec.encode(_played().engine, {"room": "clearing"})
	var envelope := _envelope(text)
	envelope["meta"]["room"] = "elsewhere"
	var target := _fresh()
	var before := _state(target.engine)
	var result := SaveGame.load_text(target.engine, JSON.stringify(envelope, "\t", true))
	eq(result["error"], "checksum_mismatch", "meta is covered by the envelope checksum")
	eq(_state(target.engine), before, "the engine is unchanged")

func test_a_truncated_save_is_rejected_and_the_engine_is_untouched() -> void:
	var text := SaveCodec.encode(_played().engine)
	var target := _fresh()
	var before := _state(target.engine)
	ok(not SaveGame.load_text(target.engine, text.substr(0, text.length() / 2))["ok"], "half a file is rejected")
	ok(not SaveGame.load_text(target.engine, text.substr(0, text.length() - 1))["ok"], "a file missing its closing brace is rejected")
	eq(_state(target.engine), before, "the engine is unchanged")

func test_a_forged_save_that_is_re_sealed_is_still_refused_by_the_replay() -> void:
	# The checksum cannot tell a forger from a writer: both can recompute it. What stops a
	# re-sealed forgery is the projection replay, which must fail before any state is adopted.
	var envelope := _envelope(SaveCodec.encode(_played().engine))
	var mirror := _mirror_of(envelope)
	var claims: Dictionary = mirror["knowledge"]["claims"]
	claims["player::forged"] = {"id": "forged", "holder_id": "player", "proposition": {}, "evidence": [], "status": 4, "source": "x", "scope": "x", "context": {}, "first_seen_event": "", "last_updated_event": "", "contradictions": [], "revision_of": ""}
	var target := _fresh()
	var before := _state(target.engine)
	var result := SaveGame.load_text(target.engine, _resealed(envelope))
	ok(not result["ok"], "a re-sealed forgery is refused")
	ok(result["error"] in ["projection_mismatch", "replay_rejected", "restore_rejected"], "refused by the replay, not by the checksum: %s" % result["error"])
	ok(not target.engine.knowledge.has("forged"), "the forged claim never reaches the engine")
	eq(_state(target.engine), before, "the engine is unchanged")

func test_a_current_save_without_its_checksum_is_rejected() -> void:
	var data: Dictionary = JSON.parse_string(_played().engine.save_json())
	data.erase("checksum")
	var target := _fresh()
	var before := _state(target.engine)
	eq(target.engine.load_json(JSON.stringify(data))["error"], "checksum_missing", "a format-7 body without a checksum is not trusted")
	eq(_state(target.engine), before, "the engine is unchanged")

func test_an_oversized_save_is_refused_before_it_is_parsed() -> void:
	var saved_limit := MirrorPersistence.max_save_bytes
	MirrorPersistence.max_save_bytes = 2000
	var text := SaveCodec.encode(_played().engine)
	var target := _fresh()
	var before := _state(target.engine)
	eq(SaveGame.load_text(target.engine, text)["error"], "oversized", "a save over the limit is refused")
	# Not valid JSON either: the size check must answer first, which proves it runs before parsing.
	eq(SaveGame.load_text(target.engine, "[" + " ".repeat(5000))["error"], "oversized", "size is checked before the text is parsed")
	eq(_state(target.engine), before, "the engine is unchanged")
	_cleanup()
	eq(SaveGame.save(_played().engine, SLOT), ERR_INVALID_DATA, "a save that could not be loaded is not written")
	ok(not SaveGame.exists(SLOT), "and no file was left behind")
	MirrorPersistence.max_save_bytes = saved_limit

func test_an_oversized_file_is_refused_before_it_is_read() -> void:
	_cleanup()
	var r := _played()
	eq(r.save_game(SLOT), OK, "saved under the normal limit")
	var saved_limit := MirrorPersistence.max_save_bytes
	MirrorPersistence.max_save_bytes = 2000
	var target := _fresh()
	var before := _state(target.engine)
	eq(SaveGame.load_into(target.engine, SLOT)["error"], "oversized", "the file is refused by its length")
	eq(_state(target.engine), before, "the engine is unchanged")
	MirrorPersistence.max_save_bytes = saved_limit
	_cleanup()

func test_saving_keeps_a_bak_of_the_previous_save() -> void:
	_cleanup()
	var r := _played()
	eq(r.save_game(SLOT, {"n": 1}), OK, "first save")
	var first := FileAccess.get_file_as_string(SaveGame.path_for(SLOT))
	ok(not FileAccess.file_exists(SaveGame.backup_path_for(SLOT)), "no backup before there is a previous save")
	GameFixtures.do(r, "look_tomas", "tomas")
	eq(r.save_game(SLOT, {"n": 2}), OK, "second save")
	ok(FileAccess.file_exists(SaveGame.backup_path_for(SLOT)), "the previous save was kept as .bak")
	eq(FileAccess.get_file_as_string(SaveGame.backup_path_for(SLOT)), first, "the .bak is byte-for-byte the previous save")
	ok(FileAccess.get_file_as_string(SaveGame.path_for(SLOT)) != first, "the slot holds the new save")
	ok(not FileAccess.file_exists(SaveGame.path_for(SLOT) + ".tmp"), "no temp file is left behind")
	var from_backup := _fresh()
	ok(SaveGame.load_text(from_backup.engine, FileAccess.get_file_as_string(SaveGame.backup_path_for(SLOT)))["ok"], "the .bak is itself a loadable save")
	_cleanup()

func test_a_round_trip_is_identical() -> void:
	_cleanup()
	var r := _played()
	var text := SaveCodec.encode(r.engine, {"room": "clearing"})
	var fresh := _fresh()
	var result := SaveGame.load_text(fresh.engine, text)
	ok(result["ok"], "loads: %s" % JSON.stringify(result))
	ok(not result["legacy"], "a current save is not legacy")
	eq(_state(fresh.engine), _state(r.engine), "identical projection, chain head and catalog lock")
	eq(SaveCodec.encode(fresh.engine, {"room": "clearing"}), text, "saving the loaded game again writes the same bytes")
	_cleanup()

func test_a_legacy_engine_body_without_checksum_still_loads() -> void:
	var data: Dictionary = JSON.parse_string(_played().engine.save_json())
	data.erase("checksum")
	data["schema_version"] = 6
	var target := _fresh()
	var result := target.engine.load_json(JSON.stringify(data))
	ok(result["ok"], "a format-6 body loads: %s" % JSON.stringify(result))
	ok(result.get("legacy", false), "and is reported as legacy (unverified by a checksum)")
	eq(MirrorHash.canonical_json(target.engine.projection_snapshot()), MirrorHash.canonical_json(_played().engine.projection_snapshot()), "with the same state")

func test_a_format_5_body_still_migrates_and_loads() -> void:
	# Format 5 already had the evidence store; format 6 added operators, which migrate() back-fills.
	var data: Dictionary = JSON.parse_string(_played().engine.save_json())
	for key in ["checksum", "operators"]:
		data.erase(key)
	data["schema_version"] = 5
	var target := _fresh()
	var result := target.engine.load_json(JSON.stringify(data))
	ok(result["ok"], "a format-5 body migrates and loads: %s" % JSON.stringify(result))
	ok(target.engine.event_store.verify_chain()["ok"], "and its event chain verifies after migration")

func test_a_format_4_body_whose_log_has_evidence_is_refused_cleanly() -> void:
	# migrate() cannot rebuild an evidence store that was never saved, so a format-4 body whose
	# event log already holds evidence fails the projection replay. This is the existing behaviour,
	# pinned here: the refusal must still leave the engine untouched.
	var data: Dictionary = JSON.parse_string(_played().engine.save_json())
	for key in ["checksum", "evidence", "operators", "catalog"]:
		data.erase(key)
	data["schema_version"] = 4
	var target := _fresh()
	var before := _state(target.engine)
	eq(target.engine.load_json(JSON.stringify(data))["error"], "projection_mismatch", "refused by the replay")
	eq(_state(target.engine), before, "the engine is unchanged")

func test_a_legacy_envelope_still_loads_and_is_reported_as_legacy() -> void:
	var r := _played()
	var mirror: Dictionary = JSON.parse_string(r.engine.save_json())
	mirror.erase("checksum")
	mirror["schema_version"] = 6
	var envelope := {"format": SaveCodec.FORMAT, "version": 1, "engine_version": MirrorDomain.ENGINE_VERSION, "catalog_fingerprint": r.engine.catalog_fingerprint, "meta": {"room": "clearing"}, "mirror": mirror}
	var target := _fresh()
	var result := SaveGame.load_text(target.engine, JSON.stringify(envelope))
	ok(result["ok"], "a version-1 envelope loads: %s" % JSON.stringify(result))
	ok(result.get("legacy", false), "and is reported as legacy")
	eq(result["meta"], {"room": "clearing"}, "its meta survives")
	eq(MirrorHash.canonical_json(target.engine.projection_snapshot()), MirrorHash.canonical_json(r.engine.projection_snapshot()), "with the same state")

func test_the_checksum_does_not_depend_on_int_versus_float_numbers() -> void:
	var body := {"a": 2, "b": [1, 2.5], "c": {"d": 7}}
	var reparsed: Dictionary = JSON.parse_string(JSON.stringify(body))
	eq(MirrorPersistence.checksum_of(reparsed), MirrorPersistence.checksum_of(body), "2 and 2.0 seal the same")
	ok(MirrorPersistence.checksum_of(body) != MirrorPersistence.checksum_of({"a": 3, "b": [1, 2.5], "c": {"d": 7}}), "a changed value changes the seal")
