extends TestCase

# game/world/painted/painted_life.gd: the painting's own light, as data (assets/painted/hall_clean/life.json).
# Pixels are checked by tests/render/painted_life_check.gd (needs a real renderer).

# A node added to the root before the first frame is not ready until that frame, so wait for one.
func _room() -> PaintedRoom:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	tree.root.add_child(room)
	room.life.auto_advance = false
	return room

func test_the_flicker_is_a_pure_quantised_staircase() -> void:
	var seen := {}
	for kind in ["candle", "lamp", "magic", "breath"]:
		for step in 64:
			var a := PaintedLife.flicker_value(kind, 11, step, 8.0, 0.3)
			eq(a, PaintedLife.flicker_value(kind, 11, step, 8.0, 0.3), "%s step %d is repeatable" % [kind, step])
			ok(a >= 0.0 and a <= 2.0, "%s stays in range (%f)" % [kind, a])
			ok(is_equal_approx(a * 16.0, roundf(a * 16.0)), "%s is quantised to 1/16 (%f)" % [kind, a])
			seen[snappedf(a, 0.0625)] = true
		eq(PaintedLife.flicker_value(kind, 11, 5, 8.0, 0.0), 1.0, "%s with no amount holds still" % kind)
	ok(seen.size() >= 5, "the flicker takes several levels (%d)" % seen.size())
	eq(PaintedLife.flicker_value("none", 1, 9, 8.0, 0.5), 1.0, "kind none is constant")
	ok(PaintedLife.flicker_value("candle", 11, 3, 8.0, 0.3) != PaintedLife.flicker_value("candle", 12, 3, 8.0, 0.3) \
		or PaintedLife.flicker_value("candle", 11, 4, 8.0, 0.3) != PaintedLife.flicker_value("candle", 12, 4, 8.0, 0.3), "two candles with other seeds do not burn in step")
	var moving := 0
	for step in 63:
		if PaintedLife.flicker_value("candle", 11, step, 8.0, 0.3) != PaintedLife.flicker_value("candle", 11, step + 1, 8.0, 0.3):
			moving += 1
	ok(moving > 20, "a candle changes level on many steps (%d of 63)" % moving)

func test_life_json_loads_into_lights_a_beam_and_a_frame() -> void:
	var room := await _room()
	var life := room.life
	ok(life != null and life.loaded, "the painted room builds its life")
	var ids := life.light_ids()
	for id in ["oculus", "candle_a", "lamp_shelf_l", "lantern_arch", "corridor"]:
		ok(ids.has(id), "light %s is authored" % id)
	var unique := {}
	var size := room.image_size()
	for id in ids:
		unique[id] = true
		var pixel := life.pixel_of(id)
		ok(Rect2(Vector2.ZERO, size).has_point(pixel), "%s sits inside the painting (%s)" % [id, pixel])
		ok(room.depth_at(pixel) > 0.5, "%s maps to a depth of the room" % id)
	eq(unique.size(), ids.size(), "light ids are unique")
	eq(life.pixel_of("nope"), Vector2(-1, -1), "an unknown id has no pixel")
	eq(life.level_of("nope"), -1.0, "an unknown id has no level")
	ok(room.get_node_or_null("Life/Glow") is MeshInstance3D, "glow cards are one mesh")
	ok(room.get_node_or_null("Life/Beam") is MeshInstance3D, "the beam is one mesh")
	ok(room.get_node_or_null("Life/Frame") is CanvasLayer, "the frame is one layer")
	ok(life.get_index() < room.get_node("Screen").get_index(), "the life is built before the screen layer, so the screen quantises it")
	var missing := PaintedLife.new()
	eq(missing.setup(room, "no_such_life.json"), false, "a room without life.json has no life")
	missing.free()
	room.queue_free()

func test_life_stays_within_budget() -> void:
	var room := await _room()
	var cost := room.life.cost()
	eq(cost["surfaces"], 2, "glow cards and the beam are two surfaces")
	ok(int(cost["triangles"]) < 8000, "the added triangles are few (%d)" % cost["triangles"])
	ok(int(cost["draw_calls"]) <= 3, "three draw calls: glow, beam, frame (%d)" % cost["draw_calls"])
	ok(room.life.light_ids().size() <= PaintedLife.MAX_SLOTS, "lights fit the shader's slots")
	room.queue_free()

func test_the_lights_move_on_steps_and_hold_still_at_zero_flicker() -> void:
	var room := await _room()
	var life := room.life
	var steps := {}
	for i in 40:
		life.advance(1.0 / life.fps)
		steps[life.level_of("candle_a")] = true
	ok(steps.size() > 2, "a candle takes several levels over five seconds (%d)" % steps.size())
	var before := life.level_of("candle_a")
	life.advance(0.01)
	eq(life.level_of("candle_a"), before, "a light changes only when a whole step has passed")
	life.flicker = 0.0
	for id in life.light_ids():
		eq(life.level_of(id), 1.0, "%s holds its base level at zero flicker" % id)
	eq(life.beam_level(), 1.0, "the beam holds still at zero flicker")
	life.advance(2.0)
	eq(life.level_of("candle_a"), 1.0, "and it stays there as time passes")
	room.queue_free()

func test_pulse_flares_a_light_then_it_fades_in_steps() -> void:
	var room := await _room()
	var life := room.life
	life.flicker = 0.0
	var home := life.pixel_of("lantern_far")
	var base := life.level_of("lantern_far")
	var id := life.pulse(home + Vector2(4, 3), Color(1.0, 0.5, 0.2), 1.0)
	eq(id, "lantern_far", "a pulse on a lamp flares that lamp")
	ok(life.level_of(id) >= base + 0.99, "the flare is at full strength at once (%f)" % life.level_of(id))
	life.advance(1.0 / life.fps)
	var after_one := life.flare_of(id)
	ok(after_one < 1.0 and after_one > 0.6, "one step later it has lost a part of itself (%f)" % after_one)
	life.advance(4.0)
	ok(life.flare_of(id) < 0.02, "and it is gone within a few seconds (%f)" % life.flare_of(id))
	eq(life.level_of(id), base, "the lamp is back at its own level")
	eq(life.pulse(Vector2(-5, 20)), "", "a pulse outside the painting does nothing")
	eq(life.pulse(home, Color.WHITE, 0.0), "", "a pulse of no strength does nothing")
	room.queue_free()

func test_pulse_in_the_dark_strikes_a_spark_that_is_reused() -> void:
	var room := await _room()
	var life := room.life
	life.flicker = 0.0
	var count := life.light_ids().size()
	var spot := Vector2(1150, 600)
	var id := life.pulse(spot, Color(0.4, 0.8, 1.0), 1.0)
	ok(id.begins_with("spark_"), "a pulse far from every lamp strikes a spark (%s)" % id)
	eq(life.light_ids().size(), count + 1, "the spark is a new light")
	eq(life.pixel_of(id), spot, "at the pixel that was poked")
	ok(life.level_of(id) > 0.9, "it is bright now (%f)" % life.level_of(id))
	eq(life.pulse(spot + Vector2(5, 0), Color.WHITE, 0.5), id, "a second poke at the same spot feeds the same spark")
	for i in 20:
		life.pulse(Vector2(1000 + i * 12, 640), Color.WHITE, 0.5 + 0.02 * i)
	ok(life.light_ids().size() <= count + 6, "sparks are capped at the spare slots (%d lights, %d authored)" % [life.light_ids().size(), count])
	life.advance(5.0)
	eq(life.flare_of(id), 0.0, "the spark has died down")
	room.queue_free()

func test_life_changed_carries_the_beam_to_the_characters() -> void:
	var room := await _room()
	var life := room.life
	ok(life.occluder_count() > 0, "the characters block the beam")
	var heard: Array[float] = []
	life.life_changed.connect(func(level: float) -> void: heard.append(level))
	for i in 80:
		life.advance(1.0 / life.fps)
	ok(heard.size() >= 3, "life_changed fires as the beam breathes (%d times in ten seconds)" % heard.size())
	for level in heard:
		ok(level > 0.7 and level < 1.3, "the level stays small (%f)" % level)
	ok(life._actor_materials.size() > 0, "the characters' light shaders were found")
	var material := life._actor_materials[0]
	ok(is_equal_approx(float(material.get_shader_parameter("light_scale")), room.actor_light * life.actor_level()), "the characters' light follows the level")
	life.flicker = 0.0
	heard.clear()
	life.advance(3.0)
	eq(life.actor_level(), 1.0, "at zero flicker the characters are lit as the painting lights them")
	ok(is_equal_approx(float(material.get_shader_parameter("light_scale")), room.actor_light), "their light is back at the room's own")
	life.pulse(life.pixel_of("candle_a"), Color.WHITE, 1.0)
	ok(life.actor_level() > 1.0, "a flare reaches the characters a little (%f)" % life.actor_level())
	room.queue_free()

func test_the_characters_shadow_follows_them_into_the_beam() -> void:
	var room := await _room()
	var life := room.life
	var spheres := life._occluders.duplicate()
	var witch := room.actors["witch"] as Node3D
	witch.position += Vector3(1.0, 0.0, 0.0)
	life._process(0.0)
	ok(life._occluders != spheres, "moving the witch moves her shadow's spheres")
	eq(life._occluders.size(), spheres.size(), "the same number of spheres")
	eq(life.occluder_count(), 6, "three spheres for each of the two characters")
	room.queue_free()

func test_intensity_zero_hides_everything_and_psx_follows_the_room() -> void:
	var room := await _room()
	var life := room.life
	var glow := room.get_node("Life/Glow") as MeshInstance3D
	var beam := room.get_node("Life/Beam") as MeshInstance3D
	ok(glow.visible and beam.visible, "visible at full intensity")
	life.intensity = 0.0
	ok(not glow.visible and not beam.visible and not (room.get_node("Life/Frame") as CanvasLayer).visible, "intensity 0 draws nothing at all")
	life.intensity = 1.0
	ok(glow.visible and beam.visible, "and back")
	room.set_psx(false)
	eq((glow.material_override as ShaderMaterial).get_shader_parameter("psx"), false, "the glow cards follow the room's PSX switch")
	eq((beam.material_override as ShaderMaterial).get_shader_parameter("psx"), false, "and so does the beam")
	room.set_psx(true)
	eq((beam.material_override as ShaderMaterial).get_shader_parameter("psx"), true, "PSX back on")
	room.queue_free()
