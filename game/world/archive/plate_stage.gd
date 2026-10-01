class_name PlateStage
extends Node3D

# Draws the archive hall: the proxy geometry (assets/archive/hall_proxy.glb) wearing the pre-rendered
# plates (PlateSet) through render/psx/plate_projection. Every frame it looks at the active camera and
# gives the shader its three plates: the shot's own (exact when the camera sits at that plate's pose),
# `wide`, and the best cover.
#
# The room can AGE: plates may come in variants ("dusk"). crossfade_to() fades a second, transparent
# copy of the proxy wearing the variant over the first, then swaps. Plates that lack the variant are
# regraded at runtime instead (VARIANT_GRADES: less sun, a tint). Presentation only: Mirror never hears of it.

const PROXY_PATH := "res://assets/archive/hall_proxy.glb"
const SHADER := "res://render/psx/plate_projection.gdshader"
const FADE_SHADER := "res://render/psx/plate_projection_fade.gdshader"
const CROSSFADE_SECONDS := 2.0
# variant -> Vector4(sun scale, tint r, g, b) for plates rendered without it
const VARIANT_GRADES := {"dusk": Vector4(0.25, 0.9, 0.8, 0.97)}

signal variant_changed(variant: String)

var plates: PlateSet
var proxy: MeshInstance3D
var overlay: MeshInstance3D
var material: ShaderMaterial
var fade_material: ShaderMaterial
var variant := ""
var sun := 1.0
var _fade_to := ""
var _fade_t := -1.0
var _fade_seconds := CROSSFADE_SECONDS
var _assigned: Array[String] = ["", "", ""]
var _assigned_fade: Array[String] = ["", "", ""]

func _ready() -> void:
	name = "PlateStage"
	plates = PlateSet.shared(PlateSet.is_mobile_platform())
	for error in plates.errors:
		push_warning("PlateStage: " + error)
	material = _make_material(SHADER)
	fade_material = _make_material(FADE_SHADER)
	fade_material.render_priority = -100   # under the dust, shadows and speech: it is the set
	var mesh := load_proxy_mesh()
	if mesh == null:
		push_warning("PlateStage: %s missing; run tools/plates_stub/make_stub.py or the plate build" % PROXY_PATH)
		return
	proxy = _instance(mesh, material, "Proxy")
	overlay = _instance(mesh, fade_material, "VariantFade")
	overlay.visible = false
	_update()

static func load_proxy_mesh() -> Mesh:
	if not ResourceLoader.exists(PROXY_PATH):
		return null
	var scene := (load(PROXY_PATH) as PackedScene).instantiate()
	var found := _first_mesh(scene)
	var mesh: Mesh = found.mesh if found != null else null
	scene.free()
	return mesh

static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null

func _instance(mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _make_material(path: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	return mat

func _process(delta: float) -> void:
	if _fade_t >= 0.0:
		_fade_t += delta
		var t := clampf(_fade_t / maxf(_fade_seconds, 0.01), 0.0, 1.0)
		fade_material.set_shader_parameter("fade", t * t * (3.0 - 2.0 * t))
		if t >= 1.0:
			_finish_fade()
	_update()

# ---- variants ----------------------------------------------------------------------------------------

# Ages (or rejuvenates) the room to `to_variant` ("" = the plates as first rendered) over `seconds`.
func crossfade_to(to_variant: String, seconds: float = CROSSFADE_SECONDS) -> void:
	if to_variant == variant and _fade_t < 0.0:
		return
	if proxy == null or seconds <= 0.0:
		set_variant(to_variant)
		return
	_fade_to = to_variant
	_fade_seconds = seconds
	_fade_t = 0.0
	_assigned_fade = ["", "", ""]
	fade_material.set_shader_parameter("fade", 0.0)
	overlay.visible = true
	_update()
	await variant_changed

func set_variant(to_variant: String) -> void:
	_fade_to = to_variant
	_finish_fade()

func is_fading() -> bool:
	return _fade_t >= 0.0

func _finish_fade() -> void:
	variant = _fade_to
	_fade_t = -1.0
	_assigned = ["", "", ""]
	if overlay != null:
		overlay.visible = false
	_update()
	variant_changed.emit(variant)

func set_sun(amount: float) -> void:
	sun = amount
	material.set_shader_parameter("sun", sun)
	fade_material.set_shader_parameter("sun", sun)

# ---- per frame -----------------------------------------------------------------------------------------

func _update() -> void:
	if proxy == null or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var chosen := plates.choose(camera.global_transform)
	var height := get_viewport().get_visible_rect().size.y
	var texels := height / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	_apply(material, chosen, variant, _assigned, texels)
	if overlay.visible:
		_apply(fade_material, chosen, _fade_to, _assigned_fade, texels)

func _apply(mat: ShaderMaterial, chosen: Array[Dictionary], with_variant: String, assigned: Array[String], texels: float) -> void:
	mat.set_shader_parameter("screen_texels", texels)
	for slot in range(3):
		var suffix := "_%d" % slot
		if slot >= chosen.size():
			mat.set_shader_parameter("eye" + suffix, Vector4.ZERO)
			assigned[slot] = ""
			continue
		var plate: Dictionary = chosen[slot]["plate"]
		var xf: Transform3D = plate["transform"]
		var tv := PlateSet.tan_half_v(plate)
		var size: Vector2i = plate["size"]
		var own := plates.has_variant(plate, with_variant)
		var signature := "%s|%s" % [plate["id"], with_variant if own else ""]
		if assigned[slot] != signature:
			var files := plates.textures(plate, with_variant)
			mat.set_shader_parameter("beauty" + suffix, files.get("beauty"))
			mat.set_shader_parameter("depth" + suffix, files.get("depth"))
			mat.set_shader_parameter("key" + suffix, files.get("key"))
			mat.set_shader_parameter("glow" + suffix, files.get("glow"))
			mat.set_shader_parameter("view" + suffix, Projection(xf.affine_inverse()))
			mat.set_shader_parameter("lens" + suffix, Vector4(tv * PlateSet.aspect(plate), tv, float(plate["near"]), float(plate["far"])))
			var grade: Vector4 = Vector4.ONE if own else VARIANT_GRADES.get(with_variant, Vector4.ONE)
			mat.set_shader_parameter("grade" + suffix, grade)
			assigned[slot] = signature
		mat.set_shader_parameter("eye" + suffix, Vector4(xf.origin.x, xf.origin.y, xf.origin.z, 1.0))
		mat.set_shader_parameter("info" + suffix, Vector2(1.0 if chosen[slot]["exact"] else 0.0, size.y / (2.0 * tv)))

# The sun's share of the light at a world point, as the room looks now (actors' sun shadows).
func key_at(world: Vector3) -> float:
	if plates == null:
		return 0.0
	var plate := plates.wide()
	var amount := plates.key_at(world, variant if plates.has_variant(plate, variant) else "")
	if not plates.has_variant(plate, variant):
		amount *= (VARIANT_GRADES.get(variant, Vector4.ONE) as Vector4).x
	return amount * sun
