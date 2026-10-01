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
