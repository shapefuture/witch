extends SceneTree

# Any character .glb on disk, standing in for the witch in the painted room and in a studio, lit and shaded by the
# game's own code (no import step, no change to assets/):
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 \
#       --script res://tools/characters/capture_candidate.gd -- OUT_DIR MODEL.glb [--fit]
# --fit scales the model to 1.3 m with its feet on the floor (for a mesh that did not come out of template_rig.py).
# Writes room_raw.png (PSX off, 1280x720), room_psx.png (game resolution, PSX on) and studio_<view>.png
# (front, back, three_quarter in the idle pose, cast_front with the wand arm raised) under the same neutral white key capture_witch.gd uses,
# so the colours read like the reference's studio render; the room shots keep the room's own actor lighting. tools/characters/eval_sheet.py lays them out.

const STUDIO := "res://assets/characters/witch.glb"
const VIEWS := {"front": 0.0, "back": 180.0, "three_quarter": 35.0}

func _initialize() -> void:
	_run()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- OUT_DIR MODEL.glb [--fit]")
		quit(2)
		return
	var out := args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var packed := _load(args[1], args.has("--fit"))
	if packed == null:
		push_error("cannot load %s" % args[1])
		quit(1)
		return
	packed.take_over_path(STUDIO)
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	root.add_child(room)
	for i in 30:
		await process_frame
	for shot in [["room_raw", false, true], ["room_psx", true, false]]:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED if shot[2] else Window.CONTENT_SCALE_MODE_VIEWPORT
		room.set_psx(shot[1])
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("%s.png" % shot[0]))
	room.queue_free()
	await process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await _studio(out)
	print("CAPTURED %s" % args[1])
	quit()

# glTF at runtime: the importer is not needed, so a candidate never touches the project's import cache.
func _load(path: String, fit: bool) -> PackedScene:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var model := doc.generate_scene(state) as Node3D
	if model == null:
		return null
	if fit:
		var holder := Node3D.new()
		root.add_child(holder)
		holder.add_child(model)
		var low := 1e9
		var high := -1e9
		var centre := Vector3.ZERO
		var count := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var box := mesh.global_transform * mesh.get_aabb()
			low = minf(low, box.position.y)
			high = maxf(high, box.end.y)
			centre += box.get_center()
			count += 1
		centre /= maxf(count, 1)
		var s := 1.3 / maxf(high - low, 0.001)
		model.scale = Vector3.ONE * s
		model.position = Vector3(-centre.x * s, -low * s, -centre.z * s)
		holder.remove_child(model)
		holder.queue_free()
	_own(model, model)
	var packed := PackedScene.new()
	packed.pack(model)
	return packed

func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)

func _studio(out: String) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	holder.add_child(camera)
	var visual := CharacterModels.instantiate("witch")
	if visual == null:
		return
	var turn := Node3D.new()
	holder.add_child(turn)
	turn.add_child(visual)
	_neutral_light(visual)
	camera.size = 1.45
	camera.position = Vector3(0.0, 0.725, 4.0)
	camera.look_at(Vector3(0.0, 0.725, 0.0))
	var shots: Array = []
	for view in VIEWS:
		shots.append([view, float(VIEWS[view]), "idle", 1.0])
	shots.append(["cast_front", 0.0, "cast", 1.0])
	for shot in shots:
		turn.rotation_degrees.y = float(shot[1])
		var player := CharacterModels.player_of(visual)
		if player != null and player.has_animation(String(shot[2])):
			player.play(String(shot[2]))
			player.seek(float(shot[3]), true)
			player.pause()
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("studio_%s.png" % shot[0]))

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
