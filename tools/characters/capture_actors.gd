extends SceneTree

# The live witch and raccoon in the painted room, for judging them against the painting
# (tools/characters/compare_painted.py cuts the same boxes out of the reference and this):
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
#       --resolution 1280x720 --script res://tools/characters/capture_actors.gd -- OUT_DIR
# Writes room_raw.png (1280x720, PSX off), room_psx.png (game resolution, PSX on) and, for each
# character, studio_<id>_<view>.png: the model alone on a grey ground, front/side/back/three-quarter.

const VIEWS := {"front": 0.0, "side": 90.0, "back": 180.0, "three_quarter": 35.0}
const STUDIO_SIZE := Vector2i(480, 640)

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://actors"
	DirAccess.make_dir_recursive_absolute(out)
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	root.add_child(room)
	for i in 30:
		await process_frame
	for shot in [["room_raw", false, true], ["room_psx", true, false]]:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED if shot[2] else Window.CONTENT_SCALE_MODE_VIEWPORT
		room.set_psx(shot[1])
		for i in 8:
			await process_frame
		var image := root.get_texture().get_image()
		image.save_png(out.path_join("%s.png" % shot[0]))
		print("CAPTURE %s %dx%d" % [shot[0], image.get_width(), image.get_height()])
	# The same frame with the actors lit harder than the room's defaults, to see how much of any colour gap is the
	# room's actor lighting (painted_room.gd: actor_light, actor_sun) rather than the models' albedo.
	room.actor_light = 1.7
	room.actor_sun = 0.8
	room.relight_actors()
	for i in 4:
		await process_frame
	var lit := root.get_texture().get_image()
	lit.save_png(out.path_join("room_psx_lit.png"))
	print("CAPTURE room_psx_lit %dx%d" % [lit.get_width(), lit.get_height()])
	room.queue_free()
	await process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await _studio(out)
	quit()

# Each character alone, turned on a plinth in front of an orthographic camera, lit by the same
# actor shader parameters the room uses (a flat grey floor light map, the room's sun colour).
func _studio(out: String) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	holder.add_child(camera)
	var viewport_size := root.size
	print("STUDIO window %s" % viewport_size)
	for id in ["witch", "raccoon"]:
		var visual := CharacterModels.instantiate(id)
		if visual == null:
			continue
		var turn := Node3D.new()
		holder.add_child(turn)
		turn.add_child(visual)
		var height := 1.45 if id == "witch" else 0.85
		camera.size = height
		camera.position = Vector3(0.0, height * 0.5, 4.0)
		camera.look_at(Vector3(0.0, height * 0.5, 0.0))
		for view in VIEWS:
			turn.rotation_degrees.y = float(VIEWS[view])
			for i in 6:
				await process_frame
			var image := root.get_texture().get_image()
			image.save_png(out.path_join("studio_%s_%s.png" % [id, view]))
		turn.queue_free()
		await process_frame
