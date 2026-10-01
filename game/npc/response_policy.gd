class_name ResponsePolicy
extends RefCounted

# How an NPC reacts is a function of the GAP between what they expect and what the witch does:
#
#   confirmed -> low engagement (resignation, routine)
#   violated  -> attention: surprise, disclosure, invitation, withdrawal
#   neutral   -> passive acts (looking) that do not engage the expectation at all
#
# The authored response contracts in data/mirror/ are the source of truth. This classifier
# exists so tests, the debug panel and content validation can state, in one place, which side
# of that gap an action lands on.

enum Kind { NEUTRAL, CONFIRMED, VIOLATED }

const PASSIVE: Array[String] = ["EXPECT_CURIOSITY"]

static func classify(expects: String, action_signature: String) -> Kind:
	if expects.is_empty() or action_signature.is_empty() or action_signature in PASSIVE:
		return Kind.NEUTRAL
	return Kind.CONFIRMED if expects == action_signature else Kind.VIOLATED

static func name_of(kind: Kind) -> String:
	return Kind.keys()[kind].to_lower()

static func classify_action(engine: MirrorEngine, npc_id: String, action_id: String) -> Kind:
	var definition: Dictionary = engine.action_definitions.get(action_id, {})
	return classify(Expectation.of(engine, npc_id), Expectation.signature_of_action(definition))
