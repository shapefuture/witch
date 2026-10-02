# Scenes: the plan from the game draft, and the factory that makes them

> **The recipe** (chosen by the user from the comparisons in `docs/art/model_comparison.md`, run r6): **Marketing Studio** (`--model marketing`),
> a **grey layout guide** (the brief's `layout`), the **master prompt with nothing forbidden** (`--style ps1p`), and **no style-reference picture**
> (a reference leaks its objects into other scenes). It is the default of `new_scene.py`. Result: every element placed where the guide puts it, a rich
> painterly look on faceted low-poly geometry. A scene built over an existing one needs `--force`. A brief with no `layout` is generated without a guide,
> which is weaker: give each brief a layout first (only `shop` and `garden` have one so far).

The painted-room pipeline (`docs/art/painted_room.md`) is not only for rooms. `tools/painted/new_scene.py` turns a **brief**
(`tools/painted/scenes/<id>.json`) of a **kind** (`tools/painted/scenes/kinds.json`) into a playable scene under `assets/painted/<id>/`.
This file is the scene plan taken from the "selected narrative build" draft (the user's own file; it is not committed because
it holds Russian phrases, and Russian text lives only in `data/text/ru.json`), and the rules of the factory.

## Kinds

| kind | what it is | horizon | light | beam | notes |
|---|---|---|---|---|---|
| `interior` | a room seen from its entrance | 0.62 | the brightest source in the picture | yes | the hall, the chamber, the shop, the house |
| `street` | an outdoor lane or square | 0.60 | fixed, a low dusk or a night (the sky is not a lamp) | no | lanterns and lit windows become glow lights |
| `garden` | an enclosed outdoor space | 0.60 | fixed, late afternoon | no | |
| `cellar` | a low vaulted room, lit by lamps | 0.62 | fixed, overhead and faint | no | darker detection thresholds; a heavier frame |
| `threshold` | the edge of the world, fog | 0.58 | fixed, low | no | a pale frame; one point of light |
| `firstperson` | eye height behind a counter, out through a window | 0.52 | fixed | no | no characters, no walkable ground |

A kind sets: `composition` (how the place is framed, appended to the prompt), `palette`, `horizon`, `floor` (where the bare ground is, for
the metric calibration), `actors` (where the witch and raccoon stand, as a fraction of the way from the horizon to the bottom), `sun`
(`source` in the picture, or a `fixed` direction), `beam`, `life` (what counts as a lamp) and `frame` (the dark foreground frame). A brief
may override any of these (the festival is a street with a night palette and a different light). To add a kind, add an entry
and a brief using it; `python tools/painted/test_new_scene.py` checks both.

## Briefs, from the draft

| brief | kind | the scene in the game | variants (a state of the world) |
|---|---|---|---|
| `shop` | interior | where the loop lives: a crowded shop whose objects answer every click | `quiet`: the magic gone, as a material change (cloudy jars, dull herbs, bare shelves), not a grey filter |
| `shop_window` | firstperson | the first-person scene: a visitor seen through the shop window, a wand in hand (the hand is an overlay) | |
| `street` | street | the town, at dusk: its people adapt when the magic goes | `quiet`: weeks later, her shop dark, a new bright shop across the way |
| `garden` | garden | the past made physical: one kind of flower, in tidy places; never explained | |
| `cellar` | cellar | the descent: the Shadow's gifts laid out; the evidence is obvious and nothing is labelled | |
| `fog_edge` | threshold | the ending: a dead flower, the fog, the light bending wrong | `open`: the flower opens in a third colour (gold); the world otherwise unchanged |
| `festival` | street | the Night of Returning: a once-a-year procession, glyphs and lanterns | |
| `house` | interior | her home | `after`: the same house vibrant and full of fun, explored when she is gone |

Run `python tools/painted/new_scene.py --list` for what is built. `--all --budget 1.0 --variants` builds the rest: each picture is
about USD 0.09, so the whole plan is under USD 1.

## What the draft rules mean for the plates

Encoded in every prompt (`new_scene.STYLE`, checked by the tests): faceted low-poly papercraft with a broken-PS1 geometry, no black outline
or inked edge, horizontal 16:9, no text or letters (glyphs and symbols are fine: Kabbalah, alchemy, cuneiform and Greek mythology symbols,
never real writing), and **nobody in a plate**: the witch, the raccoon, the Shadow, visitors and citizens are actors in the engine. The
palette follows the draft's colour soul (autumnal melancholy, moss, dusky blue, plum shadows, warm lamplight) and each kind adds its own.
A variant keeps the camera and the layout and changes only the world's state, so a magic loss or return is a change of material in the
same place; the game switches between a scene and its variant as it would between two states.

Not the factory's work (and not yet built): the fisheye camera and its roll (engine, `docs/art/compositor.md`), the first-person hand and wand
overlay, props and their reactions (`tools/painted/lift_prop.py`), the doorways between scenes, the Mirror room ids and the
text keys (`data/mirror/`, `data/text/ru.json`), and the characters. The kinds say where the witch and raccoon stand only so a built scene
can be looked at.

## Looks (styles)

`--style NAME` picks a look from `tools/painted/scenes/styles.json`. A scene in a style other than `hall` is built into `<id>_<style>`.

- **`hall`** (default): the papercraft look of the first painting; the hall plate is the style reference.
- **`ps1`**: the *master prompt v3.0* of the game draft (THE WITCH, a fictional 1997-2002 point-and-click game): catastrophically crude
  early 3D, **not** papercraft, jewel-toned theatrical palette (cobalt and plum shadows, never gray; turquoise and teal ground; amber light),
  barrel curvature inside the geometry, no vignette or screen frame, the avoid list and the recurring motifs. The blocks are the draft's own
  words; the template is its section XII. No reference picture is used (text only), the closing-in dark frame is switched off, and the
  template's character blocks are replaced by a request for clear floor, because the witch and raccoon are engine actors. A brief adds
  its own `styles.ps1` entry (`title`, `prompt`, `ui`, `motifs`, `palette`); without one the brief's plain prompt is used.

```sh
python tools/painted/new_scene.py shop --style ps1 --godot $GODOT      # assets/painted/shop_ps1/, about USD 0.08
```

`shop_ps1` is the first scene in this look: a shop that is bigger inside (a staircase that climbs the wall to a small door in the ceiling,
a pigeon with a package, a badger coming up through the floorboards, a frog in a teacup, a brass bell, a sealed envelope, blank tags knotted
to objects as the scene's diegetic interface). The generator reads the look as hand-painted and fairly polished rather than truly crude;
the engine's own PSX pass (affine mapping, snapped vertices, dither) supplies the crudeness. The fisheye barrel is in the picture, so the
flat-lens depth calibration is a little off near the edges.

## Layout guides: directing what goes where

A generator told only "a shop with a window and a counter" chooses the composition itself. `tools/painted/scene_layout.py` draws a **layout
guide**: a white canvas with grey labeled boxes and shapes (each label starts with its depth, `FG` / `MID` / `BG`), a pale `GROUND` box
that must stay empty, and a dashed horizon. A brief carries its `layout` (fractions of the frame); `new_scene.py` renders it, sends it as the
first reference with a note on how to read it, and afterwards writes `build/rooms/NAME/layout_check.png`, the guide's outlines drawn over the
result, so a misplacement is seen at once. The layout is kept beside the scene as `layout.json`.

```sh
python tools/painted/new_scene.py shop --style ps1 --layout-only    # render the guide, free: look at it first
python tools/painted/new_scene.py shop --style ps1                  # generate with the brief's layout (--no-layout to ignore it)
python tools/painted/new_scene.py shop --layout my_layout.json      # or your own layout JSON, or your own guide PNG
```

Lessons from the shop:

- **Guides must be grey.** A first guide with red, blue and yellow boxes put red, blue and yellow gems all over the floor; the generator
  echoes a guide's colours as objects. The guide is grey, and depth is a text tag.
- **A guide pulls the look toward "cute modern 3D"** (pastel gems, toy-like): the style then needs an anchor. `styles.json` gives `ps1` an
  anchor picture (`tools/painted/scenes/anchors/ps1.jpg`, the first accepted picture in that look) sent as the second reference, with a note
  to match its palette and rendering but not copy its objects. With guide and anchor the shop kept its jewel-dark look and most placements.
- Placement is followed approximately, not exactly: expect most elements within a box's width, a few moved or mirrored. Check the check image.

## Which model follows our guidance? (`compare_models.py`)

`tools/painted/compare_models.py` runs the shop through many models on the same guidance (the master prompt's style block verbatim, trimmed
only where a model's prompt limit forces it; the layout as a guide image or as words; **no style anchor**, so each model's own reading of the
style), caps the spend as a whole, and scores blind: critics who see neither the layout nor the model locate each named element and answer a
checklist, and `layout_score.py` compares their boxes with the layout (placement, presence, overlap) and tallies guide leaks, text, people,
objects on the empty ground, crude-3D, jewel palette and "cute modern". Results are in `docs/art/model_comparison.md`.

```sh
python tools/painted/compare_models.py plan                 # the runs and estimated prices (free)
python tools/painted/compare_models.py run r1 --budget 1.0  # generate (paid); a finished run is recovered, never paid twice
python tools/painted/compare_models.py blind r1             # anonymised copies and critic instructions
python tools/painted/compare_models.py score r1 a.json b.json
```

## The positive-only master prompt (`ps1p`)

A prompt that says what *not* to draw can make a model draw it, and a guide image's "do not copy" can read as "copy". `ps1p` in `styles.json` is the
master prompt with every instruction about what NOT to do removed or turned positive: no "NOT papercraft" sentence, no avoid list, no "no outline,
vignette or bloom", no "never gray", no "no people, no text" (an empty scene is asked for as "a large open stretch of empty ground"), and the
layout-guide and style-reference notes reworded the same way (`compare_models.py`). What it asks for is unchanged. A test fails if a `ps1p`
prompt contains no / not / never / without / avoid / nothing. A brief may give a `styles.ps1p` entry (otherwise its `ps1` entry is used).

On the garden scene (run r6 of `docs/art/model_comparison.md`), against the original house prompt on the same guide:

- **Grok with the engine-render reference**: the reference's dark pillars and purple crystal, which had leaked into the picture, were gone; the
  look became crude and chunky (faceted-ball foliage, a polyhedral roof, pyramids and cones scattered on the ground), every labeled element was
  placed, and the ground gained scattered pyramids.
- **Marketing Studio, guide only**: every element of the guide in its place (pear tree, bench, wall and gate with a small bell, lantern post, house,
  sundial, raised beds with blank tags knotted to the flowers, wheelbarrow, watering can), a clear gravel path, golden-hour light; a rich
  painterly look with faceted textures, less crude than Grok's.
