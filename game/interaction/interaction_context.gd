class_name InteractionContext
extends RefCounted

# Everything the resolver is allowed to consider for one target. World, knowledge,
# relationship and NPC-expectation state all come from the Mirror engine itself; the only
# things supplied from outside are who is acting, who they are pointing at, and what else is
# in reach (used to filter, never stored).

var target_id: String
var actor_id: String = "player"
var nearby: PackedStringArray = PackedStringArray()
# Extra semantic hints folded into the stored action context. Keep empty unless a rule really
# depends on it: anything here is recorded in the event log and so must be input-device
# independent (a tap and a click must produce the same action).
var hints: Dictionary = {}

func _init(p_target_id: String = "", p_actor_id: String = "player") -> void:
	target_id = p_target_id
	actor_id = p_actor_id

func action_context() -> Dictionary:
	return hints.duplicate(true)
