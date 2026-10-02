# Painted room (experiment)

A painted still made into a room, as an alternative to the Cycles plates (`docs/art/plates.md`).
`game/world/painted/painted_room.tscn` stands alone; nothing else uses it yet.

1. **Plate**: an image edit of the reference removes the characters (`tools/higgsfield`, Qwen Image 3 Edit,
   literal prompt, seed 7; provenance in `assets/painted/hall_clean/job_*.json`).
2. **Depth**: `tools/painted/build_painted.py` runs Depth Anything V2 Small (ONNX, CPU, about 3 s) and
   calibrates it to metres with the reference camera (55 degree lens, eye 1.3 m): the painted witch's
   size agrees within 3 %. The room is a 161x91 grid mesh carrying the painting by screen position, so
   from the painting's camera the frame is the painting. PSX mode: 640x360 texels, snapped vertices,
   affine mapping, 15-bit dither.
3. **Characters** stand on the calibrated floor, lit by `light_map.png` (the painting's floor seen
   from above, blurred) and the beam's colour.
4. **Props** (`props.json`, made by `tools/painted/lift_prop.py`): a second edit removes objects; the
   tool cuts each one out (diff, or a hand lasso with `--ellipse`/`--polygon`) onto a card at its
   nearest depth, and composites `plate_empty.png` behind it. A tap maps screen -> painting pixel ->
   nearest prop -> its next reaction (the vocabulary in the Toy box section); `PaintedRoom.prop_pressed`
   is where Mirror events will hook in. `kind: "hotspot"` (a polygon, no moving part) is supported.

Limits seen in the captures: the camera holds about 15 cm of movement before depth edges smear;
a Dutch roll zoomed in (the painting had no margin: fixed by overscan, below); the 3D characters don't match the painted designs.

Capture frames: see the header of `tools/painted/capture_painted.gd` for the xvfb command.

## Light and life

The painting is a still; `game/world/painted/painted_life.gd` (`PaintedLife`, built by `PaintedRoom` as `room.life`) makes
its own light breathe, with no Godot light and no new art. Everything is data in `assets/painted/hall_clean/life.json`;
every position is a pixel of `plate.png` and the room maps pixels to depth, so a light is one JSON entry:

```json
{"id": "candle_a", "pixel": [855, 226], "radius": 44, "core": 0.2, "color": [1.0, 0.72, 0.32], "strength": 0.3,
 "flicker": {"kind": "candle", "amount": 0.3, "seed": 11, "shift": 0.4}}
```

- **Glow cards** (`painted_life_glow.gdshader`, one mesh, one draw call): a flat card at the lamp's depth (`depth_mode: "near"`
  pulls a bloom in front of its surroundings, as for the oculus), additive, so a nearer prop, character or shelf hides it
  the way it would hide the lamp. Thirteen lights are authored from the reference: the oculus, the four candelabra
  crystals behind the statue, five purple crystal lamps, two arch lanterns, the daylit corridor. Flicker kinds: `candle`
  (short-memory noise with now and then a gutter), `lamp` (slower), `magic` (a slow breath, a rare blink), `breath`
  (the sky: two slow waves); `shift` moves the colour towards red as the light dips.
- **The beam** (`painted_life_beam.gdshader`, one mesh, one draw call): the room's own depth grid, kept only where the
  `shaft` and `pool` polygons say (about 4.5k triangles) and drawn 1.5 % in front of it along the painting's rays, so it
  does not move on screen. One blend_mix pass does the breathing (lit parts of the painting lift towards the beam colour,
  dim towards the shade colour; at level 1 and base 0 the painting is exactly the painting, and the painted blacks stay
  black), the characters' shadow (three spheres each, tested along the ray from the surface to the oculus, so it falls
  towards the camera and the left like the real thing), and the dust motes (one per cell of the 640x360 texel grid at
  most, falling or rising through it and fading at the ends; only where the shaft mask is strong).
- **The frame** (`painted_life_frame.gdshader`, one full-screen multiply below the screen layer): the dark foreground
  closes in a little as the beam swells.
- **The characters** follow the beam: `life_changed(level)` (and `actor_level()`) drives their `light_scale` and
  `sun_color` through the shaders `_light_actor` already feeds; `room.actor_light` / `actor_sun` stay the base.

Time is a clock of `fps` (8) steps a second and nothing reads the real-time clock: the lights change only when a whole
step has passed, every level is quantised to 1/16, and `advance(delta)` / `set_clock(t)` are the only sources of time, so
a capture or a test is repeatable. The shaders band and dither with `painted_screen.gdshader`'s 4x4 Bayer (the glow in 6
bands, the beam in 24 steps of alpha), then the screen layer quantises to 5 bits: nothing is smooth.
`life.intensity` (0 draws nothing at all, the plain room pixel for pixel; 1 is the authored look) and `life.flicker`
(0 holds every light at its base level and freezes the motes) are the two dials, for settings or for a scripted moment.

**Reaction hook**: `room.life.pulse(pixel, color, strength)` flares the light nearest a painting pixel (within its reach)
or strikes a short-lived spark there (six spare slots, the quietest is reused), and returns the id. A flare starts at
`strength` (1 is about as bright as a lit lamp) and keeps 72 % of itself each step, so it is gone in about a second; the
characters catch a tenth of it. Use it from `prop_pressed`, a tap, or a spell. `level_of(id)`, `flare_of(id)`,
`light_ids()`, `pixel_of(id)` read the state. `room.life` is `null` when a room has no `life.json`: guard it.

**Cost** (measured): +2 mesh surfaces (4.5k triangles), +3 draw calls (glow, beam, frame; the plain painted room is 8),
one extra texture fetch and a six-sphere loop per beam fragment (about a fifth of the screen), uniforms refreshed 8 times
a second. `life.cost()` reports the first three.

**Tests**: `tests/render/test_painted_life.gd` (headless: the flicker as a pure staircase, the data, the budget, the
clock, `pulse`, `life_changed`, the occluders) and `tests/render/painted_life_check.gd` (xvfb, hooked into
`render_check.sh`): intensity 0 is the plain room pixel for pixel; at zero flicker the room holds perfectly still, no glow
card draws outside its square, and the beam painted opaque covers every pixel inside its mask (no crack); with the
flicker on the candles and the beam change between frames while a quiet corner stays exactly still; a pulse lights its
lamp and the room returns to the rest picture exactly; the characters' shadow darkens the pool towards the camera.

Limits: a prop that moves (the statue's shiver) does not carry the beam with it; the beam is an overlay on the
painting's surfaces, not a volume, so it has no parallax of its own; `life.json` and `room.json` are not in the export
preset's `include_filter` yet (only `data/*` and `assets/archive/*.json` are).

## Walking

Tap the painted floor and the witch walks there (`PaintedRoom.tap`, `game/world/painted/painted_walk*.gd`).

**The floor comes from the depth.** `tools/painted/walkable.py ROOM_DIR [--preview out.png] [--check]` lifts the room's
depth grid to 3D and keeps what faces up (normal.y > 0.85), lies within 12 cm under or 36 cm over the floor plane (the
dais the statue stands on is a 0.3 m step, which the depth model smooths into a ramp: she climbs it; a rock is taller),
within 11 m of the camera, and is connected on screen to the witch's feet. Lifted props (`props.json`) are not floor.
The floor is rasterised into a 0.25 m grid in world x/z with a height per cell. What a prop hides is not in the
painting: cells that project inside its mask, with floor on both sides, are filled in (that is the dais behind the
statue), and its footprint (a disc under its pivot, as wide as its mask) is an obstacle. Cells within 0.3 m of an edge,
or whose feet would leave the frame (the camera is bolted), are not standable. The result is the `walkable` block of
`room.json` (`rows`: `#` standable, `+` floor too near an edge, `.` not floor; `heights_cm`; `obstacles`); nothing else
in that file changes, and `--check` verifies the block still matches the depth. Run it again after lifting props.
`build_painted.py` does not call it: rebuild the depth, lift the props, then run `walkable.py`.

**Runtime.** `PaintedWalkable` reads the block and plans paths with `GridNavigator` (the archive hall's A*, now with a
cell-size argument). `PaintedWalker` moves a character along a path at `Witch.SPEED`, with `Witch`'s arrival distance and
turn rate, on the floor's own height (`y` follows the cells, eased onto the tapped pixel's own height over the last 0.8 m),
playing the model's `walk` and `idle` clips; the last point is reached exactly, so her feet land on the tapped pixel
(2 px at most: the 1.2 cm the soles float above the mesh). Characters are real 3D at world positions, so perspective
scale is automatic. `PaintedWalk` owns the witch's walker and the raccoon's: the raccoon trails 1.1 m behind her while she
walks, steps aside when she comes within 0.7 m, and otherwise stands (`watch` clip) turned toward her; it is a function
of positions and time only, so it is deterministic.

**A tap** (`IntentInput` and `PlayerIntent` as in the archive hall: mouse and touch are the same tap, emulated mouse
duplicates are ignored) goes, in order, to `press(px)` (a prop answers), then the floor (walk), then `fallback(px)`.
A floor tap is a pixel whose room surface is at floor height over a floor cell; a tap on floor too near an edge walks
to the nearest place she fits. Signals: `prop_pressed` as before; `PaintedWalk.walk_started(pixel, world)` when she sets
off; `PaintedRoom.walked(pixel, world)` when she arrives (a walk cut short by a newer tap never emits).

**Occlusion** needed no fix: she is an ordinary opaque mesh in the depth buffer, the room mesh and the prop cards write
depth, and the floor she stands on is the mesh's own surface. `tests/render/painted_walk_render.gd` checks it as an
oracle: for every pixel of her silhouette (found by drawing her alone), what the room has nearer than her (mesh, or a
prop card) must hide her and what it has farther must not. In front of the floor and of the statue, behind the statue
(partly, and entirely), behind the globe and the left foreground rocks and beside the right rock: 0 pixels drawn over a
nearer surface in every case, and 0.0-1.4 % of the pixels the room should not hide are missing (depth smeared at an
object's outline). Frames: `walk_behind_the_statue_strip.png` and one picture per case, in the output directory.

Run: `GODOT=... ./tests/render/painted_walk_check.sh OUT_DIR` (xvfb; `render_check.sh` calls it) and
`GODOT=... SKIP_RENDER=1 ./tests/run_tests.sh painted_walk` (headless: floor, paths, tap order, touch = mouse, walker,
raccoon). Limits: the depth is monocular, so the floor is as good as the depth (a 5 cm wobble of the carpet is followed,
not smoothed; far corridor floor beyond 11 m is not walkable); the hidden floor behind a prop is a guess; she can be
entirely hidden behind the statue.

## Toy box

Everything visible in the room answers a poke, and a poke never does nothing (Humongous Entertainment
aliveness). `assets/painted/hall_clean/props.json` lists 14 toys: 9 lifted **cutouts** (globe, statue, clock,
wall lamp, two finial orbs, floor tablet, scroll pile, key ring) and 5 **hotspots** (the eye mural, the oculus,
the beam, the carved chest, the boulders at the right).

**Data.** A reaction entry is a word or `{"do": word, "sound": name, "say": text_key}`; the list for `press`
is walked in order, so poking twice answers differently. Words (`PaintedProp.VOCABULARY`, the only place a
new one is added): `wobble hop squash shiver spin droop peek blink rattle bob tilt_fall swing pulse ripple
flash`. A cutout moves its card about its `pivot` (the clock swings from its hook, the ring spins about its
centre); a hotspot has no moving part, so its card is the same painting drawn only while it reacts, warped by
a soft mask (`painted_hotspot.gdshader`: ripple, shake, swell, flash) and hidden again at rest. Names a kind
cannot do map onto one it can (`HOTSPOT_ALIAS`, `CUTOUT_ALIAS`). `sound` defaults per word. `say` is a key of
`data/text/ru.json` (group `toy.`); the room emits `prop_said(prop_id, key)`, the presenter shows it.

**Sound.** `tools/painted/synth.py` writes `assets/painted/sfx/*.wav` from numpy recipes (blip, thunk, chime,
creak, rattle, boing, tick, sparkle, ping, whoosh): 22.05 kHz mono, seeded by name so reruns are
byte-identical, 161 KB in all. `PaintedSfx` (four voices, a deterministic pitch drift) plays them and counts.

**The fallback.** `PaintedRoom.fallback(px)` answers a tap that hit no prop and no hotspot: a ring of light at
the pixel (`PaintedPings`, four pooled quads) and a `ping`. `press(px)` still returns `""` when nothing was
hit; the caller that owns input dispatches prop, then floor walk, then `fallback`.

**Building it.** `tools/painted/toybox.py` rebuilds every mask, rect and `plate_empty.png` from the `lift`
blocks in `props.json` plus the image edits (`--without NAME=PATH`). Cutout cards are aligned to the mesh's
8 px grid so the PSX vertex snap treats card and painting alike, and `plate_empty.png` is the plate bit for bit
outside the masks (the fill is colour-matched to the ring around its hole and faded in over 3 px), so the room
at rest is the painting. `tools/painted/lift_prop.py` does one prop the same way.

**Cost of the objects** (Qwen Image 3 Edit, 2k, 16:9, seed 7, `prompt_extend` false, $0.075 per call; the raw
outputs are in `build/higgsfield`, git-ignored, the manifests are `job_toys_{a,b,c}.json`):

| call | asked to remove | removed | lifted |
|---|---|---|---|
| a | clock, lamp, two orbs | clock, two orbs (not the lamp) | clock, orb_left, orb_mid |
| b | lamp, tablet, scrolls, ring, boulders | lamp, tablet | lamp, tablet |
| c | scrolls, ring, boulders | scrolls, ring (not the boulders) | scrolls, ring |

Three calls, **$0.225**, seven lifted objects: about $0.032 each. Three earlier submissions failed at once and
were not charged (a placeholder URL left in `image_urls`: with `--upload` the list must start empty). The
boulders never came off, so they are a hotspot. A model that skips some of a list is the cost of batching:
ask again for the leftovers. The clock and the scroll pile are cut by hand lasso (the edit changed them too
little to refine); the others by lasso intersected with what the edit changed.

**Checks.** `tests/render/test_painted_toybox.gd`: the data uses the vocabulary and every sound, mask and text
key exists; the sounds total at most 400 KB; plate_empty equals plate.png outside every mask (blit test);
a 300-tap deterministic bot (floor, dark edges, outside the frame) finds zero silent taps; every toy runs its
whole cycle, visibly displaced mid-way and back at rest. `capture_painted.gd ... toys` prints `REST` lines (the
room with its cards against the painting drawn without them) and crops every reaction;
`tools/painted/toy_sheet.py` joins them. Measured at 16:9: outside the mask contours 0 differing pixels in
raw, PSX and full-resolution PSX; inside the cards the picture equals the card-less room to within 0.5 mean
grey levels; the only differences (about 1.2 % of pixels raw) are 1 px silhouette lines where the depth mesh's
own texture mapping misregisters, and there the cards are the exact ones.

Limits: a moving cutout carries its 2 px mask margin of background with it (a faint dark outline on dark
shelves); at non-16:9 aspects the PSX snap treats the card's four corners differently from the mesh's many
vertices, so a hairline can show; no presenter shows `say` lines yet; the sounds were judged by their spectra,
not by ear.

## Margins and other shots

### Margins (overscan)

`hall_clean` carries 160x90 px of extra painting on each side (12.5 %, a 1600x900 plate, still 16:9). A roll or a
wide window now shows margin instead of zooming in; the plate's own pixel coordinates (props, actors, taps) do not move.

- `tools/painted/extend_plate.py`: `canvas` (the plate in a larger canvas, border = the plate mirrored and lightly
  blurred, sigma 2..6 px), the edit model (`alibaba/qwen-image-3/edit`, 16:9, 2k, seed 7, `PROMPT_SHARPEN`; provenance
  `job_extend.json`), `merge` (register the result to the canvas, snap the margin's colours to the plate along the seam,
  paste the ORIGINAL back with a 4 px feathered seam ring), `paste` (the same margin for `plate_empty.png`).
  `merge` measures the drift and rejects a result (exit 2): shift > 8 px, scale > 2 %, seam ring MAE > 12, margin sharpness
  < 0.3 of the plate's, seam step > 2.5x the painting's own.
- `tools/painted/extend_room.py`: Depth Anything on the extended plate, mapped onto the room's own depth by a robust affine
  fit in disparity (median depth error inside the plate 3.4 %, p90 10.4 %), the seam difference carried outward with a 60 px
  decay, the room's own grid kept exactly inside the frame. Same eye, pitch and centre of projection; the extended frame is
  a 66.1 degree vertical field of view against the painting's 55. Writes `overscan.json` (read beside `room.json`, or inline as
  `"overscan"`). `PaintedRoom.overscan = false` restores the old behaviour. Re-run it after `build_painted.py` changes the depth.
- `game/world/painted/painted_overscan.gd` holds the arithmetic (`fov_for`: the camera zooms only as far as a rolled view of the
  window's shape needs; without a margin it is the old formula). Tests: `tests/render/test_painted_overscan.gd`, `tools/painted/test_extend_plate.py`.

Measured on the hall (1280x720 and 1680x720 windows, `capture_margins.gd`):

| | no margin | margin |
|---|---|---|
| 16:9, 5 deg roll | fov 55 -> 48.7 (15 % zoom) | fov 55 (no zoom) |
| 21:9, 0 deg | void at both sides | fov 52.7 (4.8 % zoom: 21:9 needs 200 px a side, the margin is 160) |
| 21:9, 5 deg roll | void, rotated edges | fov 51.3, filled |

Centre: the 1272x712 middle of `plate_ext.png` equals `plate.png` byte for byte (a test); only the 4 px seam ring differs (7,961
pixels, at most 16/255). Rendered at roll 0 with and without the margin, the frames differ only in the actors (animation phase),
the seam ring and 546 pixels by at most 2/255. Seam step across the boundary: 4.28x the painting's own pixel step with no
colour snap, 1.64x with a hard paste, 0.81x with the 4 px feather.

What the edit model does (about $0.075 per 2k edit; this recipe cost $0.15 with one wasted call, the whole search $0.60):
- A flat grey, or magenta, border is not outpainted: grey becomes a framed picture on a grey wall, magenta makes the model
  zoom back in until the painting fills the frame again. A heavily blurred mirror (sigma 6..18) is kept as blur, and a
  smeared (edge-replicated) seed made it zoom in 5-7 % (rejected by the drift gate). Only a LIGHTLY blurred mirror, with a
  prompt that calls the band "out of focus, repaint it sharp", is repainted, and the centre stays within 0.6 % scale, 5.5 px.
- Limits that remain: the mirror seed leaks into the result (a second, mirrored globe at the far left, a second light hole in
  the ceiling, the paper card reflected below itself, shelf lines that crease where they mirror at the seam), and the margin is
  softer than the painting (sharpness 0.34 of it). A correction pass ("remove the duplicates") sharpened the margin (0.84)
  but did not remove them. They sit in the outer band, mostly seen only past about 60 px of roll or window width. Props cut by
  the frame (the globe) keep their margin half as painting when lifted.
- Strips (four edits, 7:9 sides and 21:9 top/bottom, 1k, $0.04 each, $0.16) are worse than one canvas edit ($0.075): the
  model left the seed's blur in place (margin sharpness 0.17-0.36, the seed's own was 0.19-0.24) and the top strip
  re-composed the picture (centre MAE 20, scale 5 %). One canvas edit also has one seam, not four.

### Other shots (experiment)

Held-out views of the hall from the clean plate (`hall_shot2`: the statue 3 m closer; `hall_shot3`: from the arch back toward the
shelves), built with `build_painted.py`, rendered by `PaintedRoom` with `room_dir`.

- `alibaba/qwen-image-3/edit` ($0.075) returned the input picture for both prompts (mean difference 4-6 grey levels of 255): it
  does not move the camera. `xai/grok-imagine-image-2.0` (edit, 16:9, 2k, $0.09) did: the statue shot is the same hall twice as
  close; the arch shot is a new composition (three arched shelves, spiral carpet, the arch on the left).
- Style against the reference (`metrics.py`): median luma 0.155 reference, 0.149 clean plate, 0.129 shot 2, 0.135 shot 3; mean
  saturation 0.58 / 0.61 / 0.64 / 0.61; facet gradient 1.06 / 0.79 / 1.13 / 1.04. The palette, facets and light match; the
  views are darker and cleaner than the reference. Shot 2 keeps the room's furniture (statue, globe, eye, arches) in plausible
  places; shot 3 is a plausible but invented room (it does not match the first one's layout: the shelves are re-drawn).
- Camera: `tools/painted/estimate_camera.py` fits inverse depth against the row on the floor and reads the horizon where it
  reaches the farthest disparity. It is biased: on the original plate it says 74.5 % (14.3 degrees) against the true 65.0 %
  (8.9 degrees), so it is only a relative check: the shots read 76.8 % and 77.6 %, within about 1.3 degrees of the original,
  consistent with the prompt's "same eye height and horizon". `build_painted.py` was therefore run with the original camera (55
  degrees, eye 1.3 m, horizon 65 %). The depth scale fitted on the floor was 25.7 (shot 2; original 26.1) and 32.1 (shot 3).
- Verdict: shot 2 is usable as a held shot of the same room (a cut to a close-up) after review; shot 3 is not usable as the SAME
  room (its geometry is invented), only as a second room of the same style. Neither is a measured view of the first picture: no
  guarantee that distances agree, parallax holds to the usual 15 cm, characters (placed by hand) look large in shot 2.
  Cost per shot: $0.09 for a working edit, $0.075 per failed attempt; total spent on the whole task $1.09 of 1.50.

## Actor lighting: form and cast shadow

The characters used to be lit flat (a half-lambert over the floor's colour) with a round blob under them. In the painted
room they now have what the painting's figures have: facets with a core shadow, and a shadow that has their shape.

- **Key light** (`psx_lit_actor.gdshader`, `key_strength` > 0, set by `PaintedRoom.actor_key`): each flat facet is lit in
  `key_bands` steps by a key direction (the beam's, turned partly toward the camera's side by `key_front` so backs show
  some form), gated by how lit the floor under the character is; facets turned away keep only the floor's own purple
  (the core shadow), tops are brighter than undersides. A soft fill from the camera's side (`key_fill`) keeps a face turned
  from the beam dim, not black. Faces with vertex-colour alpha 0 (the witch's face, whose tile already carries the
  reference's planes) take the key without bands, never below `soft_floor` of it, and half neutral (`soft_neutral`).
  The hall's characters keep `key_strength = 0`: nothing changes there.
- **Cast shadow** (`PaintedActorShadow`, `painted_actor_shadow.gd/.gdshader`, `PaintedRoom.actor_shadow`): each
  character has its own render layer (20, 19, ...) and a 128 px `SubViewport` whose orthographic camera looks along the
  beam at it alone, so its alpha is the character's silhouette as the sun sees it, in every pose. A quad on the floor
  (the camera's square laid along the beam) samples that silhouette where each floor point's ray toward the sun meets
  it: one sample per pixel, blurred more the farther from the feet (contact-hardening), fading toward the tip, weaker
  off the lit pool, plus a contact patch at the feet; multiplied into the painting. An earlier version flattened the
  mesh itself onto the floor as a `material_overlay`; it came out patchy (per-vertex fade under a once-per-pixel
  stencil) and jagged (every curl's edge, PSX-snapped), and its pieces sank into the bumpy painted floor.
- Dials: `actor_key` (2.6), `actor_shadow` (0.75; 0 hides it and stops its camera), `key_front`/`key_bands` in the shader.
