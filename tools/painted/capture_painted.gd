extends SceneTree

# Frames of game/world/painted/painted_room.tscn for comparison with the painting:
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1280x720 \
#       --script res://tools/painted/capture_painted.gd -- OUT_DIR [ROOM_DIR]
# Each shot: name, PSX on/off, camera offset (m, camera frame), roll (deg), full-resolution render or not.

const SHOTS := [
	["painted_raw", false, Vector3.ZERO, 0.0, true],
	["psx", true, Vector3.ZERO, 0.0, false],
	["psx_roll", true, Vector3.ZERO, 3.5, false],
	["psx_step_right", true, Vector3(0.35, 0.0, 0.0), 0.0, false],
	["psx_step_in", true, Vector3(0.0, -0.15, -0.8), 0.0, false],
	["raw_step_right", false, Vector3(0.35, 0.0, 0.0), 0.0, true],
]

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://painted"
	DirAccess.make_dir_recursive_absolute(out)
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	if args.size() > 1:
		room.room_dir = args[1]
	root.add_child(room)
	for i in 30:
		await process_frame
	for shot in SHOTS:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED if shot[4] else Window.CONTENT_SCALE_MODE_VIEWPORT
		room.set_psx(shot[1])
		room.set_camera_offset(shot[2], shot[3])
		for i in 8:
			await process_frame
		var image := root.get_texture().get_image()
		image.save_png(out.path_join("%s.png" % shot[0]))
		print("CAPTURE %s %dx%d" % [shot[0], image.get_width(), image.get_height()])
	# Every prop, tapped through its reactions: a frame every 3 ticks (press_<id>_<reaction>_<n>.png).
	room.set_camera_offset(Vector3.ZERO, 0.0)
	room.set_psx(true)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	for prop in room.props:
		for turn in (prop.reactions.get("press", []) as Array).size():
			var pressed := room.press(Vector2(prop.rect.get_center()))
			var reaction := str(prop.reactions["press"][turn])
			print("PRESS %s -> %s (%s)" % [prop.prop_id, pressed, reaction])
			for frame in 16:
				for i in 3:
					await process_frame
				root.get_texture().get_image().save_png(out.path_join("press_%s_%s_%02d.png" % [prop.prop_id, reaction, frame]))
			for i in 40:
				await process_frame
	quit()
