class_name ToneLint
extends RefCounted

# Tone rule 3 (TONE_MAPPING section 4): no verbal concession. An NPC never answers with an outcome that concedes the
# argument ("you were right") or hands the verdict to the witch: a dispute ends in a shared beat, not a win. Checked
# over every string in the authored catalog, so a banned outcome name cannot reach a response contract unnoticed.

const BANNED := ["concede", "you_were_right", "admit_defeat", "verdict_witch", "witch_wins", "yield_argument"]

# Every banned token found in any string of `value`, as "path: token". Recurses through dictionaries and arrays.
static func scan(value: Variant, path: String = "") -> Array:
	var out: Array = []
	if value is Dictionary:
		for key in value.keys():
			out.append_array(scan(value[key], "%s/%s" % [path, str(key)]))
	elif value is Array:
		for i in (value as Array).size():
			out.append_array(scan(value[i], "%s[%d]" % [path, i]))
	elif value is String:
		var text := str(value).to_lower()
		for token in BANNED:
			if text.contains(token):
				out.append("%s: %s" % [path, token])
	return out
