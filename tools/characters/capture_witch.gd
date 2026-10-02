extends SceneTree

# The live witch for judging her against the user's reference sheet (tools/characters/witch_strip.py cuts and joins these):
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
#       --resolution 1280x720 --script res://tools/characters/capture_witch.gd -- OUT_DIR
# Writes, for each view (front, left, back, back34: yaw 0, -90, 180 and 145 degrees):
#   room_<view>_raw.png  1280x720, the painted room, PSX off (the actors are lit as in the game)
#   room_<view>_psx.png  game resolution (960x540), PSX on
#   studio_<view>.png    the witch alone in front of an orthographic camera, the shader's default light
# The raccoon is hidden so it does not overlap her skirt.

const VIEWS := {"front": 0.0, "left": -90.0, "back": 180.0, "back34": 145.0}
const STUDIO_HEIGHT := 1.5

func _initialize() -> void:
	_run()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://witch"
	DirAccess.make_dir_recursive_absolute(out)
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	root.add_child(room)
	await _frames(30)
	if room.actors.has("raccoon"):
		(room.actors["raccoon"] as Node3D).visible = false
	var witch := room.actors["witch"] as Node3D
	for view in VIEWS:
		witch.rotation.y = deg_to_rad(float(VIEWS[view]))
		for shot in [["raw", false, true], ["psx", true, false]]:
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED if shot[2] else Window.CONTENT_SCALE_MODE_VIEWPORT
			room.set_psx(shot[1])
			await _frames(6)
			var image := root.get_texture().get_image()
			image.save_png(out.path_join("room_%s_%s.png" % [view, shot[0]]))
			print("CAPTURE room_%s_%s %dx%d" % [view, shot[0], image.get_width(), image.get_height()])
	room.queue_free()
	await process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await _studio(out)
	quit()

func _studio(out: String) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = STUDIO_HEIGHT
	holder.add_child(camera)
	camera.position = Vector3(0.0, STUDIO_HEIGHT * 0.5 - 0.06, 4.0)
	camera.look_at(Vector3(0.0, STUDIO_HEIGHT * 0.5 - 0.06, 0.0))
	var visual := CharacterModels.instantiate("witch")
	var turn := Node3D.new()
	holder.add_child(turn)
	turn.add_child(visual)
	for view in VIEWS:
		turn.rotation_degrees.y = float(VIEWS[view])
		await _frames(6)
		root.get_texture().get_image().save_png(out.path_join("studio_%s.png" % view))
		print("CAPTURE studio_%s" % view)
