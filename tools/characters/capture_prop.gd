extends SceneTree

# A prop .glb on disk in a studio, through the game's own PSX actor shader and the neutral white key of capture_witch.gd (no import step):
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 \
#       --script res://tools/characters/capture_prop.gd -- OUT_DIR MODEL.glb [MODEL.glb ...]
# Writes OUT_DIR/<model name>_<view>.png for front, three_quarter, side and back: an orthographic camera fitted to each model's box.

const VIEWS := {"front": 0.0, "three_quarter": 35.0, "side": 90.0, "back": 180.0}

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- OUT_DIR MODEL.glb [MODEL.glb ...]")
		quit(2)
		return
	var out := args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	holder.add_child(camera)
	for i in range(1, args.size()):
		await _shoot(holder, camera, args[i], out)
	quit()

func _shoot(holder: Node3D, camera: Camera3D, path: String, out: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("cannot load %s" % path)
		return
	var model := doc.generate_scene(state) as Node3D
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(model)
	PSXActorPresenter.apply(model, 0.0)
	_neutral_light(model)
	var low := Vector3(1e9, 1e9, 1e9)
	var high := Vector3(-1e9, -1e9, -1e9)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		low = low.min(box.position)
		high = high.max(box.end)
	model.position = -(low + high) * 0.5                       # turn about the model's centre
	camera.size = maxf(high.y - low.y, maxf(high.x - low.x, high.z - low.z)) * 1.3
	camera.position = Vector3(0.0, 0.0, 6.0)
	camera.look_at(Vector3.ZERO)
	var stem := path.get_file().get_basename()
	for view in VIEWS:
		pivot.rotation_degrees.y = float(VIEWS[view])
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [stem, view]))
	pivot.queue_free()
	await process_frame
	print("CAPTURED %s" % path)

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
