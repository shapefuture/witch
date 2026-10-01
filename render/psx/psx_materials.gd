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
const SET := "res://render/psx/psx_set.gdshader"
const TEXTURE_DIR := "res://assets/archive/textures/"
# Painted materials that glow by themselves (windows, lamps, the machine's indicator).
const GLOWING := {"glow": Color(1.0, 0.86, 0.5), "glow_warm": Color(1.0, 0.6, 0.26), "glow_green": Color(0.5, 1.0, 0.4), "glow_blue": Color(0.4, 0.65, 1.0), "glow_white": Color(0.78, 0.72, 0.56)}
const SET_SWAY := 0.16
# Flat ground that the carpet is laid on: snapped vertices would shear the two apart into shards.
const UNSNAPPED := ["floor", "carpet_purple", "carpet_gold", "carpet_dark"]
# Surfaces that should look lit even where the bake left them dim: metal and glass catch light.
# Exposure of the baked set (matches the shader default). The reference is a low-key picture: the
# sunlit floor tops out around 0.65 luma, so the pool is felt, not blown out.
const SET_GAIN := 1.05
const SHINY := {"brass": 1.25, "gold": 1.3, "crystal": 1.1, "crystal_grey": 1.2, "iron": 1.1, "coral": 1.1}
# Painted sheets cut out by their alpha (ink on the wall, not a poster).
const CUTOUT := ["mural_eye"]

static var _shaders: Dictionary = {}
static var _set_materials: Dictionary = {}
static var _tiles: Dictionary = {}

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
	StageLight.apply(material)
	return material

# A baked-set material by its painted-tile name ("grass_a", "bark", "glow_warm" ...). Shared.
static func set_material(tile: String) -> ShaderMaterial:
	if _set_materials.has(tile):
		return _set_materials[tile]
	var material := ShaderMaterial.new()
	material.shader = shader(SET)
	if GLOWING.has(tile):
		material.set_shader_parameter("glow", 1.0)
		material.set_shader_parameter("tint", GLOWING[tile])
		material.set_shader_parameter("sway", 0.0)
		material.set_shader_parameter("fog_amount", 0.5)
	else:
		material.set_shader_parameter("sway", SET_SWAY)
		if tile in UNSNAPPED:
			material.set_shader_parameter("snap_amount", 0.0)
		if tile in CUTOUT:
			material.set_shader_parameter("cutout", 1.0)
			material.set_shader_parameter("rim", 0.0)
		if SHINY.has(tile):
			material.set_shader_parameter("gain", SET_GAIN * float(SHINY[tile]) / 1.5)
	material.set_shader_parameter("albedo_tex", tile_texture(tile))
	_set_materials[tile] = material
	return material

# Textures are nearest-filtered for the chunky look, but with a mip chain so the busy painted
# noise does not crawl on far surfaces. Built from the imported image at first use.
static func tile_texture(tile: String) -> Texture2D:
	if _tiles.has(tile):
		return _tiles[tile]
	var path := TEXTURE_DIR + tile + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var source := load(path) as Texture2D
		var image := source.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		image.generate_mipmaps()
		texture = ImageTexture.create_from_image(image)
	_tiles[tile] = texture
	return texture

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
