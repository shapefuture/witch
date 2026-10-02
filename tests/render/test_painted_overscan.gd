extends TestCase

# The margin of a painted room (docs/art/painted_room.md, "Margins and other shots"): the arithmetic, the
# hall_clean asset's own margin, and that a roll or a wide window shows margin instead of zooming in.

const HALL := "res://assets/painted/hall_clean"
const SIZE := Vector2(1280, 720)
const FOV := 55.0

# The first suite to run is in the middle of SceneTree._initialize, when the root is not ready yet and a room
# added to it would never get its _ready: wait a frame.
func _tree_ready() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

func _room(with_margin: bool) -> PaintedRoom:
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	room.overscan = with_margin
	(Engine.get_main_loop() as SceneTree).root.add_child(room)
	return room

func _image(file: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(HALL.path_join(file)))
	image.convert(Image.FORMAT_RGB8)
	return image

func test_without_a_margin_the_zoom_is_the_one_the_painting_always_needed() -> void:
	var aspect := SIZE.x / SIZE.y
	var roll := deg_to_rad(5.0)
	var expected := rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV) * 0.5) / (cos(roll) + aspect * sin(roll))))
	var got := PaintedOverscan.fov_for(FOV, SIZE, Vector2.ZERO, aspect, roll)
	ok(absf(got - expected) < 0.0001, "a 5 degree roll zooms in %.2f -> %.2f deg" % [FOV, got])
	ok(absf(PaintedOverscan.fov_for(FOV, SIZE, Vector2.ZERO, aspect, 0.0) - FOV) < 0.0001, "no roll, the painting's own shape: no zoom")

func test_a_margin_absorbs_a_roll_and_a_wider_window() -> void:
	var margin := Vector2(160, 90)
	var aspect := SIZE.x / SIZE.y
	ok(absf(PaintedOverscan.fov_for(FOV, SIZE, margin, aspect, deg_to_rad(5.0)) - FOV) < 0.0001, "a 5 degree roll at 16:9 fits in the margin: no zoom")
	var phone := 19.5 / 9.0
	ok(absf(PaintedOverscan.fov_for(FOV, SIZE, margin, phone, 0.0) - FOV) < 0.0001, "a 19.5:9 phone fits in the margin: no zoom")
	var wide := 21.0 / 9.0
	var with_margin := PaintedOverscan.fov_for(FOV, SIZE, margin, wide, 0.0)
	var without := PaintedOverscan.fov_for(FOV, SIZE, Vector2.ZERO, wide, 0.0)
	ok(with_margin < FOV and with_margin > without, "21:9 needs a little zoom with the margin (%.2f deg), a lot without (%.2f)" % [with_margin, without])
	var fit := (SIZE.x * 0.5 + margin.x) / (SIZE.y * 0.5 * wide)
	ok(absf(with_margin - rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV) * 0.5) * fit))) < 0.0001, "the zoom is exactly what the margin lacks (%.4f)" % fit)
	var steep := PaintedOverscan.fov_for(FOV, SIZE, margin, aspect, deg_to_rad(15.0))
	ok(steep < FOV and steep > PaintedOverscan.fov_for(FOV, SIZE, Vector2.ZERO, aspect, deg_to_rad(15.0)), "a 15 degree roll zooms, but less than without a margin")

func test_the_plate_in_the_middle_of_the_extended_plate_is_pixel_exact() -> void:
	await _tree_ready()
	var plate := _image("plate.png")
	var extended := _image("plate_ext.png")
	var room := _room(true)
	var margin := room.margin()
	eq(margin, Vector2(160, 90), "the hall's margin")
	eq(extended.get_size(), Vector2i(SIZE + margin * 2.0), "the extended plate is the plate plus the margin")
	# The seam ring (4 px) is blended into the margin on purpose; everything inside it is the original, byte for byte.
	var ring := 4
	var inner := Rect2i(ring, ring, plate.get_width() - 2 * ring, plate.get_height() - 2 * ring)
	var middle := extended.get_region(Rect2i(Vector2i(margin) + inner.position, inner.size))
	ok(middle.get_data() == plate.get_region(inner).get_data(), "the middle of the extended plate is the original, pixel for pixel")
	var empty := _image("plate_empty.png")
	var empty_ext := _image("plate_empty_ext.png")
	ok(empty_ext.get_region(Rect2i(Vector2i(margin) + inner.position, inner.size)).get_data() == empty.get_region(inner).get_data(), "so is the middle of the extended plate with the props lifted out")
	room.queue_free()

func test_the_mesh_and_the_depth_cover_the_margin_and_leave_the_middle_alone() -> void:
	await _tree_ready()
	var room := _room(true)
	var legacy := _room(false)
	eq(legacy.margin(), Vector2.ZERO, "overscan off: the painting as it was")
	var mesh := (room.get_node("Painting") as MeshInstance3D).mesh as ArrayMesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var low := Vector2(1e9, 1e9)
	var high := Vector2(-1e9, -1e9)
	for v in vertices:
		var px := room.world_to_pixel(v)
		low = low.min(px)
		high = high.max(px)
	ok(low.distance_to(Vector2(-160, -90)) < 0.5 and high.distance_to(Vector2(1440, 810)) < 0.5, "the mesh spans the extended frame (%s .. %s)" % [low, high])
	var legacy_vertices: PackedVector3Array = ((legacy.get_node("Painting") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	ok(vertices.size() > legacy_vertices.size() and vertices.size() < 2 * legacy_vertices.size(), "a bigger grid, not a different one (%d vs %d vertices)" % [vertices.size(), legacy_vertices.size()])
	for px in [Vector2(640, 500), Vector2(735, 634), Vector2(90, 400), Vector2(1279, 719), Vector2(0, 0)]:
		ok(absf(room.depth_at(px) - legacy.depth_at(px)) < 0.002, "the room's depth inside the frame is unchanged at %s (%.3f vs %.3f)" % [px, room.depth_at(px), legacy.depth_at(px)])
	for px in [Vector2(-100, 60), Vector2(1400, 780), Vector2(-150, 800), Vector2(640, -80)]:
		var back := room.world_to_pixel(room.pixel_to_world(px))
		ok(back.distance_to(px) < 0.5, "pixel -> world -> pixel round-trips in the margin (%s -> %s)" % [px, back])
		var depth := room.depth_at(px)
		ok(depth > 0.4 and depth < 40.0, "the margin has a sane depth at %s (%.2f m)" % [px, depth])
	ok(room.plate_uv(Vector2.ZERO).distance_to(Vector2(0.1, 0.1)) < 0.0001, "the plate's corner sits inside the extended texture")
	ok(room.plate_uv(SIZE).distance_to(Vector2(0.9, 0.9)) < 0.0001, "and so does the far corner")
	room.queue_free()
	legacy.queue_free()

func test_a_roll_shows_margin_instead_of_zooming() -> void:
	await _tree_ready()
	var room := _room(true)
	var legacy := _room(false)
	room.set_camera_offset(Vector3.ZERO, 5.0)
	legacy.set_camera_offset(Vector3.ZERO, 5.0)
	var expected := PaintedOverscan.fov_for(FOV, SIZE, room.margin(), room.view_aspect(), deg_to_rad(5.0))
	ok(absf(room.camera.fov - expected) < 0.0001, "the camera follows the margin's arithmetic (%.3f deg)" % room.camera.fov)
	ok(room.camera.fov > legacy.camera.fov + 3.0, "no 11-15%% zoom any more: %.2f deg against %.2f deg without the margin" % [room.camera.fov, legacy.camera.fov])
	# A rolled screen corner lands on the margin of the painting, not past the plate texture.
	var view := room.camera.get_viewport().get_visible_rect().size
	var corner := room.screen_to_pixel(Vector2(0, 0))
	var half := room.margin() + SIZE * 0.5
	ok(absf(corner.x - SIZE.x * 0.5) <= half.x + 1.0 and absf(corner.y - SIZE.y * 0.5) <= half.y + 1.0, "the rolled window's corner %s is inside the extended frame (view %s)" % [corner, view])
	room.set_camera_offset(Vector3.ZERO, 0.0)
	room.queue_free()
	legacy.queue_free()

func test_props_still_answer_with_the_margin() -> void:
	await _tree_ready()
	var room := _room(true)
	eq(room.press(Vector2(90, 400)), "globe", "a tap on the globe pokes the globe")
	eq(room.press(Vector2(845, 450)), "statue", "a tap on the statue pokes the statue")
	var globe: PaintedProp = room.props.filter(func(p: PaintedProp) -> bool: return p.prop_id == "globe")[0]
	var mesh := (globe.get_child(0) as MeshInstance3D).mesh as ArrayMesh
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	ok(uvs[0].distance_to(room.plate_uv(Vector2(globe.rect.position))) < 0.0001, "the globe's card reads the extended plate where the painting has it (%s)" % uvs[0])
	room.queue_free()
