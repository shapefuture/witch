class_name NotebookView
extends RefCounted

# The satchel notebook (docs/design/GAME_SPEC.md section 4; BIBLE section 9): a read-only view over the claims the
# witch holds. Only claims that a content sidecar names appear (data/notebook/<area>.json), each with the kind the
# sidecar gives it. A claim whose status is UNRESOLVED_BY_DESIGN is always untestable. Every entry carries the event
# it was first learned at, so it traces back to its moment. The view writes nothing to Mirror, returns ids and
# kinds only (text lives in data/text), and phrases no task: an entry is a question or a fact, never an instruction.

const SEEN := "seen"
const HEARD := "heard"
const SHOWN := "shown"
const INFERRED := "inferred"
const PREDICTED := "predicted"
const ALTERED := "altered"
const UNTESTABLE := "untestable"
# In the order the notebook shows its groups (the witch's own words: ui.notebook.kind.*).
const KINDS := [SEEN, HEARD, SHOWN, INFERRED, PREDICTED, ALTERED, UNTESTABLE]

# The four names of the earlier view, kept for callers that still use them.
const TOLD := HEARD
const GUESSED := INFERRED
const OPEN := UNTESTABLE

const DIR := "res://data/notebook"
const CLASSES := "res://data/aliveness/classes.json"
# Claims that arrived from another mind (a share, hearsay, a custom the community holds).
const TOLD_SOURCES := ["claim_share", "hearsay", "convention"]

# One entry per claim the player holds that a sidecar names. `claims` maps a claim id to {"kind", "text"} (the merged
# sidecars, see load_claims); `classes` maps a claim id to its discovery class (discovery_classes). The result is in
# discovery-class round-robin order (DiscoveryClasses), so one class does not fill the page.
static func entries(engine: MirrorEngine, classes: Dictionary = {}, claims: Dictionary = {}) -> Array:
	var out: Array = []
	for claim in engine.knowledge.all("player"):
		var claim_id := str(claim.get("id", ""))
		if not claims.has(claim_id):
			continue
		var listed: Dictionary = claims[claim_id]
		var event_id := str(claim.get("first_seen_event", ""))
		if event_id.is_empty():
			event_id = str(claim.get("last_updated_event", ""))
		out.append({
			"claim": claim_id,
			"kind": kind_of(claim, str(listed.get("kind", ""))),
			"text": str(listed.get("text", "")),
			"event_id": event_id,
			"discovery_class": str(classes.get(claim_id, "")),
		})
	return DiscoveryClasses.interleave(out, func(entry: Dictionary) -> String: return str(entry["discovery_class"]))

# The kind an entry shows. An UNRESOLVED_BY_DESIGN claim is untestable whatever the sidecar says. Otherwise the
# authored kind wins: the kind is authored, never derived. Without one (a caller with no sidecar), the belief's
# source gives the kind.
static func kind_of(claim: Dictionary, authored: String = "") -> String:
	if int(claim.get("status", 0)) == MirrorDomain.EpistemicStatus.UNRESOLVED_BY_DESIGN:
		return UNTESTABLE
	if authored in KINDS:
		return authored
	if str(claim.get("source", "")) in TOLD_SOURCES:
		return HEARD
	if int(claim.get("status", 0)) == MirrorDomain.EpistemicStatus.ESTABLISHED and not (claim.get("evidence", []) as Array).is_empty():
		return SEEN
	return INFERRED

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

# Rhyme notes (room_engine's echo, ROOM_OF_US item 4): the same motif, authored on two entries, recurring in another
# room and in another form. `motifs` is data/aliveness/motifs.json's list: {claim, tag, room, form}. A note names the
# two claims; it is never applied to the world, only shown.
static func rhymes(entries: Array, motifs: Array) -> Array:
	var known: Array = []
	for entry in entries:
		known.append(str(entry["claim"]))
	var out: Array = []
	for i in motifs.size():
		for j in range(i + 1, motifs.size()):
			var a: Dictionary = motifs[i]
			var b: Dictionary = motifs[j]
			if str(a["tag"]) != str(b["tag"]) or str(a["room"]) == str(b["room"]) or str(a["form"]) == str(b["form"]):
				continue
			if str(a["claim"]) in known and str(b["claim"]) in known:
				out.append({"motif": str(a["tag"]), "claims": [str(a["claim"]), str(b["claim"])],
					"rooms": [str(a["room"]), str(b["room"])], "forms": [str(a["form"]), str(b["form"])]})
	return out

# The sidecars under `dir` merged into one claim table, with what was wrong with them. A claim named twice is an
# error (content areas own their claims). An entry needs one of the seven kinds and a note key. Keys starting with
# "_" are notes.
static func load_claims(dir: String = DIR) -> Dictionary:
	var claims: Dictionary = {}
	var errors: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return {"claims": claims, "errors": errors}
	var access := DirAccess.open(dir)
	if access == null:
		return {"claims": claims, "errors": errors}
	var files: Array = []
	for file_name in access.get_files():
		if file_name.get_extension() == "json":
			files.append(file_name)
	files.sort()
	for file_name in files:
		var path: String = dir.path_join(file_name)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			errors.append("%s: not a JSON object" % path)
			continue
		for claim_id in (parsed as Dictionary).keys():
			var key := str(claim_id)
			if key.begins_with("_"):
				continue
			var listed: Variant = (parsed as Dictionary)[claim_id]
			if not listed is Dictionary:
				errors.append("%s: '%s' is not an object" % [path, key])
				continue
			var kind := str((listed as Dictionary).get("kind", ""))
			var text := str((listed as Dictionary).get("text", ""))
			if not kind in KINDS:
				errors.append("%s: '%s' has kind '%s', not one of the seven kinds" % [path, key, kind])
				continue
			if not text.begins_with("note."):
				errors.append("%s: '%s' needs a note key (note.<area>.<name>)" % [path, key])
				continue
			if claims.has(key):
				errors.append("%s: '%s' is already named by another sidecar" % [path, key])
				continue
			claims[key] = {"kind": kind, "text": text}
	return {"claims": claims, "errors": errors}

# The discovery class of each claim the aliveness sidecar classes (data/aliveness/classes.json, outside the catalog).
static func discovery_classes(path: String = CLASSES) -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		return out
	var entries_map: Variant = (parsed as Dictionary).get("entries", {})
	if not entries_map is Dictionary:
		return out
	for id in (entries_map as Dictionary).keys():
		var item: Variant = (entries_map as Dictionary)[id]
		if item is Dictionary:
			out[str(id)] = str((item as Dictionary).get("class", ""))
	return out

# The entries grouped by kind (in KINDS order), each group cut into pages of at most `per_page` entries, so a page never
# mixes kinds. Each page is {"kind", "entries"}.
static func pages(entries: Array, per_page: int = 3) -> Array:
	var out: Array = []
	var step := maxi(per_page, 1)
	for kind in KINDS:
		var group: Array = []
		for entry in entries:
			if str(entry["kind"]) == kind:
				group.append(entry)
		for start in range(0, group.size(), step):
			out.append({"kind": kind, "entries": group.slice(start, start + step)})
	return out

# The index of the page that shows `claim`, or 0 when no page does.
static func page_of(page_list: Array, claim: String) -> int:
	for i in page_list.size():
		for entry in page_list[i]["entries"]:
			if str(entry["claim"]) == claim:
				return i
	return 0
