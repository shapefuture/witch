# Plate contract (set ↔ game)

The archive hall is drawn from **pre-rendered plates** (the FF7 / Resident Evil method; our camera is
bolted, which is their precondition). Blender renders the set offline (Cycles: GI, AO, volumetric
beam). Godot draws only what moves (actors, bubbles, dust) over it. The plates are projected onto
low-poly **proxy** geometry of the same set, so actors are hidden correctly behind the statue,
shelves and arch. The spell's tilt and fisheye then bend real geometry with PSX vertex wobble, and a
small camera move gets real parallax. This is view-dependent projective texturing (Debevec 1996)
with a PS1 skin.

Space: metres, Godot convention (+Y up, a camera at yaw 0 looks toward −Z), the same as
`tools/blender/kit` already uses. All files live in `assets/archive/`.

## Producer: `tools/blender/build_plates.py` (and the kit)

```
assets/archive/
  anchors.json            layout + light (extends today's file; Godot reads it, never hard-codes)
  hall_proxy.glb          proxy geometry: ONE mesh, <= 20k tris, vertex colour = a dim baked
                          fallback (the colour a fragment gets if no plate sees it)
  light_map.png           top-down light for actors (as today, same keys in anchors.json)
  plates/shots.json       the list below
  plates/<shot>/beauty.png  RGB8, display-referred, graded, final look (no characters)
  plates/<shot>/depth.png   RG8: linear view-space depth d in [near, far]:
                            v = (d-near)/(far-near); R = floor(v*65535)/256 (high byte), G = low byte
  plates/<shot>/key.png     L8: share of the pixel's light that comes from the sun + beam (0..1)
  plates/<shot>/glow.png    L8: share from emissive / candle / lamp sources (for flicker)
```

`plates/shots.json`:

```json
{ "version": 1,
  "shots": [
    { "id": "wide", "mode": "wide", "focus": [],
      "position": [x,y,z], "basis": [[xx,xy,xz],[yx,yy,yz],[zx,zy,zz]],
      "fov_v_deg": 0.0, "near": 0.1, "far": 80.0,
      "size": [W, H],
      "role": "shot" },
    { "id": "inspect:machine", "mode": "inspect", "focus": ["machine"], "...": "..." },
    { "id": "cover:stage", "mode": "", "focus": [], "role": "cover", "...": "..." }
  ] }
```

- `basis` holds the camera's global basis **columns** (x, y, z axes; the camera looks along −z).
  No Dutch roll is baked in: roll is applied at runtime, and projection mapping makes it free.
- `size` is the rendered pixel size. Each **shot** plate is rendered at **21:9** with the given
  vertical fov, so every screen from 4:3 to 21:9 is a centre crop with the same vertical fov
  (Godot `Camera3D.keep_aspect = KEEP_HEIGHT`).
- `role: "shot"` means the camera cuts to exactly this pose when `mode`+`focus` match a
  presentation entry. `role: "cover"` plates exist only to give the projection more coverage
  (the stage seen from the conversation side and from the low magic angle). Godot computes dynamic
  shots (conversation, consequence, magic_reveal) with `CameraDirector.compute_pose` and textures
  them from the best available plates.
- Budgets (they are tests): a shot plate is at most 2048 px wide (desktop) with a 1280-wide
  `beauty_m.png` mobile copy. Total plate memory, ETC2/ASTC-compressed, is at most 24 MB.

`anchors.json` gains (as well as today's keys):

```json
{ "camera_wide": "wide",
  "spawn": [x,0,z],
  "tomas_at": [x,0,z], "tomas_yaw_deg": 0,
  "interactables": { "machine": {"at": [x,y,z], "radius": r, "height": h, "approach": [x,0,z]},
                     "bell": {...}, "path_out": {...} },
  "walkable": [[x,z], ...],          "closed polygon of the floor actors may stand on",
  "obstacles": [{"at": [x,z], "radius": r}],
  "hero_regions": [{"at": [x,y,z], "radius": r, "height": h}],
  "pool": [x,0,z], "oculus": [x,y,z], "sun_dir": [x,y,z], "raccoon_perch": [x,y,z] }
```

Interactable ids are data and must not change: `machine`, `bell`, `path_out` (and the NPC
`tomas`). The Mirror room id stays `"clearing"`.

## Consumer: Godot

- `game/world/archive/` reads `anchors.json` and `plates/shots.json`; constants in GDScript are
  only fallbacks for a missing file.
- `render/psx/plate_projection.gdshader` on the proxy mesh does the following:
  - It projects up to three plates: the current shot's own, `wide`, and the best `cover`.
  - For each plate it tests visibility against that plate's `depth.png`, as with a shadow map.
  - It weights the plates by texel density and viewing angle.
  - Where no plate sees a fragment, it falls back to the proxy's vertex colour.
- The proxies write depth like any opaque mesh, so actors are occluded for free.
- Runtime light: `color = beauty * mix(1, sun, key) * mix(1, flicker, glow)`, plus the spell's
  tint. The sun dims and the candles flicker without a re-render.
- Actors are lit from `light_map.png` and given a contact shadow. They keep vertex snap and
  affine wobble. The proxies snap only while the spell's lens warp is above 0.
