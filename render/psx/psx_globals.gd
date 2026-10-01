class_name PSXGlobals
extends RefCounted

# Runtime control of the project shader globals (declared in project.godot):
#   precision_multiplier  vertex-snap coarseness (0.5 = chunky PSX; 1.0 = smooth)
#   magic_amount          how far reality has "broken" (0 = mundane, 1 = full magic)
#   snap_grid             the vertex-snap lattice, derived from the render size (half the pixels)
#   stage_time            the diorama's own clock, so wind, shimmer and captures are reproducible
#   lens_warp             the spell's fisheye swing (0..1)
#   fog_color, fog_density  the golden haze between you and the far hills
#
# The values are held here and PUSHED to the renderer; they are never read back from it
# (a headless run uses a dummy renderer that does not store global parameters).

const MUNDANE_PRECISION := 0.5
const MAGIC_PRECISION := 1.0
const FOG_COLOR := Color(0.50, 0.44, 0.28)
const FOG_DENSITY := 0.022

static var _magic := 0.0
static var _precision := MUNDANE_PRECISION
static var _lens := 0.0
static var _time := 0.0
static var _grid := Vector2(240, 180)

static func set_magic(amount: float) -> void:
	_magic = clampf(amount, 0.0, 1.0)
	# Geometry relaxes with the palette: less snapping means smoother, more continuous motion.
	_precision = lerpf(MUNDANE_PRECISION, MAGIC_PRECISION, _magic)
	RenderingServer.global_shader_parameter_set(&"magic_amount", _magic)
	RenderingServer.global_shader_parameter_set(&"precision_multiplier", _precision)

static func magic() -> float:
	return _magic

static func precision() -> float:
	return _precision

# One vertex-snap cell is about two render pixels, whatever the aspect.
static func set_render_size(size: Vector2) -> void:
	_grid = size * 0.5
	RenderingServer.global_shader_parameter_set(&"snap_grid", _grid)

static func snap_grid() -> Vector2:
	return _grid

static func set_time(seconds: float) -> void:
	_time = seconds
	RenderingServer.global_shader_parameter_set(&"stage_time", seconds)

static func time() -> float:
	return _time

static func set_lens(amount: float) -> void:
	_lens = clampf(amount, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set(&"lens_warp", _lens)

static func lens() -> float:
	return _lens

static func set_fog(color: Color, density: float) -> void:
	RenderingServer.global_shader_parameter_set(&"fog_color", color)
	RenderingServer.global_shader_parameter_set(&"fog_density", density)

static func reset() -> void:
	set_magic(0.0)
	set_lens(0.0)
	set_time(0.0)
	set_fog(FOG_COLOR, FOG_DENSITY)
