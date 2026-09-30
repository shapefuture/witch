class_name Expectation
extends RefCounted

# An NPC's hidden variable is not "trust = 67". It is what they currently expect the witch
# to DO, drawn from a small fixed vocabulary. Stored in the Mirror engine's npc_state.

const SIGNATURES: Array[String] = [
	"EXPECT_COMPLIANCE", "EXPECT_PERMISSION", "EXPECT_DISTANCE", "EXPECT_CURIOSITY", "EXPECT_MAGIC",
	"EXPECT_WITHDRAWAL", "EXPECT_RECIPROCITY", "EXPECT_CHALLENGE", "EXPECT_INDEPENDENCE",
]

static func of(engine: MirrorEngine, npc_id: String) -> String:
	return str(engine.get_npc_state(npc_id).get("expects", ""))

static func is_valid(signature: String) -> bool:
	return signature in SIGNATURES

# The EXPECT_* token an action carries in its prediction_signature, or "".
static func signature_of_action(definition: Dictionary) -> String:
	for token in definition.get("prediction_signature", []):
		if str(token).begins_with("EXPECT_"):
			return str(token)
	return ""
