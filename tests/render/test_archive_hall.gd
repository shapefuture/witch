extends TestCase

# The art pipeline's contract with the game: the live props load with the parts behaviour needs, the
# painted tiles stay small, and the bolted camera shows everywhere the witch can walk. (The set itself
# is pre-rendered plates: tests/render/test_plates.gd.)

const TILE_DIR := "res://assets/archive/textures/"
const MAX_TILE_SIZE := 256

func test_the_live_props_load_with_every_part_the_game_drives() -> void:
	var props := ArchiveProps.new()
	ok(props.load_props(), "machine and bell (props/*.glb, else the old set's)")
	for part in ["Base", "BigGear", "SmallGear", "Pipe", "Lever", "Cam", "Indicator"]:
		ok(props.machine.get_node_or_null(part) != null or props.machine.find_children("Gear*").size() > 0, "the machine has %s or Gear* parts (MachineView and the outline depend on the names)" % part)
	for node: Node3D in [props.machine, props.bell]:
		var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		ok(not meshes.is_empty(), "%s has meshes" % node.name)
		for mesh: Variant in meshes:
			var instance := mesh as MeshInstance3D
			for surface in range(instance.mesh.get_surface_count()):
				ok(instance.get_surface_override_material(surface) is ShaderMaterial, "%s surface %d wears a PSX material" % [instance.name, surface])
	track(props.machine)
	track(props.bell)

func test_painted_tiles_are_small_and_unique() -> void:
	var dir := DirAccess.open(TILE_DIR)
	ok(dir != null, "texture folder exists")
	var count := 0
	for file in dir.get_files():
		if file.ends_with(".png"):
			count += 1
			var texture := load(TILE_DIR + file) as Texture2D
			ok(texture != null and maxi(texture.get_width(), texture.get_height()) <= MAX_TILE_SIZE, "%s is at most %dpx" % [file, MAX_TILE_SIZE])
	ok(count >= 20, "a real palette of hand-painted tiles (%d)" % count)

func test_anchors_describe_the_light_the_set_was_baked_with() -> void:
	var anchors := StageLight.anchors()
	for key in ["sun_dir", "pool", "oculus", "light_map", "bell", "raccoon_perch"]:
		has_key(anchors, key, "anchors.json")
	ok(is_equal_approx(StageLight.sun_dir().length(), 1.0), "the key light is a unit vector")
	var pool := StageLight.anchor_vector("pool")
	var oculus := StageLight.anchor_vector("oculus")
	var along := (oculus - pool).normalized()
	ok(along.dot(StageLight.sun_dir()) > 0.999, "the hole in the vault is where the key light's ray from the pool leaves the hall")
	ok(oculus.y > 8.0, "high in the vault")

func test_the_room_has_its_interactables_and_they_can_be_reached() -> void:
	GameFixtures.ensure_localization()
	var room := ArchiveHall.new()
	Engine.get_main_loop().root.add_child(room)
	await Engine.get_main_loop().process_frame
	for id in ["tomas", "machine", "bell", "path_out"]:
		ok(room.get_interactable(id) != null, "%s is registered" % id)
		var approach: Vector3 = room.get_interactable(id).approach_point
		ok(not room.navigator.is_blocked(approach), "the witch can stand where she acts on %s (%s)" % [id, approach])
		ok(not room.navigator.find_path(room.spawn_position, approach).is_empty(), "and there is a walk from the start to it")
	eq(room.room_id, "clearing", "Mirror's key for this place is unchanged by how it looks")
	ok(room.machine_view != null and room.bell != null and room.raccoon != null, "machine, bell, raccoon placed")
	ok(room.plates != null and room.plates.proxy != null, "the set is the proxy wearing the plates")
	ok(room.raccoon.position.y > 1.5, "the raccoon watches from a shelf, not the floor")
	room.free()

func test_the_bolted_wide_shot_shows_everywhere_the_witch_may_stand() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 540)   # 4:3, the tightest aspect the game supports
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	Engine.get_main_loop().root.add_child(viewport)
	track(viewport)
	await Engine.get_main_loop().process_frame
	# the real shot: the wide plate's pose with the stage's roll, the lens closed to fit the plate
	var plates := PlateSet.shared(false)
	camera.set_pose(PlateSet.pose_of(plates.wide(), float(ArchiveHall.wide_framing()["roll_deg"])), true)
	var seen := 0
	var checked := 0
	for x in range(-8, 9):
		for z in range(-9, 6):
			if ArchiveHall.stage_allows(float(x), float(z)):
				checked += 1
				var head := Vector3(x, 1.7, z)
				var feet := Vector3(x, 0.0, z)
				var a := camera.unproject_position(feet)
				var b := camera.unproject_position(head)
				if not camera.is_position_behind(head) and Rect2(0, 0, 720, 540).grow(-6).has_point(a) and b.y > 0.0:
					seen += 1
	# the stage is intimate on purpose: the camera sits low and close, like the reference painting, so only a
	# strip of floor shows feet to hat at 4:3
	ok(checked > 30, "enough walkable cells to mean something (%d)" % checked)
	eq(seen, checked, "the witch is in frame wherever she can walk (%d of %d), because the camera never follows" % [seen, checked])

func test_the_camera_cuts_between_shots_and_only_the_spell_eases() -> void:
	var viewport := SubViewport.new()
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	Engine.get_main_loop().root.add_child(viewport)
	track(viewport)
	await Engine.get_main_loop().process_frame
	var director := CameraDirector.new()
	director.camera = camera
	director.framing_provider = func() -> Dictionary: return {"focus": Vector3.ZERO, "distance": 12.0, "pitch_deg": 10.0, "yaw_deg": 0.0, "fov": 50.0, "roll_deg": 2.0}
	director.focus_resolver = func(_id: String) -> Variant: return null
	var cuts: Array[String] = []
	director.cut.connect(func(mode: String) -> void: cuts.append(mode))
	director.frame("conversation")
	ok(is_equal_approx(camera.distance, 12.0 * 0.46), "a conversation is a hard cut, not a move")
	director.frame("magic_reveal")
	ok(is_equal_approx(camera.distance, 12.0 * 0.46), "the spell's shot eases in: one frame later it has not arrived at the spell's distance yet")
	ok(is_equal_approx(CameraDirector.compute_pose("magic_reveal", [], director.framing_provider.call())["roll_deg"], 2.0 - 45.0), "and it tips the world 45 degrees")
	director.return_to_wide()
	ok(is_equal_approx(camera.roll_deg, 2.0), "going back is a snap, with the stage's own small Dutch tilt")
	eq(cuts, ["conversation", "magic_reveal", "wide"], "every shot change is announced")
	director.free()

func test_camera_roll_tilts_the_horizon() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 360)
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	Engine.get_main_loop().root.add_child(viewport)
	track(viewport)
	await Engine.get_main_loop().process_frame
	camera.set_pose({"look_at": Vector3.ZERO, "distance": 10.0, "pitch_deg": 0.0, "yaw_deg": 0.0, "roll_deg": 30.0, "fov": 60.0}, true)
	ok(absf(camera.global_transform.basis.x.y) > 0.45, "a 30 degree roll leaves the camera's right axis well off the horizontal (%s)" % camera.global_transform.basis.x)
	camera.locked = true
	camera.set_pose({"look_at": Vector3.ZERO, "distance": 5.0, "pitch_deg": 0.0, "yaw_deg": 0.0, "roll_deg": 0.0, "fov": 60.0}, true)
	ok(is_equal_approx(camera.distance, 10.0), "a locked camera (capture aid) ignores pose requests")

func test_render_globals_follow_the_screen_and_reset() -> void:
	PSXGlobals.reset()
	PSXGlobals.set_render_size(Vector2(640, 360))
	eq(PSXGlobals.snap_grid(), Vector2(320, 180), "one snap cell is two pixels of a 360-row picture at any aspect")
	PSXGlobals.set_render_size(Vector2(960, 540))
	eq(PSXGlobals.snap_grid(), Vector2(320, 180), "and the 540-row render keeps that lattice, so the wobble keeps its size")
	PSXGlobals.set_lens(0.7)
	ok(is_equal_approx(PSXGlobals.lens(), 0.7), "lens swing set")
	PSXGlobals.set_time(12.5)
	ok(is_equal_approx(PSXGlobals.time(), 12.5), "the diorama clock is explicit, so captures are reproducible")
	PSXGlobals.reset()
	eq(PSXGlobals.lens(), 0.0, "the spell's snap back resets the lens")
	eq(PSXGlobals.time(), 0.0, "and the clock")
