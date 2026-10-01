# Art pipeline

The first scene, the **archive hall**, is built from the user's reference still: a faceted,
mottled, olive-and-purple library with one shaft of light (see `visual-gauntlet/BAR.md`). It is
authored in code, baked, and committed; the game never needs Blender at run time.

```
tools/blender/kit/textures.py   hand-painted 128px tiles (numpy + Pillow)   -> assets/archive/textures/*.png
tools/blender/kit/common.py     faceted-mesh Part builder (bmesh, Godot-space authoring)
tools/blender/kit/props_hall.py the hall: shell, floor, arch, shelves, towers, statue, foreground frame
tools/blender/kit/props_built.py machine, bell mount, bench, crate
tools/blender/kit/bake.py       lights, Cycles vertex-colour bake, light smoothing, glTF export
tools/blender/build_hall.py     composition + bake + export     -> assets/archive/archive_set.glb, anchors.json, light_map.png
```

```sh
pip install bpy numpy pillow          # Blender as a Python module (3.11 wheel for bpy 5.0)
python tools/blender/build_hall.py --out assets/archive --samples 96     # about a minute on 4 cores
godot --headless --path . --import && ./tests/run_tests.sh               # re-import, then the gate
```

## How a frame is made

1. **Geometry** is flat-shaded facets: noise-displaced icospheres, jittered height grids, lathes,
   tubes, boxes. Authored in *Godot* space (y up, -z forward) so numbers match `ArchiveHall`.
2. **Albedo** is a small painted tile per material (mottle, dabs, grain; palette moss, olive,
   mustard, burnt orange, coral, cream, muted purple, earth). UVs are box-projected at constant
   texel density; glyph sheets and the eye mural are placed once per face (`CENTERED`).
3. **Light** is baked into per-corner vertex colours with Cycles: one steep golden key through a
   hole in the vault (the only thing that lights the pool), a warm area "limelight" from the
   camera's side so fronts are readable, a lilac-olive ambient lift, six diffuse bounces. Corner
   noise is removed by a normal-gated neighbourhood average (`smooth_light`), then every facet gets
   its own small value/hue shift (`facet_tone`): the crystalline mosaic. Stored display-referred.
4. **Draw** with `psx_set.gdshader`: unshaded, tile x baked light x exposure, affine UVs, vertex
   snap on a grid of two render pixels, wind sway weighted by vertex alpha, warm rim, haze. The
   static set is one mesh, one surface per tile.
5. **Characters** (not baked) use `psx_lit_actor`, which samples `light_map.png` (the baked floor
   seen from above) so they glow in the shaft and go dim in the shade, with the same snap/wobble.
   Each also drops a `BlobShadow` (a flat dark smear on the floor, stretched away from the key
   light, top-level so it follows in world space) because the baked floor cannot shadow a mover.
6. **Air**: `HallAtmosphere` adds a slanted shaft prism, a floor glow and drifting dust, all from
   the diorama clock. `psx_screen` adds glow from the screen's mip chain, a warm grade, vignette,
   5-bit ordered dither and the spell's fisheye.

The floor's spiral is **geometry**: `props_hall.carpet()` lays real quad strips 1.5 cm above the
floor (dark border, purple band, dark seam, gold band) so band edges are mesh edges and the pattern
survives the 2-pixel snap and vertex-colour interpolation. Painting it into the floor tile read as
noise. Shelves are not wallpaper: each tier gets its own density, some are empty, some bays gappy.

## Rules the code learned the hard way

- The Compatibility renderer writes `ALBEDO` to the screen **as is** (probed: 0.5 in, 0.5 out). Do
  not gamma-correct in shaders; bake display-referred values.
- bmesh **reuses freed slots** (`create_icosphere` frees some), so "vertices with index >= n" is not
  "vertices added since". `Part` tracks created vertices explicitly. `bevel` deletes vertices and is
  ignored for that reason.
- `recalc_face_normals` re-guesses winding per loose triangle and flips about half of them. Winding
  is authored per primitive; shells use `tri_toward`.
- glTF `COLOR_0` is exported normalised (clamped to 1.0), so light is stored with the sunlit floor
  at 1.0 and the shader applies the exposure (`gain`).
- The set material is looked up by the glTF **material name**; aliasing two names to one Blender
  material loses one of them (`box_glyph`, `mural_eye` have their own).
- A `while` that skips a gap must step *past* it (`x = gap_end + epsilon`): ending on the boundary of
  an inclusive range loops forever, silently, inside Blender.
- Sky/dome shaders must not write depth by hand: the depth convention differs between renderers.

## The camera and the frame

Bolted. `DioramaCamera` holds a pose (look-at, distance, pitch, yaw, **roll**, fov) and never follows
the witch; `CameraDirector` changes shot by **cutting**, and only the spell's `magic_reveal` eases
(fisheye swing via the `lens_warp` global and a 45 degree tilt; the cut back to the wide is the snap).
The walkable floor (`ArchiveHall.stage_allows`) is trimmed so she is always inside the 4:3 frame; a
test projects every walkable cell through the real camera. The dark foreground shelf, globe and rock
(`FgLeft`/`FgRight`) are baked in camera space and ride on the camera; `GameRoot._fit_foreground`
pushes them to the screen edges at any aspect, and they are hidden in close-up cuts.

## Diegetic UI (no 2D)

`Diegetic` projects a screen position into the world at a fixed depth and scales one unit to one
render pixel, so slabs (`SlabMesh`) and `Label3D` text are scene geometry yet pixel-crisp and the
same physical size on every device. `SpeechBubble`: parchment slab with a tail to the speaker, brass
name tab, text pre-wrapped once (the typewriter never reflows); narration is a scalloped thought
cloud with a trail of dots. It tries six spots round the speaker's head and keeps the one that covers
the least of the room's focal points (`Room.hero_regions()`: the light pool, the arch, the statue)
and none of the speaker. `PlaqueStack`: carved wooden option plaques hung beside the tapped thing;
a tap inside a plaque (touch or mouse) chooses it, `IntentInput.intercept` asks first. The pause and
settings menus use the same plaques over a dark veil.

## Budgets (tests)

`tests/render/test_archive_hall.gd`: <= 60,000 static triangles, <= 28 surfaces, tiles <= 256 px,
every surface has a painted tile, the set has the machine's named parts, and the wide shot frames
everywhere the witch may stand at 4:3.

## Adding or changing art

Edit the kit, rebuild, run the gate, then `tools/visual_gauntlet/capture.sh` and judge the frames
against the bar. Keep gameplay anchors (`MACHINE_AT`, `BELL_PILLAR_AT`, `TOWER_AT`) identical in
`build_hall.py` and `archive_hall.gd`: the art and the interactables must agree.
