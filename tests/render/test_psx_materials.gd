extends TestCase

func test_materials_carry_their_colour_and_share_shaders() -> void:
	var a := PSXMaterials.lit(Palette.BRASS)
	var b := PSXMaterials.lit(Palette.STONE)
	ok(a.shader == b.shader, "one shared shader")
	ok(a != b, "separate materials so each object keeps its own colour")
	eq(a.get_shader_parameter("modulate_color"), Palette.BRASS, "colour set")
	eq(PSXMaterials.actor(Palette.COAT, 0.01).get_shader_parameter("wobble_amount"), 0.01, "actor wobble")

func test_every_psx_shader_path_loads() -> void:
	for path in [PSXMaterials.LIT, PSXMaterials.ACTOR, PSXMaterials.UNLIT, PSXMaterials.OUTLINE, PSXMaterials.MAGIC, PSXMaterials.SCREEN]:
		ok(load(path) is Shader, "%s loads as a Shader" % path)
	ok(load(PSXMaterials.DITHER) is Texture2D, "dither texture")

func test_magic_relaxes_snapping_and_expands_the_palette_then_resets() -> void:
	PSXGlobals.reset()
	eq(PSXGlobals.magic(), 0.0, "mundane")
	eq(PSXGlobals.precision(), PSXGlobals.MUNDANE_PRECISION, "chunky snapping")
	PSXGlobals.set_magic(1.0)
	eq(PSXGlobals.magic(), 1.0, "full magic")
	eq(PSXGlobals.precision(), PSXGlobals.MAGIC_PRECISION, "geometry relaxes with the palette")
	PSXGlobals.set_magic(9.0)
	eq(PSXGlobals.magic(), 1.0, "clamped")
	PSXGlobals.reset()
	eq(PSXGlobals.precision(), PSXGlobals.MUNDANE_PRECISION, "back to mundane")
