extends TestCase

func _engine_and_report() -> Dictionary:
	GameFixtures.ensure_localization()
	return MirrorCatalog.build_engine()

func test_authored_catalog_loads_clean() -> void:
	var built := _engine_and_report()
	var report: Dictionary = built["report"]
	eq(report["errors"], [], "no errors")
	eq(report["warnings"], [], "no warnings")
	var engine: MirrorEngine = built["engine"]
	eq(engine.action_definitions.size(), 15, "15 authored actions")
	ok(MirrorValidator.new().validate_engine(engine)["ok"], "engine-level validator agrees")

func test_catalog_contains_ids_and_keys_but_no_prose() -> void:
	var engine: MirrorEngine = _engine_and_report()["engine"]
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	var text := JSON.stringify(engine._catalog())
	ok(cyrillic.search(text) == null, "no Russian prose inside the Mirror catalog: rewording text must never change the fingerprint")

func test_every_referenced_text_key_exists() -> void:
	var engine: MirrorEngine = _engine_and_report()["engine"]
	var table := Localization.load_table()
	var missing: Array[String] = []
	for id in engine.action_definitions.keys():
		var definition: Dictionary = engine.action_definitions[id]
		if not definition.get("hidden", false) and not table.has(str(definition.get("label_key", ""))):
			missing.append("label:%s" % id)
		for response in definition.get("response_contracts", []):
			for entry in response.get("presentation", []):
				if entry.get("kind", "") == "line" and not table.has(str(entry.get("key", ""))):
					missing.append("line:%s" % entry.get("key", ""))
	for storylet in engine.storylet_definitions.values():
		for entry in storylet.get("presentation", []):
			if entry.get("kind", "") == "line" and not table.has(str(entry.get("key", ""))):
				missing.append("line:%s" % entry.get("key", ""))
	eq(missing, [], "missing text keys")

func test_every_dialogue_title_exists_in_the_conversation_file() -> void:
	var engine: MirrorEngine = _engine_and_report()["engine"]
	var source := FileAccess.get_file_as_string("res://data/conversations/tomas.dialogue")
	var titles := {}
	for line in source.split("\n"):
		if line.begins_with("~ "):
			titles[line.substr(2).strip_edges()] = true
	var missing: Array[String] = []
	for definition in engine.action_definitions.values():
		for response in definition.get("response_contracts", []):
			for entry in response.get("presentation", []):
				if entry.get("kind", "") == "dialogue" and not titles.has(str(entry.get("title", ""))):
					missing.append(str(entry.get("title", "")))
	eq(missing, [], "dialogue titles referenced but not written")

func test_labels_are_russian_prose_not_keys_and_never_expose_the_ontology() -> void:
	var r := GameFixtures.runtime()
	var cyrillic := RegEx.create_from_string("[\\x{0400}-\\x{04FF}]")
	var ontology := ["LOOK", "ASK", "SHOW", "WAIT", "GO", "CAST", "CUSTOM"]
	for target in ["tomas", "machine", "bell", "path_out"]:
		for option in r.options_for(target):
			ok(cyrillic.search(option.label) != null, "label for %s is Russian prose: %s" % [option.action_id, option.label])
			ok(not option.label.begins_with("opt."), "label key resolved: %s" % option.label)
			for word in ontology:
				ok(word not in option.label.to_upper().split(" "), "label must not expose '%s': %s" % [word, option.label])

func test_catalog_fingerprint_is_stable_across_builds() -> void:
	var a: MirrorEngine = _engine_and_report()["engine"]
	var b: MirrorEngine = _engine_and_report()["engine"]
	eq(a.compute_catalog_fingerprint(), b.compute_catalog_fingerprint(), "deterministic fingerprint")

func test_enum_names_in_json_are_normalised_and_bad_names_are_reported() -> void:
	var errors: Array = []
	var definition := {"id": "x", "action_type": "NOT_A_TYPE", "response_contracts": [{"id": "r", "knowledge_effects": [{"id": "c", "status": "WRONG"}]}]}
	MirrorCatalog._normalize_action(definition, errors, [])
	eq(errors.size(), 2, "both unknown enum names reported, not silently zeroed")
	var ok_def := {"id": "y", "action_type": "CAST", "response_contracts": [{"id": "r", "knowledge_effects": [{"id": "c", "status": "SUPPORTED"}]}]}
	MirrorCatalog._normalize_action(ok_def, [], [])
	eq(ok_def["action_type"], MirrorDomain.ActionType.CAST, "CAST resolved")
	eq(ok_def["response_contracts"][0]["knowledge_effects"][0]["status"], MirrorDomain.EpistemicStatus.SUPPORTED, "SUPPORTED resolved")

func test_fixed_evidence_ids_in_repeatable_actions_are_rejected_at_load() -> void:
	var errors: Array = []
	MirrorCatalog._normalize_action({"id": "x", "response_contracts": [{"id": "r", "evidence": [{"id": "fixed"}]}]}, errors, [])
	eq(errors.size(), 1, "a fixed id would conflict on the second firing")
	var once_errors: Array = []
	MirrorCatalog._normalize_action({"id": "x", "once_key": "k", "response_contracts": [{"id": "r", "evidence": [{"id": "fixed"}]}]}, once_errors, [])
	eq(once_errors.size(), 0, "fine when the action can only fire once")
