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
   nearest prop -> its next reaction (`wobble`, `hop`, `squash`, `shiver`, `spin`); `PaintedRoom.prop_pressed`
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
