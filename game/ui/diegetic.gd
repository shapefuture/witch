class_name Diegetic
extends RefCounted

# Helpers for UI that lives IN the 3D scene. A diegetic element is built in "pixel units"
# (see SlabMesh) and placed by projecting a screen position into the world at a fixed depth in
# front of the camera, scaled so that one unit is exactly one render pixel. So it is real scene
# geometry (shaded by the PSX pipeline, hung off the camera's pose, rolled with the Dutch angle)
# yet its type stays pixel-crisp and the same physical size on every device.

const DEPTH := 2.5

static func metres_per_pixel(camera: Camera3D, viewport_height: float, depth: float = DEPTH) -> float:
	return 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / maxf(viewport_height, 1.0)

# Transform that puts a node's local origin (the top-left of its rectangle) at `screen_px`, growing
# by `grow` about `pivot` (local pixel coordinates).
static func transform_for(camera: Camera3D, viewport_size: Vector2, screen_px: Vector2, grow: float = 1.0, pivot: Vector2 = Vector2.ZERO) -> Transform3D:
	var unit := metres_per_pixel(camera, viewport_size.y)
	var cam_basis := camera.global_transform.basis.orthonormalized()
	var origin := camera.project_position(screen_px.round(), DEPTH)
	origin += cam_basis * Vector3(pivot.x, pivot.y, 0.0) * unit * (1.0 - grow)
	return Transform3D(cam_basis * Basis.from_scale(Vector3.ONE * unit * grow), origin)

# The part of the picture that is safe to draw UI in: inside notches and rounded corners, and
# away from the screen edge a thumb rests on. In viewport pixels.
static func safe_rect(viewport_size: Vector2) -> Rect2:
	var rect := Rect2(Vector2(6, 6), viewport_size - Vector2(12, 12))
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.x > 0.0 and screen.y > 0.0 and safe.size.x > 0.0 and safe.size.y > 0.0:
		var scale := Vector2(viewport_size.x / screen.x, viewport_size.y / screen.y)
		var from_safe := Rect2(safe.position * scale + Vector2(6, 6), safe.size * scale - Vector2(12, 12))
		rect = rect.intersection(from_safe) if rect.intersects(from_safe) else rect
	return rect

static func mesh_instance(mesh: Mesh, material: Material, z: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position.z = z
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-2000, -2000, -50), Vector3(4000, 4000, 100))
	return instance

# `tile` is a painted tile name ("scroll", "wood", "brass") or "" for a flat tint.
static func slab_material(tint: Color, tile: String, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://render/psx/ui_slab.gdshader")
	material.set_shader_parameter("tint", tint)
	var texture: Texture2D = PSXMaterials.tile_texture(tile) if not tile.is_empty() else null
	material.set_shader_parameter("use_tex", 1.0 if texture != null else 0.0)
	if texture != null:
		material.set_shader_parameter("tex", texture)
	material.render_priority = priority
	return material

static func label(text: String, color: Color, priority: int) -> Label3D:
	var node := Label3D.new()
	node.font = UIKit.font()
	node.font_size = UIKit.FONT_SIZE
	node.pixel_size = 1.0
	node.text = text
	node.modulate = color
	node.outline_size = 0
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	node.shaded = false
	node.double_sided = true
	node.no_depth_test = true
	node.fixed_size = false
	node.render_priority = priority
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return node
