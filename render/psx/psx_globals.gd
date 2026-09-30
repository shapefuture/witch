class_name PSXGlobals
extends RefCounted

# Runtime control of the two project shader globals (declared in project.godot):
#   precision_multiplier  vertex-snap coarseness (0.5 = chunky PSX; 1.0 = smooth)
#   magic_amount          how far reality has "broken" (0 = mundane, 1 = full magic)
#
# The values are held here and PUSHED to the renderer; they are never read back from it
# (a headless run uses a dummy renderer that does not store global parameters).

const MUNDANE_PRECISION := 0.5
const MAGIC_PRECISION := 1.0

static var _magic := 0.0
static var _precision := MUNDANE_PRECISION

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

static func reset() -> void:
	set_magic(0.0)
