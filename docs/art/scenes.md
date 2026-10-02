# Scenes: the plan from the game draft, and the factory that makes them

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
