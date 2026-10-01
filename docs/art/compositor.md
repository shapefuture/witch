# The compositor (Godot side of the plate contract)

The archive hall is drawn from pre-rendered plates projected onto proxy geometry. The producer side
and the file formats are in [`PLATE_CONTRACT.md`](PLATE_CONTRACT.md); this page covers what Godot does
with those files and what it expects from them.

```
assets/archive/plates/shots.json ─┐
assets/archive/plates/<dir>/*.png ┼─ PlateSet (load, project, choose) ─┐
assets/archive/hall_proxy.glb ────┘                                    ├─ PlateStage ── proxy + plate_projection shader
assets/archive/anchors.json ─────── ArchiveHall (layout) ──────────────┘   (+ fade overlay for variants)
CameraDirector.pose_for ── a plate's exact pose if one exists for the beat, else compute_pose
```

## Files and classes

| What | Where |
|---|---|
| The loader, the projection math, plate choice, CPU key sampling and the memory count | `game/world/archive/plate_set.gd` (`PlateSet`) |
| The proxy, per-frame plate binding and variant crossfades | `game/world/archive/plate_stage.gd` (`PlateStage`) |
| The shader | `render/psx/plate_projection.gdshaderinc` (shared logic); `plate_projection.gdshader` (opaque); `plate_projection_fade.gdshader` (the variant overlay) |
| Layout from `anchors.json` | `game/world/archive/archive_hall.gd` (constants there are fallbacks only) |
| The live machine and bell | `game/world/archive/archive_props.gd`: `props/machine.glb` and `props/bell.glb` if present, else the Machine/Bell of the old `archive_set.glb` |
| The stub producer | `tools/plates_stub/make_stub.py` |
| The tests | `tests/render/test_plates.gd`, plus `test_archive_hall.gd` |

## The projection

`PlateSet.project(plate, world)` is the shader's math, written out in GDScript. It returns
`(pixel x, pixel y with row 0 at the top, view depth)`. In plate camera space (the camera looks down
−z), `ndc = q.xy / (z · (tan½v · W/H, tan½v))` and `uv = (ndc.x/2 + ½, ½ − ndc.y/2)`. Pixel centres
sit at `(i + ½)/W`. Three tests pin this convention:

- a synthetic plate: the centre, the top row and the right column land where they should;
- Godot's own `Camera3D`, placed at the wide plate's pose and sized like the plate, agrees with
  `project` to within half a pixel;
- floor pixels rebuilt from `depth.png` through Godot's camera come out at floor height. This is the
  test that fails if Blender and Godot disagree on fov, aspect, row order or depth encoding.

Per fragment, the shader handles up to three plates:

1. **Projection** from the unsnapped world position, so it is perspective-correct.
2. **Visibility** against that plate's depth, like a shadow map. The bias is
   `0.06 m + 0.006 · z / max(N·L, 0.25)`. Faces the plate saw from behind are rejected.
3. **Weight**: `1 / (1 − cos angle)` between our view ray and the plate's ray, times a texel-density
   ratio (plate texels per metre over our pixels per metre, clamped to 0.02..1). A 2.5 % border
   fade avoids seams at plate edges.
4. **Fallback**: blended over the proxy's vertex colour by the best plate's coverage.

At a plate's own pose (`PlateSet.is_exact`, which ignores roll), that plate skips the depth test and
wins outright. Each screen pixel is then exactly the plate pixel, whatever shape the proxy has.

## Light

The runtime light is `colour = beauty · mix(1, sun, key) · mix(1, flicker, glow)`. On top of that,
the spell tints the frame by `magic_amount`: a slightly violet cast, and warmer where the key falls.

- `sun` is set by `PlateStage.set_sun`.
- `flicker` is a deterministic function of `stage_time`.

## Plate choice (`PlateSet.choose`)

Three slots are filled every frame from the active camera:

| Slot | Plate |
|---|---|
| 0 | The plate the camera sits exactly on. Otherwise the best-scoring plate other than `wide`. |
| 1 | `wide` (named by `anchors.json` `camera_wide`). |
| 2 | The best `cover` plate. If there is none, the next best shot plate. |

The score is `dot(forward_plate, forward_camera) − 0.04 · distance`. A slot's textures are rebound
only when its plate changes. The matrices are cheap and are set every frame.

## Shots

`CameraDirector.pose_for(mode, focus)` asks the room for a `role:"shot"` plate with the same mode and
the same focus set (order does not matter). If one exists, the camera cuts to exactly that plate's
pose, plus the roll that `compute_pose` gives that mode. Otherwise it falls back to `compute_pose`
with the framing from `anchors.json` `framing`. The camera keeps `KEEP_HEIGHT`.

**Roll fit.** Plates carry no roll, so a rolled frame would poke out of the plate's corners. When the
pose is a plate's, `DioramaCamera` closes the lens to the largest vertical fov whose rolled screen
rectangle still fits inside the plate (`DioramaCamera.roll_fit`). It never opens it. The stub renders
its shot plates with that much vertical overscan, so a 16:9 screen shows exactly the authored fov
(52° wide, 44° inspect):

| Screen | Effective vertical fov |
|---|---|
| 4:3 | 52° |
| 16:9 | 52° |
| 21:9 | 51° (a 2 % crop) |

If real plates are rendered at the authored fov with no overscan, the shot zooms about 10 % at 16:9
instead. That is still correct, just tighter.

**The spell's dolly.** The `magic_reveal` pose carries `dolly` (6 % of the wide distance). After the
cut, the camera pushes in that far over 3 s, so the projected set shows real parallax.

## Variants (the ageing room)

A `shots.json` entry may carry `"variant": "dusk"`. A variant has the same pose as its base plate,
lives in its own folder (`dir`, else `<id>_<variant>`), and shares the base plate's depth.

To change variant:

- `PlateStage.crossfade_to(variant, 2 s)` fades a second copy of the proxy, drawn transparent with
  the variant's plates, over the opaque one, then swaps them.
- `PlateStage.set_variant(variant)` switches instantly.

A plate that lacks the variant is regraded at runtime instead (`VARIANT_GRADES`: dusk keeps 25 % of
the sun and adds a tint).

Content triggers it with the presentation entry `{"kind": "room_variant", "variant": "dusk"}`. It
is the last entry of `go_path_out.depart`: she leaves and the light goes. It is presentation only.
A loaded game in which she has departed is shown at dusk, because `_sync_departure` reads the
departure from Mirror.

## Resolution and UI

- **Render size.** 960×540 base, with stretch `viewport` + `expand`, so there are 540 rows on every
  screen.
- **Snapping.** Actors still snap to the lattice of a 360-row picture (`PSXGlobals.SNAP_ROWS`), so
  the wobble keeps its size. The proxy snaps only while `lens_warp > 0`.
- **Diegetic UI** is laid out in 360-row "UI pixels" (`Diegetic.UI_ROWS`, `ui_scale() = 1.5`):
  - Text is rasterised at the real size (18 px) and drawn 12 UI px tall.
  - Touch targets and the safe rect keep their physical size.
  - Every public rect (`item_rects`, `screen_rect`, taps) is in viewport pixels.
- **Mobile.** `beauty_m.png` is loaded when `OS.has_feature("mobile")` or `"web"`.

## Memory and import settings

| Map | Import | Memory |
|---|---|---|
| beauty / beauty_m | VRAM-compressed: S3TC on desktop, ETC2 on mobile | 4 bpp |
| depth | imported as an `Image`, converted to RG8 byte for byte (lossy compression would turn it into noise) | 2 B/px |
| key, glow | imported as `Image`s, halved, R8 | 0.25 B per plate pixel |

The `.import` files next to the stub's PNGs carry these settings. Godot keeps a file's `.import`
params when the PNG is replaced, so the real plates inherit them. A plate in a **new** folder gets
Godot's defaults, which are wrong. Copy the `.import` files, or run `make_stub.py`'s `write_imports`
logic. `test_depth_key_and_glow_are_imported_as_images_and_beauty_compressed` catches this.

The stub totals 14.3 MB on desktop and 12.7 MB on mobile (budget 24 MB). Depth dominates: about
3.6 MB per 2048-wide plate.

## Actors

- **`BlobShadow`** draws two layers:
  - a contact blob, always;
  - a sun shadow laid along −`sun_dir` on the ground, at a strength equal to the key at the actor's
    feet. `PlateStage.key_at` reads the wide plate's (or variant's) key on the CPU, with a depth test.
- **`psx_lit_actor`** gains, experimentally, a screen-fixed paper grain (360-row cells, ±3.5 %) and a
  ±5 % tone shift per facet. Both are uniforms (`paper_grain`, `facet_tone`), so they are easy to
  turn off.

## Capture aids

- `--no-post` hides the screen grade, so a frame can be compared with its plate.
- `--variant dusk` starts in a variant.
- `--shot inspect|magic_reveal [--focus id]` holds a shot.

## Not verified

- WebGL2 depth precision and the 12-sampler fragment shader on real mobile GPUs. GLES3 guarantees 16
  texture units, and Mesa llvmpipe compiles and runs it.
- Performance on devices: 12 texture fetches per proxy fragment, at 540 rows.
