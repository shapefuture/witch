# Style bible (draft)

Status: **draft, revised 2026-10-14** (second revision). The look is anchored to the **master prompt** of the game draft
(v3.0), in its positive-only form `ps1p`. The user chose it as the best result of the look runs (run r6, see
`docs/art/model_comparison.md` and `docs/art/scenes.md`). The user says the style is still less fixed than the prompt
itself: see "Fixed and variable" below. STYLE LOCKED 2026-10-14: the fixed and variable split (SF) is confirmed, rules R1 to R12 are accepted, and SC1, SC3, SC5, SC6 and SC7 are decided.

## Where the master prompt lives

- `tools/painted/scenes/styles.json`. `ps1` is the master prompt v3.0 as written. `ps1p` is the same with every
  "do not" turned positive, because a model may draw what a prompt names. `ps1p` is the default of
  `tools/painted/new_scene.py`.
- The draft itself is the user's own file and is not committed (it contains Russian text).
- Built in this look so far: the garden (`assets/painted/garden/`, run r6) and the shop (`shop_ps1`).

## The look, as the master prompt states it

- **Rendering.** Crude early 3D built from primitives (wedges, cubes, cones, tapered cylinders), faceted, with dry matte
  painted textures and subtle dithering. Not modern low-poly, not polished indie 3D, not papercraft, not claymation,
  not voxels, not photographed media.
- **Palette.** Saturated jewel tones. Shadows are cobalt, violet, plum and indigo. The ground and walls are turquoise,
  teal and petrol. Light is amber, gold and lemon. Accents are coral, hot pink, tangerine and lavender, with earthy
  moss, mustard and burnt orange. Never gray, never desaturated.
- **Light.** Golden-hour warmth under soft directional light, long blunt shadows, a painted glow. No bloom, no lens
  flare, no gloss.
- **Camera.** A fixed 2.5D stage framing with strong barrel curvature inside the geometry. Three to seven depth layers.
  No vignette, no screen frame, no letterboxing. A clear empty foreground where the characters stand.
- **World.** Dense and cluttered, every inch a puzzle piece. Architecture is grown rather than built. Chunky faceted
  animals are props.
- **Interface.** Diegetic only: nothing sits on top of the screen.
- **Characters and props.** Carved wooden toys rendered as low-poly 3D, except the witch and the raccoon (SC5).
- **Motifs (one to three per scene).** A wedge mark carved into stone, wood or metal; thread diagrams; a small bell; a
  sealed, unlabeled envelope; a pigeon that understands more than the characters; repairs in the wrong material; a dust
  gap where something was removed; small absurd doors on oversized facades.
- **Avoid list (for generated backgrounds).** Photorealism, glossy PBR, bloom, a modern HUD, dialogue boxes, cel shading,
  toon outlines, cute modern 3D, voxels, papercraft, horror mood, gold magic glow, arrows, glowing markers, question-mark
  icons, clue glows.

## Fixed and variable (confirmed by the user 2026-10-14)

- **Fixed:** the rendering family (crude faceted 3D, not pixel, not papercraft); the fixed stage camera; diegetic
  interface only; no vignette, frame or HUD; the jewel-toned family, not olive.
- **Variable, scene by scene:** the exact palette within the jewel range; the time of day and the light; the motifs;
  how dense the world is.

## Second prompt: the PS1 technical look (added 2026-10-14)

The user added a second prompt: a PS1-era fantasy look with a restricted palette, affine warping, vertex jitter,
dithering and screen effects. Most of its technical elements are already in the renderer (`render/psx/`). Each row is a
candidate, not a decision. Rows marked conflict are decided in SC6 and SC7.

| element (second prompt) | in the repo now | status |
|---|---|---|
| Vertex snapping (vertex jitter) | `psx_globals.gd` (snap grid, precision multiplier), `psx_set.gdshader`, `plate_projection.gdshaderinc` | R7 candidate; built |
| Affine texture mapping, texture swimming, UV stretch | `psx_set.gdshader` divides by w (affine); nearest filtering | R7 candidate; built |
| Per-vertex wobble on characters ("GTE jitter") | `psx_materials.gd`, `actor()` wobble 0.004 | R7 candidate; built |
| Dithering and quantised gradients (32 levels per channel) | `psx_screen.gdshader` (5-bit ordered dither), `pp_band-dither.gdshader`, `psxdither.png` | R8 candidate; built |
| Restricted late-1990s palette with jewel accents | `palette.gd` (mundane colours; magic colours kept apart) | R9 candidate; the base is saturated jewel (SC7) |
| Flat or minimally interpolated facets, hard planar transitions | characters are flat-faceted (`docs/art/characters_*.md`) | R10 candidate |
| Low-resolution, chunky, heavily pixelated textures | character atlases at 256 px at most; plates are painted at full detail | R11 candidate; texture budget still to choose |
| Distant elements as blocky silhouettes and pixel clusters | not built; plates are painted | R11 candidate |
| Broad low-resolution light pools, hard shadows | `StageLight` (`render/psx/stage_light.gd`) | R12 candidate |
| Gentle CRT bloom | screen pass `glow_amount` 0.4 | on (SC6) |
| Vignette (not in the second prompt; the master prompt bans it) | screen pass `vignette` 0.5 | on (SC6; overrides the ban) |
| Faint scanlines | not in the repo | new; on (SC6) |
| Subtle chromatic separation | not in the repo | new; on (SC6) |
| Low-resolution upscaling, slight softness | the render is 540 rows (`psx_globals.gd`) | not added: resolution unchanged (SC6) |
| Dark nights, deep blue shadows, glowing accents | the master prompt says golden-hour day | conflict with day: time of day is variable per scene (SF), so both are allowed |
| Muted base (navy, violet, dark teal, olive, ochre, faded gold, dusty pink, cream) with jewel accents | not the base | dropped as the base (SC7: saturated jewel) |
| Avoid: PBR, smooth subdivision, clean vector edges, realistic skin or fabric, physical reflections, cinematic bokeh, HD | consistent with the master prompt's avoid list | adopted as an avoid list |

Whether the screen pass is active in the game build is not checked here.

## Rules, restated against the master prompt

| id | rule | source | status |
|---|---|---|---|
| R1 | Palette family is jewel-toned (the `ps1p` palette), not olive. The olive hall palette is not the base. | `ps1p`; user, 2026-10-14 | accepted 2026-10-14 (user) |
| R2 | Light is golden-hour warmth with long blunt shadows; no bloom, no lens flare. | `ps1p` | accepted 2026-10-14 (user) |
| R3 | Rendering is faceted crude 3D built from primitives, with dry matte textures. | `ps1p`; SC3 | accepted 2026-10-14 (user) |
| R4 | Motifs are the prompt's own (wedge mark, bell, envelope, pigeon, absurd doors). The witch's moon and star stay on her costume. | `ps1p`; `03` | accepted 2026-10-14 (user) |
| R5 | Subtle dithering is allowed. The dusk gradient of `02` is a sample only. | `ps1p`; `02` | accepted 2026-10-14 (user) |
| R6 | Characters are readable at about 100 px. | `03`; repo tests | accepted 2026-10-14 (user) |
| R7 | Vertex snapping, affine mapping and a small per-vertex wobble on characters are the look's geometry. | second prompt; `render/psx/` | accepted 2026-10-14 (user) |
| R8 | Ordered dither and quantised gradients; no smooth gradients on surfaces. | second prompt; `psx_screen.gdshader` | accepted 2026-10-14 (user) |
| R9 | A restricted palette per world, with magic colours kept apart (`palette.gd`). | second prompt | accepted 2026-10-14 (user) |
| R10 | Flat or minimally interpolated facets and hard planar transitions; no smooth subdivision. | second prompt; characters docs | accepted 2026-10-14 (user) |
| R11 | Textures are low-resolution and chunky; distant things are blocky silhouettes. The texture budget is still to choose. | second prompt | accepted 2026-10-14 (user) |
| R12 | Light sits in broad low-resolution pools with hard-edged shadows. | second prompt; `stage_light.gd` | accepted 2026-10-14 (user) |
| R13 | Crude comes from technical limits, not from deliberate ugliness: polygon count, texture resolution and texture placement, as in early PS1 games. No intentional distortion of models. | user, 2026-10-14 | accepted 2026-10-14 (user) |

Measured on the hall sample (`01`, `tools/visual_gauntlet/metrics.py`): median luma 0.155, 99th percentile 0.636, mean
saturation 0.585. These describe the demo scene, not the style.

## Conflicts and decisions

- **SC1. The interface.** Confirmed 2026-10-14: diegetic only, with paper-strip choices, a subtitle box with an arrow,
  and one satchel. This matches the prompt's own UI rule. See `docs/design/NAVIGATION.md`.
- **SC2. The witch's hair. Decided 2026-10-14: русый** (light ash-blond, as in `04`), not the orange of `03`. The rest of
  the sheet's witch stands. The witch's texture changes to match (follow-up task in the tracker).
- **SC3. Rendering family. Decided: 3D, not pixel art.**
- **SC4. Setting. Not canon.** Decided by NQ-g, not by the references.
- **SC5. Characters. Decided 2026-10-14:** crude, as in the PS1 character references (`11`, `12`), for every character
  except the witch and the raccoon. Those two keep the sheet's look (`03`). E4 therefore re-judges the current clean builds
  (Tomas, Shadow, Vera, Elian, Ilya) against the crude references, and the witch and the raccoon against the sheet.
- **SC6. Screen effects. Decided 2026-10-14: all of the second prompt's effects are on** (CRT bloom, vignette, faint
  scanlines, subtle chromatic separation). This overrides the master prompt's ban on vignette and bloom. **Resolution is
  unchanged** (540 rows); the low-resolution upscaling of the second prompt is not added.
- **SC7. Palette base. Decided 2026-10-14: saturated jewel tones**, the master prompt's palette. The second prompt's muted
  base is not the base; its restricted-palette principle (R9) still applies within each world.
- **The hall sample (`01`).** Papercraft and olive, which the prompt excludes ("NOT papercraft"). The user says it is a
  demo scene. Whether it stays is the HALL decision, deferred to DESIGN-FREEZE.

## Notes for the build

- The avoid list governs generated backgrounds. Runtime UI (the walk ring, the item card) is a 3D object and should not
  glow, so the spirit of "no glowing markers" still applies.
- The painted-room pipeline already runs in this look (`tools/painted/`), so room 2 (decision X9) is planned in it.

## Not decided here

The final look, the final characters, the rooms and their order, and the ending. These are questions in
`docs/design/PREPRODUCTION.md`. The style bible is revised once they are answered.
