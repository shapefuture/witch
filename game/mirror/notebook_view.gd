class_name NotebookView
extends RefCounted

# The satchel notebook (ALIVENESS; ROOM_OF_US items 1 and 2): a read-only view over what the witch holds. Each entry
# is one of her claims, labelled by where it came from (seen, told, guessed), and carries the event it was first
# learned at, so the entry can be traced back to its moment. Open questions (UNRESOLVED_BY_DESIGN) stay visible.
# The view writes nothing to Mirror, returns ids and kinds only (text lives in data/text), and phrases no task:
# an entry is a question or a fact, never an instruction.

const SEEN := "seen"
const TOLD := "told"
const GUESSED := "guessed"
const OPEN := "open"
const KINDS := [SEEN, TOLD, GUESSED, OPEN]
# Claims that arrived from another mind (a share, hearsay, a custom the community holds).
const TOLD_SOURCES := ["claim_share", "hearsay", "convention"]

# One entry per claim the player holds, in discovery-class round-robin order (DiscoveryClasses). `classes` maps a
# claim id to its discovery class (data/aliveness/classes.json); unlisted claims are unclassed.
static func entries(engine: MirrorEngine, classes: Dictionary = {}) -> Array:
	var out: Array = []
	for claim in engine.knowledge.all("player"):
		var claim_id := str(claim.get("id", ""))
		var event_id := str(claim.get("first_seen_event", ""))
		if event_id.is_empty():
			event_id = str(claim.get("last_updated_event", ""))
		out.append({
			"claim": claim_id,
			"kind": kind_of(claim),
			"event_id": event_id,
			"discovery_class": str(classes.get(claim_id, "")),
		})
	return DiscoveryClasses.interleave(out, func(entry: Dictionary) -> String: return str(entry["discovery_class"]))

# Where a claim came from, as the notebook labels it.
static func kind_of(claim: Dictionary) -> String:
	if int(claim.get("status", 0)) == MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN:
		return OPEN
	if str(claim.get("source", "")) in TOLD_SOURCES:
		return TOLD
	if int(claim.get("status", 0)) == MirrorDomain.EpistemicStatus.ESTABLISHED and not (claim.get("evidence", []) as Array).is_empty():
		return SEEN
	return GUESSED

# The moment an entry came from: the event, its kind and who it touched. Empty when the log does not hold it.
static func source_event(engine: MirrorEngine, entry: Dictionary) -> Dictionary:
	var event := engine.event_store.get_by_id(str(entry.get("event_id", "")))
	if event == null:
		return {}
	return {
		"event_id": event.event_id, "event_type": event.event_type, "sequence": event.sequence,
		"actor": event.actor_id, "subject": str(event.payload.get("subject", "")),
		"kind": str(event.payload.get("kind", "")),
	}
