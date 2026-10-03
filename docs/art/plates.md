# Plates: how the hall is rendered

The hall is not drawn live. `tools/blender/build_plates.py` builds it in Blender, renders it with
Cycles from each camera the game cuts to, finishes the frames, and writes the files of
`docs/art/PLATE_CONTRACT.md`. Godot draws only what moves over them (`docs/art/compositor.md`).

```sh
pip install bpy numpy scipy scikit-image pillow
# a quick look (640 px, 12 samples, about 2.5 minutes for every shot):
python tools/blender/build_plates.py --out /tmp/plates --quick
# the real thing (2048 px, 64 samples, about 20 minutes on 4 cores):
python tools/blender/build_plates.py --out assets/archive --width 2048 --samples 64 --grade 0.85 \
    --reference docs/visual-gauntlet/bar/reference_hall.png
# re-finish without rendering again (tone, paint, grade, grain are cheap):
python tools/blender/build_plates.py --out assets/archive --from-raw --grade 0.7 --shoulder 1.2 ...
```

`--out` must already hold an `anchors.json` (the script rewrites its layout keys and keeps the
rest). The reference image is never committed; without `--reference` the grade is skipped.

## What it does

1. **The set** (`tools/blender/plates/`): a Cycles scene built *for a camera*. `layout.py` recovers
   the wide camera from the reference still (the horizon, the hall axis' vanishing point, the
   spawn mark on the floor, a 55 degree lens) and places everything else by unprojecting the pixel
   where the reference shows it. Decimated, triangulated forms give the irregular facets; a
   per-face tone attribute and a paper grain give the mottle. `shelves.py` fills the bookcases from a
   library of about twelve props by rule (runs of a kind, then a change).
2. **Light**: one sun through the oculus, a cone-shaped scattering volume only inside the beam, a hole
   light, candles, the warm stair, and area fills. Light groups `key`, `glow` and `fill` give the
   runtime its `key.png` and `glow.png`. The sun is deliberately weak against the fill: the reference
   is a low-key picture (median luma 0.16, 99th percentile 0.63) and a physically strong sun clips.
3. **Finishing** (`plates/post.py`, `build_plates.finish`): filmic tone, a procedural matte-painting pass
   (haze from depth, dodge where the key lands, bloom at the beam's edges, darker corners), a
   luma shoulder, a grade fitted to the reference's Lab quantiles, then paper grain.
4. **Shots** use the same arithmetic as `CameraDirector` (`make_stub.shot_spec`): `wide`,
   `inspect:machine`, `inspect:bell`, the covers `cover:conversation` and `cover:magic`, and an
   analytic `dusk` variant of `wide`. Shot plates are 21:9 with vertical overscan so the game's
   Dutch roll stays inside them.
5. **Proxy and props**: `hall_proxy.glb` (at most 19k triangles; vertex colour = what the wide plate sees,
   dimmed), `props/machine.glb` (gears named `Gear*`) and `props/bell.glb` (pivot at the hanger).
6. **Layout** (`anchors.json`): spawn, Tomas, interactables and their approach points, the walkable
   polygon, obstacles, hero regions for speech-bubble placement, the framing and the pool and
   beam for the actors' light. `light_map.png` is the pool of sun the actors stand in.

## Numbers

`tools/visual_gauntlet/squint.py` scores composition against the reference at 32x18 and 64x36. The
old real-time hall scored 0.32. See `docs/visual-gauntlet/rounds.json` for the log.

## Known gaps

- The nave is narrower than the painting's and the right shelves too large in the frame; the
  vault, the oculus and the nested arches behind the arch read less than in the reference.
- Facets are decimated forms with tone noise, not a hand-sculpted low-poly kit.
- Every shot after `wide` shares the wide shot's exposure; their lighting has not been
  hand-balanced.
- The `dusk` variant is analytic (the key share is dimmed), not a re-render.
