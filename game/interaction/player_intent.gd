class_name PlayerIntent
extends RefCounted

# The single input abstraction. Touch and mouse are translated into the same four intents
# before anything else happens, so "tap object" and "click object" are semantically identical
# by construction and can be tested as such.

enum Type { MOVE_TO, INSPECT, CHOOSE, CANCEL }

var type: Type = Type.CANCEL
var position: Vector3 = Vector3.ZERO
var target_id: String = ""
var option_id: String = ""
# "mouse" / "touch" / "sim": provenance for debugging only. Never part of the meaning.
var source: String = ""

static func move_to(p_position: Vector3, p_source: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new()
	intent.type = Type.MOVE_TO
	intent.position = p_position
	intent.source = p_source
	return intent

static func inspect(p_target_id: String, p_position: Vector3 = Vector3.ZERO, p_source: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new()
	intent.type = Type.INSPECT
	intent.target_id = p_target_id
	intent.position = p_position
	intent.source = p_source
	return intent

static func choose(p_target_id: String, p_option_id: String, p_source: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new()
	intent.type = Type.CHOOSE
	intent.target_id = p_target_id
	intent.option_id = p_option_id
	intent.source = p_source
	return intent

static func cancel(p_source: String = "") -> PlayerIntent:
	var intent := PlayerIntent.new()
	intent.type = Type.CANCEL
	intent.source = p_source
	return intent

# Device-independent meaning, positions quantised to a millimetre.
func semantic() -> Dictionary:
	var out := {"type": Type.keys()[type], "target_id": target_id, "option_id": option_id}
	if type == Type.MOVE_TO or type == Type.INSPECT:
		out["position"] = [snappedf(position.x, 0.001), snappedf(position.y, 0.001), snappedf(position.z, 0.001)]
	return out

func same_meaning(other: PlayerIntent) -> bool:
	return other != null and semantic() == other.semantic()
