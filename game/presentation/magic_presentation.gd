class_name MagicPresentation
extends Node

# Magic must be SEEN to break the rules. The mundane world is coarse: chunky vertex snap, a
# small banded palette, mechanical motion. While a spell plays, the screen grade expands the
# palette and relaxes the dither, geometry stops snapping, and light that comes from nowhere
# rises through the target. The player can tell reality became less constrained.
#
# The step's `mode` names one of three looks (GAME_SPEC section 4; BIBLE section 8). "violet" (the default, "I make") is
# the breaking above. "verdigris" ("I enable") is a ring of copper-green light that opens and holds still under the
# target: it frames what is there and changes nothing, so the palette, the lens and the world stay as they are. "gold"
# ("I encounter") is a warm glow at her face and nothing else moves. `effect: "fizzle"` is a misfire (act II): a small
# sputter of violet that clearly fails, and never a mess.
#
# Photosafe: a look flashes at most three times a second. A flash is one dip in brightness and its return; the fizzle's
# sputters are spaced so there are two a second at most, and the other looks only rise, hold and fall.

signal peaked(effect: String)
signal finished(effect: String)
# Each sputter of a fizzle, as it starts (0, 1, 2). Emitted by the tween, so a count does not depend on frame timing.
signal sputtered(index: int)

const EFFECTS := {
	"repair": {"rise": 0.7, "hold": 1.5, "fall": 1.2, "tint": Palette.MAGIC_GOLD, "peak": 1.0},
	"flourish": {"rise": 0.9, "hold": 2.6, "fall": 1.6, "tint": Palette.MAGIC_ROSE, "peak": 1.0},
}
const FIZZLE := "fizzle"
const MODES := ["violet", "verdigris", "gold"]
const VERDIGRIS := Color(0.36, 0.78, 0.66)
const GOLD := Color(1.0, 0.84, 0.5)
const FIZZLE_TINT := Color(0.72, 0.5, 1.0)
# When each sputter starts (seconds into the fizzle). Half a second apart: two a second at most.
const FIZZLE_BEATS := [0.3, 0.8, 1.3]
const FIZZLE_DIP := 0.1

# Multiplies every duration (tests and capture mode use a small value).
var time_scale := 1.0

func play(effect: String, at: Vector3, mode: String = "violet") -> void:
	if effect != FIZZLE and not EFFECTS.has(effect):
		push_warning("MagicPresentation: unknown effect '%s'" % effect)
		return
	var look := mode
	if not look in MODES:
		push_warning("MagicPresentation: unknown mode '%s', played as violet" % mode)
		look = "violet"
	if effect == FIZZLE:
		await _fizzle(at)
	elif look == "verdigris":
		await _ring(effect, at)
	elif look == "gold":
		await _glow(effect, at)
	else:
		await _break(effect, at)

# The fastest any look flashes, in flashes a second (see the photosafe note above).
static func max_flicker_hz() -> float:
	var gap := 1.0e9
	for i in range(1, FIZZLE_BEATS.size()):
		gap = minf(gap, float(FIZZLE_BEATS[i]) - float(FIZZLE_BEATS[i - 1]))
	return 1.0 / gap

func _span() -> float:
	return maxf(time_scale, 0.001)

# The violet look: the world breaks (palette, geometry and lens), then settles.
func _break(effect: String, at: Vector3) -> void:
	var spec: Dictionary = EFFECTS[effect]
	var span := _span()
	var column := _column(spec["tint"], at)
	var tween := create_tween()
	tween.tween_method(_set_magic, 0.0, float(spec["peak"]), float(spec["rise"]) * span)
	# the lens swings out to a fisheye as the spell rises (the camera tilts with it: see the
	# director's magic_reveal shot) and everything snaps back at once when it ends
	tween.parallel().tween_method(PSXGlobals.set_lens, 0.0, 1.0, float(spec["rise"]) * span)
	tween.parallel().tween_property(column, "scale", Vector3(1.0, 1.0, 1.0), float(spec["rise"]) * span).from(Vector3(0.2, 0.01, 0.2))
	tween.tween_callback(func() -> void: peaked.emit(effect))
	tween.tween_interval(float(spec["hold"]) * span)
	tween.tween_method(_set_magic, float(spec["peak"]), 0.0, float(spec["fall"]) * span)
	await tween.finished
	column.queue_free()
	PSXGlobals.reset()
	finished.emit(effect)

# The verdigris look: a ring of copper-green light opens under the target and holds still. It frames; it changes nothing.
func _ring(effect: String, at: Vector3) -> void:
	var span := _span()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	var ring := MeshInstance3D.new()
	ring.name = "VerdigrisRing"
	ring.mesh = torus
	var material := _unlit(VERDIGRIS)
	ring.material_override = material
	ring.position = at + Vector3(0.0, 0.05, 0.0)
	ring.scale = Vector3(0.2, 1.0, 0.2)
	_add(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3(1.2, 1.0, 1.2), 0.8 * span).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: peaked.emit(effect))
	tween.tween_interval(1.4 * span)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.6 * span)
	await tween.finished
	ring.queue_free()
	finished.emit(effect)

# The gold look: a warm glow at her face (a soft disc that always faces the camera), up and down once. Nothing else moves.
func _glow(effect: String, at: Vector3) -> void:
	var span := _span()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var halo := MeshInstance3D.new()
	halo.name = "GoldHalo"
	halo.mesh = quad
	var material := _halo_material()
	halo.material_override = material
	halo.position = at + Vector3(0.0, 1.6, 0.0)
	_add(halo)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.55, 0.9 * span)
	tween.tween_callback(func() -> void: peaked.emit(effect))
	tween.tween_interval(1.0 * span)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.9 * span)
	await tween.finished
	halo.queue_free()
	finished.emit(effect)

# The fizzle: a small violet ball puffs up, sputters three times (each a dip and a return), then goes out, shedding sparks.
func _fizzle(at: Vector3) -> void:
	var span := _span()
	var core := _sphere(0.16, FIZZLE_TINT, at + Vector3(0.0, 1.0, 0.0))
	core.name = "FizzleCore"
	core.scale = Vector3.ONE * 0.2
	var sparks: Array[MeshInstance3D] = []
	var spread := create_tween().set_parallel(true)
	for k in range(6):
		var angle := TAU * float(k) / 6.0
		var spark := _sphere(0.035, FIZZLE_TINT, core.position)
		sparks.append(spark)
		var away := Vector3(cos(angle), 0.0, sin(angle)) * 0.45 + Vector3(0.0, -0.8, 0.0)
		spread.tween_property(spark, "position", core.position + away, 1.2 * span).set_delay(0.3 * span)
		spread.tween_property(spark.material_override, "albedo_color:a", 0.0, 1.2 * span).set_delay(0.3 * span)
	var tween := create_tween()
	tween.tween_property(core, "scale", Vector3.ONE, 0.25 * span)
	var cursor := 0.25
	for index in FIZZLE_BEATS.size():
		var beat := float(FIZZLE_BEATS[index])
		tween.tween_interval((beat - cursor) * span)
		tween.tween_callback(func() -> void: sputtered.emit(index))
		tween.tween_property(core, "scale", Vector3.ONE * 0.35, FIZZLE_DIP * span)
		tween.tween_property(core, "scale", Vector3.ONE, FIZZLE_DIP * span)
		cursor = beat + 2.0 * FIZZLE_DIP
	tween.tween_callback(func() -> void: peaked.emit(FIZZLE))
	tween.tween_property(core, "scale", Vector3.ONE * 0.05, 0.4 * span)
	await tween.finished
	core.queue_free()
	for spark in sparks:
		spark.queue_free()
	finished.emit(FIZZLE)

func _set_magic(amount: float) -> void:
	PSXGlobals.set_magic(amount)

# A column of light: smooth, unlit, no vertex snapping, colour outside the world's palette.
func _column(tint: Color, at: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.15
	mesh.bottom_radius = 0.9
	mesh.height = 5.0
	mesh.radial_segments = 24
	mesh.rings = 1
	var column := MeshInstance3D.new()
	column.name = "MagicColumn"
	column.mesh = mesh
	column.material_override = PSXMaterials.magic(tint, 1.3)
	column.position = at + Vector3(0, 2.5, 0)
	_add(column)
	return column

func _sphere(radius: float, tint: Color, at: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _unlit(tint)
	node.position = at
	_add(node)
	return node

# Unlit, additive, no vertex snapping: light that comes from nowhere, outside the world's palette.
func _unlit(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	return material

# A soft radial disc, gold at its middle and clear at its edge, turned to face the camera.
func _halo_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var material := _unlit(Color(GOLD.r, GOLD.g, GOLD.b, 0.0))
	material.albedo_texture = texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material

func _add(node: Node3D) -> void:
	if get_tree().current_scene != null:
		get_tree().current_scene.add_child(node)
	else:
		get_parent().add_child(node)
