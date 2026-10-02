extends SceneTree

# Before/after frames of a room's margin (docs/art/painted_room.md, "Margins and other shots"). The window's shape
# is the shape under test:
#   xvfb-run -a -s "-screen 0 1800x1000x24" godot --path . --rendering-method gl_compatibility \
#       --rendering-driver opengl3 --resolution 1680x720 --script res://tools/painted/capture_margins.gd -- OUT_DIR TAG [ROOM_DIR]
# For each of "without margin" and "with margin": a flat frame and rolled frames, PSX look and the raw painting.
# Files: <TAG>_<nomargin|margin>_<psx|raw>_roll<deg>.png

const ROLLS := [0.0, 5.0]

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://margins"
	var tag := args[1] if args.size() > 1 else "shape"
	DirAccess.make_dir_recursive_absolute(out)
	for with_margin in [false, true]:
		var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
		room.overscan = with_margin
		if args.size() > 2:
			room.room_dir = args[2]
		root.add_child(room)
		for i in 20:
			await process_frame
		for look in ["psx", "raw"]:
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if look == "psx" else Window.CONTENT_SCALE_MODE_DISABLED
			room.set_psx(look == "psx")
			for roll in ROLLS:
				room.set_camera_offset(Vector3.ZERO, roll)
				for i in 8:
					await process_frame
				var image := root.get_texture().get_image()
				var name := "%s_%s_%s_roll%d.png" % [tag, "margin" if with_margin else "nomargin", look, int(roll)]
				image.save_png(out.path_join(name))
				print("CAPTURE %s %dx%d fov %.2f margin %s" % [name, image.get_width(), image.get_height(), room.camera.fov, room.margin()])
		room.free()
		await process_frame
	quit()
