class_name PaintedActorShadow
extends Node3D

# A character's cast shadow in a painted room: a small viewport sees only this character, from the beam
# (orthographic, along sun_dir), and a quad on the floor turns that silhouette into a soft shadow
# (painted_actor_shadow.gdshader). It follows the character and every pose; the contact patch at the feet is part of it.

const SHADER := preload("res://game/world/painted/painted_actor_shadow.gdshader")
const RESOLUTION := 128
const LOOK_HEIGHT := 0.6     # the beam's camera aims this far above the feet (about the middle of a character)

var actor: Node3D
var viewport: SubViewport
var camera: Camera3D
var floor_quad: MeshInstance3D
var material: ShaderMaterial
var _sun := Vector3.UP
var _size := 2.0
var _strength := 1.0

# `layer` (1..20) is this character's own render layer: its meshes join it, and only it is drawn by the beam's camera.
func setup(target: Node3D, layer: int, size: float, sun: Vector3, contact_radius: float) -> void:
	actor = target
	_sun = sun.normalized()
	_size = size
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers |= 1 << (layer - 1)
	viewport = SubViewport.new()
	viewport.name = "Beam"
	viewport.size = Vector2i(RESOLUTION, RESOLUTION)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = size
	camera.near = 0.05
	camera.far = 30.0
	camera.cull_mask = 1 << (layer - 1)
	viewport.add_child(camera)
	camera.current = true
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("silhouette", viewport.get_texture())
	material.set_shader_parameter("look_size", size)
	material.set_shader_parameter("contact_radius", contact_radius)
	material.set_shader_parameter("contact_offset", -Vector3(_sun.x, 0.0, _sun.z).normalized() * contact_radius * 0.35)
	var quad := QuadMesh.new()
	# the camera's square, laid on the floor along the beam: as wide, and longer by 1 / sun.y
	quad.size = Vector2(size, size / maxf(_sun.y, 0.2))
	floor_quad = MeshInstance3D.new()
	floor_quad.name = "Floor"
	floor_quad.mesh = quad
	floor_quad.material_override = material
	floor_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_quad.top_level = true
	add_child(floor_quad)
	follow()

func set_light(light_map: Texture2D, rect: Array, lit: Array, strength: float) -> void:
	material.set_shader_parameter("light_map", light_map)
	material.set_shader_parameter("light_rect", Vector4(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
	material.set_shader_parameter("lit_range", Vector2(float(lit[0]), float(lit[1])))
	material.set_shader_parameter("strength", strength)
	_strength = strength
	follow()

# The colour the floor goes to in full shadow (a room's cool fill, instead of the default violet).
func set_tint(color: Color) -> void:
	material.set_shader_parameter("tint", color)

func _process(_delta: float) -> void:
	follow()

func follow() -> void:
	if actor == null or not actor.is_inside_tree():
		return
	# a hidden character casts nothing (and its camera rests)
	var on := _strength > 0.0 and actor.is_visible_in_tree()
	visible = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var feet := actor.global_position
	var look := feet + Vector3(0.0, LOOK_HEIGHT, 0.0)
	var up_hint := Vector3.UP if absf(_sun.y) < 0.98 else Vector3.FORWARD
	camera.look_at_from_position(look + _sun * 10.0, look, up_hint)
	var along := Vector3(_sun.x, 0.0, _sun.z)
	var centre := look - along / maxf(_sun.y, 0.2) * LOOK_HEIGHT
	centre.y = feet.y + 0.01
	# flat on the floor (the quad's +Y is turned to the beam's horizontal direction)
	var basis := Basis(Vector3.UP, atan2(along.x, along.z)) * Basis(Vector3.RIGHT, -PI * 0.5)
	floor_quad.global_transform = Transform3D(basis, centre)
	material.set_shader_parameter("look_point", look)
	material.set_shader_parameter("look_right", camera.global_basis.x)
	material.set_shader_parameter("look_up", camera.global_basis.y)
	material.set_shader_parameter("feet", feet)
