class_name ExpectationSight
extends RefCounted

# Expectation-Sight, the chuika (BIBLE section 9; GAME_SPEC section 4): what someone seems to be bracing for, shown as a
# ghost. The sidecars (data/expectations/<area>.json) say which ghost an NPC shows when Mirror's state matches. This file
# holds the rules: the entries, who is in the room, which ghosts show, and how each ghost moves. It writes nothing.
#
# A "projection" entry is a false positive: what the witch expects, shown as if it were theirs. It is shown exactly as an
# "npc" entry is; `source` is never read by the presentation.

const DIR := "res://data/expectations"
const GHOSTS := ["flinch", "reach", "turn_away", "step_back", "hold_breath"]
const LOOK_PREFIX := "look_at:"
const SOURCES := ["npc", "projection"]
# One ghost's move, in seconds of scene time.
const MOVE_SECONDS := 1.6

# The entries under `dir`, merged in file order, and what was wrong with the rest. An entry needs an id (unique), an NPC,
# a `when` Mirror condition, a ghost, a source and a note key.
static func load_entries(dir: String = DIR) -> Dictionary:
	var entries: Array = []
	var errors: Array = []
	var ids: Dictionary = {}
	if not DirAccess.dir_exists_absolute(dir):
		return {"entries": entries, "errors": errors}
	var access := DirAccess.open(dir)
	if access == null:
		return {"entries": entries, "errors": errors}
	var files: Array = []
	for file_name in access.get_files():
		if file_name.get_extension() == "json":
			files.append(file_name)
	files.sort()
	for file_name in files:
		var path: String = dir.path_join(file_name)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Array:
			errors.append("%s: not a JSON list" % path)
			continue
		for item in parsed:
			if not item is Dictionary:
				errors.append("%s: an entry is not an object" % path)
				continue
			var problems := validate_entry(item)
			if not problems.is_empty():
				errors.append("%s: %s" % [path, "; ".join(PackedStringArray(problems))])
				continue
			var id := str(item["id"])
			if ids.has(id):
				errors.append("%s: '%s' is already defined by another entry" % [path, id])
				continue
			ids[id] = true
			entries.append(item)
	return {"entries": entries, "errors": errors}

static func validate_entry(entry: Dictionary) -> Array:
	var problems: Array = []
	if str(entry.get("id", "")).is_empty():
		problems.append("no id")
	if str(entry.get("npc", "")).is_empty():
		problems.append("no npc")
	if not entry.get("when", null) is Dictionary:
		problems.append("'when' is not a Mirror condition")
	elif not MirrorConditions.validate(entry["when"]).is_empty():
		problems.append("'when' is not a valid Mirror condition")
	if not is_ghost(str(entry.get("ghost", ""))):
		problems.append("ghost '%s' is not one of the known ghosts" % str(entry.get("ghost", "")))
	if not str(entry.get("source", "")) in SOURCES:
		problems.append("source must be npc or projection")
	if not str(entry.get("note", "")).begins_with("note."):
		problems.append("'note' needs a note key")
	return problems

static func is_ghost(ghost: String) -> bool:
	return ghost in GHOSTS or is_look(ghost)

static func is_look(ghost: String) -> bool:
	return ghost.begins_with(LOOK_PREFIX) and ghost.length() > LOOK_PREFIX.length()

static func look_target(ghost: String) -> String:
	return ghost.trim_prefix(LOOK_PREFIX) if is_look(ghost) else ""

# Who stands in the room: every actor on stage whose NPC state puts it here, or that has no place at all (Tomas, held by
# the room). `context` is Mirror's condition context (MirrorRuntime.context_snapshot()).
static func present_npcs(context: Dictionary, stage_ids: Array) -> Array:
	var witch_place := str(MirrorConditions.read_path(context, "witch.place", ""))
	var npc_states: Dictionary = context.get("npc", {})
	var out: Array = []
	for id in stage_ids:
		var state: Dictionary = npc_states.get(str(id), {})
		if not state.has("place") or str(state["place"]) in [witch_place, "with_witch"]:
			out.append(str(id))
	return out

# The entries whose NPC is present and whose `when` matches Mirror's state, in the order they were loaded.
static func selected(entries: Array, context: Dictionary, present: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if str(entry["npc"]) in present and MirrorConditions.matches(entry["when"], context):
			out.append(entry)
	return out

# What the presentation of one entry is: the NPC and the ghost. Nothing else (not the source, the note or the id).
static func descriptor(entry: Dictionary) -> Dictionary:
	return {"npc": str(entry["npc"]), "ghost": str(entry["ghost"])}

# A ghost's pose at progress `t` (0 at the start of its move, 1 at the end). `step` is an offset from where the actor stands,
# `turn` and `lean` are radians, `scale` multiplies the copy, `alpha` is how solid the copy is, and `look_weight` is how
# far a look_at ghost has turned towards its target (the presenter supplies the yaw).
static func pose_at(ghost: String, t: float) -> Dictionary:
	var u := clampf(t, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - u, 3.0)
	var bump := sin(u * PI)
	var pose := {
		"step": Vector3.ZERO, "turn": 0.0, "lean": 0.0, "scale": 1.0,
		"alpha": smoothstep(0.0, 0.22, u) * (1.0 - smoothstep(0.78, 1.0, u)), "look_weight": 0.0,
	}
	match ghost:
		"flinch":
			pose["step"] = Vector3(0.0, 0.0, -0.08 * bump)
			pose["lean"] = -0.22 * bump
		"reach":
			pose["step"] = Vector3(0.0, 0.0, 0.10 * eased)
			pose["lean"] = 0.16 * eased
			pose["turn"] = 0.28 * eased
		"turn_away":
			pose["step"] = Vector3(0.0, 0.0, -0.05 * eased)
			pose["turn"] = 0.9 * eased
		"step_back":
			pose["step"] = Vector3(0.0, 0.0, -0.45 * eased)
		"hold_breath":
			pose["scale"] = 1.0 + 0.025 * eased
		_:
			if is_look(ghost):
				pose["look_weight"] = eased
	return pose

# The yaw (radians about Y) that turns something at `from` to face `to`.
static func yaw_towards(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)
