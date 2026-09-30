extends TestCase

func test_imported_style_materials_are_converted_to_psx_actor_shading() -> void:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var standard := StandardMaterial3D.new()
	standard.albedo_color = Color(0.2, 0.4, 0.6)
	mesh.material_override = standard
	root.add_child(mesh)
	eq(PSXActorPresenter.apply(root), 1, "one surface converted")
	var converted := mesh.material_override as ShaderMaterial
	ok(converted != null, "now a ShaderMaterial")
	eq(converted.get_shader_parameter("modulate_color"), Color(0.2, 0.4, 0.6), "colour preserved")
	eq(PSXActorPresenter.apply(root), 0, "idempotent: already PSX, nothing to convert")
	root.free()

func test_focus_outline_is_added_and_removed_without_touching_the_base_material() -> void:
	var root := Placeholders.tomas()
	ok(not FocusOutline.is_focused(root), "starts unfocused")
	FocusOutline.set_focus(root, true)
	ok(FocusOutline.is_focused(root), "outlined when pointed at")
	FocusOutline.set_focus(root, false)
	ok(not FocusOutline.is_focused(root), "outline removed")
	root.free()

func test_placeholders_expose_the_named_parts_animation_code_drives() -> void:
	var witch := Placeholders.witch()
	for part in ["Body", "Head", "Hat", "ArmR", "RaccoonLink"]:
		ok(witch.get_node_or_null(part) != null, "witch has %s" % part)
	ok(witch.get_node_or_null("ArmR/Wand") != null, "with a wand")
	var tomas := Placeholders.tomas()
	for part in ["Body", "Head", "ArmL", "ArmR", "Scarf"]:
		ok(tomas.get_node_or_null(part) != null, "tomas has %s" % part)
	var machine := Placeholders.machine()
	for part in ["Base", "BigGear", "SmallGear", "Cam", "Indicator"]:
		ok(machine.get_node_or_null(part) != null, "machine has %s" % part)
	witch.free()
	tomas.free()
	machine.free()

func test_the_presentation_director_plays_entries_in_order_and_reports_unknown_kinds() -> void:
	var order: Array[String] = []
	var director := PresentationDirector.new()
	director.register("line", func(entry: Dictionary) -> void: order.append("line:" + entry["key"]))
	director.register("camera", func(entry: Dictionary) -> void: order.append("camera:" + entry["mode"]))
	await director.play([{"kind": "camera", "mode": "wide"}, {"kind": "line", "key": "a"}, {"kind": "typo_kind"}, {"kind": "line", "key": "b"}])
	eq(order, ["camera:wide", "line:a", "line:b"], "strictly in order")
	eq(director.unhandled, ["typo_kind"], "an unhandled kind is recorded so content typos are found")

func test_the_presentation_director_awaits_each_handler_before_the_next() -> void:
	var log: Array[String] = []
	var gate := GateEmitter.new()
	var director := PresentationDirector.new()
	director.register("slow", func(_entry: Dictionary) -> void:
		log.append("slow-start")
		await gate.opened
		log.append("slow-end"))
	director.register("fast", func(_entry: Dictionary) -> void: log.append("fast"))
	director.play([{"kind": "slow"}, {"kind": "fast"}])
	eq(log, ["slow-start"], "fast has not run while slow is still playing")
	gate.opened.emit()
	eq(log, ["slow-start", "slow-end", "fast"], "then it continues")
	ok(true, "done")

class GateEmitter:
	extends RefCounted
	signal opened
