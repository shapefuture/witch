extends TestCase

const T := MirrorDomain.ActionType

func _saved_json() -> String:
	var e := MirrorFixtures.engine()
	e.resolve_action(MirrorFixtures.act("look_door", "door", T.LOOK))
	e.resolve_action(MirrorFixtures.act("cast_light", "lamp", T.CAST))
	return e.save_json()

func test_failed_load_leaves_engine_exactly_as_before() -> void:
	# A save whose event chain is valid but whose derived projection was edited must be
	# rejected AND must not leave the rejected data inside the engine.
	var data: Dictionary = JSON.parse_string(_saved_json())
	data["knowledge"]["claims"]["player::forged"] = {"id": "forged", "holder_id": "player", "proposition": {}, "evidence": [], "status": 4, "source": "x", "scope": "x", "context": {}, "first_seen_event": "", "last_updated_event": "", "contradictions": [], "revision_of": ""}
	var target := MirrorFixtures.engine()
	var before := MirrorHash.canonical_json(target.projection_snapshot())
	var res := target.load_json(JSON.stringify(data))
	ok(not res.get("ok", true), "forged projection rejected")
	eq(res.get("error", ""), "projection_mismatch", "reported as projection mismatch")
	ok(not target.knowledge.has("forged"), "forged claim must not survive in the engine")
	eq(target.event_store.size(), 0, "no events adopted from a rejected save")
	eq(MirrorHash.canonical_json(target.projection_snapshot()), before, "engine projection unchanged by a rejected load")
	ok(not target.catalog_is_locked, "catalog lock state unchanged by a rejected load")

func test_failed_load_on_a_live_engine_keeps_its_progress() -> void:
	var target := MirrorFixtures.engine()
	target.resolve_action(MirrorFixtures.act("ask_tomas", "tomas", T.ASK))
	var head := target.event_store.head_hash()
	var data: Dictionary = JSON.parse_string(_saved_json())
	data["world_state"]["door"] = "forged"
	ok(not target.load_json(JSON.stringify(data)).get("ok", true), "rejected")
	eq(target.event_store.head_hash(), head, "live progress intact after a rejected load")

func test_empty_object_is_rejected_cleanly() -> void:
	var e := MirrorFixtures.engine()
	var res := e.load_json("{}")
	ok(not res.get("ok", true), "rejected")
	eq(e.event_store.size(), 0, "untouched")

func test_missing_section_is_rejected_cleanly() -> void:
	var data: Dictionary = JSON.parse_string(_saved_json())
	for section in ["event_store", "knowledge", "models", "evidence", "relationships", "world_state", "npc_state", "initial_world_state", "initial_npc_state", "action_memory"]:
		var bad := data.duplicate(true)
		bad.erase(section)
		var target := MirrorFixtures.engine()
		ok(not target.load_json(JSON.stringify(bad)).get("ok", true), "missing %s rejected" % section)

func test_nested_shape_corruption_is_rejected_cleanly() -> void:
	var data: Dictionary = JSON.parse_string(_saved_json())
	var cases := [
		["knowledge", "claims"], ["models", "rules"], ["models", "history"], ["evidence", "items"],
		["evidence", "by_event"], ["relationships", "relations"], ["prediction", "seen_once"],
		["operators", "acquired"], ["event_store", "events"],
	]
	for c in cases:
		var bad := data.duplicate(true)
		bad[c[0]][c[1]] = "corrupt"
		var target := MirrorFixtures.engine()
		ok(not target.load_json(JSON.stringify(bad)).get("ok", true), "corrupt %s.%s rejected" % [c[0], c[1]])
		eq(target.event_store.size(), 0, "%s.%s leaves engine empty" % [c[0], c[1]])

func test_malformed_event_fields_are_rejected_cleanly() -> void:
	var data: Dictionary = JSON.parse_string(_saved_json())
	for field in ["payload", "context", "effects", "causes", "prediction_signature", "evidence_refs", "event_id", "event_type"]:
		var bad := data.duplicate(true)
		bad["event_store"]["events"][0][field] = 12345
		var target := MirrorFixtures.engine()
		ok(not target.load_json(JSON.stringify(bad)).get("ok", true), "event field %s corrupt rejected" % field)
	var bad_entry := data.duplicate(true)
	bad_entry["event_store"]["events"][0] = "not an event"
	ok(not MirrorFixtures.engine().load_json(JSON.stringify(bad_entry)).get("ok", true), "non-dictionary event entry rejected")
