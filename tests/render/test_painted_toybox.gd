extends TestCase

# The painted room's toy box: everything in the room answers a poke, and a poke never does nothing.
# Headless: this checks logic and data (shaders are not compiled here); the pixels are checked by the capture
# (tools/painted/capture_painted.gd, which also compares the room at rest with the painting itself).

const ROOM_DIR := "res://assets/painted/hall_clean/"
const OLD_PROPS := ["globe", "statue"]

func _room() -> PaintedRoom:
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	(Engine.get_main_loop() as SceneTree).root.add_child(room)
	return room

func _props_json() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOM_DIR + "props.json"))
	return parsed as Dictionary

func _first_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout

func test_the_toy_box_data_is_valid_and_all_its_words_exist() -> void:
	var table := Localization.load_table()
	var data := _props_json()
	var toys := 0
	var problems: Array[String] = []
	var ids: Dictionary = {}
	for entry in data["props"]:
		problems.append_array(PaintedProp.problems(entry))
		ids[str(entry["id"])] = true
		if str(entry["id"]) not in OLD_PROPS:
			toys += 1
		if entry.has("mask"):
			ok(FileAccess.file_exists(ROOM_DIR + str(entry["mask"])), "%s: the mask file exists" % entry["id"])
		for trigger in entry["reactions"]:
			for reaction in entry["reactions"][trigger]:
				var sound := str(reaction.get("sound", "")) if reaction is Dictionary else ""
				ok(sound.is_empty() or PaintedSfx.exists(sound), "%s: sound '%s' exists" % [entry["id"], sound])
				var say := str(reaction.get("say", "")) if reaction is Dictionary else ""
				ok(say.is_empty() or table.has(say), "%s: line '%s' is in data/text/ru.json" % [entry["id"], say])
	eq(problems, [], "every props.json entry uses the vocabulary")
	eq(ids.size(), (data["props"] as Array).size(), "ids are listed once")
	ok(toys >= 8, "at least 8 toys beyond the globe and the statue (%d)" % toys)
	for sound in PaintedProp.VOCABULARY.values():
		ok(PaintedSfx.exists(str(sound)), "the default sound '%s' exists" % sound)
	ok(PaintedSfx.exists("ping"), "the fallback's sound exists")

func test_the_sounds_are_small() -> void:
	var total := 0
	var count := 0
	for file_name in DirAccess.get_files_at("res://assets/painted/sfx"):
		if file_name.get_extension() == "wav":
			total += FileAccess.get_file_as_bytes("res://assets/painted/sfx/" + file_name).size()
			count += 1
	ok(count >= 6, "blip, thunk, chime, creak, rattle, boing and friends (%d)" % count)
	ok(total <= 400 * 1024, "the sounds total at most 400 KB (%d bytes)" % total)

func test_plate_empty_is_the_painting_outside_every_cutout() -> void:
	# At rest the room shows plate_empty and each cutout's card shows the plate inside its mask: so wherever
	# the masks are, plate_empty may differ, and everywhere else it must be the painting bit for bit.
	var plate := Image.load_from_file(ProjectSettings.globalize_path(ROOM_DIR + "plate.png"))
	var empty := Image.load_from_file(ProjectSettings.globalize_path(ROOM_DIR + "plate_empty.png"))
	plate.convert(Image.FORMAT_RGB8)
	empty.convert(Image.FORMAT_RGB8)
	eq(empty.get_size(), plate.get_size(), "same size")
	var changed := empty.get_data() != plate.get_data()
	ok(changed, "the removed objects left holes in plate_empty")
	for entry in _props_json()["props"]:
		if entry["kind"] != "cutout":
			continue
		var r: Array = entry["rect"]
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		eq(rect.position.x % 8 + rect.position.y % 8 + rect.size.x % 8 + rect.size.y % 8, 0, "%s: the card sits on the mesh grid" % entry["id"])
		var mask := Image.load_from_file(ProjectSettings.globalize_path(ROOM_DIR + str(entry["mask"])))
		var alpha := Image.create_empty(plate.get_width(), plate.get_height(), false, Image.FORMAT_RGBA8)
		for y in rect.size.y:
			for x in rect.size.x:
				if mask.get_pixel(x, y).r > 0.5:
					alpha.set_pixel(rect.position.x + x, rect.position.y + y, Color(1, 1, 1, 1))
		empty.blit_rect_mask(plate, alpha, rect, rect.position)
	ok(empty.get_data() == plate.get_data(), "outside the masks plate_empty equals plate.png exactly")

func test_a_random_tap_bot_never_gets_silence() -> void:
	await _first_frame()
	var room := _room()
	var state := 20260702
	var props_hit := 0
	var pings := 0
	var silent: Array[String] = []
	var taps: Array[Vector2] = []
	for i in 300:
		state = (state * 1103515245 + 12345) & 0x7fffffff
		var x := float(state % 1400) - 60.0
		state = (state * 1103515245 + 12345) & 0x7fffffff
		var y := float(state % 800) - 40.0
		taps.append(Vector2(x, y))
	# the floor, the dark corners and edges, the frame's very edge, and outside the painting
	for corner in [Vector2(0, 0), Vector2(1279, 0), Vector2(0, 719), Vector2(1279, 719), Vector2(640, 650), Vector2(5, 360), Vector2(1275, 360), Vector2(-20, -20), Vector2(1300, 740)]:
		taps.append(corner)
	for px in taps:
		var sounds_before := room.sfx.play_count
		var pings_before := room.pings.ping_count
		var hit := room.press(px)
		if hit != "":
			props_hit += 1
			var prop := _prop(room, hit)
			if not prop.reacting() or room.sfx.play_count != sounds_before + 1:
				silent.append("%s at %s: prop answered without move or sound" % [hit, px])
		else:
			var answer := room.fallback(px)
			pings += 1
			if answer.is_empty() or room.pings.ping_count != pings_before + 1 or room.sfx.play_count != sounds_before + 1:
				silent.append("fallback at %s: no ping or no sound" % px)
	eq(silent, [], "no tap is ever silent")
	ok(props_hit > 10, "the bot hit props on the way (%d)" % props_hit)
	ok(pings > 100, "and the fallback answered the rest (%d)" % pings)
	ok(room.pings.active() <= PaintedPings.POOL and room.pings.get_child_count() <= PaintedPings.POOL, "the pings are pooled, not piled up")
	room.queue_free()

func test_every_toy_runs_its_whole_cycle_visibly_and_comes_to_rest() -> void:
	await _first_frame()
	var room := _room()
	var said: Array[String] = []
	room.prop_said.connect(func(_id: String, key: String) -> void: said.append(key))
	for prop in room.props:
		var centre := _inside(prop)
		ok(prop.contains(centre), "%s: found a pixel inside" % prop.prop_id)
		var names: Array = prop.reactions["press"]
		for turn in names.size():
			var sounds_before := room.sfx.play_count
			eq(room.press(centre), prop.prop_id, "%s: a tap inside answers" % prop.prop_id)
			eq(prop.last_reaction, str(names[turn]), "%s: reaction %d is %s" % [prop.prop_id, turn, names[turn]])
			eq(room.sfx.play_count, sounds_before + 1, "%s/%s: a sound plays" % [prop.prop_id, names[turn]])
			ok(PaintedSfx.exists(prop.last_sound), "%s/%s: its sound exists" % [prop.prop_id, names[turn]])
			await _wait(0.07)
			await _first_frame()
			ok(prop.displaced(), "%s/%s: it is visibly moving a moment later" % [prop.prop_id, names[turn]])
			if prop.kind == "hotspot":
				ok(prop.card_visible(), "%s/%s: the hotspot's card shows while it reacts" % [prop.prop_id, names[turn]])
			prop.rest()
			ok(not prop.displaced(), "%s/%s: at rest nothing is displaced" % [prop.prop_id, names[turn]])
			if prop.kind == "hotspot":
				ok(not prop.card_visible(), "%s: a hotspot's card is hidden at rest" % prop.prop_id)
	ok(said.size() >= 8, "the toys have things to say (%d lines)" % said.size())
	room.queue_free()

func test_the_room_without_its_cards_is_the_painting_itself() -> void:
	await _first_frame()
	var room := _room()
	room.show_originals(true)
	for prop in room.props:
		ok(not prop.card_visible(), "%s: hidden while the originals show" % prop.prop_id)
	room.show_originals(false)
	for prop in room.props:
		eq(prop.card_visible(), prop.kind == "cutout", "%s: cutouts are back, hotspots stay hidden" % prop.prop_id)
	room.queue_free()

func _prop(room: PaintedRoom, id: String) -> PaintedProp:
	for prop in room.props:
		if prop.prop_id == id:
			return prop
	return null

# A painting pixel that belongs to the prop and is the nearest one to its pivot-side centre.
func _inside(prop: PaintedProp) -> Vector2:
	var best := Vector2(prop.rect.get_center())
	var best_distance := INF
	for y in range(prop.rect.position.y, prop.rect.end.y, 2):
		for x in range(prop.rect.position.x, prop.rect.end.x, 2):
			var px := Vector2(x, y)
			if prop.contains(px):
				var distance := px.distance_to(Vector2(prop.rect.get_center()))
				if distance < best_distance:
					best_distance = distance
					best = px
	return best
