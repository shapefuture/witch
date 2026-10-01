class_name MirrorDialogueContext
extends RefCounted

# The only window .dialogue files have onto game state. It is READ-ONLY: dialogue decides
# what is SAID given what Mirror says is TRUE, and never the other way round.
# (Mutations go back through DialogueBridge -> Mirror as recorded actions.)

var engine: MirrorEngine
var player_id := "player"

func _init(p_engine: MirrorEngine) -> void:
	engine = p_engine

func can_ask(actor_id: String, topic_id: String) -> bool:
	for definition in engine.get_affordances(actor_id, {}, player_id):
		if int(definition.get("action_type", -1)) == MirrorDomain.ActionType.ASK and str(definition.get("topic", "")) == topic_id:
			return true
	return false

func has_knowledge(claim_id: String, holder_id: String = "player") -> bool:
	return engine.knowledge.has(claim_id, holder_id)

# Dotted path into the recorded relationship, e.g. relationship_value("tomas", "boundaries.intervention").
# Returns null when nothing was recorded. Deliberately NOT a numeric "trust" score.
func relationship_value(actor_id: String, key: String) -> Variant:
	return MirrorConditions.read_path(engine.relationships.get_relation(player_id, actor_id), key, null)

func expected_action(actor_id: String) -> String:
	return Expectation.of(engine, actor_id)

# The id of the most recent event of this type, or "".
func last_event(event_type: String) -> String:
	var events := engine.event_store.get_all()
	for i in range(events.size() - 1, -1, -1):
		if events[i].event_type == event_type:
			return events[i].event_id
	return ""
