extends TestCase

const T := MirrorDomain.ActionType

func _rich_engine() -> MirrorEngine:
	return MirrorFixtures.rich_engine()

func test_full_round_trip_preserves_projection_and_chain() -> void:
	var e := _rich_engine()
	var json := e.save_json()
	var e2 := MirrorFixtures.engine()
	var res := e2.load_json(json)
	ok(res.get("ok", false), "load ok: %s" % JSON.stringify(res))
	eq(MirrorHash.canonical_json(e2.projection_snapshot()), MirrorHash.canonical_json(e.projection_snapshot()), "projection identical")
	eq(e2.event_store.head_hash(), e.event_store.head_hash(), "chain head identical")
	ok(e2.event_store.verify_chain()["ok"], "loaded chain verifies")

func test_loaded_engine_continues_identically() -> void:
	var e := _rich_engine()
	var e2 := MirrorFixtures.engine()
	ok(e2.load_json(e.save_json())["ok"], "load")
	var a := e.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	var b := e2.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	eq(a["ok"], b["ok"], "same success")
	eq(e.event_store.head_hash(), e2.event_store.head_hash(), "continuation yields the same head")

func test_idempotency_survives_load() -> void:
	var e := _rich_engine()
	var e2 := MirrorFixtures.engine()
	ok(e2.load_json(e.save_json())["ok"], "load")
	var size_before := e2.event_store.size()
	var r := e2.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK, {}, "r-look"))
	ok(r.get("idempotent_replay", false), "retrying a committed request after load must replay, not recommit")
	eq(e2.event_store.size(), size_before, "no duplicate commit")

func test_load_rejects_tampered_event() -> void:
	var e := _rich_engine()
	var data: Dictionary = JSON.parse_string(e.save_json())
	data["event_store"]["events"][1]["payload"]["observed"] = {"outcome": "tampered"}
	var e2 := MirrorFixtures.engine()
	var res := e2.load_json(JSON.stringify(data))
	ok(not res.get("ok", true), "tampered event must be rejected")
	eq(e2.event_store.size(), 0, "rejected load leaves the engine untouched")

func test_load_rejects_catalog_mismatch() -> void:
	var e := _rich_engine()
	var other := MirrorEngine.new()
	other.register_action({"id": "look_door", "action_type": MirrorDomain.ActionType.LOOK})
	ok(not other.load_json(e.save_json()).get("ok", true), "save from a different catalog is rejected")

func test_load_rejects_garbage_cleanly() -> void:
	var e := MirrorFixtures.engine()
	eq(e.load_json("not json")["error"], "invalid_json", "non-json")
	eq(e.load_json("[1,2,3]")["error"], "invalid_json", "json but not an object")
	eq(e.load_json("{\"schema_version\": 99}")["error"], "future_schema", "future schema")
	ok(not e.load_json("{}").get("ok", true), "empty object")

func test_load_rejects_malformed_sections_without_script_errors() -> void:
	var e := _rich_engine()
	var good: Dictionary = JSON.parse_string(e.save_json())
	for section in ["event_store", "knowledge", "models", "evidence", "relationships", "prediction", "world_state", "npc_state", "action_memory", "operators", "catalog"]:
		var bad := good.duplicate(true)
		bad[section] = "corrupt"
		var target := MirrorFixtures.engine()
		ok(not target.load_json(JSON.stringify(bad)).get("ok", true), "corrupt %s rejected" % section)
		eq(target.event_store.size(), 0, "corrupt %s leaves engine empty" % section)

func test_load_rejects_malformed_event_entries_without_script_errors() -> void:
	var e := _rich_engine()
	var good: Dictionary = JSON.parse_string(e.save_json())
	for field in ["payload", "context", "effects", "causes", "prediction_signature", "evidence_refs"]:
		var bad := good.duplicate(true)
		bad["event_store"]["events"][0][field] = "corrupt"
		var target := MirrorFixtures.engine()
		ok(not target.load_json(JSON.stringify(bad)).get("ok", true), "event field %s corrupt rejected" % field)

func test_replay_all_reproduces_live_projection() -> void:
	var e := _rich_engine()
	var live := MirrorHash.canonical_json(e.projection_snapshot())
	var replay := e.replay_all()
	ok(replay["ok"], "replay ok")
	eq(MirrorHash.canonical_json(replay["projection"]), live, "event-log replay equals live projection (the log is the truth)")
