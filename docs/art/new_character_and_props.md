# A new character and four props from the pipeline (Vera, and a cauldron's family)

All of it generated here from text and the style of the user's two pictures (the cast sheet and the prop picture): `multiview.py make --style ... [--kind object]`, then the free CPU shape (`hunyuan_cpu.py batch`, int8 + FlashVDM, 3 steps), then `template_rig.py` (character) or `prop_bake.py` (props).
Game-renderer evidence: `docs/art/cpu_rig/new/vera_game.png` (studio front, three-quarter, back, wand arm raised, then the room frame at game resolution), `props_game.png`, `vera_dense_vs_shape.png`.

## What was made, and what it cost

| Thing | Sheet (paid) | Shape (free, CPU) | Result |
|---|---|---|---|
| **Vera**, an apothecary: green apron-dress to the ground, purple shawl, red headscarf, braids, a bandolier of bottles. **An invented design**: the repo names Vera, Elian and Ilya (docs/ARCHITECTURE.md) but describes none of them | USD 0.108, T-pose, legless, green key, the cast sheet as style reference; no crop problems | 206 s, 57k faces | 9,000 triangles, one 256 px atlas, 21 bones, the game's four clips (`docs/art/cpu_rig/new/vera_rigged.glb`) |
| Cauldron, mortar and pestle, ceramic jug, barrel | USD 0.103 each, the prop picture as style reference | about 200 s each | 1,498 triangles, one 128 px atlas, one surface each (`.../new/props/*.glb`) |

Total spend USD 0.52. Model load was 658 s the first time (cold disk), 100 s warm.

## Props: this works

Judged in the game's PSX shader under the neutral key, the props read as the objects and as the family of the user's prop picture: the jug's cork, the paper label tied on with string and the loop handle; the barrel's planks and three iron hoops; the cauldron's hexagonal rim and its ring handle; the mortar's bowl and tilted pestle.
Silhouette overlap with their own views is 0.81 to 0.93. Weaknesses: thin parts are the first to go (the cauldron's side rings are stubs and a few stray shards), the mortar's pestle leans differently in each generated view so the shape averages it, and the 128 px atlas leaves about half its texels unused (xatlas). The pale halo round every silhouette is the shader's rim light, not the mesh.
A prop costs USD 0.10 and under 4 minutes of CPU. Not run: putting them in a scene next to the existing props; there is no prop test, so the 1,500 triangle / one surface / 128 px defaults of `prop_bake.py` are mine.

## Vera: placeholder grade, and the reason

In the room frame she reads as a red scarf, a purple shawl and an olive dress, which is what her sheet makes of her at 100 px. Close up, her face is a smear and the skin tones are washed, a few red shards float beside her, and the hair knot is lost. `vera_dense_vs_shape.png` finds the cause:
the Hunyuan shape (bottom row) is good, with sleeves, hands, scarf and the bandolier's bumps in place; the paint on it (top row) is where the face goes soft, because **her face is only about 70 px across in a 1024 px view**, and the shape's face is lumpy. More triangles or a bigger atlas would not help: the pixels are not there.
The fix is a face close-up (a separate small generation, or the repo's `face_from_ref.py` and `face_plate.py`, which the witch's face came from) used as a second surface under the game's two-surface budget; `template_rig.py --hold` and the exporter's `extra_prims` already carry a second surface and atlas. Not done.

## Tools added

`multiview.py --style PIC` (extra reference: the rendering style only) and `--kind object` (no pose, "object" wording); `hunyuan_cpu.py batch`; `prop_bake.py`; `capture_prop.gd`; `template_rig.py --hold PROP.glb:BONE:DX,DY,DZ` (a prop carried on a bone as the second surface); `witch_glb.export(extra_prims=)`. Offline tests cover each.
