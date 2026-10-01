class_name MirrorValidator
extends RefCounted

func validate_project(root: String) -> Dictionary:
    var errors: Array = []
    var warnings: Array = []
    var files := _scan(root)
    for path in files:
        if path.ends_with(".json") and _read_json(path) == null:
            errors.append("Invalid JSON: " + path)
        if path.ends_with(".gd"):
            _validate_gd(path, errors, warnings)
    return {
        "ok": errors.is_empty(),
        "errors": errors,
        "warnings": warnings,
        "summary": "Mirror validation: %d errors, %d warnings, %d files." % [errors.size(), warnings.size(), files.size()],
        "files": files,
    }

func _scan(root: String) -> Array[String]:
    var out: Array[String] = []
    var dir := DirAccess.open(root)
    if dir == null:
        return out
    dir.list_dir_begin()
    while true:
        var name := dir.get_next()
        if name.is_empty():
            break
        if name.begins_with(".") or name in [".godot", ".cache", "__pycache__"]:
            continue
        var full := root.path_join(name)
        if dir.current_is_dir():
            out.append_array(_scan(full))
        else:
            out.append(full)
    dir.list_dir_end()
    return out

func _read_json(path: String) -> Variant:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return null
    return JSON.parse_string(file.get_as_text())

func validate_engine(engine: MirrorEngine) -> Dictionary:
    var report := engine.validate_catalog()
    for action_id in engine.action_definitions.keys():
        var d: Dictionary = engine.action_definitions[action_id]
        for response in d.get("response_contracts", []):
            for effect in response.get("knowledge_effects", []):
                if str(effect.get("id", "")).is_empty():
                    report["errors"].append("Action %s has knowledge effect without id" % action_id)
                if effect.get("proposition", {}).is_empty():
                    report["errors"].append("Action %s has knowledge effect without proposition" % action_id)
                var status := int(effect.get("status", MirrorDomain.EpistemicStatus.POSSIBLE))
                if MirrorDomain.epistemic_rank(status) >= MirrorDomain.epistemic_rank(MirrorDomain.EpistemicStatus.SUPPORTED) and Array(effect.get("evidence", [])).is_empty():
                    report["warnings"].append("Action %s relies on runtime event provenance for supported knowledge." % action_id)
            for effect in response.get("model_effects", []):
                if str(effect.get("type", "")).is_empty():
                    report["errors"].append("Action %s has model effect without type" % action_id)
        # NOTE: validate_catalog() already warns when a prediction candidate has no
        # `expected` block. Re-emitting that warning here made every such prediction
        # appear twice in the editor report, which reads as two distinct problems.
    report["ok"] = report["errors"].is_empty()
    return report

func _validate_gd(path: String, errors: Array, warnings: Array) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        errors.append("Unreadable GDScript: " + path)
        return
    var text := file.get_as_text()
    if text.count("func ") > 0 and text.count("->") == 0:
        warnings.append("Unannotated return types remain in: " + path)
