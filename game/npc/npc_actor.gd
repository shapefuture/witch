class_name NpcActor
extends RefCounted

# The body a person stands in: the character's model where one exists (CharacterModels, which another cell fills),
# else a crude figure in the person's colour (Placeholders.person). The room places it; this only makes it.

static func build(id: String) -> Node3D:
	var model := CharacterModels.instantiate(id)
	if model != null:
		if CharacterModels.has_clip(model, "idle"):
			CharacterModels.play(model, "idle")
		return model
	return Placeholders.person(colour_of(id))

static func colour_of(id: String) -> Color:
	match id:
		"miron":
			return Color(0.45, 0.30, 0.62)
		"elian":
			return Color(0.30, 0.36, 0.44)
		"vera":
			return Color(0.62, 0.22, 0.24)
		"ilya":
			return Color(0.24, 0.50, 0.52)
		"janitor":
			return Color(0.42, 0.44, 0.36)
		"concierge":
			return Color(0.88, 0.84, 0.74)
		"shadow":
			return Color(0.12, 0.10, 0.16)
	return Color(0.50, 0.50, 0.50)
