class_name NpcPresence
extends RefCounted

# Who stands in the room she is in (GAME_SPEC section 3, NPC presence). A person whose npc_state has a `place` stands
# where that place is, or with her when it says "with_witch". A person with no `place` field stands where Minds has
# them (Tomas: the archive). Pure: it reads only what it is given, so the rule can be tested without a scene.

const WITH_WITCH := "with_witch"

# The ids present in `place_id`, sorted. `minds_places` maps a holder id to the place Minds has them in.
static func present_ids(place_id: String, npc_state: Dictionary, minds_places: Dictionary) -> PackedStringArray:
	var ids: Array = npc_state.keys()
	for holder in minds_places.keys():
		if not ids.has(holder):
			ids.append(holder)
	ids.sort()
	var out := PackedStringArray()
	for id in ids:
		if is_present(str(id), place_id, npc_state, minds_places):
			out.append(str(id))
	return out

static func is_present(id: String, place_id: String, npc_state: Dictionary, minds_places: Dictionary) -> bool:
	if place_id.is_empty():
		return false
	var state: Dictionary = npc_state.get(id, {})
	if state.has("place"):
		var at := str(state["place"])
		return at == WITH_WITCH or at == place_id
	return str(minds_places.get(id, "")) == place_id

# Whether a person is with her wherever she goes (their place is "with_witch"): such a person is placed beside her.
static func goes_with_witch(id: String, npc_state: Dictionary) -> bool:
	var state: Dictionary = npc_state.get(id, {})
	return str(state.get("place", "")) == WITH_WITCH
