extends TestCase

# architecture/constitution.json is executable: every invariant is well formed, and every one marked verified points at
# a test function that exists, so the gate runs it. Pending invariants are reported, not failed, until the release gate.

const PATH := "res://architecture/constitution.json"
const CLASSES := ["hard", "recoverable", "soft"]
const STATUSES := ["verified", "pending", "review"]

func _invariants() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	ok(parsed is Dictionary, "the constitution is a JSON object")
	return (parsed as Dictionary).get("invariants", []) if parsed is Dictionary else []

func test_every_invariant_is_well_formed_and_unique() -> void:
	var ids: Dictionary = {}
	for invariant: Dictionary in _invariants():
		var id := str(invariant.get("id", ""))
		ok(not id.is_empty() and not ids.has(id), "%s: a unique id" % id)
		ids[id] = true
		in_array(invariant.get("class", ""), CLASSES, "%s: a known class" % id)
		in_array(invariant.get("status", ""), STATUSES, "%s: a known status" % id)
		ok(not str(invariant.get("statement", "")).is_empty(), "%s: states what must hold" % id)
		ok(not str(invariant.get("verifier", "")).is_empty(), "%s: names its verifier" % id)
	ok(ids.size() >= 20, "the constitution lists its invariants (%d)" % ids.size())

func test_every_verified_invariant_points_at_a_test_that_exists() -> void:
	var pending: Array[String] = []
	for invariant: Dictionary in _invariants():
		var id := str(invariant.get("id", ""))
		var verifier := str(invariant.get("verifier", ""))
		if invariant.get("status", "") == "pending":
			pending.append(id)
		if invariant.get("status", "") != "verified":
			continue
		var parts := verifier.split("::")
		ok(parts.size() == 2 and FileAccess.file_exists(parts[0]), "%s: the verifier's file exists (%s)" % [id, verifier])
		if parts.size() == 2 and FileAccess.file_exists(parts[0]):
			ok(FileAccess.get_file_as_string(parts[0]).contains("func %s(" % parts[1]), "%s: the verifier function exists (%s)" % [id, parts[1]])
	print("CONSTITUTION: %d pending: %s" % [pending.size(), ", ".join(pending)])
