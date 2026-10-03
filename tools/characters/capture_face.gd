extends SceneTree

# The witch's face up close, lit by the painted room exactly as in the game (the camera moves, the light does not):
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
#       --resolution 960x960 --script res://tools/characters/capture_face.gd -- OUT_DIR
# Writes face_<view>.png (front, three-quarter left/right, side) and face_<view>_psx.png (the PSX look on, game
# resolution). The raccoon is hidden.

const VIEWS := {"front": 0.0, "q_left": -35.0, "q_right": 35.0, "side": -80.0}
const HEAD := Vector3(0.0, 1.03, 0.04)   # the middle of the face, on the model
const DISTANCE := 0.85

func _initialize() -> void:
	_run()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://face"
	DirAccess.make_dir_recursive_absolute(out)
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	root.add_child(room)
	await _frames(30)
	if room.actors.has("raccoon"):
		(room.actors["raccoon"] as Node3D).visible = false
	var witch := room.actors["witch"] as Node3D
	var head := witch.to_global(HEAD)
	var camera := Camera3D.new()
	camera.fov = 22.0
	room.add_child(camera)
	camera.current = true
	for view in VIEWS:
		var yaw := deg_to_rad(float(VIEWS[view]))
		var forward := witch.global_basis * Vector3(sin(yaw), 0.0, cos(yaw))
		camera.global_position = head + forward.normalized() * DISTANCE
		camera.look_at(head)
		for shot in [["", false, true], ["_psx", true, false]]:
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED if shot[2] else Window.CONTENT_SCALE_MODE_VIEWPORT
			room.set_psx(shot[1])
			await _frames(6)
			var image := root.get_texture().get_image()
			image.save_png(out.path_join("face_%s%s.png" % [view, shot[0]]))
			print("CAPTURE face_%s%s %dx%d" % [view, shot[0], image.get_width(), image.get_height()])
	quit()
