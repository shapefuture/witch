# The witch: two character models

`assets/characters/witch.glb` (v1, the concept sheet's witch) and `witch_antler.glb` (v2, the
antler variant) are built by code from the user's procedural models (numpy to glTF), ported into
`tools/characters/`:

```sh
python tools/characters/witch.py --out assets/characters --refs <dir with the concept art>
python tools/characters/witch.py --out assets/characters --preview /tmp/witch   # six views, face, clips
python tools/characters/witch_antler.py --out assets/characters                 # v2 only
```

The concept art is **not in the repository**. With `--refs` (or `$WITCH_REFS`) the face textures
are extracted from it. Without it, they are read back out of the GLBs already in `--out`, whose
`asset.extras.face_rect` records where the face sits in the atlas. A rebuild without the art is
byte-identical in the atlas. Then re-import (`godot --headless --path . --import`).

| file | role |
|---|---|
| `witch_kit.py` | geometry kit: lofts, blobs, tubes, `Grid` robe surfaces, embossed star/moon decals, `Model` (parts, skinning, flatten) |
| `atlas.py` | one atlas per character: deferred shelf packing, per-tile scale, colour swatches, edge bleed, 5-bit colour (replaces the source's missing `fw_core.ATL`) |
| `face_plate.py` | the photo face: reference to texture, and the relief plate (below) |
| `witch_tex.py` | v2 painters from the source (felt/boucle, tree-of-life cape, appliqué skirt, vest roots, bib, sleeves, boots, satchels, sprites) |
| `witch_glb.py` | rotations, clips, linear-blend skinning for previews, the glTF 2.0 binary writer |
| `witch_preview.py` | textured six-view and close-up renderer (judging against the art, not the game renderer) |
| `witch.py`, `witch_antler.py` | the two characters, their poses and clips |

## What ships

|  | v1 `witch.glb` | v2 `witch_antler.glb` |
|---|---|---|
| triangles (budget 9,000) | **8,016** | **7,234** |
| bones | 21 | 23 (adds `charm.L/R`) |
| surfaces / materials | 1 / 1 | 1 / 1 |
| atlas (nearest, clamped, 5-bit) | 256 x 256 (face 176 x 184 + 45 swatches) | 512 x 512 (face + 22 painted tiles + swatches) |
| height | hood top 1.30 m | hood top 1.30 m, antlers 1.32 m |

Root at the feet, facing +Z, metres. Flat normals everywhere except the face plate (smooth, so
the painted face is not cut into facets twice). The rest pose is a T-pose. Every clip keys
**every** bone, so switching clips never leaves a bone behind or falls back to the T-pose. The
`.import` files keep constant tracks (`remove_immutable_tracks=false`), turn off LODs and shadow
meshes, embed the atlas uncompressed (`embedded_image_handling=3`, so no loose PNG with the face
is extracted next to the GLB), and set the loop modes.

| clip | length | loop | what |
|---|---|---|---|
| `idle` | 4.0 s | yes | breathing, head and hair sway, bird looks about (v2: charms swing) |
| `walk` | 1.0 s | yes | in place, two steps: legs, hip bob/sway, counter-twist, cape and hair lag |
| `talk` | 3.0 s | yes | nods and tilts, the wand hand gestures |
| `cast` | 1.6 s | no | wand raised out and up in 0.35 s (star above the hood), held with a flourish; ends raised |

Base pose (all clips): wand up in her right hand at the chest. v1 holds the bird up on her left
hand (the sheet's pose; the `bird` bone is a child of `hand.L`). v2 has the bird on her left
shoulder and the left arm relaxed by the satchel.

## The face (both witches)

The decal face (v1: painted polygons; v2: a painted 256 px face) is replaced by the photo
face plate technique of the user's Shadow model, generalised in `face_plate.py`:

1. **Mapping.** Five landmarks (eye centres, nose tip, mouth, chin) are read off the art once:
   v1 from the sheet's top-left front view, v2 from `witch2_antler_front`. The same landmarks are
   placed on the head in model units, as fractions of the eye spacing measured on both
   references (nose 0.45, mouth 0.66 and chin 1.04 of the eye spacing below the eyes). A
   least-squares **affine** maps model to pixels. v1's head is tilted about 16 degrees in the
   sheet, and the affine stands it upright (2.2 px residual; v2 0.7 px).
2. **Texture.** The face (about 50 to 90 px wide) is upscaled **Lanczos x3** and resampled
   bicubic through the affine into an upright 176 x 184 texture that is linear in model x and y.
   It is colour-normalised to the model's skin tone through a tall, narrow low-pass of the skin
   pixels: the art's lit and shaded planes (v2's grey left half) flatten, while eyes, brows and
   lips keep their contrast. Then it is **mirrored** from the better half (v1: her right; v2:
   her left).
3. **Window.** Skin connected to the face centre becomes a smooth, symmetric contour (per-row
   half width, median-smoothed, a jaw that only narrows, a round hairline arc where the petals
   and fringe would leave spikes). Outside it is **hair colour**.
4. **Features, repainted.** At 50 to 90 px the art's eyes upscale into smears, so the photo
   keeps only the skin. The original eyes, brows and lips are filled from a masked low-pass of
   the surrounding skin, so the plate's shading survives. They are then redrawn at 4x in
   texture space from the source's `tex_face` geometry (same model frame as the landmarks),
   box-downsampled and blended back through feathered masks. Each eye is an almond (`seg`)
   with lid shading, an iris in three rings sampled toward the art (v1 light grey-violet,
   v2 hazel-green), a pupil, one catch-light, a dark upper lash line with a wing flick and a
   soft lower lid. The brows are thin and orange-brown, the lips soft coral. Then an unsharp
   mask and **5-bit quantisation**.
5. **Plate.** An 18 x 13 grid over the head front follows the head's analytic superellipse
   surface plus a **relief**: nose bridge and tip, alae, lips, brow ridge, eye sockets,
   cheekbones and chin. The sockets are centred on the eye landmarks, as are the painted
   eyes, and the brow ridge sits under the painted brows. All are sized by the eye spacing, so the relief fits whatever head it
   sits on. UVs use the same linear model-to-texture map, so the texture lands where the
   landmarks say. Each head's front rings were refitted to its reference's face window: v1 is
   round with a soft chin, v2 heart-shaped. The plate's edges sit 4 mm (model units) proud of
   the head, and the hood, fringe, cheek ringlets, side curtains and flower crown are geometry
   around the window.

## v1 against the sheet

Before: the source model, 9,328 triangles (over budget), 46 flat materials, T-pose, a painted
decal face. Measured against the sheet (front view, hood top to floor about 272 px):

- **Proportions.** The head is scaled 1.45 about the neck (the sheet's hood-to-chin is 32% of
  her height; the source's was 23%), and the torso is shortened 9% (`remap_y`) so the chin and
  waist land where the sheet puts them.
- **Silhouette.** The skirt is a floor-length 12-facet cone whose hem is two thirds of her height
  wide (the source's was 0.39 and stopped above the boots). The hood gained a peak leaning back
  (side view), the vest is wider, and the sleeves are bell-shaped.
- **Hair.** Cheek ringlets now hug the face, and side curtains fill the gap to the hood. The
  back has six locks per side that follow the cape's surface (the sheet's mass of curls), plus
  big hip spirals and temple curls on both sides.
- **Colour.** Pulled toward the sheet's measured values: a warmer mauve-violet, peach-gold stars
  (not saturated yellow), a less saturated orange, a lighter brown vest, pinker flowers, a
  pale pink wand.
- **Budget.** Decals use low-poly crescents, the boots and legs (hidden under the skirt) are
  simplified, and flat colours are atlas swatches on one surface.

## v2 (finished)

The source stopped at the texture painters. Their missing `fw_core.ATL` is reimplemented as
`atlas.Atlas`, and the painters are ported as written, keeping only the final versions where the
source redefines one. The model reuses v1's kit, hair, bird, hands and clips at the source's own
proportions, which match this concept. New geometry:

- branch antlers with tines from the hood sides, with oak-leaf, carrot, lavender and feather
  charms and little lights hanging on threads from two swinging `charm` bones;
- a maroon boucle hood with a long drooping peak;
- a tree-of-life cape that covers the whole back, as in the back view;
- a maroon bib with pink roots, a front-only green felt mantle with points, and the green vest
  with roots embroidered up from the hem;
- a chain with a silver crescent pendant;
- satchels with stitched flaps and a strap: a mouse in a little hat, a spoon, a feather card
  and lavender in one; a house (painted walls, roof), a map card, a mushroom card and a light
  in the other;
- a garland of bones on a cord over the skirt top;
- the 10-facet appliqué skirt (one painted band per facet) and laced boots, visible under it;
- orange hair framing the face, temple curls by the antlers, and hip spirals that run under
  the cape and curl out at the sides.

## Still off

- The faces mix a soft photo (skin, nose, chin) with crisply painted features. In a close-up
  the skin is softer than the eyes, and v1's eyes are rounder than the sheet's heavy-lidded almonds.
- v1's back hair is flat paper-strip ribbons, not the sheet's dense mop of ringlets, so the
  cape shows between locks. More locks would cost about 120 triangles each.
- The skirt and cape are rigid: the walk moves the legs under a stiff cone. The camera never
  sees the legs on v1, but v2's boots step under the hem.
- The atlas is display-referred sRGB (the glTF convention). The game's `psx_lit_actor` samples
  `source_color`, and the GLBs are not wired into `Placeholders.witch()` yet: that needs the
  named handles (`Body`, `Hat`, `ArmR/Wand`, `RaccoonLink`), which is game code.
