extends TestCase

# The plate contract (docs/art/PLATE_CONTRACT.md) from the game's side: the files the set build
# delivers are valid, inside the mobile budget, and projected with exactly the camera they were
# rendered with; the layout in anchors.json is playable; shots cut to their plates.

const MAX_PROXY_TRIANGLES := 20000
const MAX_PROXY_SURFACES := 1
const MAX_PLATE_MEMORY := 24 * 1024 * 1024
const MAX_SHOT_WIDTH := 2048
const MOBILE_WIDTH := 1280
const INTERACTABLES := ["machine", "bell", "path_out"]

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _shots() -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(PlateSet.SHOTS_PATH))

func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		total += (indices as PackedInt32Array).size() / 3 if indices != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total

# ---- shots.json and the files -----------------------------------------------------------------------

func test_shots_json_keeps_the_contract() -> void:
	ok(PlateSet.available(), "assets/archive/plates/shots.json exists")
	eq(PlateSet.validate(_shots()), [] as Array[String], "shots.json is valid")
	var plate_set := PlateSet.new()
	ok(plate_set.read(PlateSet.SHOTS_PATH), "and reads")
	ok(not plate_set.wide().is_empty(), "the wide plate named by anchors.json camera_wide (%s) exists" % plate_set.wide_id)
	eq(plate_set.wide()["role"], "shot", "and it is a shot")
	eq(plate_set.wide()["mode"], "wide", "for the wide mode")
	for plate in plate_set.plates:
		var dir := PlateSet.PLATE_DIR + str(plate["dir"]) + "/"
		ok(ResourceLoader.exists(dir + "beauty.png"), "%s has beauty.png" % dir)
		for name in ["key.png", "glow.png"]:
			ok(ResourceLoader.exists(dir + name), "%s has %s" % [dir, name])
		if str(plate["variant"]).is_empty():
			ok(ResourceLoader.exists(dir + "depth.png"), "%s has depth.png" % dir)
		else:
			ok(not plate_set.find(plate["id"]).is_empty(), "variant %s@%s has a base plate" % [plate["id"], plate["variant"]])
		if plate["role"] == "shot":
			ok(absf(PlateSet.aspect(plate) - 21.0 / 9.0) < 0.01, "%s is 21:9 (%s)" % [plate["id"], plate["size"]])
			ok((plate["size"] as Vector2i).x <= MAX_SHOT_WIDTH, "%s is at most %d wide" % [plate["id"], MAX_SHOT_WIDTH])
			ok(ResourceLoader.exists(dir + "beauty_m.png"), "%s has the mobile copy" % plate["id"])

func test_validation_catches_broken_plates() -> void:
	var good: Dictionary = (_shots() as Dictionary).duplicate(true)
	var shot: Dictionary = good["shots"][0]
	shot["basis"] = [[1, 0.2, 0], [0, 1, 0], [0, 0, 1]]
	ok(not PlateSet.validate(good).is_empty(), "a basis that is not orthonormal")
	shot["basis"] = [[0.9848, 0.1736, 0], [-0.1736, 0.9848, 0], [0, 0, 1]]
	ok(PlateSet.validate(good).any(func(e: String) -> bool: return e.contains("roll")), "a plate with roll baked in")
	shot["basis"] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
	shot["size"] = [4096, 1755]
	ok(PlateSet.validate(good).any(func(e: String) -> bool: return e.contains("2048")), "an over-wide shot plate")
	shot["size"] = [2048, 878]
	shot["role"] = "hero"
	ok(not PlateSet.validate(good).is_empty(), "an unknown role")
	ok(not PlateSet.validate({"shots": "no"}).is_empty(), "a malformed file")

func test_depth_key_and_glow_are_imported_as_images_and_beauty_compressed() -> void:
	# Lossy VRAM compression would turn a 16-bit depth into noise; plates must keep these settings
	# when the real ones replace the stub (Godot keeps a file's .import params).
	var plate_set := PlateSet.new()
	plate_set.read(PlateSet.SHOTS_PATH)
	for plate in plate_set.plates:
		var dir := "res://assets/archive/plates/%s/" % plate["dir"]
		for name in ["depth.png", "key.png", "glow.png"]:
			if FileAccess.file_exists(dir + name):
				ok(FileAccess.get_file_as_string(dir + name + ".import").contains("importer=\"image\""), "%s%s is imported as an Image" % [dir, name])
		for name in ["beauty.png", "beauty_m.png"]:
			if FileAccess.file_exists(dir + name):
				ok(FileAccess.get_file_as_string(dir + name + ".import").contains("compress/mode=2"), "%s%s is VRAM-compressed" % [dir, name])

# ---- mobile budgets ------------------------------------------------------------------------------------

func test_the_proxy_fits_the_mobile_budget() -> void:
	var mesh := PlateStage.load_proxy_mesh()
	ok(mesh != null, "assets/archive/hall_proxy.glb has a mesh")
	ok(mesh.get_surface_count() <= MAX_PROXY_SURFACES, "one draw call (%d surfaces)" % mesh.get_surface_count())
	var tris := _triangles(mesh)
	ok(tris <= MAX_PROXY_TRIANGLES, "proxy triangles %d <= %d" % [tris, MAX_PROXY_TRIANGLES])
	ok(tris > 1000, "and it is the hall, not a box (%d)" % tris)
	var arrays := mesh.surface_get_arrays(0)
	ok(arrays[Mesh.ARRAY_COLOR] != null, "vertex colour = the fallback where no plate sees")

func test_plate_memory_fits_the_mobile_budget() -> void:
	for mobile in [true, false]:
		var plate_set := PlateSet.new()
		plate_set.mobile = mobile
		plate_set.read(PlateSet.SHOTS_PATH)
		plate_set.load_textures()
		eq(plate_set.errors, [] as Array[String], "every plate loads (mobile=%s)" % mobile)
		var bytes := plate_set.memory_bytes()
		ok(bytes <= MAX_PLATE_MEMORY, "plate memory %.1f MB <= %.0f MB (mobile=%s)" % [bytes / 1048576.0, MAX_PLATE_MEMORY / 1048576.0, mobile])
		var wide: Dictionary = plate_set.textures(plate_set.wide())
		eq((wide["depth"] as ImageTexture).get_format(), Image.FORMAT_RG8, "depth is kept as exact RG8")
		if mobile:
			eq((wide["beauty"] as Texture2D).get_width(), MOBILE_WIDTH, "mobile draws the %d-wide copy" % MOBILE_WIDTH)

# ---- projection ------------------------------------------------------------------------------------------

func test_a_world_point_lands_on_the_expected_plate_pixel() -> void:
	# A synthetic plate: at (0, 2, 10) looking down -z, 60 degrees tall, 2100 x 900.
	var plate := {"transform": Transform3D(Basis(), Vector3(0, 2, 10)), "fov_v_deg": 60.0, "size": Vector2i(2100, 900), "near": 0.1, "far": 80.0}
	var centre := PlateSet.project(plate, Vector3(0, 2, 0))
	ok(centre.distance_to(Vector3(1050, 450, 10)) < 1e-3, "straight ahead is the centre pixel at depth 10 (%s)" % centre)
	var up := PlateSet.project(plate, Vector3(0, 2 + 10.0 * tan(deg_to_rad(30.0)), 0))
	ok(absf(up.y) < 1e-3, "the top of the vertical fov is row 0 (%s)" % up)
	var right := PlateSet.project(plate, Vector3(10.0 * tan(deg_to_rad(30.0)) * 2100.0 / 900.0, 2, 0))
	ok(absf(right.x - 2100.0) < 1e-2, "the side of the horizontal fov is the last column (%s)" % right)
	ok(PlateSet.project(plate, Vector3(0, 2, 20)).z < 0.0, "a point behind the plate's camera is rejected")

func test_plate_projection_matches_a_camera_at_the_plates_pose() -> void:
	# Godot's own camera, placed by the shot logic at the wide plate's pose (no roll), sized like the
	# plate, must see every point where PlateSet.project (the shader's math) says it is.
	var plate_set := PlateSet.shared(false)
	var plate := plate_set.wide()
	var size: Vector2i = plate["size"]
	var viewport := SubViewport.new()
	viewport.size = size
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	_tree().root.add_child(viewport)
	track(viewport)
	await _tree().process_frame
	camera.set_pose(PlateSet.pose_of(plate, 0.0), true)
	ok(PlateSet.is_exact(plate, camera.global_transform), "the camera sits exactly on the plate")
	var worst := 0.0
	for p in [Vector3(1.0, 0.0, -0.2), Vector3(-1.6, 0.8, -1.2), Vector3(4.3, 2.25, -3.0), Vector3(-4.2, 2.0, -9.4)]:
		var mine := PlateSet.project(plate, p)
		var godot := camera.unproject_position(p)
		worst = maxf(worst, Vector2(mine.x, mine.y).distance_to(godot))
	ok(worst < 0.5, "PlateSet.project and the Godot camera agree to half a pixel (worst %.3f px)" % worst)

func test_the_depth_plate_agrees_with_the_projection() -> void:
	# Rebuild 3D points from depth.png with GODOT's camera at the plate's pose: the floor in front comes
	# out at floor height, and PlateSet.project sends each point back to its own pixel. A renderer and a
	# game that disagreed on the camera (fov, aspect, rows top-down, depth encoding) would fail here.
	var plate_set := PlateSet.shared(false)
	var plate := plate_set.wide()
	var size: Vector2i = plate["size"]
	var depth: Image = plate_set.textures(plate)["depth_image"]
	var viewport := SubViewport.new()
	viewport.size = size
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	_tree().root.add_child(viewport)
	track(viewport)
	await _tree().process_frame
	camera.set_pose(PlateSet.pose_of(plate, 0.0), true)
	var worst_height := 0.0
	var worst_pixel := 0.0
	for i in range(9):
		var px := Vector2i(int(size.x * (0.3 + 0.05 * i)), size.y - 12)
		var c := depth.get_pixelv(px)
		var z := PlateSet.decode_depth(roundi(c.r * 255.0), roundi(c.g * 255.0), plate["near"], plate["far"])
		var world := camera.project_position(Vector2(px) + Vector2(0.5, 0.5), z)
		worst_height = maxf(worst_height, absf(world.y))
		var back := PlateSet.project(plate, world)
		worst_pixel = maxf(worst_pixel, Vector2(back.x, back.y).distance_to(Vector2(px) + Vector2(0.5, 0.5)) + absf(back.z - z))
	ok(worst_height < 0.06, "the bottom rows of the wide plate rebuild onto the floor (worst %.3f m off)" % worst_height)
	ok(worst_pixel < 0.05, "and project back onto their own pixels (worst %.4f)" % worst_pixel)
	ok(plate_set.key_at(StageLight.anchor_vector("pool")) > 0.4, "the beam lands on the pool (key %.2f)" % plate_set.key_at(StageLight.anchor_vector("pool")))
	ok(plate_set.key_at(Vector3(-5.0, 0.0, 2.0)) < 0.1, "and not in the shade by the shelves")

func test_the_rolled_shot_never_leaves_its_plate() -> void:
	var plate_set := PlateSet.shared(false)
	var plate := plate_set.wide()
	var roll := float(ArchiveHall.wide_framing()["roll_deg"])
	for screen in [Vector2i(720, 540), Vector2i(960, 540), Vector2i(1260, 540)]:
		var viewport := SubViewport.new()
		viewport.size = screen
		var camera := DioramaCamera.new()
		viewport.add_child(camera)
		_tree().root.add_child(viewport)
		track(viewport)
		await _tree().process_frame
		camera.set_pose(PlateSet.pose_of(plate, roll), true)
		var inside := true
		for corner in [Vector2(0, 0), Vector2(screen.x, 0), Vector2(0, screen.y), Vector2(screen)]:
			var ray := camera.project_ray_origin(corner) + camera.project_ray_normal(corner) * 10.0
			var at := PlateSet.project(plate, ray)
			var size: Vector2i = plate["size"]
			inside = inside and at.x >= -0.5 and at.y >= -0.5 and at.x <= size.x + 0.5 and at.y <= size.y + 0.5
		ok(inside, "at %s the %.1f-degree roll stays inside the plate (fov %.1f)" % [screen, roll, camera.fov])
		ok(camera.fov <= float(plate["fov_v_deg"]) + 1e-3, "by closing the lens, never opening it")

# ---- anchors.json ------------------------------------------------------------------------------------------

func test_anchors_json_describes_a_playable_layout() -> void:
	var anchors := StageLight.anchors()
	for key in ["camera_wide", "framing", "spawn", "tomas_at", "tomas_yaw_deg", "interactables", "walkable", "obstacles", "hero_regions", "pool", "oculus", "sun_dir", "raccoon_perch", "light_map"]:
		has_key(anchors, key, "anchors.json")
	for id in INTERACTABLES:
		ok((anchors["interactables"] as Dictionary).has(id), "interactable '%s' (ids are data and never change)" % id)
		var spec: Dictionary = anchors["interactables"][id]
		for key in ["at", "radius", "height", "approach"]:
			has_key(spec, key, "interactables.%s" % id)
	var polygon := ArchiveHall.walkable_polygon()
	ok(polygon.size() >= 3, "the walkable floor is a polygon")
	ok(not Geometry2D.triangulate_polygon(polygon).is_empty(), "a simple one (it triangulates)")
	var spawn := ArchiveHall.anchor_point("spawn", Vector3.INF)
	ok(ArchiveHall.stage_allows(spawn.x, spawn.z), "she starts on the walkable floor")
	for id in INTERACTABLES:
		var approach: Vector3 = ArchiveHall.interactable_spec(id)["approach"]
		ok(ArchiveHall.stage_allows(approach.x, approach.z), "%s's approach point is walkable" % id)
	for region in anchors["hero_regions"]:
		ok(region is Dictionary and region.has("at") and region.has("radius"), "hero region %s" % [region])

func test_spawn_reaches_every_approach_point() -> void:
	GameFixtures.ensure_localization()
	var room := ArchiveHall.new()
	_tree().root.add_child(room)
	await _tree().process_frame
	for id in ["tomas"] + INTERACTABLES:
		var approach: Vector3 = room.get_interactable(id).approach_point
		ok(not room.navigator.is_blocked(approach), "%s's approach is not blocked" % id)
		var path := room.navigator.find_path(room.spawn_position, approach)
		ok(not path.is_empty() and path[path.size() - 1].distance_to(Vector3(approach.x, 0, approach.z)) < 0.01, "a walk from the start reaches %s" % id)
	room.free()

# ---- shots cut to their plates ---------------------------------------------------------------------------

func test_a_beat_with_a_plate_cuts_to_exactly_that_pose() -> void:
	GameFixtures.ensure_localization()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	_tree().root.add_child(viewport)
	track(viewport)
	var room := ArchiveHall.new()
	viewport.add_child(room)
	var camera := DioramaCamera.new()
	viewport.add_child(camera)
	await _tree().process_frame
	var director := CameraDirector.new()
	director.camera = camera
	director.framing_provider = room.framing
	director.focus_resolver = room.focus_position
	director.shot_provider = room.shot_pose
	viewport.add_child(director)
	var plate_set := room.plates.plates
	for beat in [["wide", []], ["inspect", ["machine"]]]:
		var plate := plate_set.shot_for(beat[0], beat[1])
		ok(not plate.is_empty(), "a plate was rendered for %s %s" % beat)
		director.frame(beat[0], beat[1])
		ok(PlateSet.is_exact(plate, camera.global_transform), "%s cuts to the plate's own pose" % beat[0])
		var roll := CameraDirector.compute_pose(beat[0], [Vector3.ZERO], room.framing())["roll_deg"] as float
		ok(absf(camera.roll_deg - roll) < 1e-4 and absf(camera.global_transform.basis.x.y) > 0.01, "with the beat's roll added at runtime")
	director.frame("conversation", ["tomas"])
	ok(plate_set.choose(camera.global_transform).all(func(c: Dictionary) -> bool: return not c["exact"]), "a conversation has no plate: it is computed and textured from the nearest ones")
	eq(plate_set.choose(camera.global_transform).size(), 3, "three plates texture it")
	director.frame("magic_reveal", ["machine"])
	ok(float(director.pose_for("magic_reveal", ["machine"]).get("dolly", 0.0)) > 0.2, "the spell's shot pushes in for real parallax")
	room.queue_free()

func test_the_room_ages_to_a_variant_and_back() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	_tree().root.add_child(viewport)
	track(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var stage := PlateStage.new()
	viewport.add_child(stage)
	await _tree().process_frame
	ok("dusk" in stage.plates.variants(), "the plates come in a dusk variant")
	var before := stage.key_at(StageLight.anchor_vector("pool"))
	var done := [false]
	var run := func() -> void:
		await stage.crossfade_to("dusk", 0.25)
		done[0] = true
	run.call()
	ok(stage.is_fading() and stage.overlay.visible, "a second, transparent proxy fades in")
	for i in range(60):
		await _tree().process_frame
		if done[0]:
			break
	ok(done[0] and not stage.is_fading() and stage.variant == "dusk", "and the room is dusk once it has")
	ok(not stage.overlay.visible, "the overlay is put away")
	ok(stage.key_at(StageLight.anchor_vector("pool")) < before - 0.1, "the sun's share at the pool falls (%.2f -> %.2f)" % [before, stage.key_at(StageLight.anchor_vector("pool"))])
	stage.set_variant("")
	eq(stage.variant, "", "an instant reset")
