extends TestCase

# Save recovery (REQ-34 / audit M3): a damaged slot loads the longest run of its event log that still verifies, and
# says so; strict mode refuses it; a file with no valid event leaves the engine alone. The event cap is reconciled
# with the save limit, so a game that reaches it can still be saved.

const SLOT := 97

func _cleanup() -> void:
	for path in [SaveGame.path_for(SLOT), SaveGame.backup_path_for(SLOT)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _played() -> MirrorRuntime:
	var r := GameFixtures.runtime()
	GameFixtures.play(r, [["look_bell", "bell"], ["ask_tomas_what", "tomas"], ["wait_watch", "tomas"]])
	return r

func _fresh() -> MirrorRuntime:
	var fresh: MirrorRuntime = track(MirrorRuntime.new())
	fresh.setup()
	return fresh

func test_a_truncated_slot_loads_its_valid_prefix_and_says_so() -> void:
	_cleanup()
	var r := _played()
	var text := SaveCodec.encode(r.engine)
	_write(SaveGame.path_for(SLOT), text.substr(0, int(text.length() * 0.6)))
	var fresh := _fresh()
	var result := fresh.load_game(SLOT)
	ok(result.get("ok", false), "the damaged slot still loads: %s" % JSON.stringify(result))
	ok(result.has("recovered"), "and the result says it was recovered")
	var kept := int(result["recovered"]["kept"])
	ok(kept > 0 and kept < r.engine.event_store.size(), "a prefix of the log, not all of it (%d of %d)" % [kept, r.engine.event_store.size()])
	eq(int(result["recovered"]["kept"]), fresh.engine.event_store.size(), "the engine holds exactly the events it kept")
	eq(fresh.engine.event_store.head_hash(), r.engine.event_store.get_all()[kept - 1].hash, "its head is the original event at that position")
	ok(fresh.engine.replay_all()["ok"], "the recovered log replays")
	_cleanup()

func test_strict_mode_refuses_a_damaged_slot_and_leaves_the_engine_alone() -> void:
	_cleanup()
	var r := _played()
	var text := SaveCodec.encode(r.engine)
	_write(SaveGame.path_for(SLOT), text.substr(0, int(text.length() * 0.6)))
	var fresh := _fresh()
	var before := MirrorHash.canonical_json(fresh.engine.projection_snapshot())
	var result := fresh.load_game(SLOT, true)
	ok(not result.get("ok", false), "strict mode refuses")
	ok(not result.has("recovered"), "and does not recover")
	eq(MirrorHash.canonical_json(fresh.engine.projection_snapshot()), before, "the engine is exactly as it was")
	_cleanup()

func test_an_event_altered_in_place_keeps_only_the_events_before_it() -> void:
	_cleanup()
	var r := _played()
	var envelope: Dictionary = JSON.parse_string(SaveCodec.encode(r.engine))
	var events: Array = envelope["mirror"]["event_store"]["events"]
	var altered := 3
	ok(events.size() > altered + 1, "the fixture has events after the one altered")
	(events[altered]["payload"] as Dictionary)["tampered"] = true
	_write(SaveGame.path_for(SLOT), JSON.stringify(envelope))
	var fresh := _fresh()
	var result := fresh.load_game(SLOT)
	ok(result.has("recovered"), "flagged as recovered")
	eq(int(result["recovered"]["kept"]), altered, "the events before the altered one are kept, nothing at or after it")
	eq(str(result["recovered"]["reason"]), "hash_mismatch", "and the reason is the altered event's hash")
	eq(str(result["recovered"]["source"]), "slot", "from the slot itself")
	ok(fresh.engine.replay_all()["ok"], "what was kept replays")
	_cleanup()

func test_a_file_with_no_valid_event_is_refused_and_leaves_the_engine_alone() -> void:
	_cleanup()
	_write(SaveGame.path_for(SLOT), "this is not a save")
	var fresh := _fresh()
	var before := MirrorHash.canonical_json(fresh.engine.projection_snapshot())
	var result := fresh.load_game(SLOT)
	ok(not result.get("ok", false), "nothing to recover: refused")
	ok(not result.has("recovered"), "and not reported as a recovery")
	eq(MirrorHash.canonical_json(fresh.engine.projection_snapshot()), before, "the engine is exactly as it was")
	_cleanup()

func test_the_event_cap_is_reconciled_with_the_save_limit() -> void:
	var r := _played()
	var per_event := float(SaveCodec.encode(r.engine).length()) / float(r.engine.event_store.size())
	ok(per_event * MirrorEventStore.DEFAULT_MAX_EVENTS < float(MirrorPersistence.max_save_bytes), "at %.0f bytes an event the full event cap (%d) still saves under the %d-byte limit" % [per_event, MirrorEventStore.DEFAULT_MAX_EVENTS, MirrorPersistence.max_save_bytes])
	eq(MirrorEventStore.new().max_events, MirrorEventStore.DEFAULT_MAX_EVENTS, "a new store is capped at the reconciled value")
