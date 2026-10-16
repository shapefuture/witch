extends TestCase

# Spike: does a StringName key or value change anything the engine hashes? The engine hashes
# through MirrorHash.canonical_json (JSON text) and also uses Godot's builtin Dictionary.hash()
# as an in-process catalog stamp. A save round trip turns every StringName into a String, so any
# difference between the two forms would make a live hash disagree with a reloaded one.

func test_canonical_json_ignores_string_name_versus_string_keys() -> void:
	var as_string := {"id": "look_bell", "nested": {"stance": "braced"}}
	var as_name := {&"id": &"look_bell", "nested": {&"stance": &"braced"}}
	eq(MirrorHash.canonical_json(as_name), MirrorHash.canonical_json(as_string), "StringName keys and values canonicalise to the same JSON")
	eq(MirrorHash.sha256(as_name), MirrorHash.sha256(as_string), "and therefore to the same sha256")

func test_a_string_name_and_a_string_key_are_one_dictionary_key() -> void:
	var d := {"a": 1}
	d[&"a"] = 2
	eq(d.size(), 1, "Godot treats &\"a\" and \"a\" as the same key, so canonical() never sees both")

func test_builtin_dictionary_hash_is_type_insensitive() -> void:
	eq({"a": 1}.hash(), {&"a": 1}.hash(), "builtin Dictionary.hash() (the catalog stamp) does not see key type")
	eq({"a": "x"}.hash(), {"a": &"x"}.hash(), "nor value type")

func test_engine_catalog_stamp_does_not_depend_on_key_type_after_a_round_trip() -> void:
	var engine: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	var catalog: Dictionary = engine._catalog()
	var reloaded: Variant = JSON.parse_string(JSON.stringify(catalog))
	eq(MirrorHash.sha256(catalog), MirrorHash.sha256(reloaded), "the catalog's fingerprint survives a JSON round trip")
	var again: MirrorEngine = MirrorCatalog.build_engine()["engine"]
	eq(again._catalog().hash(), catalog.hash(), "the stamp is stable across two builds in one process")

func test_a_resource_built_definition_hashes_like_a_dictionary_built_one() -> void:
	# The only StringName surfaces are @export ids on the resource classes; to_definition() must
	# turn them into Strings before the engine hashes or stores them.
	var resource := MirrorActionResource.new()
	resource.id = &"look_probe"
	resource.action_type = MirrorDomain.ActionType.LOOK
	resource.valid_targets = PackedStringArray(["bell"])
	var definition: Dictionary = resource.to_definition()
	eq(typeof(definition["id"]), TYPE_STRING, "the id is a String, not a StringName")
	var built := {"id": "look_probe", "action_type": MirrorDomain.ActionType.LOOK, "valid_targets": ["bell"]}
	eq(MirrorHash.sha256(definition["valid_targets"]), MirrorHash.sha256(built["valid_targets"]), "packed targets hash like plain targets")
	eq(MirrorHash.canonical_json(definition["id"]), MirrorHash.canonical_json("look_probe"), "and the id hashes like the plain string")
