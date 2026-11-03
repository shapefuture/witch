extends TestCase

# The live hall's reactions. Mirror's reactions to a poke come back to the room through the existing presenter
# (PropEvents.play_prop_reactions_on_room): what the room can show it moves, and what it cannot is reported, not
# lost. Headless: the calls and the transforms are checked, not the pictures.

func _first_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

func _until(condition: Callable, max_frames: int = 900) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await (Engine.get_main_loop() as SceneTree).process_frame
	return condition.call()

func _hall_on(r: MirrorRuntime) -> Dictionary:
	GameFixtures.ensure_localization()
	var hall: ArchiveHall = track(ArchiveHall.new()) as ArchiveHall
	(Engine.get_main_loop() as SceneTree).root.add_child(hall)
	var live: LiveHallCoordinator = track(LiveHallCoordinator.new()) as LiveHallCoordinator
	live.runtime = r
	live.run_clock = false
	var bridge: PropEvents = live.attach(hall)
	return {"hall": hall, "live": live, "bridge": bridge}

func test_attaching_connects_the_existing_presenter_so_mirrors_reactions_reach_the_room() -> void:
	await _first_frame()
	var bridge: PropEvents = _hall_on(GameFixtures.runtime())["bridge"]
	ok(bridge.reaction_requested.is_connected(bridge._play_prop_reaction), "PropEvents.play_prop_reactions_on_room is connected by the coordinator")

func test_a_poke_makes_the_bell_hop_and_it_settles_back_on_its_mount() -> void:
	await _first_frame()
	var made := _hall_on(GameFixtures.runtime())
	var hall: ArchiveHall = made["hall"]
	var rest := hall.bell.position
	ok(hall.press("bell", "hop"), "the bell answers the poke")
	ok(await _until(func() -> bool: return hall.bell.position.distance_to(rest) > 0.01), "it hops: its place changes while Mirror answers")
	ok(await _until(func() -> bool: return hall.bell.position.distance_to(rest) < 0.001), "and it settles back on its mount")

func test_a_reaction_from_mirror_for_the_bell_is_played_on_the_bell_and_reported_as_shown() -> void:
	await _first_frame()
	var made := _hall_on(GameFixtures.runtime())
	var bridge: PropEvents = made["bridge"]
	var reported: Array = []
	bridge.reaction_presented.connect(func(reaction: Dictionary, presented: bool) -> void: reported.append([reaction["target"], presented]))
	bridge.reaction_requested.emit({"op": "PROP_REACT", "target": "bell", "reaction": "shiver"})
	eq(reported, [["bell", true]], "a PROP_REACT for the bell reaches the bell through the presenter")
	bridge.reaction_requested.emit({"op": "LOOK_AT", "actor": "raccoon", "target": "bell"})
	eq(reported.size(), 1, "a LOOK_AT is not a move of a prop, so it is not reported as one")

func test_a_poke_whose_reactions_the_hall_cannot_show_is_reported_not_lost() -> void:
	await _first_frame()
	var made := _hall_on(GameFixtures.runtime())
	var hall: ArchiveHall = made["hall"]
	var bridge: PropEvents = made["bridge"]
	var reported: Array = []
	bridge.reaction_presented.connect(func(reaction: Dictionary, presented: bool) -> void: reported.append([reaction["target"], presented]))
	ok(hall.press("bell", "hop"), "the poke is made")
	eq(reported, [["statue", false]], "regard asks for the statue to lean in; this hall has no statue, and the report says so")

func test_a_thing_the_hall_does_not_have_is_refused_and_writes_nothing() -> void:
	await _first_frame()
	var r := GameFixtures.runtime()
	var made := _hall_on(r)
	var hall: ArchiveHall = made["hall"]
	var before := r.engine.event_store.size()
	eq(hall.press("statue", "shiver"), false, "there is no statue in the hall to poke")
	eq(hall.request_reaction("statue", "shiver"), false, "nor one to move")
	eq(r.engine.event_store.size(), before, "and no poke of it reaches Mirror")

func test_detached_the_hall_still_answers_but_mirror_hears_nothing() -> void:
	await _first_frame()
	var r := GameFixtures.runtime()
	var made := _hall_on(r)
	var hall: ArchiveHall = made["hall"]
	var live: LiveHallCoordinator = made["live"]
	live.detach()
	var before := r.engine.event_store.size()
	ok(hall.press("bell", "hop"), "the bell still answers a poke of the hall")
	eq(r.engine.event_store.size(), before, "with no bridge, nothing reaches Mirror")
