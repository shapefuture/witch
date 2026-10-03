# Which result is best for the game: the evidence

Everything compared here was rendered **by the game**: `tools/characters/capture_candidate.gd` loads any `.glb` from disk and puts it in as the witch in the painted room and in a studio, through `CharacterModels`, the PSX actor shader, the room's lights and its shadow
(no change to `assets/`). `tools/characters/eval_sheet.py` lays the captures out. Figures: `docs/art/cpu_rig/eval/eval_game.png` (the room frame), `eval_studio.jpg` (front, back, three-quarter, wand arm raised, under the neutral white key of `capture_witch.gd`),
`same_file_three_renderers.png`. The target is the user's original witch picture (the first column; it is not in the repo).

## First: why the summary picture made her look worse than she was

`build/rigs/witch_summary.png` drew the shipped `assets/characters/witch.glb` with `image2rig.py preview`, which then coloured **one flat colour per triangle, sampled once from the atlas at the triangle's centre**. Her face, eyes, flowers and the
moons and stars are drawn in the 256 px atlas, not in the geometry, so a triangle swallowed them: a mushy brown face and a few giant gold triangles instead of crisp decals (row A of `same_file_three_renderers.png`). The file did not change: its SHA-256 is that of
its last commit (`f40f8f5`, 2 October 15:57; the first image-to-3D commit, `8609314`, is at 21:36), and the game renders it as before (row C). The summary also labelled the row "9k triangles" (it has 6,164), and a later change of mine to the previewer, which read vertex colours (`COLOR_0`) instead of multiplying them into the texture, drew this file plain grey. Both previewer faults are fixed in `image2rig.py preview`: the atlas is sampled per pixel and multiplied by the vertex colour (row B), with a test. **That row, and any judgement made from it, is superseded by this page.**
The mistake also tilted the comparison: the generated meshes carry their detail in dense geometry, so the old previewer flattered them and punished the hand-built asset.

## What the game needs, from first principles

The camera sees the witch **from behind at about 100 px** on a 480 x 360 viewport (`tests/render/test_character_models.gd`: "the width and the palette are the checks that matter"). At that size what carries identity is the **silhouette** (the hood's peak, spiral curls
standing out to both sides, a flared star skirt), a few **colour blocks** (purple, gold-orange, pink) and one or two props. A face, a surface texture or the stitching of a pocket is below the pixel. The budget is 9,000 triangles, two surfaces, a 256 px atlas and a
fixed skeleton with the game's bone names, so the clips play. A candidate is good if it reads like the painting in the room frame and costs little to make; fidelity in a studio render is a second-order matter.

## The measurements (the game's own renderer; the repo's own look test)

| Candidate | Cost | Triangles, bones | Plays the game's clips | Width, idle, from behind (the test wants 0.90 to 1.15 m) | Bind depth (0.70 to 1.00 m) | Palette texels: orange / purple / pink (test: over 100 / 1,000 / 8) |
|---|---|---|---|---|---|---|
| **shipped `witch.glb`** (hand-built kit, painted references) | hours of authoring, once | 6,164, 22 | yes | **0.92** | **0.88** | **1,279 / 24,618 / 128** |
| CPU Hunyuan int8, 3 steps, + `template_rig` | USD 0.10 sheet, 211 s CPU | 9,000, 21 | yes | 0.84 | 0.63 | 940 / 527 / 0 |
| CPU Hunyuan fp32, 5 steps, + `template_rig` | USD 0.10, 809 s CPU | 8,998, 21 | yes | 0.81 | 0.63 | 739 / 364 / 1 |
| **Tencent paid texture** (on the Hunyuan shape) + `template_rig --textured` | USD 0.10 sheet, Space quota, Tencent texture credits | 9,000, 21 | yes | 0.80 | 0.60 | 44 / 1,556 / 0 |
| Tencent as delivered (`lowpoly_bake`) | as above | 9,000, none | no (static T-pose) | n/a | n/a | n/a |
| silhouette hull + `template_rig` | USD 0.10, 10 s | 9,000, 21 | yes | 0.77 | 0.56 | 723 / 2,206 / 2 |

Widths are the silhouette of the studio back view in the idle pose (720 px = 1.45 m); the palette counts use the thresholds of `test_the_witch_has_the_new_references_proportions_and_palette` on each file's atlas. **Only the shipped witch passes all of the repo's own width, depth and palette checks.** Every generated candidate is 9 to 16 % narrower than it (0.77 to 0.84 m against 0.92, under the test's 0.90 m floor: the curls do not stand out),
0.25 to 0.3 m shallower (the skirt does not flare), and short on palette: orange passes only for the CPU meshes (the Tencent texture has 44 texels), purple only for the Tencent texture and the hull, pink for none (the flower crown is too muted to count), and no candidate
has more than a tenth of the shipped witch's purple (24,618 texels). The diffusion textures are muted and the projection averages views.

## What the screenshots say

* **In the room frame (`eval_game.png`) the shipped witch is the only one that reads as the painting**: a peaked purple hood with stars, a band of golden curls with spirals standing out left and right, a flared skirt with moons and stars. The generated ones read as
  "a figure in a purple robe with a golden mass behind it": the hood is a dull cone, the curls are gone, the skirt pattern is mud. At 100 px the face, which is what the generators got right, is not there to be seen.
* **Studio (`eval_studio.jpg`)**: the shipped witch has the wand, the bird, the pockets with their contents and the flower crown, all in the painting; none of the generated ones has a prop (the T-pose sheet was drawn without them on purpose). The generated faces are recognisable,
  and the paid Tencent texture is clearly the best of them: clean curls, a face with blue eyes, the necklace. The free CPU meshes have frayed, tangled hair that tears when the arm swings (the cast frame), a soft pixelated face, and a muddier palette; fp32 5 steps is not visibly better than int8 3 steps.
* **The hull** (an X across the chest, a smeared back) is a blockout and nothing more.

## What was best

| Question | Best result | Evidence |
|---|---|---|
| The witch the game ships | **the hand-built `witch.glb`**, unchanged | passes the repo's look test; the only one that reads in the room frame |
| Best generated look | **paid Tencent texture on the Hunyuan shape, our skeleton on it** | cleanest face, hair and trims in the studio; still fails the width, depth and palette checks |
| Best free route | **Hunyuan3D-2mv-turbo on the CPU, int8 + FlashVDM, 3 steps (211 s)** | visually level with fp32 at 809 s; silhouette IoU 0.866 against 0.870 |
| Best way to rig a mesh | **`template_rig.py`**: the game's skeleton fitted to the T-pose, distance skin weights | gate passes (Godot 4.6.3, 43 suites); plays idle, walk, talk, cast; 8 s, no GPU, no credits |
| Best shape source | Hunyuan3D-2mv (any backend) | the hull is a blockout; a 515k-triangle sculpt is thrown away at 9,000 |
| Dead ends, measured | OpenVINO on the DiT (7 %), pruning background tokens (IoU 0.87 to 0.71), 2 steps, hair skinning by colour, the silhouette hull as a character | `cpu_pipeline.md` |

## What it means for the pipeline

The generators optimise what this game cannot show (a face, a skin of texture) and lose what it can (silhouette features, colour blocks, props). For the witch the answer is to keep the hand-built model. The pipeline earns its place elsewhere:

1. **A placeholder for a character that has no model yet** (Vera, Elian, Ilya): free, three and a half minutes, rigged, on the game's clips, and plainly recognisable as the sheet's character. For a hero, use the paid texture and the same rig.
2. **`template_rig.py` on its own**: it rigs any T-pose mesh onto the game's skeleton, whatever made the mesh (a modeller, the kit, a purchased asset), in seconds.
3. **The next experiment, not run**: restore the silhouette the game reads by taking the body and face from the generator and building the hair, props and hood trim with the kit's own generators (curls, ribbons, the wand), which already reproduce them from the painting (TRIZ: segmentation). The measurements above say exactly what to fix: width, depth and palette.

Limits: one character, one seed per configuration, the lighting of the room's frame (the witch is small and the scene is dim); a human judge of the room frame may rank the generated ones differently from the repo's test. The Tencent rig (10 credits) was delivered earlier but not run through the game.
