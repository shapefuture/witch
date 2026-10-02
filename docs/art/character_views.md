# One picture of a character to six views (for image-to-3D and rigging)

`tools/characters/multiview.py`: one generation draws all six views on one sheet, then a free crop cuts them out. Tests: `python3 tools/characters/test_multiview.py`.

```sh
python tools/characters/multiview.py guide out.png --pose t     # the guide, free: look at it first
python tools/characters/multiview.py make witch --ref front.png --pose t     # one paid call, then the crop (chroma-key green by default; --key white)
python tools/characters/multiview.py make fox --text "a fox in a red coat, faceted low-poly"   # words only
python tools/characters/multiview.py crop sheet.png --out DIR     # a sheet made anywhere (no cost; the matte follows its own background)
```

Output in `build/views/NAME/` (git-ignored): `sheet.png`, `views/<view>.png` (transparent), `white/<view>.png` (on white),
`contact.png`, `sheet_boxes.png` (the boxes it found, over the sheet), `views.json` (boxes, problems, cost, prompt), `job_views.json`.
The six views, in the sheet's reading order: `front`, `front34`, `right`, `back`, `back34`, `left`. Names say where she FACES in the picture
(`right` = she faces the right edge, so we see her right side). Every output is square (`--size`, 1024), the figure the same height (84 %) and centred.

## What the pipeline does and why

1. **A guide, as the scene factory does** (`scene_layout.py`): a canvas of three columns by two rows (3:2, so every cell is square), one framed
   cell per view with its label, a head line, a foot line, a centre line and the symbol for the way she faces (dot = toward you, cross = away,
   arrows). It goes to the model as the FIRST reference, the character as the second, and the prompt says how to read it. The lines are the
   background colour darkened, never a new colour (a model copies a guide's colours as objects). `--no-guide` describes the grid in words only.
2. **`--key green` (the default; `white` for a character with green in it)**: the guide's canvas, the prompt and the matte all use a flat chroma-key green. Against white a pale pixel of the figure
   (a bird's breast, a silver moon) and a hole of background (inside a hair curl) look alike, and the first witch run left a white blob in a curl.
   Against a key every key pixel is a hole, wherever it is, and keyness (the green channel over the other two, as a share of the background's) is
   measured, not distance from one colour: the key between hair curls is shaded darker than the rest and still counts. The edge is despilled.
   Pick a key the character lacks: green for the witch; a green character would need another one (the code has green and white only).
3. **`--pose t` / `a`**: T-pose or A-pose for auto-riggers (Mixamo, Meshy, Tripo): arms straight out or angled down, hands open and empty, head
   forward, legs straight. What she held is left out of the pose (the witch's wand and bird are not in her hands: they become separate pieces).
   The T guide has a dashed shoulder line so the span of the arms stays in its cell. `keep` (default) keeps the reference's pose.
4. **The crop** (free, any sheet): a figure is what differs from the background; thin things (frame lines, label strokes) are dropped; nearby
   parts merge (wand, curls); each group goes to the cell its centre is in. Problems are printed and never hidden: an empty cell, a figure cut by
   the sheet's edge or spilling into the next cell, two figures in a cell, a view much bigger or smaller than the rest (still scaled to one
   height), a background that is not the one asked for.

## The test: the witch from the user's own picture (Marketing Studio 2k, medium, 3:2; about USD 0.10 each)

| Run | Result |
|---|---|
| white, her own pose | Six consistent views on the first try: same face, flowers, hair, skirt, the wand and bird on the same sides in every view (wand seen from the right, bird from the left). The 3/4 views were only turned about 20 degrees. The cut-out left a white blob in a hair curl. |
| green, her own pose | Same, on green. The matte first read the shaded key between curls as figure (green specks): fixed by measuring keyness. A handful of pixels (the olive sprig, the plume) stay greenish because they really are. |
| green, T-pose | Arms straight out, hands empty, boots, wand and bird gone; the arms and hands stay inside their cells. Good rigging input. |
| green, T-pose, stricter 3/4 wording ("a full 45 degrees, half way between ...") | The 3/4 views are clearly turned now. This wording is the default. |

Not tested: feeding the six views to an image-to-3D tool (this account's Higgsfield catalog has none; use the files in whichever you have).
What the picture does not show (her feet, the back of the vest) the model invents, and it invents differently on each run (boots in one
run, buckled shoes in the next): if the invented parts matter, keep one run and re-crop it, do not regenerate.

## Limits

- The views are painted, not rendered: they agree on the design, not to the pixel. Counts of up to about 3 % in height between views are
  normal (the crop equalises them); a view with a visibly different design or pose is a bad run: regenerate that sheet.
- The side views are not exact profiles and the 3/4 views not exact 45 degrees; image-to-3D tools tolerate it, a multi-view reconstructor
  that wants exact azimuths may not.
- One key colour only (`green`); `magenta`/`blue` would need their own despill.

## Next stage

`docs/art/image_to_rig.md` (`tools/characters/image2rig.py`): the four canonical views to a 3D mesh, a rig and parts on free Spaces and Tripo, with the witch's results (the geometry is good; the textured and rigged results are not as good as our own `witch.glb`).
