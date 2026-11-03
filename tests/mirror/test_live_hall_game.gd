extends TestCase

# L-live (witch-29y.12.16, X13): the game's own hall is wired to the Minds layer. A poke of the bell in the game commits
# the same happenings as the same poke in the headless hall (tests/mirror/test_live_hall.gd), in the same order.

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# GameRoot is untyped here, as in tests/interaction/test_game_flow.gd: a typed GameRoot beside the named ArchiveHall keeps
# the script graph alive at exit under Godot 4.6.3 (see docs/progress/fw.md).
func _boot() -> Node:
	GameFixtures.ensure_localization()
	var game = GameRoot.new()
	game.demo = true   # the archive hall demo (the game's own hall, under the root catalog)
	game.runtime = track(MirrorRuntime.new())
	game.auto_advance = 0.0
	game.magic_time_scale = 0.01
	game.run_clock = false   # the live hall keeps Mirror time only in play; a test's chain must not depend on wall time
	_tree().root.add_child(game)
	track(game)
	for i in 3:
		await _tree().physics_frame
	return game

# The game opens with a line that types out and then waits for the player (auto_advance = 0.0 dismisses it the moment
# it has typed). A test that ends before that line, or any line its poke starts, is through leaves the presentation
# suspended, and the suspended coroutines hold the line's audio and the events of the action at exit. So each test
# plays its game out first.
func _settle(game: GameRoot) -> void:
	for i in 1200:
		if not game.subtitles.is_active() and not game.runtime.is_busy():
			return
		game.subtitles.advance()
		await _tree().process_frame

# The world's happenings (not the clock's ticks), as "KIND:subject", in log order.
func _happenings(r: MirrorRuntime) -> Array:
	var out: Array = []
	for event in r.engine.event_store.get_all():
		if event.event_type == "WorldEventHappened":
			out.append("%s:%s" % [event.payload.get("kind", ""), event.payload.get("subject", "")])
	return out

func test_the_game_hall_is_attached_to_the_minds_layer() -> void:
	var game = await _boot()
	ok(game.live != null and game.live.bridge != null, "the game's hall has a coordinator and a bridge")
	ok(game.live.bridge.room == game.room, "the bridge is attached to the game's own hall")
	eq(game.live.bridge.place, "clearing", "under the hall's Mirror id")
	await _settle(game)

func test_a_poke_in_the_game_commits_the_same_happenings_as_the_headless_hall() -> void:
	var game = await _boot()
	game.live.bridge.run_clock = false
	ok((game.room as ArchiveHall).press("bell", "hop"), "the game's hall answers the poke")
	await _tree().process_frame
	var in_game := _happenings(game.runtime)
	ok(in_game.has("PROP_POKED:bell"), "the poke is a PROP_POKED on the bell in the game's log")
	var headless := GameFixtures.runtime()
	var hall: ArchiveHall = track(ArchiveHall.new()) as ArchiveHall
	_tree().root.add_child(hall)
	var live: LiveHallCoordinator = track(LiveHallCoordinator.new()) as LiveHallCoordinator
	live.runtime = headless
	live.run_clock = false
	live.attach(hall)
	await _tree().process_frame
	hall.press("bell", "hop")
	eq(in_game, _happenings(headless), "the same happenings, in the same order, as the headless hall")
	await _settle(game)
