class_name GameRoot
extends Node

# Composition root. It builds the room, the witch, the camera and the UI, and connects them:
#
#   pointer -> PlayerIntent -> InteractionFlow -> Mirror (commit) -> PresentationDirector
#
# Nothing here decides what happened. Command-line hooks (after `--`):
#   --debug-sim [script.json]   run deterministic simulation(s) headlessly, print the transcript, exit
#   --capture out.png           render, save a screenshot after --capture-frames N (default 45), exit
#   --sim-first name            play data/sim/name.json first, so the scene starts in that state
#   --show-options target       open the action surface for a target without walking (capture aid)
#   --load                      continue from save slot 1
#   --magic amount              hold the magic shader globals at 0..1 (capture aid: shows the break)
#   --shot mode                 hold the camera on a director shot (wide, inspect, conversation, magic_reveal ...)
#   --lens amount               hold the fisheye lens swing at 0..1 (capture aid)
#   --no-fx                     leave out the light shaft, dust and glow (capture aid)
#   --cam x,y,z,tx,ty,tz[,fov] put the camera there, looking at t (capture aid: inspect the set)

const SLOT := 1

# Injected by tests; otherwise the `Mirror` autoload is used.
var runtime: MirrorRuntime
var args: Dictionary = {}
# Headless tests and capture aids: advance subtitles by themselves, and shorten magic.
var auto_advance := -1.0
var magic_time_scale := 1.0

var room: ArchiveHall
var witch: Witch
var camera: DioramaCamera
var director: CameraDirector
var input: IntentInput
var probe: InteractionProbe
var flow: InteractionFlow
var subtitles: SubtitleUI
var surface: InteractionPresenter
var pause_menu: PauseMenuUI
var inspector: MirrorInspector
var magic: MagicPresentation
var dialogue: DialogueBridge
var presentation := PresentationDirector.new()
var hover_target := ""
var _outlined: Node3D
var _frame_left: Node3D
var _frame_right: Node3D
var _frame_left_x := 0.0
var _frame_right_x := 0.0
var _started := false
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

func _build() -> void:
	PSXGlobals.reset()
	ArchiveHall.atmosphere_enabled = not args.has("no-fx")
	room = ArchiveHall.new()
	room.name = "ArchiveHall"
	add_child(room)

	witch = Witch.new()
	witch.name = "Witch"
	witch.navigator = room.navigator
	witch.position = room.spawn_position
	add_child(witch)

	camera = DioramaCamera.new()
	camera.name = "DioramaCamera"
	camera.current = true
	add_child(camera)
	_mount_foreground()
	director = CameraDirector.new()
	director.camera = camera
	director.framing_provider = room.framing
	director.focus_resolver = _focus_position
	add_child(director)
	director.frame("wide", [], true)
	director.cut.connect(func(mode: String) -> void:
		# the frame suits the wide and the spell; close-ups need the space
		if room.foreground != null:
			room.foreground.visible = mode in ["wide", "magic_reveal", "stay"])

	var post := CanvasLayer.new()
	post.name = "PSXScreen"
	post.layer = 1
	var grade := ColorRect.new()
	grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade.material = PSXMaterials.screen()
	post.add_child(grade)
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
	flow.room = room
	flow.witch = witch
	flow.runtime = runtime
	flow.surface = surface
	add_child(flow)

	input.intent_emitted.connect(flow.handle)
	surface.option_chosen.connect(flow.choose_option)
	flow.focus_changed.connect(_on_focus_changed)
	subtitles.active_changed.connect(func(active: bool) -> void: input.enabled = not active and not runtime.is_busy())
	pause_menu.save_requested.connect(_on_save)
	pause_menu.load_requested.connect(_on_load)
	pause_menu.quit_requested.connect(func() -> void: get_tree().quit())
	runtime.presenter = _present
	_register_presentation()
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
	if args.has("magic"):
		PSXGlobals.set_magic(float(str(args["magic"])))
	if args.has("lens"):
		PSXGlobals.set_lens(float(str(args["lens"])))
	if args.has("shot"):
		var focus: Array = ["tomas"] if str(args["shot"]) in ["inspect", "conversation", "consequence"] else []
		var points: Array = []
		for id in focus:
			var at: Variant = _focus_position(str(id))
			if at is Vector3:
				points.append(at)
		camera.set_pose(CameraDirector.compute_pose(str(args["shot"]), points, room.framing()), true)
		camera.locked = true
	if args.has("cam"):
		var v := str(args["cam"]).split_floats(",")
		if v.size() >= 6:
			director.frozen = true
			camera.debug_place(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]), v[6] if v.size() > 6 else 62.0)

# The dark shelf/globe/rock frame rides on the camera: it is authored in camera space.
func _mount_foreground() -> void:
	var frame := room.foreground
	if frame == null:
		return
	room.remove_child(frame)
	camera.add_child(frame)
	frame.transform = Transform3D.IDENTITY
	for child in frame.get_children():
		if child.name == "FgLeft":
			_frame_left = child as Node3D
			_frame_left_x = _frame_left.position.x
		elif child.name == "FgRight":
			_frame_right = child as Node3D
			_frame_right_x = _frame_right.position.x
	_fit_foreground()

# Keeps the two edges of the frame at the two edges of the picture at any aspect ratio. The pieces
# were authored for 16:9; a narrower screen pulls them in, a wider one pushes them out.
func _fit_foreground() -> void:
	if _frame_left == null or camera == null:
		return
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var depth := 4.4
	var half_actual := depth * tan(deg_to_rad(camera.fov) * 0.5) * aspect
	var half_authored := depth * tan(deg_to_rad(60.0) * 0.5) * (16.0 / 9.0)
	_frame_left.position.x = _frame_left_x - (half_actual - half_authored)
	_frame_right.position.x = _frame_right_x + (half_actual - half_authored)

func _register_presentation() -> void:
	presentation.register("line", _play_line)
	presentation.register("dialogue", _play_dialogue)
	presentation.register("camera", _play_camera)
	presentation.register("anim", _play_anim)
	presentation.register("npc", _play_npc)
	presentation.register("magic", _play_magic)
	presentation.register("leave_frame", _play_leave_frame)
	presentation.register("wait", _play_wait)

func _begin() -> void:
	if args.has("load") and SaveGame.exists(SLOT):
		var loaded := runtime.load_game(SLOT)
		if loaded.get("ok", false):
			room.apply_mirror_state(runtime.engine)
	elif runtime.engine.event_store.size() == 0:
		runtime.new_game()
	dialogue = DialogueBridge.new(runtime.engine)
	room.apply_mirror_state(runtime.engine)
	_sync_departure()
	_started = true
	if args.has("show-options"):
		var target := str(args["show-options"])
		var interactable := room.get_interactable(target)
		if interactable != null:
			surface.show_options(interactable.display_name(), runtime.options_for(target), interactable.focus_point())
		return
	var story := runtime.next_story()
	if story.get("ok", false):
		input.enabled = false
		await presentation.play(story.get("presentation", []))
		input.enabled = true
		director.return_to_wide()

func _capture_then_quit() -> void:
	var frames := int(str(args.get("capture-frames", "45")))
	for i in range(frames):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := str(args["capture"])
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
		var fresh := MirrorRuntime.new()
		fresh.new_game()
		var runner := SimulationRunner.new()
		var outcome := runner.run(fresh, SimulationRunner.load_script(path))
		print("=== %s: %s" % [path.get_file(), "OK" if outcome["ok"] else "FAILED"])
		for line in runner.report(fresh):
			print(line)
		if not outcome["ok"]:
			failed = true
			print("failed_step=%d expect=%s" % [outcome["failed_step"], outcome["expect_failures"]])
		fresh.free()
	get_tree().quit(1 if failed else 0)

# ---- per-frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	# The diorama's own clock drives wind, shimmer and the vertex wobble. Captures use the frame
	# count instead of wall time, so the same frame number is the same picture, every run.
	_frames += 1
	_clock = float(_frames) / 60.0 if args.has("capture") else _clock + delta
	PSXGlobals.set_time(_clock)
	# The camera is bolted: it never follows the witch. Only the director moves it.
	if input != null and camera != null and not runtime.is_busy():
		input.enabled = not subtitles.is_active() and not pause_menu.is_open()

func _on_resized() -> void:
	PSXGlobals.set_render_size(get_viewport().get_visible_rect().size)
	_fit_foreground()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and surface != null:
		surface.hover(event.position)
	if event is InputEventMouseMotion and probe != null and not surface.is_open() and not subtitles.is_active():
		var hit := probe.pick(event.position)
		if str(hit.get("target_id", "")) != hover_target:
			hover_target = str(hit.get("target_id", ""))
			_update_outline()

# ---- focus, outline -----------------------------------------------------------------------------

func _on_focus_changed(_target_id: String) -> void:
	inspector.focus_target = flow.focused_target
	inspector.refresh()
	_update_outline()

# A saved game in which the witch already took the path out has no witch in the clearing.
func _sync_departure() -> void:
	var departed: bool = bool(runtime.engine.get_world("clearing", {}).get("departed", false))
	witch.visible = not departed
	if departed:
		director.frame("stay")

func _update_outline() -> void:
	var wanted := flow.focused_target if not flow.focused_target.is_empty() else hover_target
	var node := room.focus_node(wanted) if not wanted.is_empty() else null
	if node == _outlined:
		return
	if _outlined != null and is_instance_valid(_outlined):
		FocusOutline.set_focus(_outlined, false)
	_outlined = node
	if _outlined != null:
		FocusOutline.set_focus(_outlined, true)

# Where a speaker's head is, for the bubble's tail. The narrator is the witch's own thought.
func _bubble_anchor(speaker_id: String) -> Vector3:
	if speaker_id == "tomas" and room != null and room.tomas != null:
		return room.tomas.global_position + Vector3(0, 1.45, 0)
	return witch.global_position + Vector3(0, 1.8, 0)

# The room's focal cylinders as screen rectangles, so a bubble can keep off them.
func _hero_rects() -> Array:
	var rects: Array = []
	if room == null or camera == null:
		return rects
	for region: Dictionary in room.hero_regions():
		var at: Vector3 = region["at"]
		var radius := float(region["radius"])
		var top := at + Vector3(0, float(region["height"]), 0)
		var corners: Array[Vector3] = [at + Vector3(radius, 0, 0), at - Vector3(radius, 0, 0), at + Vector3(0, 0, radius), at - Vector3(0, 0, radius), top]
		var rect := Rect2(camera.unproject_position(at), Vector2.ZERO)
		for corner in corners:
			if camera.is_position_behind(corner):
				continue
			rect = rect.expand(camera.unproject_position(corner))
		rects.append(rect)
	return rects

func _focus_position(id: String) -> Variant:
	if id == "player":
		return witch.global_position + Vector3(0, 1.0, 0)
	return room.focus_position(id)

# ---- presentation handlers --------------------------------------------------------------------

func _present(entries: Array, _result: Dictionary) -> void:
	input.enabled = false
	await presentation.play(entries)
	# Mirror is the truth: whatever the choreography did, end on what actually happened.
	room.apply_mirror_state(runtime.engine)
	director.return_to_wide()
	inspector.refresh()
	input.enabled = true

func _play_line(entry: Dictionary) -> void:
	var speaker := str(entry.get("speaker", ""))
	var shown := "" if speaker.is_empty() or speaker == "narrator" else tr("speaker." + speaker)
	await subtitles.show_line(shown, tr(str(entry.get("key", ""))), speaker)

func _play_dialogue(entry: Dictionary) -> void:
	if dialogue == null or not dialogue.is_ready():
		return
	await dialogue.run(str(entry.get("title", "")), _dialogue_sink)

func _dialogue_sink(speaker: String, text: String, _responses: Array) -> int:
	await subtitles.show_line(speaker, text, dialogue.current_speaker_id)
	return 0

func _play_camera(entry: Dictionary) -> void:
	director.frame(str(entry.get("mode", "wide")), entry.get("focus", []))

func _play_anim(entry: Dictionary) -> void:
	match str(entry.get("actor", "")):
		"player":
			await witch.animation.play(str(entry.get("name", "")))
		"tomas":
			await room.tomas.play_anim(str(entry.get("name", "")))

func _play_npc(entry: Dictionary) -> void:
	if str(entry.get("actor", "")) == "tomas":
		await room.tomas.set_pose(str(entry.get("pose", "")))

func _play_magic(entry: Dictionary) -> void:
	var at: Variant = room.focus_position(str(entry.get("target", "")))
	var position: Vector3 = at if at is Vector3 else Vector3.ZERO
	witch.animation.play("cast")
	magic.peaked.connect(func(_effect: String) -> void: room.apply_mirror_state(runtime.engine), CONNECT_ONE_SHOT)
	await magic.play(str(entry.get("effect", "")), Vector3(position.x, 0.0, position.z))

func _play_leave_frame(_entry: Dictionary) -> void:
	# The camera has been told to stay; the witch walks away along the path and keeps going.
	await witch.walk_off(Vector3(0, 0, -16.0))
	witch.visible = false

func _play_wait(entry: Dictionary) -> void:
	await get_tree().create_timer(float(entry.get("seconds", 0.5))).timeout

# ---- menu hooks ---------------------------------------------------------------------------------

func _on_save() -> void:
	var error := runtime.save_game(SLOT, {"room": room.room_id})
	pause_menu.say(tr("ui.saved") if error == OK else tr("ui.load_failed"))

func _on_load() -> void:
	var result := runtime.load_game(SLOT)
	if result.get("ok", false):
		room.apply_mirror_state(runtime.engine)
		_sync_departure()
		pause_menu.say(tr("ui.loaded"))
		pause_menu.close()
	elif result.get("error", "") == "no_save":
		pause_menu.say(tr("ui.no_save"))
	else:
		pause_menu.say(tr("ui.load_failed"))
