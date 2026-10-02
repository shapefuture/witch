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
