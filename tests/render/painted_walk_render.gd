extends SceneTree

# Real pixels of walking in the painted room (see docs/art/painted_room.md, "Walking"). Run by painted_walk_check.sh:
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 \
#       --script res://tests/render/painted_walk_render.gd -- OUT_DIR
#
# 1. Feet to pixel: she is sent to a tapped pixel of the floor; the foot pixel the engine reports lands on it, and
#    the lowest rendered pixel of her body (her silhouette, found by drawing her alone) is on that row.
# 2. Occlusion, as an oracle: for every pixel of her silhouette, what the painted room has nearer than her (the room
#    mesh, a prop's card) must hide her there, and what it has farther must not. Checked in front of the floor, in
#    front of the statue, behind the statue, behind the globe and behind the foreground rock; the picture of each
#    is kept in OUT_DIR, with a strip of the walk behind the statue.

const FRAME := 1.0 / 30.0
const MARGIN := 0.45            # metres of camera depth between "clearly nearer" and her body
const MAX_LEAK := 0.02          # of the pixels the room should hide, the share she may be drawn over
const MAX_MISSING := 0.04       # of the pixels the room should not hide, the share she may be missing from
const MIN_CHANGE := 0.03        # summed colour difference that counts as "she is drawn here"

var failures := 0
var scale_to_image := 0.75
var room: PaintedRoom
var out_dir := "user://painted_walk"

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	print("%s %s" % ["ok  " if condition else "FAIL", message])
	if not condition:
		failures += 1

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _shot() -> Image:
	await _frames(3)
	return root.get_texture().get_image()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	room = (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	root.add_child(room)
	await _frames(15)
	room.walk.set_process(false)
	scale_to_image = root.get_texture().get_size().x / room.image_size().x
	print("viewport %s, scale %.3f" % [root.get_texture().get_size(), scale_to_image])
	(room.actors["raccoon"] as Node3D).visible = false

	await _feet_scenario()
	await _occlusion_scenario("in_front_of_the_floor", Vector3(0.3, 0.0, -5.0), 0, 150)
	await _occlusion_scenario("in_front_of_the_statue", Vector3(2.1, 0.0, -6.0), 0, 150)
	await _occlusion_scenario("behind_the_statue", Vector3(2.1, 0.0, -8.6), 150, 100)
	await _occlusion_scenario("behind_the_statue_centre", Vector3(2.6, 0.0, -8.4), 150, 0)
	await _occlusion_scenario("behind_the_globe", Vector3(-3.6, 0.0, -5.9), 100, 100)
	await _occlusion_scenario("behind_the_left_rocks", Vector3(-3.0, 0.0, -5.1), 100, 100, 100)
	await _occlusion_scenario("beside_the_right_rock", Vector3(3.75, 0.0, -6.1), 0, 100)
	await _strip()
	print("WALK RENDER %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	quit(0 if failures == 0 else 1)

# ---- the witch alone ------------------------------------------------------------------------------------------

func _witch_visual() -> Node3D:
	return (room.actors["witch"] as Node3D).get_node("Visual") as Node3D

func _freeze_animation() -> void:
	CharacterModels.player_of(_witch_visual()).pause()

func _set_room_visible(on: bool) -> void:
	(room.get_node("Painting") as Node3D).visible = on
	for prop in room.props:
		prop.visible = on

func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > MIN_CHANGE

# Her silhouette in image pixels: what changes when she alone is drawn on a bare background.
func _silhouette() -> Dictionary:
	var feet_image := room.world_to_pixel(_feet()) * scale_to_image
	var window := Rect2i(Vector2i(int(feet_image.x) - 140, int(feet_image.y) - 260), Vector2i(280, 290)).intersection(Rect2i(Vector2i.ZERO, Vector2i(root.get_texture().get_size())))
	_set_room_visible(false)
	_witch_visual().visible = true
	var with_her := await _shot()
	_witch_visual().visible = false
	var without := await _shot()
	_witch_visual().visible = true
	_set_room_visible(true)
	var pixels := PackedVector2Array()
	var bounds := Rect2()
	var first := true
	for y in range(window.position.y, window.end.y):
		for x in range(window.position.x, window.end.x):
			if _differs(with_her.get_pixel(x, y), without.get_pixel(x, y)):
				pixels.append(Vector2(x, y))
				var p := Vector2(x, y)
				bounds = Rect2(p, Vector2.ZERO) if first else bounds.expand(p)
				first = false
	return {"pixels": pixels, "bounds": bounds}

func _feet() -> Vector3:
	var p := (room.actors["witch"] as Node3D).position
	return Vector3(p.x, p.y - PaintedWalker.FOOT_LIFT, p.z)

func _walk_to(world: Vector3) -> void:
	var w := room.walk.walkable
	room.walk.walk_to(Vector3(world.x, w.height_at(world.x, world.z), world.z))
	var t := 0.0
	while room.walk.witch.is_walking() and t < 30.0:
		room.walk.step(FRAME)
		t += FRAME

# ---- 1. feet to pixel -----------------------------------------------------------------------------------------

func _feet_scenario() -> void:
	var tapped := Vector2(430, 660)
	var kind := room.tap(tapped)
	_check(kind == "walk", "a tap on the carpet at %s is a walk (%s)" % [tapped, kind])
	var worst_off_surface := 0.0
	var t := 0.0
	var frames: Array[Image] = []
	while room.walk.witch.is_walking() and t < 20.0:
		room.walk.step(FRAME)
		t += FRAME
		var feet := _feet()
		worst_off_surface = maxf(worst_off_surface, absf(room.pixel_to_world(room.world_to_pixel(feet)).y - feet.y))
	_freeze_animation()
	var landed := room.world_to_pixel(_feet())
	_check(landed.distance_to(tapped) < 3.0, "her feet land on the tapped pixel: %s vs %s (%.2f px)" % [landed, tapped, landed.distance_to(tapped)])
	# The camera's own projection of her feet agrees with the painting pixel (the whole chain, not only the helper).
	var through_camera := room.screen_to_pixel(room.camera.unproject_position(_feet()))
	_check(through_camera.distance_to(landed) < 1.0, "the camera sees her feet at the same pixel (%s)" % through_camera)
	var silhouette := await _silhouette()
	var bounds: Rect2 = silhouette["bounds"]
	var bottom := (bounds.end.y + 1.0) / scale_to_image
	var centre := bounds.get_center().x / scale_to_image
	# Her hem reaches a little nearer the camera than her feet's centre: up to her skirt's radius lower on screen.
	var hem := 22.0
	_check(bottom > landed.y - 3.0 and bottom < landed.y + hem, "the lowest rendered pixel of her is at her feet, not floating or sunk: %.1f vs %.1f" % [bottom, landed.y])
	_check(absf(centre - landed.x) < 12.0, "and she is centred over the feet: %.1f vs %.1f" % [centre, landed.x])
	_check(worst_off_surface < 0.08, "on the way she stayed on the painted surface (worst %.3f m)" % worst_off_surface)
	(await _shot()).save_png(out_dir.path_join("feet_on_the_tapped_pixel.png"))

# ---- 2. occlusion ---------------------------------------------------------------------------------------------

func _depth_of_room(px: Vector2) -> float:
	var d := room.depth_at(px)
	for prop in room.props:
		if prop.contains(px):
			d = minf(d, prop.depth)
	return d

func _occlusion_scenario(label: String, world: Vector3, min_hidden: int, min_visible: int, min_by_mesh: int = 0) -> void:
	_walk_to(world)
	_freeze_animation()
	var feet := _feet()
	var eye := Vector3(0.0, float(room.room["eye_height"]), 0.0)
	var z_witch := (feet - eye).dot(room.view_axis())
	var silhouette := await _silhouette()
	var pixels: PackedVector2Array = silhouette["pixels"]
	var with_her := await _shot()
	_witch_visual().visible = false
	var without := await _shot()
	_witch_visual().visible = true
	var hidden_total := 0
	var by_mesh := 0
	var leaks := 0
	var visible_total := 0
	var missing := 0
	for p in pixels:
		var px := (p + Vector2(0.5, 0.5)) / scale_to_image
		var nearest := INF
		var farthest := 0.0
		var mesh_farthest := 0.0
		for offset in [Vector2.ZERO, Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			var d := _depth_of_room(px + offset)
			nearest = minf(nearest, d)
			farthest = maxf(farthest, d)
			mesh_farthest = maxf(mesh_farthest, room.depth_at(px + offset))
		var drawn := _differs(with_her.get_pixelv(Vector2i(p)), without.get_pixelv(Vector2i(p)))
		if farthest < z_witch - MARGIN:
			hidden_total += 1
			by_mesh += 1 if mesh_farthest < z_witch - MARGIN else 0
			leaks += 1 if drawn else 0
		elif nearest > z_witch + MARGIN:
			visible_total += 1
			missing += 0 if drawn else 1
	var leak_share := float(leaks) / maxf(hidden_total, 1.0)
	var missing_share := float(missing) / maxf(visible_total, 1.0)
	print("%s: silhouette %d px, room nearer on %d (the mesh alone on %d; drawn over it on %d), room farther on %d (missing on %d), her depth %.2f m" % [label, pixels.size(), hidden_total, by_mesh, leaks, visible_total, missing, z_witch])
	_check(hidden_total >= min_hidden, "%s: the room hides %d px of her (at least %d)" % [label, hidden_total, min_hidden])
	_check(by_mesh >= min_by_mesh, "%s: of which the depth mesh alone hides %d (at least %d)" % [label, by_mesh, min_by_mesh])
	_check(leak_share <= MAX_LEAK, "%s: nothing nearer is drawn over (%.2f%% leaked)" % [label, leak_share * 100.0])
	_check(visible_total >= min_visible, "%s: and part of her shows (%d px)" % [label, visible_total])
	_check(missing_share <= MAX_MISSING, "%s: nothing farther hides her (%.2f%% missing)" % [label, missing_share * 100.0])
	with_her.save_png(out_dir.path_join("%s.png" % label))

# ---- the walk behind the statue, as a strip ---------------------------------------------------------------------

func _strip() -> void:
	# From the first spot of the floor to behind the statue and out the other side.
	var w := room.walk.walkable
	_walk_to(Vector3(0.754, 0.0, -5.761))
	CharacterModels.player_of(_witch_visual()).play("idle")
	room.walk.walk_to(Vector3(3.6, w.height_at(3.6, -7.9), -7.9))
	var crop := Rect2i(Vector2i(int(470 * scale_to_image), int(360 * scale_to_image)), Vector2i(int(560 * scale_to_image), int(340 * scale_to_image)))
	var tiles: Array[Image] = []
	var steps := 0
	while room.walk.witch.is_walking() and steps < 900:
		room.walk.step(FRAME)
		steps += 1
		if steps % 7 == 0:
			var shot := await _shot()
			tiles.append(shot.get_region(crop))
	tiles.append((await _shot()).get_region(crop))
	var columns := 4
	var rows := ceili(float(tiles.size()) / columns)
	var sheet := Image.create(crop.size.x * columns, crop.size.y * rows, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, crop.size), Vector2i((i % columns) * crop.size.x, (i / columns) * crop.size.y))
	sheet.save_png(out_dir.path_join("walk_behind_the_statue_strip.png"))
	print("strip: %d frames" % tiles.size())
	_check(tiles.size() >= 6, "the walk behind the statue took %d strip frames" % tiles.size())
