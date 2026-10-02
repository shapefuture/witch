extends SceneTree

# Pixels of the painted room's light and life. Needs a real renderer (shaders do not compile headlessly):
#   xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 \
#       --script res://tests/render/painted_life_check.gd -- [OUT_DIR]
# Prints PAINTED_LIFE lines and ends with PAINTED_LIFE PASSED or PAINTED_LIFE FAILED (tests/render/render_check.sh greps it).
#   rest        life at intensity 0 is pixel-for-pixel the room without any life
#   seams       with the flicker at zero no glow card shows its edge; the beam covers its interior with no cracks
#   breathing   the glows and the beam change over time, the rest of the picture does not
#   pulse       a flare brightens its lamp and dies away to exactly the rest picture
#   shadow      the characters darken the pool of light, towards the camera and away from the oculus
#   cost        draw calls the life adds

const SIZE := Vector2(1280.0, 720.0)

var _failures := 0
var _out := ""

func _initialize() -> void:
	_run()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PAINTED_LIFE ok   ", message)
	else:
		_failures += 1
		print("PAINTED_LIFE FAIL ", message)

func _room(with_life: bool) -> PaintedRoom:
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	root.add_child(room)
	if with_life:
		room.life.auto_advance = false
	else:
		room.life.free()
		room.life = null
	# The characters idle; hold them on one frame so two captures differ only by the light.
	for player in room.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).pause()
		(player as AnimationPlayer).seek(0.0, true)
	return room

func _shot() -> Image:
	for i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image

func _save(image: Image, name: String) -> void:
	if _out != "":
		image.save_png(_out.path_join(name + ".png"))

func _scale(image: Image) -> float:
	return float(image.get_width()) / SIZE.x

# Mean over a box (painting pixels) of the grey value, 0..255.
func _mean(image: Image, box: Rect2) -> float:
	var s := _scale(image)
	var x0 := int(box.position.x * s)
	var y0 := int(box.position.y * s)
	var x1 := int(box.end.x * s)
	var y1 := int(box.end.y * s)
	var data := image.get_data()
	var w := image.get_width()
	var total := 0.0
	var count := 0
	for y in range(maxi(y0, 0), mini(y1, image.get_height())):
		for x in range(maxi(x0, 0), mini(x1, w)):
			var i := (y * w + x) * 3
			total += (data[i] + data[i + 1] + data[i + 2]) / 3.0
			count += 1
	return total / maxf(count, 1)

# Number of pixels of a box that differ between two images by more than `tolerance` (0..255 on any channel).
func _changed(a: Image, b: Image, box: Rect2, tolerance: int) -> int:
	var s := _scale(a)
	var data_a := a.get_data()
	var data_b := b.get_data()
	var w := a.get_width()
	var count := 0
	for y in range(maxi(int(box.position.y * s), 0), mini(int(box.end.y * s), a.get_height())):
		for x in range(maxi(int(box.position.x * s), 0), mini(int(box.end.x * s), w)):
			var i := (y * w + x) * 3
			if absi(data_a[i] - data_b[i]) > tolerance or absi(data_a[i + 1] - data_b[i + 1]) > tolerance or absi(data_a[i + 2] - data_b[i + 2]) > tolerance:
				count += 1
	return count

# True where a character is drawn (the picture with characters differs from the one without), a few pixels around.
func _covered(with_actors: PackedByteArray, without: PackedByteArray, w: int, x: int, y: int) -> bool:
	for offset: Vector2i in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]:
		var i := ((y + offset.y) * w + x + offset.x) * 3
		if i >= 0 and i + 2 < with_actors.size() and (with_actors[i] != without[i] or with_actors[i + 1] != without[i + 1] or with_actors[i + 2] != without[i + 2]):
			return true
	return false

# The mask's value at a point given in texels, interpolated like the shader's texture lookup (R or G, whichever is larger).
func _bilinear(mask: Image, at: Vector2) -> float:
	var p := at - Vector2(0.5, 0.5)
	var x0 := clampi(floori(p.x), 0, mask.get_width() - 1)
	var y0 := clampi(floori(p.y), 0, mask.get_height() - 1)
	var x1 := mini(x0 + 1, mask.get_width() - 1)
	var y1 := mini(y0 + 1, mask.get_height() - 1)
	var fx := clampf(p.x - x0, 0.0, 1.0)
	var fy := clampf(p.y - y0, 0.0, 1.0)
	var best := 0.0
	for channel in 2:
		var top := lerpf(mask.get_pixel(x0, y0)[channel], mask.get_pixel(x1, y0)[channel], fx)
		var bottom := lerpf(mask.get_pixel(x0, y1)[channel], mask.get_pixel(x1, y1)[channel], fx)
		best = maxf(best, lerpf(top, bottom, fy))
	return best

func _max_diff(a: Image, b: Image) -> int:
	var data_a := a.get_data()
	var data_b := b.get_data()
	var worst := 0
	for i in data_a.size():
		worst = maxi(worst, absi(data_a[i] - data_b[i]))
	return worst

# Two 3-pixel bands along the middle half of one side of a rectangle: just inside it, and just outside it.
func _edge_bands(rect: Rect2, edge: int) -> Array[Rect2]:
	var half := rect.size.x * 0.25
	var mid := rect.get_center()
	match edge:
		0:
			return [Rect2(mid.x - half, rect.position.y + 3.0, half * 2.0, 3.0), Rect2(mid.x - half, rect.position.y - 6.0, half * 2.0, 3.0)]
		1:
			return [Rect2(rect.end.x - 6.0, mid.y - half, 3.0, half * 2.0), Rect2(rect.end.x + 3.0, mid.y - half, 3.0, half * 2.0)]
		2:
			return [Rect2(mid.x - half, rect.end.y - 6.0, half * 2.0, 3.0), Rect2(mid.x - half, rect.end.y + 3.0, half * 2.0, 3.0)]
	return [Rect2(rect.position.x + 3.0, mid.y - half, 3.0, half * 2.0), Rect2(rect.position.x - 6.0, mid.y - half, 3.0, half * 2.0)]

func _draw_calls() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
	await process_frame

	# The room as painted, without any life; the draw calls it costs.
	var plain_room := _room(false)
	var plain := await _shot()
	var plain_calls := _draw_calls()
	_save(plain, "plain")
	for id in plain_room.actors:
		(plain_room.actors[id] as Node3D).visible = false
	var plain_empty := await _shot()
	for id in plain_room.actors:
		(plain_room.actors[id] as Node3D).visible = true
	plain_room.free()

	var room := _room(true)
	var life := room.life
	_check(life != null and life.loaded, "the room builds its life")

	# rest: intensity 0 draws nothing.
	life.intensity = 0.0
	var off := await _shot()
	_check(_max_diff(plain, off) == 0, "intensity 0 is the plain room, pixel for pixel (max diff %d)" % _max_diff(plain, off))
	_save(off, "intensity_zero")
	life.intensity = 1.0

	# seams: flicker at zero.
	life.flicker = 0.0
	life.set_clock(0.0)
	var rest := await _shot()
	var life_calls := _draw_calls()
	_save(rest, "rest")
	var drawn := _changed(plain, rest, Rect2(Vector2.ZERO, SIZE), 2)
	_check(drawn > 20000, "the life at rest changes the picture (%d px)" % drawn)
	_check(_max_diff(rest, await _shot()) == 0, "and holds perfectly still at zero flicker")
	# No glow card draws beyond its own square: with the beam and the frame hidden, the pixels in a band just outside
	# each card (and outside every other card) are exactly the plain room's.
	var s := _scale(rest)
	(room.get_node("Life/Beam") as Node3D).visible = false
	(room.get_node("Life/Frame") as CanvasLayer).visible = false
	var glow_only := await _shot()
	_save(glow_only, "glow_only")
	var rects: Array[Rect2] = []
	for index in life.light_ids().size():
		var radius := float(life._lights[index]["radius"])
		rects.append(Rect2(life.pixel_of(life.light_ids()[index]) - Vector2(radius, radius), Vector2(radius, radius) * 2.0))
	var bounds := Rect2(Vector2.ZERO, SIZE)
	var strays := 0
	var glow_pixels := 0
	for index in rects.size():
		for edge in 4:
			var band := _edge_bands(rects[index], edge)[1]
			var alone := bounds.encloses(band)
			for other in rects.size():
				if other != index and rects[other].grow(4.0).intersects(band):
					alone = false
			if alone:
				strays += _changed(plain, glow_only, band, 0)
		glow_pixels += _changed(plain, glow_only, rects[index], 2)
	_check(glow_pixels > 5000, "the glow cards draw (%d px lit)" % glow_pixels)
	_check(strays == 0, "no glow card draws outside its square (%d stray px)" % strays)
	(room.get_node("Life/Beam") as Node3D).visible = true

	# seams: the beam painted opaque must cover every pixel deep inside its mask.
	var beam_material := life._beam_material as ShaderMaterial
	var mask_texture := beam_material.get_shader_parameter("mask") as ImageTexture
	var mask := mask_texture.get_image()
	beam_material.set_shader_parameter("shaft", Vector4(100.0, 0.0, 1.0, 0.0))
	beam_material.set_shader_parameter("pool", Vector4(100.0, 0.0, 1.0, 0.0))
	beam_material.set_shader_parameter("beam_color", Vector3(1.0, 0.0, 1.0))
	beam_material.set_shader_parameter("luma_range", Vector2(-1.0, -0.5))
	beam_material.set_shader_parameter("motes", Vector4(9.0, 0.0, 0.0, 0.0))
	(room.get_node("Life/Glow") as Node3D).visible = false
	(room.get_node("Life/Frame") as CanvasLayer).visible = false
	var opaque := await _shot()
	_save(opaque, "beam_opaque")
	var covered := 0
	var cracks := 0
	var data := opaque.get_data()
	var plain_data := plain.get_data()
	var empty_data := plain_empty.get_data()
	var w := opaque.get_width()
	var step := float(room.room.get("grid_step", 8))
	for y in range(0, opaque.get_height(), 3):
		for x in range(0, w, 3):
			var px := Vector2(x, y) / s
			var cell := Vector2i(int(px.x / step), int(px.y / step))
			if cell.x < 1 or cell.y < 1 or cell.x >= mask.get_width() - 1 or cell.y >= mask.get_height() - 1:
				continue
			if _bilinear(mask, px / step) < 0.05:
				continue
			# Characters stand in front of the beam: skip what they cover.
			if _covered(plain_data, empty_data, w, x, y):
				continue
			covered += 1
			var i := (y * w + x) * 3
			# (a character's contact shadow multiplies the magenta a little darker, which is not a crack)
			if data[i] < 225 or data[i + 1] > 30 or data[i + 2] < 225:
				cracks += 1
				print("PAINTED_LIFE crack at painting px ", px.round(), " colour ", Vector3i(data[i], data[i + 1], data[i + 2]), " mask ", _bilinear(mask, px / step))
	_check(covered > 5000, "enough of the beam is inside its mask to test (%d samples)" % covered)
	_check(cracks == 0, "the opaque beam leaves no crack or hole anywhere inside its mask (%d of %d samples not covered)" % [cracks, covered])
	life.set_clock(0.0)
	life.free()
	room.free()

	# breathing: the room with its life running.
	var live_room := _room(true)
	life = live_room.life
	life.set_clock(0.0)
	var frames: Array[Image] = []
	for n in 8:
		life.set_clock(n * 0.375)
		frames.append(await _shot())
		_save(frames[n], "f%02d" % n)
	var candle := Rect2(life.pixel_of("candle_a") - Vector2(40, 40), Vector2(80, 80))
	var shaft_box := Rect2(700, 300, 60, 100)
	var quiet := Rect2(400, 200, 120, 80)
	var candle_moves := 0
	var beam_moves := 0
	var quiet_moves := 0
	for n in 7:
		if _changed(frames[n], frames[n + 1], candle, 2) > 30:
			candle_moves += 1
		if _changed(frames[n], frames[n + 1], shaft_box, 2) > 100:
			beam_moves += 1
		quiet_moves += _changed(frames[n], frames[n + 1], quiet, 0)
	_check(candle_moves >= 3, "the candles' glow changes between frames (%d of 7 pairs)" % candle_moves)
	_check(beam_moves >= 3, "the beam changes between frames (%d of 7 pairs)" % beam_moves)
	_check(quiet_moves == 0, "a quiet corner of the painting stays exactly still (%d px changed)" % quiet_moves)

	# pulse: a flare brightens its lamp and dies away to the rest picture.
	life.flicker = 0.0
	life.set_clock(0.0)
	var before := await _shot()
	var lamp := life.pixel_of("lantern_far")
	var lamp_box := Rect2(lamp - Vector2(12, 12), Vector2(24, 24))
	life.pulse(lamp, Color(1.0, 0.55, 0.25), 1.0)
	var flared := await _shot()
	_save(flared, "pulse")
	var gain := _mean(flared, lamp_box) - _mean(before, lamp_box)
	_check(gain > 8.0, "a pulse lights its lamp (+%.1f of 255 around it)" % gain)
	life.advance(4.0)
	var after := await _shot()
	_check(_max_diff(before, after) == 0, "and the room is exactly at rest again after it fades (max diff %d)" % _max_diff(before, after))
	var spark_at := Vector2(1150, 560)
	var spark_box := Rect2(spark_at - Vector2(30, 30), Vector2(60, 60))
	life.pulse(spark_at, Color(0.5, 0.8, 1.0), 1.0)
	var sparked := await _shot()
	_check(_mean(sparked, spark_box) - _mean(after, spark_box) > 5.0, "a pulse in the dark strikes a visible spark")
	life.advance(4.0)

	# shadow: the characters darken the pool of light.
	var shadowed := await _shot()
	life._occluder_config.clear()
	life._process(0.0)
	var unshadowed := await _shot()
	_save(shadowed, "shadow_on")
	_save(unshadowed, "shadow_off")
	var count := 0
	var brighter := 0
	var sum := Vector2.ZERO
	var data_on := shadowed.get_data()
	var data_off := unshadowed.get_data()
	for y in range(0, shadowed.get_height()):
		for x in range(0, shadowed.get_width()):
			var i := (y * shadowed.get_width() + x) * 3
			var d := (int(data_on[i]) + data_on[i + 1] + data_on[i + 2]) - (int(data_off[i]) + data_off[i + 1] + data_off[i + 2])
			if d < -12:
				count += 1
				sum += Vector2(x, y) / s
			elif d > 12:
				brighter += 1
	var feet := live_room.world_to_pixel((live_room.actors["witch"] as Node3D).position)
	_check(count > 150, "the characters cast a shadow on the beam (%d px darker)" % count)
	_check(brighter < count * 0.1, "and it only darkens (%d px brighter)" % brighter)
	if count > 0:
		var centre := sum / count
		_check(centre.x < feet.x + 40.0 and centre.y > feet.y - 30.0, "towards the camera, away from the oculus (shadow centre %s, witch's feet %s)" % [centre.round(), feet.round()])
	live_room.free()

	print("PAINTED_LIFE DRAWCALLS plain=%d with_life=%d (added %d)" % [plain_calls, life_calls, life_calls - plain_calls])
	_check(life_calls - plain_calls <= 4, "the life adds at most four draw calls (%d)" % (life_calls - plain_calls))
	print("PAINTED_LIFE PASSED" if _failures == 0 else "PAINTED_LIFE FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)
