class_name MirrorConditions
extends RefCounted

# Small deterministic authoring DSL shared by actions, predictions, responses, planners,
# transfers and storylets. Plain dictionaries remain the authoring surface.

# Named read_path, not get_path: a static `get_path` on a GDScript class shadows the built-in
# Resource.get_path(), so MirrorConditions.get_path(...) could not be called from outside the
# class at all ("Invalid call ... Expected 0 argument(s)"). Internal callers masked the bug.
static func read_path(root: Dictionary, path: String, default_value: Variant = null) -> Variant:
    if path.is_empty():
        return root
    var current: Variant = root
    for part in path.split("."):
        if current is Dictionary and current.has(part):
            current = current[part]
        else:
            return default_value
    return current

static func has_path(root: Dictionary, path: String) -> bool:
    # The previous implementation compared the looked-up value with a freshly allocated
    # Object sentinel. That raised "Invalid operands 'int' and 'Object'" whenever the value at
    # the path was a number (or similar), and leaked one Object per call.
    if path.is_empty():
        return true
    return bool(_lookup(root, path)["exists"])

# GDScript raises "Invalid operands" for some cross-type comparisons (for example
# bool == Dictionary), which surfaces as a SCRIPT ERROR on stderr even though the
# logically correct answer is simply "not equal". A scalar requirement can never
# equal dictionary-shaped state, so incomparable types are treated as unequal
# instead of emitting an engine error. Results are unchanged; the noise is not.
static func _safe_equals(a: Variant, b: Variant) -> bool:
    var ta := typeof(a)
    var tb := typeof(b)
    if ta != tb:
        var numeric := [TYPE_INT, TYPE_FLOAT]
        var textual := [TYPE_STRING, TYPE_STRING_NAME]
        if not (ta in numeric and tb in numeric) and not (ta in textual and tb in textual):
            return false
    return a == b

static func matches(requirements: Variant, actual: Dictionary) -> bool:
    if not requirements is Dictionary:
        return _safe_equals(requirements, actual)
    return _eval(requirements, actual)

static func explain_failures(requirements: Variant, actual: Dictionary, prefix: String = "") -> Array:
    var failures: Array = []
    _explain(requirements, actual, prefix, failures)
    return failures


static func complexity(requirements: Variant) -> int:
    # Yarn-inspired structural complexity: authors can use it for deterministic
    # saliency without turning the engine into a hidden numeric relationship system.
    if not requirements is Dictionary:
        return 1
    var total := 0
    for key in requirements.keys():
        var op := str(key)
        var value: Variant = requirements[key]
        match op:
            "$all", "$any":
                total += 1
                if value is Array:
                    for child in value:
                        total += complexity(child)
            "$not":
                total += 1 + complexity(value)
            "$eq", "$neq", "$in", "$nin", "$exists", "$contains", "$gt", "$gte", "$lt", "$lte":
                total += 1
                if value is Dictionary:
                    total += value.size()
            _:
                total += 1 + complexity(value)
    return total

static func validate(requirements: Variant, path: String = "") -> Array:
    var errors: Array = []
    _validate(requirements, path, errors)
    return errors

static func _validate(node: Variant, path: String, errors: Array) -> void:
    if not node is Dictionary:
        return
    for key in node.keys():
        var op := str(key)
        var full := path if path.is_empty() else path + "." + op
        var value: Variant = node[key]
        if op == "$all" or op == "$any":
            if not value is Array:
                errors.append(full + ":expected_array")
                continue
            for i in range(value.size()):
                _validate(value[i], full + "." + str(i), errors)
        elif op == "$not":
            _validate(value, full, errors)
        elif op in ["$eq", "$neq", "$in", "$nin", "$exists", "$contains", "$gt", "$gte", "$lt", "$lte"]:
            if not value is Dictionary:
                errors.append(full + ":expected_dictionary")
            elif op == "$in" or op == "$nin":
                for sub_path in value.keys():
                    if not value[sub_path] is Array:
                        errors.append(full + "." + str(sub_path) + ":expected_array")
            elif op == "$exists":
                for sub_path in value.keys():
                    if not (value[sub_path] is bool):
                        errors.append(full + "." + str(sub_path) + ":expected_boolean")
        elif op.begins_with("$"):
            errors.append(full + ":unknown_operator")
        else:
            _validate(value, full, errors)

static func _eval(node: Dictionary, actual: Dictionary) -> bool:
    for key in node.keys():
        var value: Variant = node[key]
        var path := str(key)
        match path:
            "$all":
                if not value is Array:
                    return false
                for child in value:
                    if not matches(child, actual): return false
            "$any":
                if not value is Array:
                    return false
                var ok := false
                for child in value:
                    if matches(child, actual):
                        ok = true
                        break
                if not ok: return false
            "$not":
                if matches(value, actual): return false
            "$eq":
                if not _compare_map(value, actual, "eq"): return false
            "$neq":
                if not _compare_map(value, actual, "neq"): return false
            "$in":
                if not _compare_map(value, actual, "in"): return false
            "$nin":
                if not _compare_map(value, actual, "nin"): return false
            "$exists":
                if not _compare_map(value, actual, "exists"): return false
            "$contains":
                if not _compare_map(value, actual, "contains"): return false
            "$gt", "$gte", "$lt", "$lte":
                if not _compare_map(value, actual, path.substr(1)): return false
            _:
                var expected: Variant = value
                var info := _lookup(actual, path)
                if not bool(info["exists"]) or not _safe_equals(info["value"], expected):
                    return false
    return true

static func _compare_map(value: Variant, actual: Dictionary, op: String) -> bool:
    if value is Dictionary:
        for path in value.keys():
            if not _compare_one(actual, str(path), value[path], op): return false
        return true
    return false

static func _compare_one(actual: Dictionary, path: String, expected: Variant, op: String) -> bool:
    var info := _lookup(actual, path)
    var exists := bool(info["exists"])
    var current: Variant = info["value"]
    match op:
        "exists": return exists == bool(expected)
        "eq": return exists and _safe_equals(current, expected)
        "neq": return (not exists) or not _safe_equals(current, expected)
        "in": return exists and expected is Array and current in expected
        "nin": return (not exists) or (expected is Array and current not in expected)
        "contains": return exists and _contains(current, expected)
        "gt": return exists and _ordered(current, expected, 1)
        "gte": return exists and _ordered(current, expected, 2)
        "lt": return exists and _ordered(current, expected, -1)
        "lte": return exists and _ordered(current, expected, -2)
    return false

static func _ordered(a: Variant, b: Variant, mode: int) -> bool:
    if not ((a is int or a is float) and (b is int or b is float)):
        if not (a is String and b is String): return false
    if mode == 1: return a > b
    if mode == 2: return a >= b
    if mode == -1: return a < b
    return a <= b

static func _contains(container: Variant, wanted: Variant) -> bool:
    if container is Array: return wanted in container
    if container is Dictionary: return container.has(wanted)
    if container is String: return str(wanted) in container
    return false

static func _lookup(root: Dictionary, path: String) -> Dictionary:
    var current: Variant = root
    for part in path.split("."):
        if current is Dictionary and current.has(part):
            current = current[part]
        else:
            return {"exists": false, "value": null}
    return {"exists": true, "value": current}

static func _explain(node: Variant, actual: Dictionary, prefix: String, out: Array) -> void:
    if not node is Dictionary:
        if not matches(node, actual): out.append({"path": prefix, "reason": "value_mismatch"})
        return
    for key in node.keys():
        var path := str(key)
        var full := prefix if prefix.is_empty() else prefix + "." + path
        var value = node[key]
        match path:
            "$all":
                if not value is Array:
                    out.append({"path": full, "reason": "expected_array"})
                else:
                    for child in value: _explain(child, actual, full, out)
            "$any":
                if not matches({"$any": value}, actual): out.append({"path": full, "reason": "no_any_branch_matched"})
            "$not":
                if matches(value, actual): out.append({"path": full, "reason": "negation_matched"})
            "$eq", "$neq", "$in", "$nin", "$exists", "$contains", "$gt", "$gte", "$lt", "$lte":
                # Mirrors the guard _validate() already has. A comparison operator must
                # carry a Dictionary of path -> expected value. Without this guard
                # value.keys() raised "Nonexistent function 'keys' in base 'bool'",
                # which unwound _explain and returned a TRUNCATED array: explain_action
                # then reported available:true for an unparseable condition and
                # get_affordances() offered that action to the player.
                if not value is Dictionary:
                    out.append({"path": full, "reason": "expected_dictionary"})
                else:
                    for sub_path in value.keys():
                        if not _compare_one(actual, str(sub_path), value[sub_path], path.substr(1)):
                            out.append({"path": str(sub_path), "reason": path.substr(1), "expected": value[sub_path], "actual": read_path(actual, str(sub_path), null)})
            _:
                var info := _lookup(actual, path)
                if not bool(info["exists"]) or not _safe_equals(info["value"], value):
                    out.append({"path": full, "reason": "equals", "expected": value, "actual": info["value"]})
