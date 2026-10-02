# Character lighting from the painting

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

**Next steps.** (1) Write the measurement into `room.json` (`lighting`: key direction and colour, fill colour, sky, ground, fill:key) from `new_scene.py`;
(2) a character shader that uses a warm key, a cool hemisphere fill (sky above, ground bounce below) from those numbers, replacing the single `sun_color` tint;
(3) blind-compare the witch in the garden with old and new lighting; (4) extend to several positions (probes) if one spot is not enough.

```sh
python tools/painted/sphere_probe.py make   plate.png OUT [--model marketing|qwen]          # the paid edit, about USD 0.07
python tools/painted/sphere_probe.py grid   OUT/.../image_0.png grid.png --box 380 420 860 660   # read the circles off a grid
python tools/painted/sphere_probe.py measure OUT/.../image_0.png --grey 548 516 79 --chrome 755 506 70 --plate plate.png --out lighting.json
python tools/painted/test_new_scene.py                                                       # includes a synthetic-light recovery test
```
