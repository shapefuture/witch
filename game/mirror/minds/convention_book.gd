class_name ConventionBook
extends RefCounted

# Folklore: when members of a community keep reading the same kind of event the same way, the reading can
# become a CONVENTION, and a convention is a causal force (it biases how members interpret later events,
# alters what a world-rule variant does, and can grant members operators). Law 4 of comic causal
# worldmaking: repeated interpretations become conventions, and conventions become causal forces.
#
# This is deliberately separate from MirrorEngine.share_claim, which stays word for word: a claim passed on
# is exactly what was said; a convention is what a group comes to take for granted.
#
# The book is derived state, like the queue: every decision (a tally moving, an adoption, a retirement) is
# made when an event is committed, written into that event's payload as absolute values, and merely applied
# here. Replaying the log therefore needs no decisions and cannot disagree with the live run.
#
# Bounded on purpose, per convention: an adoption threshold (readings needed), a minimum number of distinct
# holders (a custom needs more than one mind), a cap on the tally, decay with time (a custom nobody feeds
# dies), and a short list of origin events (the first events that fed it, so a custom can always be traced
# to where it began).
#
# Clocks (optional, per convention): a `cadence` class (sprint | bell, resolved through data["clocks"]) or an
# explicit `dormancy` in Mirror clock ticks. A clocked convention nobody feeds for `dormancy` ticks FADES
# (change `forgotten`, cause `dormant`). One that was in force when it faded may REVIVE at most
# `revivals` (<= MAX_REVIVALS) times: the next member reading that matches puts it straight back in force,
# change `revived`, without replaying its origin (origin events are kept, never re-announced, and no
# `adopted` change is emitted, so nothing that explains the custom plays again). Once its revivals are spent
# a faded convention stays faded. Unclocked conventions behave exactly as before.

const DEFAULT_STATE := {
	"tally": 0, "last_reinforced": 0, "holders": {}, "origin_events": [],
	"adopted": false, "adopted_at": -1, "adopted_event": "", "retired": false, "stalled": false,
}

const MAX_REVIVALS := 1

var _state: Dictionary = {}

func reset() -> void:
	_state = {}

func apply_updates(updates: Array) -> void:
	for update in updates:
		var id := str(update.get("id", ""))
		if id.is_empty():
			continue
		var next: Dictionary = DEFAULT_STATE.duplicate(true)
		for key in update.keys():
			if key != "id":
				next[key] = update[key]
		_state[id] = next

func get_state(id: String) -> Dictionary:
	var found: Dictionary = _state.get(id, DEFAULT_STATE)
	return found.duplicate(true)

func is_active(id: String) -> bool:
	return bool(_state.get(id, {}).get("adopted", false))

func active_ids() -> Array:
	var out: Array = []
	for id in _state.keys():
		if is_active(str(id)):
			out.append(str(id))
	out.sort()
	return out

func ids() -> Array:
	var out: Array = _state.keys()
	out.sort()
	return out

func snapshot() -> Dictionary:
	return _state.duplicate(true)

# The tally a convention would have at `now`, decay included, without committing anything.
func effective_tally(definition: Dictionary, now: int) -> int:
	var state: Dictionary = _state.get(str(definition.get("id", "")), DEFAULT_STATE)
	var decay: Dictionary = definition.get("decay", {})
	var every := int(decay.get("every", 0))
	if every <= 0:
		return int(state["tally"])
	var steps := floori(float(now - int(state["last_reinforced"])) / float(every))
	return maxi(0, int(state["tally"]) - steps * int(decay.get("amount", 1)))

# The clock a convention runs on: {} when it has none, else {"dormancy": ticks, "revivals": n}.
static func clock_of(definition: Dictionary, clocks: Dictionary) -> Dictionary:
	var cadence := str(definition.get("cadence", ""))
	if cadence.is_empty() and not definition.has("dormancy"):
		return {}
	var base: Dictionary = clocks.get("cadences", {}).get(cadence, {})
	return {
		"dormancy": int(definition.get("dormancy", base.get("dormancy", 0))),
		"revivals": clampi(int(definition.get("revivals", base.get("revivals", MAX_REVIVALS))), 0, MAX_REVIVALS),
	}

# When the earliest clocked convention will fade, or -1. A faded one waits for a revival, not a clock.
static func next_fade(definitions: Array, book: ConventionBook, clocks: Dictionary) -> int:
	var best := -1
	for definition in definitions:
		var clock := clock_of(definition, clocks)
		if clock.is_empty() or int(clock["dormancy"]) <= 0:
			continue
		var state: Dictionary = book.get_state(str(definition.get("id", "")))
		if bool(state.get("faded", false)) or not _is_live(state):
			continue
		var at := int(state.get("last_fed", state["last_reinforced"])) + int(clock["dormancy"])
		if best < 0 or at < best:
			best = at
	return best

static func _is_live(state: Dictionary) -> bool:
	return bool(state["adopted"]) or int(state["tally"]) > 0 or not (state["holders"] as Dictionary).is_empty()

static func _mark_faded(state: Dictionary, at: int) -> void:
	state["faded"] = true
	state["faded_at"] = at
	state["fades"] = int(state.get("fades", 0)) + 1

# Decides what one committed event does to every convention. Pure: (definitions, current state, the
# event's readings) -> absolute new values + the changes worth announcing. `readings` is
# [{holder, reads, subject, kind}]; `subject_tags` are the tags of the event's subject.
# Returns {"updates": [{id, ...state}], "changes": [{id, change, ...}]} where change is one of
# adopted | retired | stalled | forgotten | capped | revived.
static func evaluate(definitions: Array, book: ConventionBook, communities: Dictionary, readings: Array, event_id: String, event_kind: String, now: int, subject_tags: Array, limits: Dictionary, clocks: Dictionary = {}) -> Dictionary:
	var updates: Array = []
	var changes: Array = []
	var max_origin := int(limits.get("max_origin_events", 5))
	var max_active := int(limits.get("max_active_conventions", 12))
	var active := book.active_ids().size()
	var sorted_defs: Array = definitions.duplicate()
	sorted_defs.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	for definition in sorted_defs:
		var id := str(definition.get("id", ""))
		var before: Dictionary = book.get_state(id)
		var state: Dictionary = before.duplicate(true)
		var members: Array = communities.get(str(definition.get("community", "")), {}).get("members", [])
		var adopt: Dictionary = definition.get("adopt", {})
		var threshold := int(adopt.get("threshold", 3))
		var min_holders := int(adopt.get("min_holders", 2))
		var cap := int(definition.get("cap", 8))
		var decay: Dictionary = definition.get("decay", {})
		var every := int(decay.get("every", 0))
		var clock := clock_of(definition, clocks)

		if every > 0 and int(state["tally"]) > 0:
			var steps := floori(float(now - int(state["last_reinforced"])) / float(every))
			if steps > 0:
				state["tally"] = maxi(0, int(state["tally"]) - steps * int(decay.get("amount", 1)))
				state["last_reinforced"] = int(state["last_reinforced"]) + steps * every
				if bool(state["adopted"]) and int(state["tally"]) <= int(definition.get("retire_at", 0)):
					state["adopted"] = false
					state["retired"] = true
					active -= 1
					changes.append({"id": id, "change": "retired", "tally": int(state["tally"])})
					if not clock.is_empty():
						_mark_faded(state, now)
				if int(state["tally"]) == 0 and not bool(state["adopted"]):
					if not (state["holders"] as Dictionary).is_empty():
						changes.append({"id": id, "change": "forgotten"})
					state["holders"] = {}
					state["stalled"] = false

		if not clock.is_empty() and int(clock["dormancy"]) > 0 and not bool(state.get("faded", false)) and _is_live(state):
			var last_fed := int(state.get("last_fed", state["last_reinforced"]))
			if now - last_fed >= int(clock["dormancy"]):
				var lapsed := bool(state["adopted"])
				if lapsed:
					active -= 1
					state["retired"] = true
					_mark_faded(state, last_fed + int(clock["dormancy"]))
				state["adopted"] = false
				state["tally"] = 0
				state["holders"] = {}
				state["stalled"] = false
				changes.append({"id": id, "change": "forgotten", "cause": "dormant", "lapsed": lapsed})

		var fed: Array = []
		for reading in readings:
			if _matches(definition, reading, members, event_kind, subject_tags) and str(reading.get("holder", "")) not in fed:
				fed.append(str(reading.get("holder", "")))
		fed.sort()
		if not fed.is_empty() and not clock.is_empty() and bool(state.get("faded", false)):
			# Faded: one matching reading brings it back, once, unexplained; after that it stays faded.
			if int(state.get("revivals", 0)) < int(clock["revivals"]):
				if active < max_active:
					var holders_now: Dictionary = {}
					for holder in fed:
						holders_now[holder] = 1
					state["adopted"] = true
					state["retired"] = false
					state["stalled"] = false
					state["faded"] = false
					state["revivals"] = int(state.get("revivals", 0)) + 1
					state["tally"] = mini(cap, maxi(threshold, int(state["tally"]) + 1))
					state["holders"] = holders_now
					state["last_reinforced"] = now
					state["last_fed"] = now
					state["revived_at"] = now
					state["revived_event"] = event_id
					active += 1
					changes.append({"id": id, "change": "revived"})
				else:
					changes.append({"id": id, "change": "capped"})
		elif not fed.is_empty():
			if not clock.is_empty():
				state["last_fed"] = now
			state["tally"] = mini(cap, int(state["tally"]) + 1)
			state["last_reinforced"] = now
			var holders: Dictionary = state["holders"]
			for holder in fed:
				holders[holder] = int(holders.get(holder, 0)) + 1
			state["holders"] = holders
			var origins: Array = state["origin_events"]
			if origins.size() < max_origin and event_id not in origins:
				origins.append(event_id)
			state["origin_events"] = origins
			if not bool(state["adopted"]) and int(state["tally"]) >= threshold:
				if (state["holders"] as Dictionary).size() >= min_holders:
					if active < max_active:
						state["adopted"] = true
						state["retired"] = false
						state["stalled"] = false
						state["adopted_at"] = now
						state["adopted_event"] = event_id
						active += 1
						changes.append({"id": id, "change": "adopted", "tally": int(state["tally"]), "holders": _sorted_keys(state["holders"]), "origin_events": (state["origin_events"] as Array).duplicate()})
					else:
						changes.append({"id": id, "change": "capped"})
				elif not bool(state["stalled"]):
					state["stalled"] = true
					changes.append({"id": id, "change": "stalled", "tally": int(state["tally"]), "holders": _sorted_keys(state["holders"])})
		if MirrorHash.canonical_json(state) != MirrorHash.canonical_json(before):
			var update: Dictionary = state.duplicate(true)
			update["id"] = id
			updates.append(update)
	return {"updates": updates, "changes": changes}

static func _matches(definition: Dictionary, reading: Dictionary, members: Array, event_kind: String, subject_tags: Array) -> bool:
	if str(reading.get("reads", "")) != str(definition.get("reads", "")):
		return false
	if str(reading.get("holder", "")) not in members:
		return false
	var kinds: Array = definition.get("event_kinds", [])
	if not kinds.is_empty() and event_kind not in kinds:
		return false
	var subjects: Array = definition.get("subjects", [])
	var tags: Array = definition.get("subject_tags", [])
	if subjects.is_empty() and tags.is_empty():
		return true
	if str(reading.get("subject", "")) in subjects:
		return true
	for tag in tags:
		if tag in subject_tags:
			return true
	return false

static func _sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys
