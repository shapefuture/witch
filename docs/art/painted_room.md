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
a Dutch roll zooms in (the painting has no margin); the 3D characters don't match the painted designs.

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
