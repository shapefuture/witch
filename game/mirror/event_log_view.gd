class_name EventLogView
extends RefCounted

# Human-readable rendering of the canonical event log, for debugging and for diffing two
# playthroughs ("why did this run diverge?"). Purely a view: never feeds back into state.

static func describe(event: MirrorEvent) -> String:
	var stamp := "#%03d" % event.sequence
	match event.event_type:
		"ActionResolved":
			var action: Dictionary = event.payload.get("action", {})
			var prediction: Dictionary = event.payload.get("prediction", {})
			var expected := "" if prediction.is_empty() else "  (expected: %s)" % _short(prediction.get("expected", {}))
			return "%s %s -> %s: %s%s" % [stamp, event.actor_id, event.target_id if not event.target_id.is_empty() else "-", action.get("id", "?"), expected]
		"ResponseResolved":
			var observed: Dictionary = event.payload.get("observed", {})
			return "%s    %s responded [%s]: %s" % [stamp, event.actor_id, event.payload.get("response_id", "?"), _short(observed)]
		"DiscrepancyDetected":
			var kinds: Array = event.payload.get("kinds", [])
			var names: Array[String] = []
			for kind in kinds:
				names.append(_enum_name(MirrorDomain.DiscrepancyKind, int(kind)))
			return "%s    prediction missed: %s" % [stamp, ", ".join(names)]
		"TimeAdvanced":
			return "%s    time %d -> %d (%s)" % [stamp, int(event.payload.get("from", 0)), int(event.payload.get("to", 0)), event.payload.get("reason", "")]
		"ObservationRecorded":
			return "%s %s observed %s" % [stamp, event.actor_id, event.target_id]
		"KnowledgeShared":
			return "%s %s told %s about %s" % [stamp, event.actor_id, event.target_id, event.payload.get("claim_id", "?")]
		"OperatorAcquired":
			return "%s %s acquired operator %s" % [stamp, event.actor_id, event.payload.get("operator_id", "?")]
		"OperatorRevoked":
			return "%s %s lost operator %s" % [stamp, event.actor_id, event.payload.get("operator_id", "?")]
		"ContentConsumed":
			return "%s content consumed: %s" % [stamp, event.payload.get("storylet_id", "?")]
	return "%s %s" % [stamp, event.event_type]

static func describe_all(engine: MirrorEngine, last: int = 0) -> Array[String]:
	var lines: Array[String] = []
	var events := engine.event_store.get_all()
	var start := 0 if last <= 0 else maxi(0, events.size() - last)
	for i in range(start, events.size()):
		lines.append(describe(events[i]))
	return lines

static func _short(dict: Dictionary) -> String:
	var parts: Array[String] = []
	for key in dict.keys():
		parts.append("%s=%s" % [key, str(dict[key])])
	return "{" + ", ".join(parts) + "}"

static func _enum_name(table: Dictionary, value: int) -> String:
	for key in table.keys():
		if int(table[key]) == value:
			return str(key).to_lower()
	return str(value)
