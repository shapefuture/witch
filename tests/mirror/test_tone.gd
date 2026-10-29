extends TestCase

# Tone rule 3 (TONE_MAPPING section 4): no verbal concession anywhere in the authored catalog.

func test_the_authored_catalog_never_concedes_an_argument() -> void:
	var found := ToneLint.scan(AlivenessLint.load_catalog())
	eq(found, [], "no banned concession outcome in the authored data")

func test_the_linter_catches_a_concession_when_one_is_written() -> void:
	var found := ToneLint.scan({"responses": [{"outcome": "you_were_right"}]})
	eq(found.size(), 1, "a 'you were right' outcome is flagged, at its path")
