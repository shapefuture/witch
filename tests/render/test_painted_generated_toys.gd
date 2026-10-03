extends TestCase

# The toy boxes of the rooms tools/painted/toys.py made (every painted room with a props.json except the hand-made hall, which
# test_painted_toybox.gd covers): the same promises, per room. Headless: logic and data; the pixels are checked by the capture.

const HAND_MADE := ["hall_clean"]

func _rooms() -> Array[String]:
	var found: Array[String] = []
	for dir_name in DirAccess.get_directories_at("res://assets/painted"):
		if dir_name not in HAND_MADE and FileAccess.file_exists("res://assets/painted/%s/props.json" % dir_name):
			found.append("res://assets/painted/%s/" % dir_name)
	return found

func _data(room_dir: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(room_dir + "props.json")) as Dictionary

func _first_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

func _wait(seconds: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(seconds).timeout

func _room(room_dir: String) -> PaintedRoom:
	var room := (load("res://game/world/painted/painted_room.tscn") as PackedScene).instantiate() as PaintedRoom
	room.room_dir = room_dir.trim_suffix("/")
	(Engine.get_main_loop() as SceneTree).root.add_child(room)
	return room

func test_there_are_generated_rooms_with_toys() -> void:
	ok(not _rooms().is_empty(), "at least one generated room has a toy box (the garden)")

func test_every_generated_toy_box_uses_the_vocabulary_and_has_its_files() -> void:
	var table := Localization.load_table()
	for room_dir in _rooms():
		var data := _data(room_dir)
		var ids: Dictionary = {}
		var cutouts := 0
		for entry in data["props"]:
			var problems := PaintedProp.problems(entry)
			eq(problems, [], "%s%s: valid" % [room_dir, entry["id"]])
			ids[str(entry["id"])] = true
			if entry["kind"] == "cutout":
				cutouts += 1
				ok(FileAccess.file_exists(room_dir + str(entry["mask"])), "%s: the mask file exists" % entry["id"])
				var r: Array = entry["rect"]
				eq(int(r[0]) % 8 + int(r[1]) % 8 + int(r[2]) % 8 + int(r[3]) % 8, 0, "%s: the card sits on the mesh grid" % entry["id"])
			for trigger in entry["reactions"]:
				ok(not (entry["reactions"][trigger] as Array).is_empty(), "%s: %s has answers" % [entry["id"], trigger])
				for reaction in entry["reactions"][trigger]:
					var sound := str(reaction.get("sound", "")) if reaction is Dictionary else ""
					ok(sound.is_empty() or PaintedSfx.exists(sound), "%s: sound '%s' exists" % [entry["id"], sound])
					var say := str(reaction.get("say", "")) if reaction is Dictionary else ""
					ok(say.is_empty() or table.has(say), "%s: line '%s' is in data/text/ru.json" % [entry["id"], say])
		eq(ids.size(), (data["props"] as Array).size(), "%s: ids are listed once" % room_dir)
		ok(cutouts >= 1, "%s: at least one object was lifted" % room_dir)

func test_plate_empty_is_the_painting_outside_every_cutout() -> void:
	for room_dir in _rooms():
		var plate := Image.load_from_file(ProjectSettings.globalize_path(room_dir + "plate.png"))
		var empty := Image.load_from_file(ProjectSettings.globalize_path(room_dir + "plate_empty.png"))
		plate.convert(Image.FORMAT_RGB8)
		empty.convert(Image.FORMAT_RGB8)
		eq(empty.get_size(), plate.get_size(), "%s: same size" % room_dir)
		ok(empty.get_data() != plate.get_data(), "%s: the lifted objects left holes in plate_empty" % room_dir)
		for entry in _data(room_dir)["props"]:
			if entry["kind"] != "cutout":
				continue
			var r: Array = entry["rect"]
			var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
			var mask := Image.load_from_file(ProjectSettings.globalize_path(room_dir + str(entry["mask"])))
			var alpha := Image.create_empty(plate.get_width(), plate.get_height(), false, Image.FORMAT_RGBA8)
			for y in rect.size.y:
				for x in rect.size.x:
					if mask.get_pixel(x, y).r > 0.5:
						alpha.set_pixel(rect.position.x + x, rect.position.y + y, Color(1, 1, 1, 1))
			empty.blit_rect_mask(plate, alpha, rect, rect.position)
		ok(empty.get_data() == plate.get_data(), "%s: outside the masks plate_empty equals plate.png exactly" % room_dir)

func test_every_toy_of_a_generated_room_answers_a_tap_and_comes_to_rest() -> void:
	await _first_frame()
	for room_dir in _rooms():
		var room := _room(room_dir)
		eq(room.props.size(), (_data(room_dir)["props"] as Array).size(), "%s: every toy is in the room" % room_dir)
		for prop in room.props:
			var centre := _inside(prop)
			ok(prop.contains(centre), "%s: found a pixel inside" % prop.prop_id)
			var sounds_before := room.sfx.play_count
			eq(room.press(centre), prop.prop_id, "%s: a tap inside answers" % prop.prop_id)
			eq(room.sfx.play_count, sounds_before + 1, "%s: a sound plays" % prop.prop_id)
			ok(PaintedSfx.exists(prop.last_sound), "%s: its sound exists" % prop.prop_id)
			await _wait(0.07)
			await _first_frame()
			ok(prop.displaced(), "%s: it is visibly moving a moment later" % prop.prop_id)
			prop.rest()
			ok(not prop.displaced(), "%s: at rest nothing is displaced" % prop.prop_id)
		room.queue_free()

func test_a_second_poke_answers_differently() -> void:
	await _first_frame()
	for room_dir in _rooms():
		var room := _room(room_dir)
		for prop in room.props:
			var names: Array = prop.reactions["press"]
			ok(names.size() >= 2, "%s: two answers or more" % prop.prop_id)
			var centre := _inside(prop)
			room.press(centre)
			var first := prop.last_reaction
			prop.rest()
			room.press(centre)
			ok(prop.last_reaction != first or str(names[0]) == str(names[1]), "%s: the second poke is the second answer" % prop.prop_id)
			prop.rest()
		room.queue_free()

# A painting pixel that belongs to the prop and is the nearest one to its centre.
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
