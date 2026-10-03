class_name MindsTemplate
extends RefCounted

# `$name` substitution for authored effects, so one interpretation rule or world-rule variant serves every
# holder and every prop. Only String values are rewritten (never dictionary keys), and only `$name` tokens
# that exist in `vars`; an unknown token is left alone so the linter can report it.

const VARIABLES := ["holder", "actor", "subject", "place", "kind", "channel", "time", "reaction"]

static func apply(value: Variant, vars: Dictionary) -> Variant:
	if value is String:
		return _text(value, vars)
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(apply(item, vars))
		return items
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value.keys():
			out[key] = apply(value[key], vars)
		return out
	return value

# Every `$token` in a structure, so a linter can check them against what a context actually provides.
static func tokens(value: Variant, out: Array = []) -> Array:
	if value is String:
		var pattern := RegEx.create_from_string("\\$([a-z_][a-z0-9_]*)")
		for found in pattern.search_all(value):
			var token_name := found.get_string(1)
			if token_name not in out:
				out.append(token_name)
	elif value is Array:
		for item in value:
			tokens(item, out)
	elif value is Dictionary:
		for key in value.keys():
			tokens(value[key], out)
	return out

static func _text(text: String, vars: Dictionary) -> String:
	if not text.contains("$"):
		return text
	var names: Array = vars.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool:
		var la := str(a).length()
		var lb := str(b).length()
		if la == lb:
			return str(a) < str(b)
		return la > lb)
	for token_name in names:
		text = text.replace("$" + str(token_name), str(vars[token_name]))
	return text
