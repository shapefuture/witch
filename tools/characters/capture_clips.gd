extends SceneTree

# Every clip of a character, frame by frame, to check the rig (hands holding, sleeves following, hair swinging):
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
#       --resolution 480x540 --script res://tools/characters/capture_clips.gd -- OUT_DIR [witch] [front|q_left|q_right|back]
# Writes clip_<name>_<i>.png: FRAMES evenly spaced poses of each clip, the character alone under a neutral white key
# (as capture_witch.gd's studio). tools/characters/clip_sheet.py joins them into one sheet.

const FRAMES := 6
const VIEW_YAW := {"front": 0.0, "q_left": -35.0, "q_right": 35.0, "back": 180.0}
const HEIGHT := 1.45

func _initialize() -> void:
	_run()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://clips"
	var id := args[1] if args.size() > 1 else "witch"
	var view := args[2] if args.size() > 2 else "q_left"
	DirAccess.make_dir_recursive_absolute(out)
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = HEIGHT
	holder.add_child(camera)
	camera.position = Vector3(0.0, HEIGHT * 0.5 - 0.04, 4.0)
	camera.look_at(Vector3(0.0, HEIGHT * 0.5 - 0.04, 0.0))
	var turn := Node3D.new()
	holder.add_child(turn)
	turn.rotation_degrees.y = float(VIEW_YAW.get(view, -35.0))
	var visual := CharacterModels.instantiate(id)
	turn.add_child(visual)
	_neutral_light(visual)
	var player := CharacterModels.player_of(visual)
	for clip in player.get_animation_list():
		var length := player.get_animation(clip).length
		player.play(clip)
		player.pause()
		for i in FRAMES:
			player.seek(length * float(i) / float(FRAMES), true)
			await _frames(3)
			root.get_texture().get_image().save_png(out.path_join("clip_%s_%d.png" % [clip, i]))
		print("CLIP %s %.2f s" % [clip, length])
	quit()

func _neutral_light(node: Node) -> void:
	var floor_image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	floor_image.fill(Color(0.62, 0.62, 0.62))
	var floor_texture := ImageTexture.create_from_image(floor_image)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as ShaderMaterial
			if material == null:
				continue
			material.set_shader_parameter("light_map", floor_texture)
			material.set_shader_parameter("light_scale", 1.0)
			material.set_shader_parameter("lit_range", Vector2(0.0, 0.5))
			material.set_shader_parameter("sun_dir", Vector3(-0.45, 0.6, 0.65))
			material.set_shader_parameter("sun_color", Color(0.62, 0.6, 0.57))
			material.set_shader_parameter("key_strength", 1.0)
			material.set_shader_parameter("key_front", 0.0)
			material.set_shader_parameter("rim_strength", 0.0)
