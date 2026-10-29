class_name ReactionBeats
extends RefCounted

# Tone rule 4 (TONE_MAPPING section 4): warmth after the laugh. Within one reaction, the comic beat comes first and the
# warm beat follows it, never in the same line. Beats are {reaction, tone, key}; tone is "comic", "warm" or "plain".
# Plain beats keep their order.

# The beats in presentation order: each reaction's warm beats are moved to directly after its last comic beat. A
# reaction with no comic beat keeps its own order.
static func ordered(beats: Array) -> Array:
	var order: Array = []
	var groups: Dictionary = {}
	for beat in beats:
		var reaction := str(beat.get("reaction", ""))
		if not groups.has(reaction):
			groups[reaction] = []
			order.append(reaction)
		(groups[reaction] as Array).append(beat)
	var out: Array = []
	for reaction in order:
		var seq: Array = groups[reaction]
		var warm: Array = seq.filter(func(b: Dictionary) -> bool: return str(b.get("tone", "")) == "warm")
		var rest: Array = seq.filter(func(b: Dictionary) -> bool: return str(b.get("tone", "")) != "warm")
		var last_comic := -1
		for i in rest.size():
			if str(rest[i].get("tone", "")) == "comic":
				last_comic = i
		if last_comic < 0:
			out.append_array(seq)
			continue
		out.append_array(rest.slice(0, last_comic + 1))
		out.append_array(warm)
		out.append_array(rest.slice(last_comic + 1))
	return out

# Problems with a reaction's beats in the order they are given: a warm beat with no comic beat before it, or a warm beat
# in the same line as the comic beat it answers.
static func violations(beats: Array) -> Array:
	var out: Array = []
	var last_comic: Dictionary = {}
	for beat in beats:
		var reaction := str(beat.get("reaction", ""))
		match str(beat.get("tone", "")):
			"comic":
				last_comic[reaction] = beat
			"warm":
				if not last_comic.has(reaction):
					out.append("%s: warm beat %s has no comic beat before it" % [reaction, str(beat.get("key", ""))])
				elif str(last_comic[reaction].get("key", "")) == str(beat.get("key", "")):
					out.append("%s: warm beat %s is in the same line as the comic beat" % [reaction, str(beat.get("key", ""))])
	return out
