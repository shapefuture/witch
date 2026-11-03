class_name FlashPresenter
extends Node

# The `flash` presentation step (GAME_SPEC section 4; BIBLE section 6): the raccoon's telesomatic link. For about two
# seconds a place's plate is seen through a soft, warped, slightly colour-shifted card hung in front of the camera. It
# draws no caption: a sensation is an image, not a sentence, so the step's `sensation` note is never shown. It has a
# sound cue from the painted-room sounds.

signal finished

const PLACES := "res://data/world/places"
const PAINTED := "res://assets/painted"
const SHADER := "res://render/psx/flash_card.gdshader"
const CARD_NAME := "FlashCard"
const SECONDS := 2.0
const FADE_IN := 0.35
const FADE_OUT := 0.45
const DEPTH := 1.0
const WARP := 0.025
const CUE := "chime"
const WASH := Color(0.62, 0.52, 0.95)

# Scene seconds per real second (tests shorten the step).
var time_scale := 1.0
# Returns the camera to hang the card on. Default: the viewport's current camera.
var camera_provider: Callable

static var _shader: Shader

var _card: MeshInstance3D
var _sfx: PaintedSfx
var _last_cue := ""

# Where the plate of `image` is: the painted room of the place of that name (its place file, when there is one), or the
# painted directory of the same name. "" when neither has a plate, and the card is then a flat stand-in.
static func plate_path(image: String, places_dir: String = PLACES) -> String:
	if image.is_empty():
		return ""
	var place_file := places_dir.path_join(image + ".json")
	if FileAccess.file_exists(place_file):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(place_file))
		if parsed is Dictionary:
			var room: Variant = (parsed as Dictionary).get("room", {})
			if room is Dictionary and str((room as Dictionary).get("kind", "")) == "painted":
				var dir := str((room as Dictionary).get("dir", ""))
				var candidate := dir.path_join("plate.png") if not dir.is_empty() else ""
				if not candidate.is_empty() and ResourceLoader.exists(candidate):
					return candidate
	var painted := PAINTED.path_join(image).path_join("plate.png")
	return painted if ResourceLoader.exists(painted) else ""

# The card's size in metres at `depth`, so it fills the picture (fov is the vertical field of view, as Camera3D uses it),
# with a margin for the warp at its edges.
static func card_size(fov_degrees: float, aspect: float, depth: float) -> Vector2:
	var height := 2.0 * depth * tan(deg_to_rad(fov_degrees) * 0.5) * 1.15
	return Vector2(height * aspect, height)

func play_entry(entry: Dictionary) -> void:
	var camera := _camera()
	if camera == null:
		return
	_card = _make_card(camera, str(entry.get("image", "")))
	_cue()
	var material := _card.material_override as ShaderMaterial
	var span := maxf(time_scale, 0.001)
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("strength", value), 0.0, 1.0, FADE_IN * span)
	tween.tween_interval((SECONDS - FADE_IN - FADE_OUT) * span)
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("strength", value), 1.0, 0.0, FADE_OUT * span)
	await tween.finished
	_remove_card()
	finished.emit()

# What the last flash's sound cue was ("" when none played).
func last_cue() -> String:
	return _last_cue

func card() -> MeshInstance3D:
	return _card

func _exit_tree() -> void:
	_remove_card()

func _camera() -> Camera3D:
	if camera_provider.is_valid():
		return camera_provider.call() as Camera3D
	return get_viewport().get_camera_3d() if is_inside_tree() else null

func _make_card(camera: Camera3D, image: String) -> MeshInstance3D:
	_remove_card()
	var viewport := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(480, 360)
	var quad := QuadMesh.new()
	quad.size = card_size(camera.fov, viewport.x / maxf(viewport.y, 1.0), DEPTH)
	var mesh := MeshInstance3D.new()
	mesh.name = CARD_NAME
	mesh.mesh = quad
	mesh.position = Vector3(0.0, 0.0, -DEPTH)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = _flash_shader()
	material.render_priority = 100
	material.set_shader_parameter("plate", _plate_texture(image))
	material.set_shader_parameter("strength", 0.0)
	material.set_shader_parameter("warp", 0.0 if PSXGlobals.reduced_effects() else WARP)
	mesh.material_override = material
	camera.add_child(mesh)
	return mesh

func _plate_texture(image: String) -> Texture2D:
	var path := FlashPresenter.plate_path(image)
	if not path.is_empty():
		var texture := load(path) as Texture2D
		if texture != null:
			return texture
	var stand_in := Image.create(4, 4, false, Image.FORMAT_RGB8)
	stand_in.fill(WASH * 0.7)
	return ImageTexture.create_from_image(stand_in)

func _cue() -> void:
	if _sfx == null:
		_sfx = PaintedSfx.new()
		_sfx.name = "Cue"
		add_child(_sfx)
	if PaintedSfx.exists(CUE) and _sfx.play(CUE):
		_last_cue = CUE

func _remove_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null

static func _flash_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER) as Shader
	return _shader
