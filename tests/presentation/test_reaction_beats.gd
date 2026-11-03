extends TestCase

# Tone rule 4 (TONE_MAPPING section 4): within a reaction the comic beat comes first and the warm beat right after it,
# never in the same line.

func test_the_warm_beat_follows_the_last_comic_beat_and_the_plain_beats_keep_their_order() -> void:
	var beats := [
		{"reaction": "r1", "tone": "warm", "key": "w"},
		{"reaction": "r1", "tone": "plain", "key": "p"},
		{"reaction": "r1", "tone": "comic", "key": "c"},
	]
	var keys: Array = []
	for beat in ReactionBeats.ordered(beats):
		keys.append(str(beat["key"]))
	eq(keys, ["p", "c", "w"], "comic, then warm straight after it; the plain beat stays where it was")

func test_a_reaction_with_no_comic_beat_keeps_its_order() -> void:
	var beats := [{"reaction": "r2", "tone": "warm", "key": "w"}, {"reaction": "r2", "tone": "plain", "key": "p"}]
	var keys: Array = []
	for beat in ReactionBeats.ordered(beats):
		keys.append(str(beat["key"]))
	eq(keys, ["w", "p"], "nothing to answer: the order is the author's")

func test_the_checker_flags_a_warm_beat_in_the_comic_line_or_with_no_comic_before_it() -> void:
	eq(ReactionBeats.violations([{"reaction": "r", "tone": "comic", "key": "c"}, {"reaction": "r", "tone": "warm", "key": "c"}]).size(), 1, "same line: flagged")
	eq(ReactionBeats.violations([{"reaction": "r", "tone": "warm", "key": "w"}]).size(), 1, "no comic before it: flagged")
	eq(ReactionBeats.violations([{"reaction": "r", "tone": "comic", "key": "c"}, {"reaction": "r", "tone": "warm", "key": "w"}]).size(), 0, "comic then warm in its own line: fine")
