# Character lighting from the painting

> **Status (2026-10-02): built.** A room's `room.json` may carry a `lighting` block (measured from calibration spheres, below); its characters are then lit by
> it. `new_scene.py` measures it for every generated scene (about USD 0.07 extra). The garden and the shop have one; rooms without keep the floor-map light.

**The problem.** A character is a 3D model on a painted plate. Today it gets one brightness from the blurred floor map, one beam colour and one sun direction
(`docs/art/painted_room.md`, actor lighting). In the garden that single warm tint turned the witch's purple dress maroon: the painting is warm
where the sun hits and cool in the shade, and the character is warm everywhere.

## Ways to get lighting out of the image (none built yet except the experiment below)

1. **Sample the plate**: the blurred plate colour around the feet and head as local ambient. Free, no direction.
2. **Light probes baked from the painting**: at each walkable cell, gather the painted pixels' colours at their 3D positions (we have depth) into a small
   direction-aware description (9 coefficients per channel); the character blends the nearest cells. Light probes in games; AR light estimation.
3. **The lamps we already detect** (`life.json`) as point lights on the characters, flicker included.
4. **Shadows from the painting's geometry**: a few steps of ray march toward the light through the depth grid in the actor shader.
5. **Atmosphere and grade**: the plate's haze colour, grain and dither on the characters.
6. **Calibration spheres** (below): ask the generator to paint a grey and a chrome ball into the plate.
7. Workarounds: grade the plate near the character; fit the shader to a generated composite as a target; authored light zones, as fixed-camera adventures did.

## Experiment: calibration spheres (2026-10-02)

Film crews photograph a matte grey ball and a chrome ball in the set. `tools/painted/sphere_probe.py` asks an image-editing model for a same-camera
variant of the plate with the two balls on the foreground path, then measures them: the grey ball's shading (a Lambert fit, ambient + one light, the
direction searched over a lattice) gives the key direction and the fill and key colours; the chrome ball is a 360-degree picture of the light
around it (every pixel covers the same solid angle). Two models, one plate (the garden), about USD 0.15 in all:

| | Marketing Studio | Qwen Image 3 Edit |
|---|---|---|
| plate unchanged outside the spheres | mean difference 6/255, 1.8 % of pixels changed, no camera drift | 8/255, 5.9 %, no drift |
| grey ball explained by "ambient + one light" (r2) | **0.97** | **0.96** |
| key direction from the grey ball (x right, y up, z to the camera) | 0.76, 0.65, 0.02 | 0.69, 0.71, 0.16 |
| sun glint direction in the chrome ball | 0.84, 0.53, -0.13 | 0.93, 0.27, -0.27 |
| angle between the two estimates | 12 degrees | 38 degrees |
| grey shading vs the irradiance predicted from the chrome ball (correlation) | **0.88** | **0.92** |
| key colour (normalised) | 1.00, 0.66, 0.42 (warm orange) | 1.00, 0.73, 0.54 |
| fill colour (the shaded side) | 1.00, 0.95, 0.82 | 0.93, 0.96, 1.00 (neutral to cool) |
| sky / ground bounce in the chrome ball | 0.89, 0.86, 1.00 / 1.00, 0.59, 0.22 | 0.56, 0.69, 1.00 / 1.00, 0.71, 0.50 |
| fill : key (luma) | 0.10 | 0.14 |

**Reading.** Both models painted convincing, coherent spheres without disturbing the plate. Each pair is self-consistent (the grey ball's shading follows the
irradiance the chrome ball implies: 0.88 and 0.92), the grey ball is explained by one warm light plus a weak fill (0.96-0.97), and the two *different* models agree
on the key direction to within 10 degrees (upper right, about 40 degrees up). The structure the garden's light has is the one the single tint lacks: a
**warm low key from the upper right, a cool fill in the shade at a tenth of its strength, a cool sky above and an orange ground bounce below**. A purple dress
lit this way keeps its purple on top and in shade, and goes warm only where the sun hits.

**Not shown.** There is no ground truth for the plate's real lighting (the sky is brightest toward the right edge of the plate, which fits the key from the
right, no more). The spheres measure one spot, the foreground path; probes for the whole floor need several spheres or variants. Directions are in the camera's frame and still
have to be turned into world space with the room's pitch. Absolute intensities mean nothing (only ratios and colours). Nothing here has been fed to a character yet.

**Next steps (done below).** (1) Write the measurement into `room.json` (`lighting`: key direction and colour, fill colour, sky, ground, fill:key) from `new_scene.py`;
(2) a character shader that uses a warm key, a cool hemisphere fill (sky above, ground bounce below) from those numbers, replacing the single `sun_color` tint;
(3) blind-compare the witch in the garden with old and new lighting; (4) extend to several positions (probes) if one spot is not enough.

```sh
python tools/painted/sphere_probe.py make   plate.png OUT [--model marketing|qwen]          # the paid edit, about USD 0.07
python tools/painted/sphere_probe.py grid   OUT/.../image_0.png grid.png --box 380 420 860 660   # read the circles off a grid
python tools/painted/sphere_probe.py measure OUT/.../image_0.png --grey 548 516 79 --chrome 755 506 70 --plate plate.png --out lighting.json
python tools/painted/test_new_scene.py                                                       # includes a synthetic-light recovery test
```


## Applied to the characters (built)

**The `lighting` block** (`tools/painted/relight.py` writes it; `PaintedRoom.lighting()` reads it; `psx_lit_actor.gdshader`, `lighting_mode`, uses it):

| field | what it does |
|---|---|
| `key_dir`, `key_color`, `key_level` | a warm key from the measured direction (turned into world space with the room's pitch), as the grey ball's fit says; its level follows the scene's own exposure (1.5 x the floor band's mean luma: the garden 0.45, the dark shop 0.34), so the characters are no brighter than their surroundings |
| `sky_color`, `ground_color`, `fill_level` | a hemisphere fill instead of the floor's purple: the sky's colour on top-facing facets, the ground's bounce under them; its strength is a share of the key's peak (the measured ratio is 0.10-0.14; it is raised to 0.25-0.5 so shadows stay readable), so the room's flicker moves both |
| (rim) | the rim light is the sky's colour, not the sun's |
| `shadow_tint` | the colour the floor goes to in a character's shadow: cool, from the sky; the shadow also falls along the measured key direction |
| `grade`, `grade_strength` | the plate's own colour cast (its floor band's mean colour over its luma), taken in part (0.5) by the characters: they sit in the same golden or teal light |
| `source` | `spheres` (measured) or `plate` (derived, opt-in) |

**Before and after.** In the garden the witch's dress went from a dark maroon to purple on top and plum where the sun hits it, her hair from brown to orange, the raccoon from a muddy
brown to a warm taupe; in the shop the characters stopped being muddy and took the teal shade and the warm window key. Not yet compared by blind critics.

**Workarounds added along the way, and what did not work**

- **Exposure matching** (`key_level` from the floor's luma): without it the first version over-lit the characters in the dark shop (the raccoon went nearly white).
- **The plate's grade** applied in part: the first version looked cool and clean next to a golden floor; a 0.5 share of the cast sat them in.
- **A sanity gate** on the measurement (`sphere_probe.GOOD_FIT` 0.85: the grey ball must be explained by one light; `GOOD_AGREEMENT` 0.6: the grey ball's shading must follow the chrome ball's irradiance). A measurement that fails leaves the characters on the floor-map light, never on a bad guess.
- **Smooth spheres in the prompt**: in the shop style the generator painted faceted balls, which breaks the shading fit and the circle search; "perfectly smooth, perfectly round, the same size" fixed that.
- **Plate-derived lighting is a poor guess in interiors** (`relight.py --plate`, opt-in): the "sky" is the ceiling and the "ground" the teal floor, so on the shop it washed the raccoon out to yellow. Only the grade and exposure are safe to take from a plate alone.
- **Finding the balls automatically** (`sphere_probe.find_spheres`): a gradient Hough vote finds the grey ball exactly (within 3 px on the garden); the chrome ball is then found by its outline in the same row to its right. It works on the garden (fit 0.97, agreement 0.89) but not yet on the faceted shop, which needed circles read off a grid by hand (`sphere_probe.py grid`, then `measure --grey ... --chrome ...`).
  The pipeline's gate catches a failed search, so the cost is a missing improvement, not a worse picture.

**One edit for objects and spheres (tested on the garden, one call each).** Asking one editing call to take four objects away (wheelbarrow, watering can, sundial, lantern) *and* paint the two balls works, so the toy box's "without" edit and the sphere probe can share a call.

| | Marketing Studio (1k, USD 0.056) | Qwen Image 3 Edit (2k, USD 0.075) |
|---|---|---|
| the four objects taken away | all four | all four |
| both balls painted | yes, about the same size | yes, but the balls differ in size (r 194 and 152 px at 2000 wide) |
| rest of the picture | **registered exactly** (0 px shift in every region, as in the sphere-only edits) | **stretched about 1.6 % sideways** (7 px at the left, 19 px at the right of 1280): every lasso and diff against the plate would be off |
| lighting from the balls (hand circles) | fit 0.97, agreement 0.92, key direction within 7 degrees of the sphere-only edit | fit 0.95, agreement 0.92, within 10 degrees |

The edit with the balls only is pixel-aligned in both models; it is the larger edit that makes Qwen redraw the frame. So the combined call goes to Marketing Studio. Open: `find_spheres` is fooled by the pixels the removed objects changed
(it found a sundial remnant and a half-ball), so after a combined edit the circles are still read by hand (`sphere_probe.py grid`, then `measure`); an automatic search that ignores the removal boxes is not built. The key colour came out a little more orange
than in the sphere-only call (1.0, 0.57, 0.27 against 1.0, 0.66, 0.42): the colour varies between generations, the direction does not.
A bug found on the way: `cross_check` paired every grey-ball pixel with every chrome-ball pixel (about 10 GB for balls of 120 px) and was killed; it now takes a regular subsample of each (same result, 1.6 s).

**Not done / open.** One measurement per scene (the foreground path); characters keep one lighting wherever they stand (probes are the next step). The shop's measurement agrees less well than the garden's
(0.66 against 0.88, several lights in an interior). Local lamps (the shop's fireplace) do not yet light the characters. A blind comparison of old and new lighting has not been run.
