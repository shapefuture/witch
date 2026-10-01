"""Cycles materials for the plates.

Every surface material is a rough diffuse whose albedo is a base colour (given in sRGB, like a
painter's swatch) times three small modulations: the facet tone (a face attribute written by
`geo.facet`), a fine paper grain (world-space noise) and a per-object variation (Object Info random)
for props. Painted sheets (the eye, glyphs, scroll spirals, the carpet) are mixed in by their alpha.
"""
import bpy

from . import textures


def srgb_to_linear(c):
    c = c / 255.0 if c > 1.0 else c
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin(rgb):
    return tuple(srgb_to_linear(c) for c in rgb)


# name: (sRGB swatch, facet value amplitude, warm/cool facet swing, grain, per-object variation)
SWATCHES = {
    "stone":       ((148, 133, 92), 0.16, 0.035, 0.10, 0.0),
    "stone_dark":  ((104, 93, 66), 0.16, 0.035, 0.10, 0.0),
    "stone_warm":  ((160, 136, 92), 0.15, 0.04, 0.10, 0.0),
    "plaster":     ((178, 160, 114), 0.10, 0.03, 0.10, 0.0),
    "floor":       ((116, 100, 74), 0.18, 0.04, 0.12, 0.0),
    "wood_dark":   ((82, 55, 37), 0.12, 0.03, 0.10, 0.10),
    "wood":        ((132, 96, 60), 0.12, 0.03, 0.10, 0.14),
    "crate":       ((140, 110, 72), 0.10, 0.03, 0.08, 0.18),
    "scroll":      ((200, 184, 142), 0.10, 0.03, 0.08, 0.12),
    "book_olive":  ((112, 108, 58), 0.10, 0.03, 0.08, 0.18),
    "book_tan":    ((156, 128, 86), 0.10, 0.03, 0.08, 0.18),
    "book_red":    ((122, 64, 42), 0.10, 0.03, 0.08, 0.18),
    "book_green":  ((72, 88, 58), 0.10, 0.03, 0.08, 0.18),
    "book_purple": ((86, 62, 100), 0.10, 0.03, 0.08, 0.15),
    "cloak":       ((96, 88, 66), 0.18, 0.03, 0.10, 0.0),
    "void":        ((9, 8, 11), 0.05, 0.0, 0.02, 0.0),
    "iron":        ((62, 58, 66), 0.12, 0.02, 0.08, 0.10),
    "brass":       ((178, 132, 52), 0.10, 0.03, 0.06, 0.08),
    "gold":        ((196, 160, 80), 0.10, 0.03, 0.06, 0.08),
    "purple":      ((98, 62, 132), 0.22, 0.04, 0.06, 0.10),
    "crystal":     ((118, 114, 104), 0.18, 0.03, 0.06, 0.10),
    "crystal_dark": ((70, 68, 66), 0.2, 0.03, 0.06, 0.0),
    "wax":         ((214, 198, 160), 0.06, 0.02, 0.04, 0.10),
    "pale":        ((206, 194, 160), 0.10, 0.03, 0.08, 0.0),
}

# Emissive: (linear colour, strength, light group)
EMISSIVE = {
    "flame":      ((1.0, 0.62, 0.28), 14.0, "glow"),
    "stair_glow": ((1.0, 0.80, 0.52), 9.0, "glow"),
    "lamp_glow":  ((1.0, 0.70, 0.38), 6.0, "glow"),
    "sky":        ((1.0, 0.93, 0.78), 9.0, "fill"),
}


class Nodes:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.x = 0

    def new(self, kind, **props):
        n = self.nt.nodes.new(kind)
        n.location = (self.x, 0)
        self.x += 180
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        n = self.new("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def vmul(self, a, b):
        n = self.new("ShaderNodeVectorMath", operation="MULTIPLY")
        for i, v in enumerate((a, b)):
            if isinstance(v, tuple):
                n.inputs[i].default_value = v
            else:
                self.link(v, n.inputs[i])
        return n.outputs[0]

    def mix(self, fac, a, b):
        n = self.new("ShaderNodeMix", data_type="RGBA", blend_type="MIX")
        for sock, v in ((n.inputs[0], fac), (n.inputs[6], a), (n.inputs[7], b)):
            if isinstance(v, (int, float)):
                sock.default_value = v
            elif isinstance(v, tuple):
                sock.default_value = v if len(v) == 4 else (*v, 1.0)
            else:
                self.link(v, sock)
        return n.outputs[2]


def _new(name):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    return m


def surface(name, swatch, facet_amp, hue, grain, obj_var, sheet=None, sheet_strength=1.0, sheet_uv="UV",
            roughness=1.0, metallic=0.0, grain_scale=38.0, sheet_tint=None):
    m = _new(name)
    n = Nodes(m)
    base = lin(swatch)
    fa = n.new("ShaderNodeAttribute", attribute_type="GEOMETRY", attribute_name="facet").outputs["Fac"]
    v = n.math("MULTIPLY_ADD", n.math("SUBTRACT", fa, 0.5), 2.0 * facet_amp)
    v = n.math("ADD", v, 1.0)
    hshift = n.math("MULTIPLY", n.math("SUBTRACT", n.math("FRACT", n.math("MULTIPLY", fa, 7.13)), 0.5), 2.0 * hue)
    # grain: two octaves of fine noise, world space
    pos = n.new("ShaderNodeNewGeometry").outputs["Position"]
    noise = n.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = grain_scale
    noise.inputs["Detail"].default_value = 4.0
    noise.inputs["Roughness"].default_value = 0.65
    n.link(pos, noise.inputs["Vector"])
    g = n.math("ADD", n.math("MULTIPLY", n.math("SUBTRACT", noise.outputs["Fac"], 0.5), 2.0 * grain), 1.0)
    tone = n.math("MULTIPLY", v, g)
    if obj_var > 0:
        rnd = n.new("ShaderNodeObjectInfo").outputs["Random"]
        tone = n.math("MULTIPLY", tone, n.math("ADD", n.math("MULTIPLY", n.math("SUBTRACT", rnd, 0.5), 2.0 * obj_var), 1.0))
    comb = n.new("ShaderNodeCombineXYZ")
    n.link(n.math("MULTIPLY", tone, n.math("ADD", hshift, 1.0)), comb.inputs[0])
    n.link(tone, comb.inputs[1])
    n.link(n.math("MULTIPLY", tone, n.math("SUBTRACT", 1.0, hshift)), comb.inputs[2])
    col = n.vmul(base, comb.outputs[0])
    if sheet is not None:
        tex = n.new("ShaderNodeTexImage", interpolation="Closest", extension="CLIP")
        tex.image = sheet
        uvn = n.new("ShaderNodeUVMap")
        n.link(uvn.outputs[0], tex.inputs["Vector"])
        paint = tex.outputs["Color"]
        if sheet_tint is not None:
            paint = n.vmul(paint, sheet_tint)
        paint = n.vmul(paint, comb.outputs[0])
        fac = n.math("MULTIPLY", tex.outputs["Alpha"], sheet_strength)
        col = n.mix(fac, col, paint)
    bsdf = n.new("ShaderNodeBsdfPrincipled")
    n.link(col, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25 if roughness > 0.8 else 0.5
    out = n.new("ShaderNodeOutputMaterial")
    n.link(bsdf.outputs["BSDF"], out.inputs["Surface"])
    m["swatch"] = list(swatch)
    return m


def emissive(name, colour, strength):
    m = _new(name)
    n = Nodes(m)
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*colour, 1.0)
    em.inputs["Strength"].default_value = strength
    out = n.new("ShaderNodeOutputMaterial")
    n.link(em.outputs[0], out.inputs["Surface"])
    m["swatch"] = [int(255 * min(1.0, c)) for c in colour]
    return m


def beam_volume(name, density=0.06, anisotropy=0.5, colour=(1.0, 0.93, 0.80), mottle=0.5):
    """Dust in the beam: scattering only inside the beam-shaped hull, gently mottled."""
    m = _new(name)
    n = Nodes(m)
    noise = n.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.9
    noise.inputs["Detail"].default_value = 3.0
    d = n.math("MULTIPLY", n.math("ADD", n.math("MULTIPLY", n.math("SUBTRACT", noise.outputs["Fac"], 0.5), 2.0 * mottle), 1.0), density)
    # denser high up (dust hangs near the hole, the beam fades as it falls); Blender z = height
    height = n.new("ShaderNodeSeparateXYZ")
    n.link(n.new("ShaderNodeNewGeometry").outputs["Position"], height.inputs[0])
    fall = n.math("ADD", n.math("MULTIPLY", n.math("DIVIDE", n.math("SUBTRACT", height.outputs["Z"], 1.0), 9.0, clamp=True), 0.7), 0.3)
    d = n.math("MULTIPLY", d, fall)
    vol = n.new("ShaderNodeVolumeScatter")
    vol.inputs["Color"].default_value = (*colour, 1.0)
    vol.inputs["Anisotropy"].default_value = anisotropy
    n.link(d, vol.inputs["Density"])
    out = n.new("ShaderNodeOutputMaterial")
    n.link(vol.outputs[0], out.inputs["Volume"])
    return m


def holdout_grey(name="blockout"):
    m = _new(name)
    n = Nodes(m)
    bsdf = n.new("ShaderNodeBsdfDiffuse")
    bsdf.inputs["Color"].default_value = (0.3, 0.3, 0.3, 1.0)
    out = n.new("ShaderNodeOutputMaterial")
    n.link(bsdf.outputs[0], out.inputs["Surface"])
    return m


def make_all():
    mats = {}
    for name, (sw, fa, hue, grain, ov) in SWATCHES.items():
        mats[name] = surface(name, sw, fa, hue, grain, ov, metallic=0.55 if name in ("brass", "gold") else 0.0,
                             roughness=0.5 if name in ("brass", "gold") else (0.45 if name == "purple" else 1.0))
    eye = textures.to_image("eye", textures.eye())
    glyph = textures.to_image("glyphs", textures.glyphs())
    scroll = textures.to_image("scroll_end", textures.scroll_end())
    star = textures.to_image("star", textures.star())
    carpet = textures.to_image("carpet", textures.carpet())
    mats["mural"] = surface("mural", SWATCHES["plaster"][0], 0.10, 0.03, 0.10, 0.0, sheet=eye)
    mats["crate_glyph"] = surface("crate_glyph", SWATCHES["crate"][0], 0.10, 0.03, 0.08, 0.18, sheet=glyph, sheet_strength=0.85)
    mats["scroll_end"] = surface("scroll_end", SWATCHES["scroll"][0], 0.08, 0.02, 0.06, 0.12, sheet=scroll)
    mats["medallion"] = surface("medallion", SWATCHES["pale"][0], 0.06, 0.02, 0.06, 0.0, sheet=star)
    mats["carpet"] = surface("carpet", SWATCHES["floor"][0], 0.18, 0.04, 0.12, 0.0, sheet=carpet)
    for name, (col, strength, _group) in EMISSIVE.items():
        mats[name] = emissive(name, col, strength)
    mats["beam"] = beam_volume("beam")
    mats["blockout"] = holdout_grey()
    return mats


def light_group_of(material_name):
    e = EMISSIVE.get(material_name)
    return e[2] if e else None
