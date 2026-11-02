class_name GameRoot
extends Node

# Composition root. It builds the camera, the UI and the witch once, and builds the room of each place she is in (the
# place file decides the kind of room, see game/world/places). It connects them:
#
#   pointer -> PlayerIntent -> InteractionFlow -> Mirror (commit) -> PresentationDirector
#                                                              -> settle: move her, storylets, offers
#
# Nothing here decides what happened. Command-line hooks (after `--`):
#   --demo                      the legacy archive-hall demo: the root catalog, no places, no main menu (tests boot it)
#   --debug-sim [script.json]   run deterministic simulation(s) headlessly, print the transcript, exit
#   --capture out.png           render, save a screenshot after --capture-frames N (default 45), exit
#   --sim-first name            play data/sim/name.json first, so the scene starts in that state
#   --show-options target       open the action surface for a target without walking (capture aid)
#   --load                      continue from save slot 1 without the main menu
#   --magic amount              hold the magic shader globals at 0..1 (capture aid: shows the break)
#   --shot mode                 hold the camera on a director shot (wide, inspect, conversation, magic_reveal ...)
#   --lens amount               hold the fisheye lens swing at 0..1 (capture aid)
#   --no-fx                     leave out the dust (capture aid: the bare plates)
#   --no-post                   leave out the screen grade (capture aid: compare the frame with a plate)
#   --variant name [--fade s]   show the hall in a plate variant ("dusk"), or crossfade to it over s seconds
#   --cam x,y,z,tx,ty,tz[,fov] put the camera there, looking at t (capture aid: inspect the set)

const SLOT := SaveGame.DEFAULT_SLOT
const WITCH_TARGET := "witch"
# How many storylets one settle may play, so a chain cannot run away.
const MAX_STORYLETS := 12
const BACKDROP_COLOUR := Color(0.06, 0.04, 0.09)

# Injected by tests; otherwise the `Mirror` autoload is used.
var runtime: MirrorRuntime
var args: Dictionary = {}
# The legacy hall demo: root catalog only, the hall as the one room, no main menu. Tests boot it.
var demo := false
# Headless tests and capture aids: advance subtitles by themselves, and shorten magic.
var auto_advance := -1.0
var magic_time_scale := 1.0
# Mirror's clock in a live room. Off in headless tests, so a run's event chain does not depend on how long it took.
var run_clock := true

# The room she is in (built from the place file), and the place id it is for.
var room: PlaceRoom
var current_place := ""
var witch: Witch
var witch_hotspot: Interactable
var camera: DioramaCamera
var director: CameraDirector
var input: IntentInput
var probe: InteractionProbe
var flow: InteractionFlow
var live: LiveHallCoordinator
var subtitles: SubtitleUI
var surface: InteractionPresenter
var pause_menu: PauseMenuUI
var inspector: MirrorInspector
var magic: MagicPresentation
var dialogue: DialogueBridge
var menu: MainMenuUI
var presentation := PresentationDirector.new()
var hover_target := ""
var _outlined: Node3D
var _backdrop: WorldEnvironment
var _started := false
var _presenting := false
var _held := false          # a `stay` camera holds until she changes room
var _postgame := false
var _frames := 0
var _clock := 0.0

static func parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		var token := raw[i]
		if token.begins_with("--"):
			var key := token.substr(2)
			if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				out[key] = raw[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out

func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	demo = demo or args.has("demo")
	_acquire_runtime()
	if args.has("debug-sim"):
		_run_debug_sim()
		return
	if args.has("sim-first"):
		runtime.new_game()
		var script := SimulationRunner.load_script("res://data/sim/%s.json" % str(args["sim-first"]))
		SimulationRunner.new().run(runtime, script)
	_build()
	if args.has("capture"):
		_capture_then_quit()
	await _begin()

func _acquire_runtime() -> void:
	if runtime == null:
		runtime = get_node_or_null("/root/Mirror") as MirrorRuntime
	if runtime == null:
		runtime = MirrorRuntime.new()
		add_child(runtime)
	# An injected or freshly made runtime has no engine until it is set up.
	if runtime.engine == null:
		runtime.setup()

# ---- construction -----------------------------------------------------------------------------

# Everything that outlives a room: the camera, the UI, the input, the witch. Rooms are built by _enter_place.
func _build() -> void:
	PSXGlobals.reset()
	ArchiveHall.atmosphere_enabled = not args.has("no-fx")
	witch = Witch.new()
	witch.name = "Witch"
	add_child(witch)
	witch_hotspot = Interactable.new()
	witch_hotspot.name = "Interact_witch"
	witch_hotspot.target_id = WITCH_TARGET
	witch_hotspot.display_key = "obj.witch"
	witch_hotspot.focus_height = 1.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	witch_hotspot.add_child(shape)
	witch.add_child(witch_hotspot)

	camera = DioramaCamera.new()
	camera.name = "DioramaCamera"
	camera.current = true
	add_child(camera)
	director = CameraDirector.new()
	director.camera = camera
	director.framing_provider = _framing
	director.focus_resolver = _focus_position
	director.shot_provider = _shot_pose
	add_child(director)
	director.frame("wide", [], true)

	var post := CanvasLayer.new()
	post.name = "PSXScreen"
	post.layer = 1
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade.material = PSXMaterials.screen()
	post.add_child(grade)
	post.visible = not args.has("no-post")
	add_child(post)

	surface = InteractionPresenter.new()
	surface.name = "InteractionPresenter"
	surface.camera = camera
	add_child(surface)
	subtitles = SubtitleUI.new()
	subtitles.name = "SubtitleUI"
	subtitles.camera = camera
	subtitles.anchor_provider = _bubble_anchor
	subtitles.hero_provider = _hero_rects
	add_child(subtitles)
	pause_menu = PauseMenuUI.new()
	pause_menu.name = "PauseMenu"
	pause_menu.camera = camera
	add_child(pause_menu)
	inspector = MirrorInspector.new()
	inspector.name = "MirrorInspector"
	inspector.runtime = runtime
	add_child(inspector)
	subtitles.auto_advance_delay = auto_advance
	magic = MagicPresentation.new()
	magic.name = "MagicPresentation"
	magic.time_scale = magic_time_scale
	add_child(magic)

	probe = InteractionProbe.new(camera)
	input = IntentInput.new()
	input.name = "IntentInput"
	input.picker = probe.pick
	input.intercept = func(px: Vector2) -> bool: return surface.handle_tap(px)
	add_child(input)
	flow = InteractionFlow.new()
	flow.name = "InteractionFlow"
	flow.witch = witch
	flow.witch_hotspot = witch_hotspot
	flow.runtime = runtime
	flow.surface = surface
	add_child(flow)
	# The live room (X13): its props are happenings committed through the Minds layer, its characters turn to what
	# moved, and Mirror's clock runs while the game does. The room's lines come back through _present.
	live = LiveHallCoordinator.new()
	live.name = "LiveHall"
	live.runtime = runtime
	live.run_clock = run_clock
	add_child(live)

	input.intent_emitted.connect(flow.handle)
	surface.option_chosen.connect(flow.choose_option)
	flow.focus_changed.connect(_on_focus_changed)
	subtitles.active_changed.connect(func(_active: bool) -> void: _refresh_input())
	pause_menu.save_requested.connect(_on_save)
	pause_menu.load_requested.connect(_on_load)
	pause_menu.quit_requested.connect(func() -> void: get_tree().quit())
	runtime.presenter = _present
	_register_presentation()
	SystemsPresenters.register(presentation, self)
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
	if not demo:
		menu = MainMenuUI.new()
		menu.name = "MainMenu"
		menu.camera = camera
		add_child(menu)
		menu.new_game_requested.connect(_on_new_game)
		menu.continue_requested.connect(_on_continue)
		menu.settings_requested.connect(_on_settings)

func _register_presentation() -> void:
	presentation.register("line", _play_line)
	presentation.register("dialogue", _play_dialogue)
	presentation.register("camera", _play_camera)
	presentation.register("anim", _play_anim)
	presentation.register("npc", _play_npc)
	presentation.register("magic", _play_magic)
	presentation.register("leave_frame", _play_leave_frame)
	presentation.register("ending", _play_ending)
	presentation.register("wait", _play_wait)
	presentation.register("room_variant", _play_room_variant)

# ---- boot -------------------------------------------------------------------------------------------

func _begin() -> void:
	if demo:
		await _begin_demo()
		return
	_scope_game()
	if args.has("load") and SaveGame.exists(SLOT):
		_start_session(true)
		return
	_show_menu()

# The whole game: every area package, so the catalog is the game's (the hall demo keeps the root files only).
func _scope_game() -> void:
	if not runtime.include_areas:
		runtime.include_areas = true
		runtime.setup()

func _begin_demo() -> void:
	if args.has("load") and SaveGame.exists(SLOT):
		runtime.load_game(SLOT)
	elif runtime.engine.event_store.size() == 0:
		runtime.new_game()
	dialogue = DialogueBridge.new(runtime.engine)
	_enter_place("clearing", "")
	_sync_departure()
	_started = true
	if args.has("show-options"):
		var target := str(args["show-options"])
		var interactable := room.get_interactable(target)
		if interactable != null:
			surface.show_options(interactable.display_name(), runtime.options_for(target), interactable.focus_point())
		return
	await _run_turn()

func _show_menu() -> void:
	_started = false
	if _backdrop == null:
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = BACKDROP_COLOUR
		_backdrop = WorldEnvironment.new()
		_backdrop.name = "MenuBackdrop"
		_backdrop.environment = environment
		add_child(_backdrop)
	camera.set_pose({"look_at": Vector3(0.0, 1.0, 0.0), "distance": 10.0, "pitch_deg": 5.0, "yaw_deg": 0.0, "roll_deg": 0.0, "fov": 60.0}, true)
	menu.camera = camera
	menu.open()
	_refresh_input()

func _on_new_game() -> void:
	_scope_game()
	var started := runtime.new_game()
	if not started.get("ok", false):
		push_error("GameRoot: a new game did not start: %s" % JSON.stringify(started))
		menu.open()
		return
	_start_session(false)

func _on_continue() -> void:
	_scope_game()
	var loaded := runtime.load_game(SLOT)
	if not loaded.get("ok", false):
		menu.open()
		return
	_start_session(true)

func _on_settings() -> void:
	# The settings screen is not wired into the boot path yet; the menu stays up.
	menu.open()

# The first room of a game (a new game, or a continued one): she is where Mirror has her. Storylets then play (the
# arrival of a first visit, for one).
func _start_session(continued: bool) -> void:
	_started = true
	menu.close()
	_remove_backdrop()
	dialogue = DialogueBridge.new(runtime.engine)
	await _take_turn()
	_held = false
	_enter_place(_witch_place(), _witch_from())
	if not continued:
		await _play_storylets()
	_refresh_world_view()
	_release_turn()

# ---- rooms ------------------------------------------------------------------------------------------

# Builds the room of a place and puts the witch in it. Whatever was there is taken away first.
func _enter_place(place_id: String, from: String, variant: String = "") -> void:
	var place := PlaceCatalog.load_place(place_id)
	if place == null:
		push_error("GameRoot: no usable place '%s'" % place_id)
		return
	_leave_room()
	current_place = place_id
	room = RoomFactory.build(place, variant)
	add_child(room)
	if not room is PaintedRoom:
		camera.make_current()
	RoomFactory.dress(room, place)
	flow.room = room
	_point_views_at_camera()
	live.attach(room)
	room.apply_mirror_state(runtime.engine)
	_place_witch(from)
	_sync_presence()
	_apply_capture_aids()
	_refresh_offers()

func _leave_room() -> void:
	if room == null:
		return
	surface.close()
	live.detach()
	remove_child(room)
	room.queue_free()
	room = null
	flow.room = null
	_outlined = null
	camera.make_current()

# A painted room has a camera of its own, and that is the one she is seen through.
func _point_views_at_camera() -> void:
	var view := _view_camera()
	probe.camera = view
	surface.camera = view
	subtitles.camera = view
	pause_menu.camera = view

func _view_camera() -> Camera3D:
	var current := get_viewport().get_camera_3d()
	return current if current != null else camera

func _place_witch(from: String) -> void:
	witch.stop()
	witch.navigator = room.navigator
	witch.position = room.arrival_point(from)
	witch.visible = not _postgame

func _remove_backdrop() -> void:
	if _backdrop != null:
		remove_child(_backdrop)
		_backdrop.queue_free()
		_backdrop = null

# Mirror says she is in another place than the room she is in: she moved (a GO action or a storylet). Returns true
# when the room was rebuilt.
func _sync_place() -> bool:
	if demo or runtime == null or runtime.engine == null:
		return false
	var target := _witch_place()
	if target.is_empty() or target == current_place:
		return false
	_held = false
	_enter_place(target, _witch_from())
	return true

func _witch_place() -> String:
	return str(runtime.engine.get_world("witch", {}).get("place", ""))

func _witch_from() -> String:
	return str(runtime.engine.get_world("witch", {}).get("from", ""))

# The people in the room she is in. Each person with a place in npc_state is shown where that place is; a person
# with none stands where Minds has them. A person who is not in the room is hidden, not removed.
func _sync_presence() -> void:
	if demo or room == null or runtime.minds == null:
		return
	var npc_state: Dictionary = runtime.engine.npc_state
	var minds_places: Dictionary = {}
	for holder in runtime.minds.data.get("holders", {}).keys():
		if str(holder) != MirrorRuntime.PLAYER:
			minds_places[str(holder)] = runtime.minds.presence_of(str(holder))
	var here := NpcPresence.present_ids(current_place, npc_state, minds_places)
	var everyone: Array = npc_state.keys()
	for holder in minds_places.keys():
		if not everyone.has(holder):
			everyone.append(holder)
	for id: Variant in everyone:
		var person := str(id)
		var is_here := here.has(person)
		if is_here and room.npc_node(person) == null:
			var at := room.spot_point(person)
			if NpcPresence.goes_with_witch(person, npc_state):
				at = witch.position + Vector3(-0.8, 0.0, 0.3)
			room.place_npc(person, NpcActor.build(person), at)
		room.show_npc(person, is_here)

# Offers a hotspot (its pick layer on) only while Mirror offers an action on it, and it is on stage.
func _refresh_offers() -> void:
	if room == null or runtime == null or runtime.engine == null:
		return
	for target in room.interactables.keys():
		var interactable: Interactable = room.get_interactable(str(target))
		PlaceRoom.set_offered(interactable, interactable.is_visible_in_tree() and _offers(str(target)))
	PlaceRoom.set_offered(witch_hotspot, witch.visible and _offers(WITCH_TARGET))

func _offers(target: String) -> bool:
	return not runtime.options_for(target).is_empty()

# The state the rest of the game reads after a change: the postgame, the offers, whether input may run.
func _refresh_world_view() -> void:
	_postgame = _is_postgame()
	flow.postgame = _postgame
	if _postgame:
		witch.visible = false
	_refresh_offers()
	_refresh_input()

func _is_postgame() -> bool:
	return str(runtime.engine.get_world("story", {}).get("act", "")) == "postgame"

# Capture aids (--variant, --magic, --shot ...) apply to whichever room is up, as they did to the hall.
func _apply_capture_aids() -> void:
	if args.has("magic"):
		PSXGlobals.set_magic(float(str(args["magic"])))
	if args.has("lens"):
		PSXGlobals.set_lens(float(str(args["lens"])))
	var hall := room as ArchiveHall
	if hall != null and args.has("variant"):
		if args.has("fade"):
			hall.plates.crossfade_to(str(args["variant"]), float(str(args["fade"])))
		else:
			hall.plates.set_variant(str(args["variant"]))
	if args.has("shot"):
		var shot := str(args["shot"])
		var focus: Array = ["tomas"] if shot in ["conversation", "consequence"] else []
		if shot in ["inspect", "magic_reveal"]:
			focus = [str(args.get("focus", "machine"))]
		var pose := director.pose_for(shot, focus)
		pose.erase("dolly")
		camera.set_pose(pose, true)
		camera.locked = true
	if args.has("cam"):
		var v := str(args["cam"]).split_floats(",")
		if v.size() >= 6:
			director.frozen = true
			camera.debug_place(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), v[6] if v.size() > 6 else 62.0)

# ---- the turn: one presentation at a time, storylets after every committed action ----------------------

# Serial: a presentation waits for the one before it. Input runs only when the turn is free.
func _take_turn() -> void:
	while _presenting:
		await get_tree().process_frame
	_presenting = true
	_refresh_input()

func _release_turn() -> void:
	_presenting = false
	_refresh_input()

func _run_turn() -> void:
	await _take_turn()
	await _play_storylets()
	_refresh_world_view()
	_release_turn()

# After a committed result: its presentation plays, then she is moved if Mirror moved her, then every eligible
# storylet plays (one at a time; a storylet may move her too, so the place is checked after each).
func _present(entries: Array, _result: Dictionary) -> void:
	await _take_turn()
	await presentation.play(entries)
	await _play_storylets()
	_refresh_world_view()
	if room != null:
		room.apply_mirror_state(runtime.engine)
	inspector.refresh()
	_release_turn()

func _play_storylets() -> void:
	_sync_place()
	for i in range(MAX_STORYLETS):
		var story := runtime.next_story()
		if not story.get("ok", false):
			break
		await presentation.play(story.get("presentation", []))
		_sync_place()

func _refresh_input() -> void:
	if input == null:
		return
	input.enabled = _started and not _presenting and not _menu_open() and not subtitles.is_active() and not pause_menu.is_open()

func _menu_open() -> bool:
	return menu != null and menu.is_open()

# ---- per-frame --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	# The diorama's own clock drives wind, shimmer and the vertex wobble. Captures use the frame
	# count instead of wall time, so the same frame number is the same picture, every run.
	_frames += 1
	_clock = float(_frames) / 60.0 if args.has("capture") else _clock + delta
	PSXGlobals.set_time(_clock)
	# The camera is bolted: it never follows the witch. Only the director moves it.
	_refresh_input()

func _on_resized() -> void:
	PSXGlobals.set_render_size(get_viewport().get_visible_rect().size)
	if camera != null:
		camera.refit()   # the roll fit depends on the screen's shape

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and surface != null:
		surface.hover(event.position)
	if event is InputEventMouseMotion and probe != null and room != null and not surface.is_open() and not subtitles.is_active():
		var hit := probe.pick(event.position)
		if str(hit.get("target_id", "")) != hover_target:
			hover_target = str(hit.get("target_id", ""))
			_update_outline()

# ---- focus, outline -----------------------------------------------------------------------------

func _on_focus_changed(_target_id: String) -> void:
	inspector.focus_target = flow.focused_target
	inspector.refresh()
	_update_outline()

func _update_outline() -> void:
	var wanted := flow.focused_target if not flow.focused_target.is_empty() else hover_target
	var node: Node3D = room.focus_node(wanted) if room != null and not wanted.is_empty() else null
	if node == _outlined:
		return
	if _outlined != null and is_instance_valid(_outlined):
		FocusOutline.set_focus(_outlined, false)
	_outlined = node
	if _outlined != null:
		FocusOutline.set_focus(_outlined, true)

# The node a speaker stands at, when it is in the room and showing ("witch" is the witch; the narrator has none).
func _actor_node(id: String) -> Node3D:
	if id == "witch" or id == "player":
		return witch
	if id.is_empty() or id == "narrator" or room == null:
		return null
	return room.npc_node(id)

# Where a speaker's head is, for the bubble's tail. Her own thought comes from her head.
func _bubble_anchor(speaker_id: String) -> Vector3:
	var node := _actor_node(speaker_id)
	if node != null and node != witch and node.is_inside_tree() and node.visible:
		return node.global_position + Vector3(0, 1.45, 0)
	return witch.global_position + Vector3(0, 1.8, 0)

# The room's focal regions as screen rectangles, so a bubble can keep off them.
func _hero_rects() -> Array:
	var rects: Array = []
	if room == null or camera == null:
		return rects
	for region: Dictionary in room.hero_regions():
		var at: Vector3 = region["at"]
		var radius := float(region["radius"])
		var top := at + Vector3(0, float(region["height"]), 0)
		var corners: Array[Vector3] = [at + Vector3(radius, 0, 0), at - Vector3(radius, 0, 0), at + Vector3(0, 0, radius), at - Vector3(0, 0, radius), top]
		if region.has("to"):
			var to: Vector3 = region["to"]
			corners.append_array([to + Vector3(radius, 0, 0), to - Vector3(radius, 0, 0), to + Vector3(0, 0, radius), to - Vector3(0, 0, radius)])
		var rect := Rect2(camera.unproject_position(at), Vector2.ZERO)
		for corner in corners:
			if camera.is_position_behind(corner):
				continue
			rect = rect.expand(camera.unproject_position(corner))
		rects.append(rect)
	return rects

func _focus_position(id: String) -> Variant:
	if id == "player" or id == WITCH_TARGET:
		return witch.global_position + Vector3(0, 1.0, 0)
	return room.focus_position(id) if room != null else null

func _framing() -> Dictionary:
	return room.framing() if room != null else {"focus": Vector3.ZERO, "distance": 11.5, "pitch_deg": 32.0, "yaw_deg": 0.0, "fov": 40.0, "roll_deg": 0.0}

func _shot_pose(mode: String, focus_ids: Array, roll_deg: float) -> Dictionary:
	return room.shot_pose(mode, focus_ids, roll_deg) if room != null else {}

# ---- presentation handlers --------------------------------------------------------------------------

func _play_line(entry: Dictionary) -> void:
	var speaker := str(entry.get("speaker", ""))
	var text := tr(str(entry.get("key", "")))
	if speaker.is_empty() or speaker == "narrator":
		await subtitles.show_line("", text, "")
		return
	var shown := tr("speaker." + speaker)
	var node := _actor_node(speaker)
	var present := speaker == "witch" or (node != null and node.visible)
	if present:
		await subtitles.show_line(shown, text, speaker)
	else:
		# A caption: the speaker is not on stage, so the line says who it is in the narration's own voice.
		await subtitles.show_line("", "%s: %s" % [shown, text], "")

func _play_dialogue(entry: Dictionary) -> void:
	if dialogue == null or not dialogue.is_ready():
		return
	await dialogue.run(str(entry.get("title", "")), _dialogue_sink, null, str(entry.get("npc", "tomas")))

func _dialogue_sink(speaker: String, text: String, _responses: Array) -> int:
	await subtitles.show_line(speaker, text, dialogue.current_speaker_id)
	return 0

# A `stay` holds the camera until she changes room: later camera entries do not undo it (the ending's contract).
func _play_camera(entry: Dictionary) -> void:
	var mode := str(entry.get("mode", "wide"))
	if _held and mode != "stay":
		return
	if mode == "stay":
		_held = true
	director.frame(mode, entry.get("focus", []))

func _play_anim(entry: Dictionary) -> void:
	var actor := str(entry.get("actor", ""))
	var clip := str(entry.get("name", ""))
	if actor == "player" or actor == WITCH_TARGET:
		await witch.animation.play(clip)
		return
	var node := _actor_node(actor)
	if node is NPC:
		await (node as NPC).play_anim(clip)
	elif node != null and CharacterModels.has_clip(node, clip):
		CharacterModels.play(node, clip)

func _play_npc(entry: Dictionary) -> void:
	var node := _actor_node(str(entry.get("actor", "")))
	if node is NPC:
		await (node as NPC).set_pose(str(entry.get("pose", "")))

func _play_magic(entry: Dictionary) -> void:
	var at: Variant = room.focus_position(str(entry.get("target", ""))) if room != null else null
	var position: Vector3 = at if at is Vector3 else Vector3.ZERO
	witch.animation.play("cast")
	magic.peaked.connect(func(_effect: String) -> void: room.apply_mirror_state(runtime.engine), CONNECT_ONE_SHOT)
	await magic.play(str(entry.get("effect", "")), Vector3(position.x, 0.0, position.z))

# The actor walks off the frame (the witch by default) and is gone from it. `to` (a plate pixel) sets the way out.
func _play_leave_frame(entry: Dictionary) -> void:
	var actor := str(entry.get("actor", WITCH_TARGET))
	var to := room.exit_point()
	var px: Variant = entry.get("to")
	if px is Array and (px as Array).size() >= 2 and room != null:
		var floor_point := room.pixel_to_floor(Vector2(float(px[0]), float(px[1])))
		if floor_point.is_finite():
			to = floor_point
	if actor == "player" or actor == WITCH_TARGET:
		await witch.walk_off(to)
		witch.visible = false
		return
	var node := _actor_node(actor)
	if node != null:
		node.visible = false

# The ending (the invitation): she walks out of the frame, the camera holds where it is, and the postgame begins.
func _play_ending(_entry: Dictionary) -> void:
	await witch.walk_off(room.exit_point())
	witch.visible = false
	_held = true
	director.frame("stay")

func _play_wait(entry: Dictionary) -> void:
	await get_tree().create_timer(float(entry.get("seconds", 0.5))).timeout

# The room ages. The archive crossfades its plates; a painted place rebuilds on the variant's picture, with her back at
# the arrival point.
func _play_room_variant(entry: Dictionary) -> void:
	var variant := str(entry.get("variant", ""))
	var hall := room as ArchiveHall
	if hall != null:
		await hall.set_room_variant(variant, float(entry.get("seconds", PlateStage.CROSSFADE_SECONDS)))
	elif room != null and not variant.is_empty():
		_enter_place(current_place, _witch_from(), variant)

# ---- save and load ----------------------------------------------------------------------------------

func _on_save() -> void:
	var error := runtime.save_game(SLOT, {"room": current_place})
	pause_menu.say(tr("ui.saved") if error == OK else tr("ui.load_failed"))

func _on_load() -> void:
	var result := runtime.load_game(SLOT)
	if result.get("ok", false):
		_restore_from_mirror()
		if result.has("recovered"):
			# A recovered game says so and stays open: the count is the notice.
			var recovered: Dictionary = result["recovered"]
			pause_menu.say(tr("ui.save_recovered") % [int(recovered["kept"]), int(recovered["of"])])
		else:
			pause_menu.say(tr("ui.loaded"))
			pause_menu.close()
	elif result.get("error", "") == "no_save":
		pause_menu.say(tr("ui.no_save"))
	else:
		pause_menu.say(tr("ui.load_failed"))

# Rebuilds what Mirror's state describes after a load: the dialogue bridge is on the new engine, the room is the
# place she is in, and the people and offers follow.
func _restore_from_mirror() -> void:
	dialogue = DialogueBridge.new(runtime.engine)
	_held = false
	if demo:
		if room != null:
			room.apply_mirror_state(runtime.engine)
		_sync_departure()
		return
	_enter_place(_witch_place(), _witch_from())
	_refresh_world_view()

# ---- the hall demo's departure (the demo's own story: the hall is the whole game) -----------------------

# A saved demo game in which the witch already took the path out has no witch in the clearing.
func _sync_departure() -> void:
	var departed: bool = bool(runtime.engine.get_world("clearing", {}).get("departed", false))
	witch.visible = not departed
	var hall := room as ArchiveHall
	if departed:
		director.frame("stay")
		# the light has gone on without her (the beat that ages the room, replayed instantly)
		if hall != null:
			hall.plates.set_variant("dusk")
	elif hall != null and not hall.plates.variant.is_empty() and not args.has("variant"):
		hall.plates.set_variant("")

# ---- debug ------------------------------------------------------------------------------------------

func _capture_then_quit() -> void:
	var frames := int(str(args.get("capture-frames", "45")))
	for i in range(frames):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := str(args["capture"])
	# The arrival subtitle's box in the picture's own pixels, for the pixel check (tests/render/analyze_shots.gd).
	var box: Variant = null
	if subtitles.is_active() and subtitles.bubble().is_showing():
		var rect := subtitles.bubble().screen_rect()
		box = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var sidecar := FileAccess.open(path.get_basename() + ".subtitle.json", FileAccess.WRITE)
	if sidecar != null:
		sidecar.store_string(JSON.stringify({"subtitle": box}))
		sidecar.close()
	var error := image.save_png(path)
	print("CAPTURE %s %s (%s)" % [path, image.get_size(), "ok" if error == OK else "error %d" % error])
	get_tree().quit(0 if error == OK else 1)

func _run_debug_sim() -> void:
	var paths: Array[String] = []
	if args["debug-sim"] is String:
		paths.append(str(args["debug-sim"]))
	else:
		paths = SimulationRunner.list_scripts()
	var failed := false
	for path in paths:
		var script := SimulationRunner.load_script(path)
		var fresh := MirrorRuntime.new()
		fresh.include_areas = SimulationRunner.wants_areas(script)
		fresh.new_game()
		var runner := SimulationRunner.new()
		var outcome := runner.run(fresh, script)
		print("=== %s: %s" % [path.get_file(), "OK" if outcome["ok"] else "FAILED"])
		for line in runner.report(fresh):
			print(line)
		if not outcome["ok"]:
			failed = true
			print("failed_step=%d expect=%s" % [outcome["failed_step"], outcome["expect_failures"]])
		fresh.free()
	get_tree().quit(1 if failed else 0)
