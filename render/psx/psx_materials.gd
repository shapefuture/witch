class_name PSXMaterials
extends RefCounted

# Factory for the project's PSX materials. Shaders are loaded once and shared; every call
# returns a fresh ShaderMaterial so each object can carry its own colour.

const LIT := "res://render/psx/psx_lit.gdshader"
const ACTOR := "res://render/psx/psx_lit_actor.gdshader"
const UNLIT := "res://render/psx/psx_unlit.gdshader"
const OUTLINE := "res://render/psx/focus_outline.gdshader"
const MAGIC := "res://render/psx/magic_break.gdshader"
const SCREEN := "res://render/psx/psx_screen.gdshader"
const DITHER := "res://render/psx/psxdither.png"

static var _shaders: Dictionary = {}

static func shader(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path)
	return _shaders[path]

static func lit(color: Color) -> ShaderMaterial:
	return _colored(LIT, color)

static func unlit(color: Color) -> ShaderMaterial:
	return _colored(UNLIT, color)

# Lit with the per-vertex wobble that makes characters feel hand-animated (PSX GTE jitter).
static func actor(color: Color, wobble: float = 0.004) -> ShaderMaterial:
	var material := _colored(ACTOR, color)
	material.set_shader_parameter("wobble_amount", wobble)
	return material

static func outline(width: float = 0.03) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader(OUTLINE)
	material.set_shader_parameter("outline_width", width)
	return material

static func magic(tint: Color = Palette.MAGIC_GOLD, intensity: float = 1.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader(MAGIC)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("intensity", intensity)
	return material

static func screen() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader(SCREEN)
	material.set_shader_parameter("dither_tex", load(DITHER))
	return material

static func _colored(path: String, color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader(path)
	material.set_shader_parameter("modulate_color", color)
	return material
