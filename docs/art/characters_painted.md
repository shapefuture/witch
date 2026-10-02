# The witch and the raccoon as the painting has them

The painted room (`docs/art/painted_room.md`) stands two live 3D characters on the feet of the two painted
ones. The first versions (the concept sheet's orange-haired witch, the pale upright raccoon) did not look like
the painted pair. `assets/characters/witch.glb` and `raccoon.glb` are rebuilt after the painting; the file
names, bone names, clip names and budgets are unchanged, so game code did not change.

## Source: the reference still, then a turnaround

The painted witch and raccoon are about 130 x 190 and 85 x 130 px in the 1280 x 720 reference (not in the
repository). What the painting shows, from behind:

- **Witch.** A very large, floppy violet hat with a wide brim and gold stars. The whole hat is tipped back and
  to her left: the brim is lowest behind and on her left, high in front and on her right, and the tip hooks
  over to the left. Under it a short, dark-navy blocky robe (a dark yoke above a lighter blue-violet skirt),
  dark sleeves, small dark hands, short dark boots. The hat is 55 % of her height and rests on her shoulders.
- **Raccoon.** Four-legged, dark grey-brown, round, with a fat tail ringed in dark and cream, and a tall
  straight violet cone hat with a small brim and a few yellow marks.

Front and side are not in the painting, so each crop (upscaled 5-6x) went to Qwen Image 3 Edit through
`tools/higgsfield/hf.py` for a three-view turnaround (front / side / back, flat light, plain background, no
text). They are kept as `tools/characters/ref/{witch,raccoon}_turnaround.png` (1280 x 720) with the job
files beside them; the input crop itself is a cut of the user's still and is not kept. Spend: 2 jobs,
USD 0.15 (estimate USD 0.075 each, seed 11, 2k, 16:9). The sheets gave the face, the sides, the hat's profile
and the raccoon's mask; proportions and colours were then matched to the painting itself.

## Builders

```sh
python tools/characters/witch_painted.py --out assets/characters [--preview DIR]   # also: witch.py --only painted
python tools/characters/raccoon.py --out assets/characters [--preview DIR]
```

`witch.py` still builds the concept-sheet witch (`--only v1`, now written as `witch_concept.glb`, not shipped)
and the antler witch reuses its kit; `witch_painted.py` builds `witch.glb`.

| | witch.glb | raccoon.glb |
|---|---|---|
| triangles (budget 9,000) | 1,442 | 1,424 |
| surfaces after `CharacterModels` folds flat colours | 1 | 1 |
| bones | 22 (the 21 of the concept witch + `hat_tip`) | 22 (same names as before) |
| clips | idle 4.0 s, walk 1.0 s, talk 3.0 s, cast 1.6 s (not looping) | idle 4.0 s, walk 0.9 s, talk 2.4 s, watch 4.0 s |
| height | 1.33 m (hat tip) | 0.70 m (hat tip) |
| texture | one 256 px atlas: a hat tile with the stars, a 60 x 48 face, colour swatches | none (vertex-coloured per material, 19 materials) |

Both are authored in metres, y up, facing +Z, +X her left, feet on y = 0, flat normals. Colours are
display-referred and 5-bit, and chosen for the painted room's actor light (see below).

**Witch.** The hat is modelled upright on its own pivot and then tipped 19 degrees to her left and 12 behind;
its brim is rolled up on her right; the cone is a Grid whose tile (`paint_hat_tile`) has a violet wash per
triangle of the geometry plus nine stars sized in metres. The head is a boxy skin loft with a textured face
plate (two big dark eyes just under the front brim, a nose shadow, a small mouth), a bob that covers the
sides and back, and a short neck. The robe is a blocky bell in three tones per facet; the lower rows partly
follow the legs, so the hem swings in `walk`. Sleeves and boots are dark. The right hand holds a short wand
(`cast` raises it clear of the hat). `cape` carries a short back panel, `hairB/hairT` the bob, `hat_tip` the
upper hat (it lags in every clip); `bird` is kept for compatibility and carries nothing.
The rest pose is relaxed (arms hang), not a T-pose; bones are still translation-only.

**Raccoon.** Modelled on all fours on the old skeleton names: `upper_arm/forearm/hand` are the front legs,
`leg/foot` the hind legs. The head is the concept sheet's (bandit mask, cream muzzle, half-lidded pale eyes,
built in the source's units and scaled onto the neck), the ears moved lower so they show under the brim. The
tail is thick, curls a little to its left, and has dark and cream rings with a dark tip. The hat is a straight
cone with a small brim, three tones per facet and seven small gold marks. `walk` is a trot (diagonal pairs),
`talk` lifts the left front paw, `watch` turns the head to its left.

## Checked against the painting

`tools/characters/capture_actors.gd` renders the room and each character in a studio;
`compare_painted.py` cuts the same box out of the reference and the live frame (PSX off, PSX on, and PSX on
with the actors lit 1.7x); `silhouette_diff.py` overlays the two silhouettes by one colour test.

- Witch silhouette IoU 0.78 (a crude colour mask: painted-only red, live-only green); the hat tip lands
  within 1 px of the painted tip (the figure is about 172 px tall in the 1280 x 720 frame); the live figure's
  centroid sits about 5 px left of the painted one (the room puts the origin at x = 735, the painted boots
  centre on about 740). The mask is not usable for the raccoon (its colours are too close to the floor), so
  that one was judged by eye: hat tip and tail end match the painted frame to a few pixels.
- Hat colour in the room: mean (62, 41, 45) live against (67, 45, 52) painted; robe (41, 34, 38) against
  (44, 34, 40).

## Still different

- **Light.** Characters take the painted room's actor light (`painted_room.gd`: `light_map.png`, the sun
  colour, `actor_light`, `actor_sun`). At the raccoon's spot it multiplies albedo by about (0.43, 0.31, 0.17),
  so nothing can be as bright or as cool as the painting's own lit planes; the painted lit facets reach luma
  96 where the live hat tops out near 64, and the raccoon's cream rings are dull. The fourth column of the
  comparison images shows the same frame with `actor_light` 1.7 and `actor_sun` 0.8, closer to the painting.
  That is a room setting, not an albedo.
- **Raccoon facing.** The room turns it `PI * 0.92`; the painted raccoon heads about 40 degrees further to the
  right (`PI * 0.8` would match), so its tail lies behind it toward the camera and shows as a few arcs rather
  than the painted sweep toward the lower left. The model's tail already curls a little to its left.
- **Witch detail.** The painted hat is rounder and has a sharper hooked tip flap, and its lit planes are
  brighter; the painted torso is narrower at the shoulders and the arms stand clear of the robe; the painted
  boots are slimmer. Her face was invented from the turnaround (the painting only shows her back).
- **Raccoon detail.** The painted body is rounder, the ears are rounded lumps beside the brim, and the
  tail rings are wider and fewer; the face is the concept sheet's grumpy one, not drawn from the painting.
- Cloth is rigid (the robe only swings through leg weights); the hat tip is one bone.
