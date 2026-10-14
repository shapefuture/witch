# Style bible (draft, from the references)

Status: **draft**. Built from the five references in `docs/art/references/`. Nothing here is final.
Each rule names the reference that supports it. Anything marked SC-n is a conflict that needs a decision
before the style is locked (decision STYLE-LOCK in `docs/design/PREPRODUCTION.md`).

## Already settled by the repo (not by the references)

- Rooms are pre-rendered plates over a low-poly proxy, so actors are occluded correctly. Characters are
  real skinned 3D models. Shading is PSX-style (`CLAUDE.md`, art rules).
- The camera is bolted, and shot changes are cuts.
- No 2D UI. Speech, options and the pause menu are 3D slabs (`game/ui/`).
- All player-visible text is Russian, in `data/text/ru.json`.

## Rules drafted from the references

| id | rule | source |
|---|---|---|
| R1 | Base palette is olive, khaki and sepia with purple accents (orbs, carpet, hats, cloaks). Measured in the hall: mean saturation 0.585, 45% olive-gold pixels. | 01 (measured with `tools/visual_gauntlet/metrics.py`), 02, 03 |
| R2 | Low key with one warm source. Median luma 0.155, 99th percentile 0.636, and under 1% of pixels above 0.75: the light is felt, not blown out. | 01 (measured), 05 (lantern) |
| R3 | Surfaces are faceted low-poly, with soft gradients across the larger facets (facet gradient 0.85 measured in 01). | 01, 03 |
| R4 | Motifs: crescent moon and star for the witch's world; the eye glyph for the archive; keys with eyes as a recurring object. | 01, 03, 04, 05 |
| R5 | Outdoor scenes use a dusk gradient (purple above, orange at the horizon) and ordered dithering on water. | 02 |
| R6 | Characters are readable at about 100 px: the witch's hood, the raccoon's hat and the cloak's silhouette carry identity. | 03 (the sheet's own camera distance, from `docs/art/characters_*.md`) |

## Conflicts (decide before STYLE-LOCK)

- **SC1. HUD counters in 02.** The river scene has two numeric overlays, "U/0" top right and "I0" bottom right.
  This conflicts with the no-2D-UI rule. Options: keep the rule and drop the counters; or change the rule
  and allow diegetic counters on the boat or the frame.
- **SC2. Which witch.** 03 has orange curls, flowers and a bird on her wrist. 05 has gold braids, a gown and a
  pink star wand. 04 is blonde. 02 has brown-gold hair in a boat. One canonical design is needed; the
  characters docs (`docs/art/characters_witch.md`) build on 03.
- **SC3. Rendering family.** 01, 02 and 03 are 3D with faceting or dithering. 04 and 05 are pixel-art
  illustrations with a visible pixel grid. The repo's architecture (3D plates, 3D actors) follows 01 to 03.
  Choosing 04 or 05 as the look would change the architecture, not just the palette.
- **SC4. Setting.** 01 is the archive hall. 04 is a hotel lobby. 02 is a river with a crowned frog. 05 is
  ruins at night. Which of these are places in the game is a narrative question (`PREPRODUCTION.md`).

## Not decided here

The final look, the final characters, the rooms and their order, and the ending. These are questions in
`docs/design/PREPRODUCTION.md`. The style bible is revised once they are answered.
