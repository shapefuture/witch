class_name MindsFixtures
extends RefCounted

# A tiny world for the Minds tests: a room with a door and a bell, a hall next door, and four minds. It is
# deliberately NOT the game's content (that is data/mirror/minds, tested by test_hall_rules.gd); it exists
# to exercise each mechanism on its own with the smallest data that shows it.
#
#   ana, bo   people in the room (the "house" community)     cat   lives in the hall next door (overhears)
#   player    the witch                                      KNOCK a thump on a prop; ECHO its answer

class Rig extends RefCounted:
	var engine: MirrorEngine
	var minds: MirrorMinds
	var raw: Dictionary

static func raw() -> Dictionary:
	return {
		"default_place": "room",
		"limits": {"max_pending": 8, "max_fired_per_pump": 16, "max_chain_depth": 3, "max_active_conventions": 4, "max_origin_events": 3},
		"event_kinds": {
			"KNOCK": {"channels": {"sight": {"range": 10}, "sound": {"range": 8, "carries": true}}, "truth": {"outcome": "knocked"}},
			"ECHO": {"channels": {"sight": {"range": 10}}, "truth": {"outcome": "knocked"}},
			"QUIET": {"quiet": true, "channels": {"sight": {"range": 10}}, "truth": {"outcome": "stirred"}},
		},
		"places": {
			"room": {"adjacent": ["hall"], "subjects": {"door": {"tags": ["wood"]}, "bell": {"tags": ["brass"]}}},
			"hall": {"adjacent": ["room"], "subjects": {}},
		},
		"holders": {
			"player": {"place": "room", "tags": ["witch"]},
			"ana": {"place": "room", "tags": ["person"]},
			"bo": {"place": "room", "tags": ["person"]},
			"cat": {"place": "hall", "tags": ["animal"]},
		},
		"communities": {"house": {"members": ["ana", "bo"]}},
		"interpretations": [
			{"id": "i.player.sees", "event_kind": "KNOCK", "holder": "player", "knowledge_effects": [{"id": "player_saw.$subject", "proposition": {"saw": "$subject"}, "status": "SUPPORTED"}]},
			{"id": "i.ana.rude", "event_kind": "KNOCK", "holder": "ana", "priority": 10, "min_clarity": 40, "reads": "rude", "perceived": {"actor_id": "$actor", "outcome": "knocked"},
				"knowledge_effects": [{"id": "ana_saw.$subject", "proposition": {"rude": "$actor"}, "status": "SUPPORTED"}]},
			{"id": "i.bo.game", "event_kind": "KNOCK", "holder": "bo", "priority": 10, "min_clarity": 40, "reads": "game", "perceived": {"actor_id": "$actor", "outcome": "knocked"},
				"knowledge_effects": [{"id": "bo_saw.$subject", "proposition": {"game": "$actor"}, "status": "SUPPORTED"}]},
			{"id": "i.bo.serious", "event_kind": "KNOCK", "holder": "bo", "priority": 20, "min_clarity": 40, "when": {"npc.bo.stance": "grim"}, "reads": "serious", "perceived": {"actor_id": "$actor", "outcome": "knocked"}},
			{"id": "i.cat.heard", "event_kind": "KNOCK", "holder": "cat", "channels": ["overheard"], "priority": 5, "reads": "noise", "perceived": {"actor_id": "ana", "outcome": "knocked"},
				"knowledge_effects": [{"id": "cat_heard_ana", "proposition": {"ana": "knocked"}, "status": "POSSIBLE"}]},
		],
		"rules": [],
		"conventions": [],
		"initial_beliefs": [],
	}

# door -> bell: a knock on the door is answered by the bell after `delay`, with the same move.
static func echo_rule(delay: int = 3, policy: String = "replace") -> Dictionary:
	return {
		"id": "rule.t.echo", "label_key": "x", "domain": "temporal", "learnable": true,
		"invariant": {"relation": "answers_later", "polarity": "+", "roles": ["q", "a"], "constraints": {"delay_min": 1}},
		"variants": [{
			"id": "t.door_bell", "domain": "physical", "form": "direct", "source": "door",
			"relation": {"id": "answers_later", "polarity": "+", "bindings": {"q": "door", "a": "bell"}},
			"trigger": {"event_kind": "KNOCK", "subject": "door"},
			"transformation": {"schedule": [{"delay": delay, "event": {"kind": "ECHO", "actor": "world", "subject": "bell", "data": {"reaction": "$reaction", "answers": "$subject"}}, "key": "echo", "if_pending": policy}]},
			"evidence": {"holders": ["player"], "at": "consequence", "knowledge_effects": [{"id": "echo.$data_answers", "proposition": {"answered_by": "$subject"}, "status": "SUPPORTED"}]},
		}],
	}

# Two minds reading a knock on the door the same way, three times, make it a custom.
static func door_convention(extra_force: Dictionary = {}) -> Dictionary:
	var force: Dictionary = {"bias": 20, "enables_operators": []}
	force.merge(extra_force, true)
	return {
		"id": "conv.t.door_is_a_game", "label_key": "x", "community": "house", "reads": "game", "subjects": ["door"], "event_kinds": ["KNOCK"],
		"origin": {"event_kinds": ["KNOCK"], "fed_by": ["i.bo.game"]},
		"adopt": {"threshold": 3, "min_holders": 2}, "cap": 5, "decay": {"every": 20, "amount": 1}, "retire_at": 0,
		"force": force,
	}

static func rig(raw_data: Dictionary = {}, engine: MirrorEngine = null) -> Rig:
	var made := Rig.new()
	made.raw = raw_data if not raw_data.is_empty() else raw()
	made.engine = engine if engine != null else MirrorEngine.new()
	var built := MindsCatalog.build(made.raw.duplicate(true))
	assert(built["errors"].is_empty(), "fixture data: %s" % JSON.stringify(built["errors"]))
	made.minds = MirrorMinds.new(made.engine, built["data"])
	return made

static func knock(subject: String = "door", actor: String = "player", hints: Dictionary = {}, reaction: String = "hop") -> Dictionary:
	return {"kind": "KNOCK", "actor": actor, "subject": subject, "data": {"reaction": reaction}, "hints": hints}
