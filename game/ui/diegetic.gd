class_name Diegetic
extends RefCounted

# Helpers for UI that lives IN the 3D scene. A diegetic element is built in "pixel units"
# (see SlabMesh) and placed by projecting a screen position into the world at a fixed depth in
# front of the camera, scaled so that one unit is exactly one render pixel. So it is real scene
# geometry (shaded by the PSX pipeline, hung off the camera's pose, rolled with the Dutch angle)
# yet its type stays pixel-crisp and the same physical size on every device.

const DEPTH := 2.5
# UI is laid out in the pixels of a 360-row picture (the size it was designed and touch-tested at);
# the render is taller (540 rows), so one UI pixel is ui_scale() render pixels. Callers lay out in UI
# pixels and give rectangles to the outside world (taps, tests) in viewport pixels.
const UI_ROWS := 360.0

static func ui_scale(viewport_size: Vector2) -> float:
	return maxf(viewport_size.y, 1.0) / UI_ROWS

static func ui_size(viewport_size: Vector2) -> Vector2:
	return viewport_size / ui_scale(viewport_size)

static func metres_per_pixel(camera: Camera3D, viewport_height: float, depth: float = DEPTH) -> float:
	return 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5) / maxf(viewport_height, 1.0)

# Transform that puts a node's local origin (the top-left of its rectangle) at `screen_px` (UI pixels),
# growing by `grow` about `pivot` (local UI pixels). `viewport_size` is the real one.
# `upright`: keep the slab's "up" on the WORLD's up while it still faces the camera, so a rolled camera
# (the Dutch tilt, the spell's 45 degrees) tips speech and plaques with the world instead of leaving
# them as a flat overlay. Menus use the camera's own axes.
static func transform_for(camera: Camera3D, viewport_size: Vector2, screen_px: Vector2, grow: float = 1.0, pivot: Vector2 = Vector2.ZERO, upright: bool = false) -> Transform3D:
	var scale := ui_scale(viewport_size)
	var unit := metres_per_pixel(camera, viewport_size.y) * scale
	var cam_basis := camera.global_transform.basis.orthonormalized()
	if upright:
		var back := cam_basis.z
		var right := Vector3.UP.cross(back)
		if right.length() > 0.001:
			right = right.normalized()
			cam_basis = Basis(right, back.cross(right).normalized(), back)
	var origin := camera.project_position((screen_px * scale).round(), DEPTH)
	origin += cam_basis * Vector3(pivot.x, pivot.y, 0.0) * unit * (1.0 - grow)
	return Transform3D(cam_basis * Basis.from_scale(Vector3.ONE * unit * grow), origin)

# The part of the picture that is safe to draw UI in: inside notches and rounded corners, and
# away from the screen edge a thumb rests on. In the pixels of `viewport_size` (pass ui_size()).
static func safe_rect(viewport_size: Vector2) -> Rect2:
	# phones round their corners and hide a notch even when they report no insets: stay clear of the sides
	var side := maxf(26.0, viewport_size.x * 0.045)
	var rect := Rect2(Vector2(side, 12), viewport_size - Vector2(side * 2.0, 12 + 24))
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.x > 0.0 and screen.y > 0.0 and safe.size.x > 0.0 and safe.size.y > 0.0:
		var scale := Vector2(viewport_size.x / screen.x, viewport_size.y / screen.y)
		var from_safe := Rect2(safe.position * scale + Vector2(side, 12), safe.size * scale - Vector2(side * 2.0, 12 + 24))
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

# `scale` = ui_scale(): the glyphs are rasterised at the real pixel size, then drawn UIKit.FONT_SIZE
# UI pixels tall, so text stays crisp at 540 rows and keeps its physical size.
static func label(text: String, color: Color, priority: int, scale: float = 1.0) -> Label3D:
	var node := Label3D.new()
	node.font = UIKit.font()
	node.font_size = roundi(UIKit.FONT_SIZE * scale)
	node.pixel_size = float(UIKit.FONT_SIZE) / float(node.font_size)
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
