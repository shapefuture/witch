# Style bible (draft)

Status: **draft, revised 2026-10-14** after the user's notes. Built from the five style references in
`docs/art/references/`. Nothing here is locked. The user says the olive palette is one sample scene, which may not be
in the final game, so no palette is the base.

Each rule names the reference behind it. "Candidate" means a rule that is only a candidate; "decided" means settled.

## Already settled by the repo (not by the references)

- Rooms are pre-rendered plates over a low-poly proxy, so actors are occluded correctly. Characters are real skinned
  3D models. Shading is PSX-style (`CLAUDE.md`, art rules).
- The camera is bolted, and shot changes are cuts.
- Text is Russian only, in `data/text/ru.json`.
- No 2D HUD. The interface is diegetic: strips, a satchel, a subtitle box (SC1, `docs/design/NAVIGATION.md`).

## Decided

- **SC3. Rendering family: 3D, not pixel art (decided 2026-10-14).** The pixel-art look of 04 and 05 is out.
  A dither texture effect (as in 02) stays open, as long as the scene still reads as 3D.

## Rules (candidates, not locked)

| id | rule | source | status |
|---|---|---|---|
| R1 | Palette is not locked. The olive and purple of 01 is one sample scene, not the base. | 01 | candidate; sample only |
| R2 | A single warm key light is a candidate for any scene (01's shaft of light, 05's lantern). | 01, 05 | candidate |
| R3 | Surfaces are faceted low-poly 3D, with soft gradients across the larger facets. | 01, 03 | decided with SC3 |
| R4 | Motifs for the witch's world: crescent moon and star (03, 04, 05). Keys with eyes and the eye glyph are not motifs. | 03, 04, 05 | candidate |
| R5 | Outdoor scenes may use a dusk gradient (purple above, orange at the horizon) and dither on water. | 02 | candidate; sample only |
| R6 | Characters are readable at about 100 px: the witch's hood, the raccoon's hat and the cloak's silhouette carry identity. | 03; repo tests | candidate |

Measured on 01 (`tools/visual_gauntlet/metrics.py`): median luma 0.155, 99th percentile 0.636, mean saturation 0.585.
These describe that sample scene, not the style.

## Conflicts

- **SC1. The interface (river counters in 02, and the other references).** Recommendation, awaiting the user's
  confirmation: no numeric counters and no sidebar. Choices are paper strips (06); the subtitle is a dark box with an
  advance arrow (09); one satchel opens as a letter cabinet for knowledge, inventory and objectives. Declined: the
  bubble bar (08), the sidebar (10), the card tray (07). Full reasoning in `docs/design/NAVIGATION.md` section 3, with
  the screenshots in `docs/design/ui_references/`.
- **SC2. Which witch. Interim: orange (03).** The sheet's witch is used for work now. The user prefers blonde, as in
  04, and the final choice is made at DESIGN-FREEZE. The gold-braided gown (05) is a style reference only.
- **SC4. Setting. Not canon.** The user says none of the settings in the references is canon: the archive hall (01),
  the hotel (04), the river (02) and the ruins (05). The narrative decides this (NQ-g).

## Open question for the hall

The archive hall is the built scene, and `CLAUDE.md` calls it the first scene and says not to invent another. The
user says the olive hall may not be in the final game. Decision **HALL** (in `docs/PLAN.md`) decides whether the grade
and geometry work (G1, G3, G4) continues. Until then, that work is held.

## Not decided here

The final look, the final characters, the rooms and their order, and the ending. These are questions in
`docs/design/PREPRODUCTION.md`. The style bible is revised once they are answered.
