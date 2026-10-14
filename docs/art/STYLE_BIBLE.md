# Style bible (draft)

Status: **draft, revised 2026-10-14** (second revision). The look is anchored to the **master prompt** of the game draft
(v3.0), in its positive-only form `ps1p`. The user chose it as the best result of the look runs (run r6, see
`docs/art/model_comparison.md` and `docs/art/scenes.md`). The user says the style is still less fixed than the prompt
itself: see "Fixed and variable" below. Nothing is locked.

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
- **Characters and props.** Carved wooden toys rendered as low-poly 3D.
- **Motifs (one to three per scene).** A wedge mark carved into stone, wood or metal; thread diagrams; a small bell; a
  sealed, unlabeled envelope; a pigeon that understands more than the characters; repairs in the wrong material; a dust
  gap where something was removed; small absurd doors on oversized facades.
- **Avoid list (for generated backgrounds).** Photorealism, glossy PBR, bloom, a modern HUD, dialogue boxes, cel shading,
  toon outlines, cute modern 3D, voxels, papercraft, horror mood, gold magic glow, arrows, glowing markers, question-mark
  icons, clue glows.

## Fixed and variable (my reading; the user to correct)

- **Fixed:** the rendering family (crude faceted 3D, not pixel, not papercraft); the fixed stage camera; diegetic
  interface only; no vignette, frame or HUD; the jewel-toned family, not olive.
- **Variable, scene by scene:** the exact palette within the jewel range; the time of day and the light; the motifs;
  how dense the world is.

## Rules, restated against the master prompt

| id | rule | source | status |
|---|---|---|---|
| R1 | Palette family is jewel-toned (the `ps1p` palette), not olive. The olive hall palette is not the base. | `ps1p`; user, 2026-10-14 | candidate; the user to confirm, since the earlier R1 is replaced |
| R2 | Light is golden-hour warmth with long blunt shadows; no bloom, no lens flare. | `ps1p` | candidate |
| R3 | Rendering is faceted crude 3D built from primitives, with dry matte textures. | `ps1p`; SC3 | decided with SC3 (3D, not pixel) |
| R4 | Motifs are the prompt's own (wedge mark, bell, envelope, pigeon, absurd doors). The witch's moon and star stay on her costume. | `ps1p`; `03` | candidate |
| R5 | Subtle dithering is allowed. The dusk gradient of `02` is a sample only. | `ps1p`; `02` | candidate |
| R6 | Characters are readable at about 100 px. | `03`; repo tests | candidate |

Measured on the hall sample (`01`, `tools/visual_gauntlet/metrics.py`): median luma 0.155, 99th percentile 0.636, mean
saturation 0.585. These describe the demo scene, not the style.

## Conflicts and decisions

- **SC1. The interface.** Confirmed 2026-10-14: diegetic only, with paper-strip choices, a subtitle box with an arrow,
  and one satchel. This matches the prompt's own UI rule. See `docs/design/NAVIGATION.md`.
- **SC2. Which witch. Interim: orange (`03`).** The user prefers blonde (`04`); the final choice is made at DESIGN-FREEZE.
- **SC3. Rendering family. Decided: 3D, not pixel art.**
- **SC4. Setting. Not canon.** Decided by NQ-g, not by the references.
- **SC5. Characters: crude toys or clean faceted?** The prompt says characters are carved wooden toys and not polished
  indie 3D. The sheet (`03`), the character bar, is clean faceted low-poly. The environments follow the prompt. The
  characters follow the sheet unless decided otherwise. This decides the character work (E4, REQ-24, REQ-26).
- **The hall sample (`01`).** Papercraft and olive, which the prompt excludes ("NOT papercraft"). The user says it is a
  demo scene. Whether it stays is the HALL decision, deferred to DESIGN-FREEZE.

## Notes for the build

- The avoid list governs generated backgrounds. Runtime UI (the walk ring, the item card) is a 3D object and should not
  glow, so the spirit of "no glowing markers" still applies.
- The painted-room pipeline already runs in this look (`tools/painted/`), so room 2 (decision X9) is planned in it.

## Not decided here

The final look, the final characters, the rooms and their order, and the ending. These are questions in
`docs/design/PREPRODUCTION.md`. The style bible is revised once they are answered.
