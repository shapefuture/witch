extends TestCase

const SLOT := 98

func _cleanup() -> void:
	if SaveGame.exists(SLOT):
		DirAccess.remove_absolute(SaveGame.path_for(SLOT))

func _played() -> MirrorRuntime:
	var r := GameFixtures.runtime()
	GameFixtures.play(r, [["look_bell", "bell"], ["ask_tomas_what", "tomas"], ["wait_watch", "tomas"]])
	return r

func test_file_round_trip_preserves_everything() -> void:
	_cleanup()
	var r := _played()
	eq(r.save_game(SLOT, {"room": "clearing"}), OK, "saved")
	ok(SaveGame.exists(SLOT), "file exists")
	var fresh: MirrorRuntime = track(MirrorRuntime.new())
	fresh.setup()
	var result := fresh.load_game(SLOT)
	ok(result["ok"], "loaded: %s" % JSON.stringify(result))
	eq(result["meta"], {"room": "clearing"}, "meta survives")
	eq(MirrorHash.canonical_json(fresh.engine.projection_snapshot()), MirrorHash.canonical_json(r.engine.projection_snapshot()), "identical canonical state")
	eq(fresh.engine.event_store.head_hash(), r.engine.event_store.head_hash(), "identical history")
	ok(fresh.engine.knowledge.has("bell_tilted_into_wind"), "epistemic state survived, not just the world")
	ok(fresh.engine.models.query_rules("tomas", "help", "player").size() > 0, "the player's models survived")
	_cleanup()

func test_loaded_game_offers_the_same_options() -> void:
	_cleanup()
	var r := _played()
	r.save_game(SLOT)
	var fresh: MirrorRuntime = track(MirrorRuntime.new())
	fresh.setup()
	fresh.load_game(SLOT)
	for target in ["tomas", "machine", "bell", "path_out"]:
		eq(GameFixtures.action_ids(fresh, target), GameFixtures.action_ids(r, target), "same options for %s" % target)
	_cleanup()

func test_saved_file_contains_mirror_state_and_no_presentation_state() -> void:
	_cleanup()
	_played().save_game(SLOT)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.path_for(SLOT)))
	eq(envelope["format"], SaveCodec.FORMAT, "format tag")
	for key in ["event_store", "knowledge", "models", "relationships", "prediction", "evidence", "world_state", "npc_state"]:
		ok(envelope["mirror"].has(key), "mirror section %s" % key)
	var text := FileAccess.get_file_as_string(SaveGame.path_for(SLOT))
	# Authored presentation INSTRUCTIONS live in response events and are fine; what must never be
	# persisted is runtime presentation STATE.
	for forbidden in ["transform", "global_position", "animation_frame", "particles", "camera_position"]:
		ok(forbidden not in text.to_lower(), "no %s in a save" % forbidden)
	_cleanup()

func test_loading_nothing_or_garbage_fails_cleanly_and_leaves_the_game_untouched() -> void:
	_cleanup()
	var r := _played()
	var head := r.engine.event_store.head_hash()
	eq(r.load_game(SLOT)["error"], "no_save", "missing slot")
	eq(SaveGame.load_text(r.engine, "not json")["error"], "invalid_json", "garbage")
	eq(SaveGame.load_text(r.engine, "{\"format\": \"other\"}")["error"], "not_a_witch_save", "foreign file")
	eq(SaveGame.load_text(r.engine, JSON.stringify({"format": SaveCodec.FORMAT, "version": 99, "mirror": {}}))["error"], "future_version", "future version")
	eq(SaveGame.load_text(r.engine, JSON.stringify({"format": SaveCodec.FORMAT, "version": 1}))["error"], "missing_mirror_state", "no mirror")
	eq(r.engine.event_store.head_hash(), head, "the running game survived every rejected load")

func test_a_save_from_a_different_catalog_is_rejected_and_the_game_is_untouched() -> void:
	var r := _played()
	var text := SaveCodec.encode(r.engine)
	var other: MirrorRuntime = track(MirrorRuntime.new())
	other.setup()
	other.engine.register_action({"id": "extra_action", "action_type": MirrorDomain.ActionType.CUSTOM})
	var result := SaveGame.load_text(other.engine, text)
	ok(not result["ok"], "catalog fingerprint mismatch rejected")
	eq(other.engine.event_store.size(), 0, "engine untouched")

func test_saving_is_atomic_no_temp_file_left_behind() -> void:
	_cleanup()
	_played().save_game(SLOT)
	ok(not FileAccess.file_exists(SaveGame.path_for(SLOT) + ".tmp"), "temp file renamed away")
	_cleanup()
