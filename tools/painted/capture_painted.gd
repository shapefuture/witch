extends SceneTree

# Frames of game/world/painted/painted_room.tscn for comparison with the painting:
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 \
#       --script res://tools/painted/capture_painted.gd -- OUT_DIR [ROOM_DIR] [toys|views|all]
# views: the standard shots (name, PSX on/off, camera offset (m, camera frame), roll (deg), full-resolution or not).
# toys:  the room at rest with its cards against the painting itself (REST lines: the pixels must agree), then
#        every prop through every reaction, cropped (toy_<id>_<n>_<reaction>_<frame>.png, 2 ticks apart; join
#        them with tools/painted/toy_sheet.py).

const SHOTS := [
	["painted_raw", false, Vector3.ZERO, 0.0, true],
	["psx", true, Vector3.ZERO, 0.0, false],
	["psx_roll", true, Vector3.ZERO, 3.5, false],
	["psx_step_right", true, Vector3(0.35, 0.0, 0.0), 0.0, false],
	["psx_step_in", true, Vector3(0.0, -0.15, -0.8), 0.0, false],
	["raw_step_right", false, Vector3(0.35, 0.0, 0.0), 0.0, true],
]
const FRAMES_PER_REACTION := 12
const TICKS_PER_FRAME := 2

func _initialize() -> void:
	_run()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://painted"
	var which := args[2] if args.size() > 2 else "all"
	DirAccess.make_dir_recursive_absolute(out)
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	if args.size() > 1 and not args[1].is_empty():
		room.room_dir = args[1]
	root.add_child(room)
	await _frames(30)
	if which in ["views", "all"]:
		await _views(room, out)
	if which in ["toys", "all"]:
		await _rest_check(room, out)
		await _toys(room, out)
	quit()

func _views(room: PaintedRoom, out: String) -> void:
	for shot in SHOTS:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED if shot[4] else Window.CONTENT_SCALE_MODE_VIEWPORT
		room.set_psx(shot[1])
		room.set_camera_offset(shot[2], shot[3])
		await _frames(8)
		var image := root.get_texture().get_image()
		image.save_png(out.path_join("%s.png" % shot[0]))
		print("CAPTURE %s %dx%d" % [shot[0], image.get_width(), image.get_height()])
	room.set_camera_offset(Vector3.ZERO, 0.0)

# The room with its cards at rest, against the room drawn as the painting itself (cards hidden, plate for the
# base): the two must be the same picture, in PSX mode and in the raw one. The characters would move, so they hide.
func _rest_check(room: PaintedRoom, out: String) -> void:
	for actor in room.actors.values():
		(actor as Node3D).visible = false
	room.set_camera_offset(Vector3.ZERO, 0.0)
	for mode in [["psx", true, Window.CONTENT_SCALE_MODE_VIEWPORT], ["psx_full", true, Window.CONTENT_SCALE_MODE_DISABLED], ["raw", false, Window.CONTENT_SCALE_MODE_DISABLED]]:
		root.content_scale_mode = mode[2]
		room.set_psx(mode[1])
		room.show_originals(false)
		await _frames(8)
		var cards := root.get_texture().get_image()
		room.show_originals(true)
		await _frames(8)
		var originals := root.get_texture().get_image()
		room.show_originals(false)
		cards.convert(Image.FORMAT_RGB8)
		originals.convert(Image.FORMAT_RGB8)
		var a := cards.get_data()
		var b := originals.get_data()
		var differing := 0
		var worst := 0
		var diff := Image.create_empty(cards.get_width(), cards.get_height(), false, Image.FORMAT_RGB8)
		for i in range(0, a.size(), 3):
			var d := maxi(maxi(absi(a[i] - b[i]), absi(a[i + 1] - b[i + 1])), absi(a[i + 2] - b[i + 2]))
			if d > 0:
				differing += 1
				worst = maxi(worst, d)
				var index := floori(i / 3.0)
				diff.set_pixel(index % cards.get_width(), floori(float(index) / cards.get_width()), Color(1, 1, 1))
		print("REST %s %dx%d differing_pixels=%d worst_channel_difference=%d" % [mode[0], cards.get_width(), cards.get_height(), differing, worst])
		cards.save_png(out.path_join("rest_%s_cards.png" % mode[0]))
		originals.save_png(out.path_join("rest_%s_originals.png" % mode[0]))
		if differing > 0:
			diff.save_png(out.path_join("rest_%s_diff.png" % mode[0]))
	for actor in room.actors.values():
		(actor as Node3D).visible = true

# Every prop through every reaction: crops of the prop's rect (with a margin), a frame every few ticks.
func _toys(room: PaintedRoom, out: String) -> void:
	room.set_camera_offset(Vector3.ZERO, 0.0)
	room.set_psx(true)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await _frames(8)
	for prop in room.props:
		var names: Array = prop.reactions.get("press", [])
		var margin := 24
		var crop := Rect2i(prop.rect).grow(margin).intersection(Rect2i(0, 0, 1280, 720))
		for turn in names.size():
			var pressed := room.press(_inside(prop))
			print("PRESS %s -> %s (%s) sound=%s say=%s" % [prop.prop_id, pressed, prop.last_reaction, prop.last_sound, prop.last_say])
			for frame in FRAMES_PER_REACTION:
				await _frames(TICKS_PER_FRAME)
				var image := root.get_texture().get_image().get_region(crop)
				image.save_png(out.path_join("toy_%s_%d_%s_%02d.png" % [prop.prop_id, turn, prop.last_reaction, frame]))
			prop.rest()
			await _frames(4)

func _inside(prop: PaintedProp) -> Vector2:
	var best := Vector2(prop.rect.get_center())
	var best_distance := INF
	for y in range(prop.rect.position.y, prop.rect.end.y, 2):
		for x in range(prop.rect.position.x, prop.rect.end.x, 2):
			var px := Vector2(x, y)
			if prop.contains(px) and px.distance_to(Vector2(prop.rect.get_center())) < best_distance:
				best_distance = px.distance_to(Vector2(prop.rect.get_center()))
				best = px
	return best
