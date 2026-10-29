extends TestCase

# The live hall wired to Mirror's Minds layer through LiveHallCoordinator (game/mirror/coordinator.gd). A poke of the
# bell is one happening: committed through Mirror.minds.perceive as one transaction, with its witnesses recorded, and
# the same inputs write the same chain as the headless simulation. Only the hall's own rules answer (echo, regard,
# name); nothing here adds a rule or a line of text.

func _first_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

# A hall in the tree, as the game builds it, with a coordinator attached to it and Mirror's clock off.
func _hall_on(r: MirrorRuntime) -> Dictionary:
	GameFixtures.ensure_localization()
	var hall: ArchiveHall = track(ArchiveHall.new()) as ArchiveHall
	(Engine.get_main_loop() as SceneTree).root.add_child(hall)
	var live: LiveHallCoordinator = track(LiveHallCoordinator.new()) as LiveHallCoordinator
	live.runtime = r
	live.run_clock = false
	var bridge: PropEvents = live.attach(hall)
	return {"hall": hall, "live": live, "bridge": bridge}

func _count(events: Array, event_type: String) -> int:
	var n := 0
	for event: MirrorEvent in events:
		if event.event_type == event_type:
			n += 1
	return n

func test_the_coordinator_attaches_to_the_hall_under_its_own_mirror_id_and_refuses_a_stranger() -> void:
	await _first_frame()
	var made := _hall_on(GameFixtures.runtime())
	var hall: ArchiveHall = made["hall"]
	var bridge: PropEvents = made["bridge"]
	ok(bridge != null and bridge.room == hall, "the bridge is attached to the hall")
	eq(bridge.place, "clearing", "under the hall's Mirror id, read from the room")
	var live: LiveHallCoordinator = made["live"]
	var stranger: Node = track(Node.new())
	eq(live.attach(stranger), null, "a plain node is not a room: refused")
	ok(live.bridge == bridge and bridge.room == hall, "and the hall stays attached")

func test_poking_the_bell_commits_one_happening_as_one_transaction_with_its_witnesses_recorded() -> void:
	await _first_frame()
	var r := GameFixtures.runtime()
	var made := _hall_on(r)
	var hall: ArchiveHall = made["hall"]
	var bridge: PropEvents = made["bridge"]
	var happened: Array = []
	bridge.happened.connect(func(result: Dictionary) -> void: happened.append(result))
	var commits: Array = []
	r.engine.transaction_committed.connect(func(result: Dictionary) -> void: commits.append(result))
	r.minds.pending()   # synchronises the Minds layer with the log, so `seeded` is current
	var needs_seed := not r.minds.state.seeded
	ok(hall.press("bell", "hop"), "the hall's bell answers a poke")
	eq(happened.size(), 1, "one happening was committed")
	eq(commits.size(), 2 if needs_seed else 1, "as one transaction (the Minds layer writes its starting beliefs with the first happening)")
	var result: Dictionary = happened[0]
	eq([result["kind"], result["subject"], result["actor"]], ["PROP_POKED", "bell", "player"], "a poke of the bell by the witch")
	var witnesses: Array = result["witnesses"]
	for holder in ["player", "raccoon", "tomas"]:
		ok(holder in witnesses, "%s saw it, and the witness is recorded" % holder)
	var transaction: Array[MirrorEvent] = r.engine.event_store.get_transaction(str(result["transaction_id"]))
	eq(_count(transaction, "WorldEventHappened"), 1, "the happening is one event")
	eq(_count(transaction, "ObservationRecorded"), witnesses.size(), "and every witness's observation is in the same transaction")
	eq(r.engine.event_store.get_by_id(str(result["event_id"])).payload["place"], "clearing", "in the hall's place")

func test_the_hall_answers_the_bell_with_its_own_rules_only() -> void:
	await _first_frame()
	var made := _hall_on(GameFixtures.runtime())
	var hall: ArchiveHall = made["hall"]
	var bridge: PropEvents = made["bridge"]
	var happened: Array = []
	bridge.happened.connect(func(result: Dictionary) -> void: happened.append(result))
	hall.press("bell", "hop")
	var result: Dictionary = happened[0]
	var looks: Array = result["reactions"].filter(func(x: Dictionary) -> bool: return x["op"] == "LOOK_AT")
	eq(looks.size(), 1, "regard: one witness turns to it")
	eq([looks[0]["actor"], looks[0]["target"]], ["raccoon", "bell"], "the raccoon turns to the bell")
	var pending: Array = bridge.runtime.minds.pending()
	eq(pending.size(), 1, "echo: one answer is due")
	eq([pending[0]["event"]["kind"], pending[0]["event"]["actor"], pending[0]["event"]["subject"], pending[0]["due"]], ["PROP_POKED", "raccoon", "bell", 5], "the raccoon repeats the poke five ticks later (the social echo answers any prop; the physical echoes only know the globe and the statue)")

func test_the_bell_poke_writes_the_chain_of_the_headless_simulation_and_replays_from_the_log() -> void:
	await _first_frame()
	var r := GameFixtures.runtime()
	var made := _hall_on(r)
	var hall: ArchiveHall = made["hall"]
	var bridge: PropEvents = made["bridge"]
	var hints: Dictionary = bridge.hints(hall.bell.global_position)
	ok(hall.press("bell", "hop") and hall.press("bell", "spin"), "two pokes of the bell")
	var twin := GameFixtures.runtime()
	ok(SimulationRunner.run_step(twin, {"poke": "bell", "reaction": "hop", "hints": hints})["ok"], "the headless poke commits")
	ok(SimulationRunner.run_step(twin, {"poke": "bell", "reaction": "spin", "hints": hints})["ok"], "and the second")
	eq(twin.engine.event_store.head_hash(), r.engine.event_store.head_hash(), "the room's pokes and the headless pokes write the identical chain")
	var live := MirrorHash.canonical_json(r.engine.projection_snapshot())
	var pending := MirrorHash.canonical_json(r.minds.pending())
	ok(r.engine.replay_all()["ok"], "the log replays")
	eq(MirrorHash.canonical_json(r.engine.projection_snapshot()), live, "every belief of every mind is reproduced from the log")
	r.minds.rebuild()
	eq(MirrorHash.canonical_json(r.minds.pending()), pending, "and the queue is too")
	ok(r.engine.audit_integrity()["ok"], "the chain is intact")
