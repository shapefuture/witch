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
a Dutch roll zoomed in (the painting had no margin: fixed by overscan, below); the 3D characters don't match the painted designs.

Capture frames: see the header of `tools/painted/capture_painted.gd` for the xvfb command.

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
