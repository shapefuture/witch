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
