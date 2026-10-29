class_name SystemsPresenters
extends RefCounted

# The seam between the game root (the framework cell) and the systems cell (docs/design/GAME_SPEC.md section 7). The
# game root calls register() once while it builds; the systems cell adds the handlers for the presentation kinds it
# owns here: "flash" (a telesomatic vignette, no caption), "sight" (the chuika ghosts, Expectation-Sight, of the NPCs in
# the room) and "notebook" (opens the notebook at a claim). `host` is the game root, which offers the room, the actors
# and Mirror. Each presenter is a child of the host.

static func register(director: PresentationDirector, host: Node) -> void:
	var notebook := NotebookPresenter.new()
	notebook.name = "NotebookPresenter"
	notebook.runtime_provider = func() -> MirrorRuntime: return runtime_of(host)
	host.add_child(notebook)
	director.register("notebook", notebook.play_entry)
	var sight := SightPresenter.new()
	sight.name = "SightPresenter"
	sight.host = host
	sight.runtime_provider = func() -> MirrorRuntime: return runtime_of(host)
	sight.room_provider = func() -> Object: return host.get("room") as Object
	host.add_child(sight)
	director.register("sight", sight.play_entry)

# The Mirror runtime the host holds, or the Mirror autoload when the host holds none.
static func runtime_of(host: Node) -> MirrorRuntime:
	if host == null:
		return null
	var held: Variant = host.get("runtime")
	if held is MirrorRuntime:
		return held as MirrorRuntime
	return host.get_node_or_null("/root/Mirror") as MirrorRuntime if host.is_inside_tree() else null
