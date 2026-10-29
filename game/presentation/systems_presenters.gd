class_name SystemsPresenters
extends RefCounted

# The seam between the game root (the framework cell) and the systems cell (docs/design/GAME_SPEC.md section 7). The
# game root calls register() once while it builds; the systems cell adds the handlers for the presentation kinds it
# owns here: "flash" (a telesomatic vignette, no caption), "sight" (the chuika ghosts, Expectation-Sight, of the NPCs in the room) and
# "notebook" (opens the notebook at a claim). `host` is the game root, which offers the room, the actors and Mirror.

static func register(_director: PresentationDirector, _host: Node) -> void:
	pass
