extends TestCase

# The systems cell's seam (GAME_SPEC section 7): the game root calls SystemsPresenters.register(director, host) once,
# and every presentation kind the systems cell owns has a handler afterwards.

func test_the_systems_kinds_have_handlers_after_the_seam_is_registered() -> void:
	var director := PresentationDirector.new()
	var host := Node.new()
	track(host)
	SystemsPresenters.register(director, host)
	for kind in ["notebook", "sight", "flash"]:
		ok(director.handlers.has(kind), "%s has a handler" % kind)
	eq(host.get_child_count(), 3, "the systems presenters are hung on the host, not kept loose")

func test_an_unknown_kind_is_still_reported_not_silently_skipped() -> void:
	var director := PresentationDirector.new()
	var host := Node.new()
	track(host)
	SystemsPresenters.register(director, host)
	director.play([{"kind": "systems_typo"}])
	eq(director.unhandled, ["systems_typo"], "an unknown kind stays visible to the flow test")
