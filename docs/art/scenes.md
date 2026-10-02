# Scenes: the plan from the game draft, and the factory that makes them

> **The recipe** (chosen by the user from the comparisons in `docs/art/model_comparison.md`, run r6): **Marketing Studio** (`--model marketing`),
> a **grey layout guide** (the brief's `layout`), the **master prompt with nothing forbidden** (`--style ps1p`), and **no style-reference picture**
> (a reference leaks its objects into other scenes). It is the default of `new_scene.py`. Result: every element placed where the guide puts it, a rich
> painterly look on faceted low-poly geometry. A scene built over an existing one needs `--force`. A brief with no `layout` is generated without a guide,
> which is weaker: give each brief a layout first (only `shop` and `garden` have one so far). A layout can also mark its objects as **toys**
> (`"toy": "<type>"`): the same run then makes them poke-able, with one extra editing call that also measures the lighting (see Toys, below).

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

## Toys: making a scene's objects alive (`toys.py`)

The hall's objects answer a poke (`docs/art/painted_room.md`, Toy box); `tools/painted/toys.py` does the same for any generated scene, from its layout.

1. **Mark the objects.** A layout element gets `"toy": "<type>"` (types of `tools/painted/scenes/toys.json`: lantern, sundial, wheelbarrow, watering_can,
   bell, teapot, bag, creature, crate for objects that come off; bench, tree, window, gate, plants, thing for things that stay put), optionally `"toy_at"`
   (the object's own box, when the element is bigger than the object, as a tree is bigger than a bench under it) and `"toy_note"` (where it is, for the prompt:
   "hanging in the arched gate"). A type fixes how the object is cut (`cutout`: lifted onto a card that moves; `hotspot`: nothing moves, the painting itself
   ripples, shakes or flashes), its noun for the prompt, the point a cutout turns about (`base`, `top`) and its answers to successive pokes (words and sounds
   the engine already has; no line of text, since a text key would need Russian in `data/text/ru.json`).
2. **One edit.** `toys.py` sends the plate to **Marketing Studio** (always: it is the editor that keeps the frame registered; Qwen's larger edits stretched it
   1.6 %) with one positive instruction: the cutout objects "taken away" (each named by its noun and place in the picture) and, in the same picture, the two
   calibration spheres of `sphere_probe.py` on the layout's open ground. About USD 0.056, and the lighting measurement costs nothing more.
3. **Lift what changed.** For each cutout, the pixels the edit changed inside its box (the box searched 8 to 16 px bigger, since the generator puts things where it
   likes) become its mask, with three guards. Objects that stand on the ground are kept only where the room's calibrated depth puts them above the floor
   (`RAISED` 0.08 m): the edit redraws the gravel behind a removed wheelbarrow, so its change alone would take the gravel with it. The two spheres are painted
   back to the plate before anything is read. A card is at one depth, so its depth is set from its nearest pixels, else a long object's near corner would
   sit behind the room's own mesh and show the ground (the wheelbarrow did).
4. **What does not come off becomes a hotspot** with the same answers: an object the edit left alone (under 12 % of its box changed), a mask that is not object-sized,
   a mask that fills its whole window (the edit redrew everything around it: the garden's bell, whose gate was redrawn), or any edit that is not registered to the
   plate (more than 2.5 px off). The report says which and why; `build/rooms/NAME/toys/toys_preview.png` draws every box and mask over the plate: a box that sits off
   its object is moved by editing `toy_at`, then `--toys-only --edit <the same picture>` is free.
5. **Checks.** `toys.py check ROOM` (and `tools/painted/test_toys.py`, offline) verify the toy box the way the engine does: vocabulary and sounds exist, cards sit on the
   mesh grid, masks match their rects, `plate_empty.png` is the plate bit for bit outside every mask. `tests/render/test_painted_generated_toys.gd` runs every
   generated room's toys in the engine (a tap inside answers, plays a sound, moves, comes to rest; a second poke answers differently). `capture_painted.gd ... toys`
   joins every reaction into one sheet per toy (`build/rooms/NAME/toys_sheets/`).

```sh
python tools/painted/toys.py prompt garden                      # the toys the brief marks and the edit's prompt (free)
python tools/painted/new_scene.py garden                        # a new scene: generate, then ONE edit for toys + spheres, lift, light, capture (--no-toys to skip)
python tools/painted/new_scene.py garden --toys-only            # add the toys to a scene already built (about USD 0.06; the lighting is kept)
python tools/painted/new_scene.py garden --toys-only --edit P   # ... from a picture that edit already made (free)
python tools/painted/toys.py check assets/painted/garden        # the toy box's invariants
```

The garden got eight toys: a lantern, sundial, wheelbarrow and watering can lifted as cutouts, and the bell, the pear tree, the bench and the lit window as
hotspots. Known limits: where the edit also redraws what surrounds an object (grass beside the wheelbarrow, flowers beside the sundial) a little of it comes along in
the card, since a pixel's colour cannot tell the two apart (a colour test against the ring around the box was tried and rejected: most objects share colours with their
surroundings); the toys of a scene built from a new picture rest on the guide's boxes, which the generator only roughly follows (read the preview, move `toy_at`);
a hotspot is a rectangle or ellipse of the painting, not the object's outline.

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
