class_name TestCase
extends RefCounted

# Nodes created by fixtures (runtimes, UI) are freed after the whole run so the headless
# process exits without "instances leaked" noise, which the release gate treats as an error.
static var _tracked: Array[Node] = []

static func track(node: Node) -> Node:
	_tracked.append(node)
	return node

static func free_tracked() -> void:
	for node in _tracked:
		if is_instance_valid(node):
			node.free()
	_tracked.clear()

var assertions := 0
var failures: Array[String] = []
var _current := ""

func begin(test_name: String) -> void:
	_current = test_name

func ok(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append("[%s] %s" % [_current, message])

func eq(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("[%s] %s | expected=%s actual=%s" % [_current, message, JSON.stringify(expected), JSON.stringify(actual)])

func has_key(dict: Dictionary, key: Variant, message: String) -> void:
	ok(dict.has(key), "%s | missing key %s in %s" % [message, str(key), JSON.stringify(dict).left(200)])

func in_array(value: Variant, array: Array, message: String) -> void:
	ok(value in array, "%s | %s not in %s" % [message, str(value), JSON.stringify(array).left(200)])

func not_in_array(value: Variant, array: Array, message: String) -> void:
	ok(value not in array, "%s | %s unexpectedly in %s" % [message, str(value), JSON.stringify(array).left(200)])
