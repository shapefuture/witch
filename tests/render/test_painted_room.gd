extends TestCase

# game/world/painted: a painted still as a room, with props that answer a tap.

# A frame has to pass before a node added to the root counts as inside the tree (the first test of a run).
func _first_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

func _room() -> PaintedRoom:
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	(Engine.get_main_loop() as SceneTree).root.add_child(room)
	return room

func test_the_room_loads_its_camera_depth_actors_and_props() -> void:
	await _first_frame()
	var room := _room()
	ok(room.camera != null, "the painting's camera exists")
	ok(room.actors.has("witch") and room.actors.has("raccoon"), "the witch and the raccoon stand in it")
	eq(room.props.size(), 14, "the toy box: globe, statue and twelve more")
	var px := Vector2(640, 500)
	var back := room.world_to_pixel(room.pixel_to_world(px))
	ok(back.distance_to(px) < 0.5, "pixel -> world -> pixel round-trips (%s)" % back)
	var feet := room.world_to_pixel(room.actors["witch"].position)
	ok(feet.distance_to(Vector2(735, 634)) < 1.0, "the witch's feet are where the painting had them (%s)" % feet)
	room.queue_free()

func test_the_characters_have_a_key_light_and_cast_a_shadow_along_the_beam() -> void:
	await _first_frame()
	var room := _room()
	for id in ["witch", "raccoon"]:
		var meshes := (room.actors[id] as Node3D).get_node("Visual").find_children("*", "MeshInstance3D", true, false)
		ok(not meshes.is_empty(), "%s has meshes" % id)
		var shadow := room.shadows.get(id) as PaintedActorShadow
		ok(shadow != null and shadow.visible, "%s casts a shadow" % id)
		for mesh in meshes:
			var instance := mesh as MeshInstance3D
			ok(instance.layers & shadow.camera.cull_mask != 0, "%s: every mesh is in its beam camera's layer" % id)
			var lit := instance.get_active_material(0) as ShaderMaterial
			ok(lit != null and float(lit.get_shader_parameter("key_strength")) > 0.0, "%s: faceted key light is on" % id)
		ok(shadow.material.get_shader_parameter("silhouette") is ViewportTexture, "%s: the floor reads the beam camera's view" % id)
		# the shadow falls away from the sun
		var sun: Array = room.room["sun_dir"]
		var away := -Vector2(float(sun[0]), float(sun[2]))
		var centre := shadow.floor_quad.global_position - (room.actors[id] as Node3D).global_position
		ok(Vector2(centre.x, centre.z).dot(away) > 0.0, "%s: its shadow lies away from the beam" % id)
	var witch_shadow := room.shadows["witch"] as PaintedActorShadow
	var raccoon_shadow := room.shadows["raccoon"] as PaintedActorShadow
	ok(witch_shadow.camera.cull_mask & raccoon_shadow.camera.cull_mask == 0, "each beam camera sees only its own character")
	room.actor_shadow = 0.0
	room.relight_actors()
	ok(not witch_shadow.visible, "shadow off hides it")
	eq(witch_shadow.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "shadow off stops its camera")
	room.queue_free()

# A room with a `lighting` block (measured from calibration spheres or derived from its plate) lights its characters by it:
# a warm key from its own direction, a cool sky fill, a ground bounce; one without keeps the floor-map light.
func test_a_rooms_own_lighting_lights_the_characters() -> void:
	await _first_frame()
	var hall := _room()
	eq(hall.lighting().size(), 0, "the hall has no lighting block")
	var hall_material := ((hall.actors["witch"] as Node3D).get_node("Visual").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0) as ShaderMaterial
	eq(float(hall_material.get_shader_parameter("lighting_mode")), 0.0, "so its characters stay on the floor-map light")
	hall.queue_free()
	var garden := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	garden.room_dir = "res://assets/painted/garden"
	(Engine.get_main_loop() as SceneTree).root.add_child(garden)
	var l := garden.lighting()
	ok(not l.is_empty() and str(l["source"]) == "spheres", "the garden carries the lighting measured from its spheres")
	var key: Array = l["key_dir"]
	for id in ["witch", "raccoon"]:
		for mesh in (garden.actors[id] as Node3D).get_node("Visual").find_children("*", "MeshInstance3D", true, false):
			var material := (mesh as MeshInstance3D).get_active_material(0) as ShaderMaterial
			eq(float(material.get_shader_parameter("lighting_mode")), 1.0, "%s: lighting mode is on" % id)
			var dir := material.get_shader_parameter("sun_dir") as Vector3
			ok(dir.distance_to(Vector3(float(key[0]), float(key[1]), float(key[2]))) < 1e-4, "%s: the key comes from the measured direction" % id)
			var sky := material.get_shader_parameter("sky_color") as Color
			var ground := material.get_shader_parameter("ground_color") as Color
			ok(sky.b >= sky.r and ground.r > ground.b, "%s: cool sky above, warm bounce below" % id)
			eq(float(material.get_shader_parameter("key_front")), 0.0, "%s: the key is not turned toward the camera" % id)
		var shadow := garden.shadows[id] as PaintedActorShadow
		var tint := shadow.material.get_shader_parameter("tint") as Color
		ok(tint.b >= tint.r, "%s: its shadow takes the cool fill, not the default violet" % id)
	garden.measured_lighting = false
	garden.relight_actors()
	var off := ((garden.actors["witch"] as Node3D).get_node("Visual").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_active_material(0) as ShaderMaterial
	eq(float(off.get_shader_parameter("lighting_mode")), 0.0, "switching it off puts the characters back on the floor map")
	garden.queue_free()

func test_a_tap_finds_the_nearest_prop_and_walks_its_reactions() -> void:
	await _first_frame()
	var room := _room()
	eq(room.press(Vector2(90, 400)), "globe", "a tap on the globe pokes the globe")
	eq(room.press(Vector2(845, 450)), "statue", "a tap on the statue pokes the statue")
	eq(room.press(Vector2(640, 40)), "", "a tap on bare painting pokes nothing")
	var globe: PaintedProp = room.props.filter(func(p: PaintedProp) -> bool: return p.prop_id == "globe")[0]
	eq(globe.react("press"), "hop", "the second poke answers differently")
	room.queue_free()
