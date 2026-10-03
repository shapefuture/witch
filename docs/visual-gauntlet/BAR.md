# The bar, in words

This is a reading of the user's reference still (a faceted, olive-and-purple library hall with a
shaft of light, a small witch and a raccoon) and the character sheet beside it. **The image itself
is the bar**; see `bar/README.md` for where it goes. Rounds 1-4 were judged against an earlier
*eyeballed* version of this file and got several things wrong (the picture is darker and more
saturated than described, and its characters are larger). The numbers below were measured from the
image itself with `tools/visual_gauntlet/metrics.py` after downscaling it to 640x360.

## Composition
- A low camera at figure height, about 6 m from the characters, moderate lens (~40-50 degrees):
  the characters are about 15% of frame height, the hooded statue about 45%; the shelf walls press
  in close on both sides. Intimate and towering, not a long wide shot.
- Dark, cropped **foreground frame** on both sides: a tall shelf with scrolls and carved boxes on
  the left with a **purple faceted glass globe** on a stand and a big dark rock at the bottom-left;
  a tall dark shelf wall on the right and a **grey faceted crystal on a stone pedestal** bottom-right.
- Mid-ground: a tall **pointed stone arch** (left of centre) opening onto a bright corridor with
  steps; above it on the wall a **pixel-stepped eye glyph** with lashes; two **tapering gothic
  bookcase towers** with dark purple orb finials in the centre; a **hooded, faceless statue** holding
  a scroll on a stepped plinth, right of centre; round compass plate on the wall.
- A rough **oculus** in the vault (top right) and one **diagonal golden god-ray** from it to the
  floor, with glittering **dust motes** in the beam.
- A **spiral carpet** (purple and pale olive-gold bands) on the floor leads the eye to the two
  characters standing in the light pool.

## Value structure (measured)
- **Low key.** Luma percentiles 1/5/25/50/75/95/99 = 0.013 / 0.023 / 0.076 / 0.155 / 0.258 / 0.431 /
  0.632. 38% of the frame is below 0.12; only 0.5% is above 0.75. The beam is soft and the pool on
  the floor tops out near 0.6: it is *felt*, not blown out. Deep blacks in the foreground corners.
- Vignette is gentle: corner luma is 44% of centre luma.
- The lit pool, the oculus and a little corridor glow are the only places that glow.

## Colour
- Dominant **olive / khaki / sepia** (hue 40-55), mean saturation **0.58** (not washed out: dark
  and rich), 45% olive-gold pixels, 9.5% orange, deep brown woodwork, warm gold light. **Purple accents** (hue 270-285): orbs, globe, carpet stripes, hats.
- Haze lifts distant things toward warm beige; shadows are brown-olive, not black, not blue.

## Surface
- Everything is **faceted triangles**; stone facets about 1-3% of the picture width, each facet a
  slightly different value (a crystalline mosaic) with **soft gradients across large facets**.
  Edge energy (`facet_gradient`) is 1.74: calm planes, not noise.
- A fine **paper-grain / mottle** texture over all surfaces; edges stay crisp; nothing is a clean
  flat colour. Glyphs on boxes and on the wall are **pixel-stepped**.

## Light
- One key light through the vault; volumetric scattering; warm rim light on shelf edges; soft
  long shadows; bounce light warms the shade.

## What the critic should reject
- Cartoon outlines, clean vector flats, 2D UI furniture, horror, claymation, voxels, fabric/paper
  photographs, flat even lighting, a muddy single-brown image with no bright pool and no purple.

## Tools
`tools/visual_gauntlet/`, Python 3 with numpy, Pillow, scipy and scikit-image
(`pip install numpy pillow scipy scikit-image`). Each tool runs `--selftest` on synthetic images.
- `metrics.py FRAME...`: the whole-frame numbers above.
- `squint.py A B`: value structure at thumbnail scale. Both images are centre-cropped to one aspect,
  then compared with SSIM of luma at 32x18 and at 64x36, a rank correlation of the values (exposure
  does not matter), and notan agreement. `squint` is the mean of the first three. Other tools import
  `score` and `load`.
- `regions.py REF OURS [--overlay out.png]`: median luma, p99, saturation, contrast, edge density
  and facet gradient in five fixed regions read off the reference: the outer frame ring, the shelves,
  the arch passage, the beam (oculus to the pool of light) and the statue. Both images are measured
  at 640x360.
- `grade.py fit REF OURS lut.png`: a grade from per-channel Lab quantile matching. It is smoothed,
  monotonic and blended by `--strength` (0.6), and it is fitted to histograms only, so it can never
  copy the picture. It writes a 17^3 LUT strip (289x17: x = r + 17*b, y = g, so import it in Godot
  as a Texture3D with 17 horizontal slices). `grade.py apply` previews the grade on any frame.
- `blind_ab.py OURS REF DIR --print-prompt`: the blind pair, in matched mode by default. Both images
  get the same crop and one working resolution, then are scaled to 1280x720, and metadata is stripped.
  Labels are random. The key goes to `DIR_KEY.json` beside the folder. It prints `critic_prompt.md`
  with the two paths filled in, ready for a fresh critic.

Baseline, the `wide_169` of each round against the reference: `squint` was 0.16 for r01, 0.37 for r04
(the best) and 0.32 for r08 (SSIM 0.23 / 0.18, value correlation 0.56). Use frames without UI. The
r08 speech bubble sits inside `shelves` and `arch_passage` and inflates their p99.
