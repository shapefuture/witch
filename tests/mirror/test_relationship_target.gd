extends TestCase

const T := MirrorDomain.ActionType

func _engine() -> MirrorEngine:
	var e := MirrorEngine.new()
	e.register_action({
		"id": "cast_on_machine", "action_type": T.CAST, "valid_targets": ["machine"],
		"response_contracts": [{
			"id": "r", "observed": {"outcome": "done"},
			"relationship_target": "tomas",
			"relationship_tags": ["BOUNDARY"], "relationship_payload": {"domain": "intervention", "boundary": {"unasked": "withdrew"}},
		}],
	})
	e.register_action({
		"id": "plain", "action_type": T.CUSTOM,
		"response_contracts": [{"id": "r", "observed": {"outcome": "done"}, "relationship_tags": ["NOTE"]}],
	})
	return e

func test_response_can_record_the_relationship_with_someone_other_than_the_target() -> void:
	var e := _engine()
	ok(e.resolve_action(MirrorFixtures.act("cast_on_machine", "machine", T.CAST))["ok"], "resolved")
	eq(e.relationships.get_relation("player", "tomas")["boundaries"]["intervention"], {"unasked": "withdrew"}, "recorded against Tomas")
	eq(e.relationships.get_relation("player", "machine"), {}, "nothing recorded against the machine")

func test_default_behaviour_is_unchanged() -> void:
	var e := _engine()
	e.resolve_action(MirrorFixtures.act("plain", "door", T.CUSTOM))
	eq(e.relationships.get_relation("player", "door")["events"].size(), 1, "still recorded against the action target")

func test_override_survives_save_and_replay() -> void:
	var e := _engine()
	e.resolve_action(MirrorFixtures.act("cast_on_machine", "machine", T.CAST))
	var e2 := _engine()
	var res := e2.load_json(e.save_json())
	ok(res.get("ok", false), "load: %s" % JSON.stringify(res))
	eq(MirrorHash.canonical_json(e2.projection_snapshot()), MirrorHash.canonical_json(e.projection_snapshot()), "replay reproduces the override")

func test_payload_key_absent_when_unused_so_existing_hashes_are_untouched() -> void:
	var e := _engine()
	e.resolve_action(MirrorFixtures.act("plain", "door", T.CUSTOM))
	var response_event: MirrorEvent = e.event_store.get_all()[1]
	ok(not response_event.payload.has("relationship_target"), "no new key unless the contract uses it")
