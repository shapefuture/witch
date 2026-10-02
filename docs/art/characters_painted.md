# The witch and the raccoon as the painting has them

The painted room (`docs/art/painted_room.md`) stands two live 3D characters on the feet of the two painted
ones. The first versions (the concept sheet's orange-haired witch, the pale upright raccoon) did not look like
the painted pair. `assets/characters/witch.glb` and `raccoon.glb` are rebuilt after the painting; the file
names, bone names, clip names and budgets are unchanged, so game code did not change.

## The witch of the new references (current `witch.glb`)

The user generated a turnaround sheet (witch and raccoon, front / side / back) and a hero render, and asked for the
characters again from those. The painted-hat witch described further down (`witch_painted.py`) is superseded: it is
kept as `--only painted` (writing `witch_painted.glb`, not shipped); `assets/characters/witch.glb` is now built by
`tools/characters/witch_ref.py` (`witch.py` calls it by default). The references themselves are the user's
artwork and are not in the repository.

**What the sheet says, and what the model does with it.** A purple hooded cloak with gold stars and moons whose
peak is folded back into a tip below the top of the hood; a ring of pink flowers on the hood's edge; a young face
with big blue eyes; very long golden-orange hair, a bulb behind her that ends in tentacle-like tails with spiral
tips, and big spiral curls sticking out to both sides; a brown vest with two big pockets and a crescent pendant;
a pink star wand in one hand, a small grey bird on the other; a flared skirt of twelve flat panels covered in gold
stars and crescents. The game's camera sees her from behind, above, at about 100 px, so the model was judged back
first (hood and its peak, the hair's lobes and tails, the cloak's hem band, the skirt), then side, then front.

```sh
python tools/characters/witch_ref.py --out assets/characters [--preview DIR]      # or witch.py (default: ref + antler)
xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 \
    --script res://tools/characters/capture_witch.gd -- CAPDIR                     # room (raw, PSX) and studio, 4 views
python tools/characters/witch_strip.py CAPDIR OUTDIR --ref REF_SHEET.png           # the reference next to the live witch
python tools/characters/witch_turnaround.py OUT.png --ref REF_SHEET.png            # same, from the numpy previewer (fast)
```

| | witch.glb |
|---|---|
| triangles (budget 9,000; the brief asks for about 3,000) | 3,022 |
| surfaces after `CharacterModels` folds flat colours | 1 (one atlas, one material) |
| bones | 22: the 21 every witch has had + `hat_tip` (the hood's peak and upper hood, which lag the head) |
| clips | idle 4.0 s, walk 1.0 s, talk 3.0 s, cast 1.6 s (not looping); every bone keyed in every clip |
| size | 1.33 m (hood top), 1.02 m across the curls, 0.92 m across the hem (the sheet's 0.67 of her height) |
| texture | one 256 px atlas, 41 % used: the skirt's star tile (240 x 40), the hood's (144 x 60), the face (64 x 56), 4 px colour swatches; 5-bit |

Authored in metres, y up, facing +Z, +X her left, feet on y = 0; the rest pose is the pose she holds on the sheet
(wand arm raised, bird arm held out), not a T-pose, so the clips rotate the arms relative to that. Colours are albedo
only: the room lights her.

**How she is built** (all procedural, numpy -> glTF through the kit the other witches use):
- *Skirt*: a 12-sided cone, three rows, every second corner pulled in 4.5 % at the hem (pleats); its tile has the stars
  and crescents sized in metres (compensated for the cone's narrowing) and a tone per panel and triangle. The hem
  follows the legs a little in `walk`.
- *Hood*: a six-ring dome, bell-shaped (see lighting below), open at the front below the brow ring, with a lining; the
  back-centre column is pulled out to the tip and its neighbours half way, which makes the ridge and the point. Its
  upper back weights to `hat_tip`. Nine five-petal flowers sit on the rim.
- *Hair*: one lobed mass (15 columns, every second one 12 % smaller, the lower edge dragged down under the odd
  lobes), five thin tails from those tips, each ending in a spiral, two spiral curls per side near the shoulder and
  the hip, two small ones by the hood, two locks framing the face and a small spiral on the back's hollow. The spirals
  are polylines walked by a turtle (`turtle()`: a stalk, then a spiral that shrinks), swept as 4- or 5-sided tubes.
  Hair vertices weight to `head`, `hairB.*` and `hairT.*` by height and side, so the curls swing in every clip.
- *Cloak* (shoulders to a hem just below the hair, open at the front, on `cape`), *vest* with two pocket boxes and
  things sticking out of them, a crescent pendant and its chain, bell sleeves, small hands, the wand and its pink star
  (`hand.R`), the bird (`bird`, parented to `hand.L`), the head with a rounded face plate (the tile has the eyes,
  brows, nose, mouth and cheeks).

**Lessons from the room's light** (`docs/art/painted_room.md`, "Actor lighting"). A facet is lit in steps by a key from
above and the beam's side, and only facets tilted at least about 25 degrees up from vertical catch any: a vertical back
wall facing the camera is in core shadow, so a plain lathe-turned hood showed a dark band. The hood therefore leans
(its back wall slopes) and the hair is a bulb that widens downward, the curls are tilted back at the bottom by
`TILT`, and the skirt is a cone: every large surface she shows the camera tilts up. The hair's albedo is yellower
than the sheet's (1.0, 0.70, 0.26) because the room's warm, dim light turns orange to brown. `gp()` also gives every
face its own anchor so the kit's outward test cannot flip a face whose winding is right (the peak's ridge did).

**Checked.** `tests/render/test_character_models.gd`: the clips, the height and the floor, the budgets, the bone names
(plus `hat_tip`), and `test_the_witch_has_the_new_references_proportions_and_palette` (0.9-1.15 m across the curls, a
skirt at least 0.7 m wide, at most 3,300 triangles, one atlas of at most 256 px with golden-orange, purple and pink
texels). `painted_walk_check.sh` passes (0 failures; occlusion unchanged). Frames: the turnaround strip
(reference | studio | room), the room at game resolution with PSX on, and the three sizes (100 %, 50 %, 25 % of the
row height; the game sees her at about 100 px). No image generation was used: the sheet already is a turnaround.

**Still different from the sheet**
- The hair is a smooth flute mass with thin tails; the sheet's is layered, with thick rounded locks and more, bigger
  spirals. The curls' ribbons are 4-5 sided tubes, so at the sheet's scale they look sharper.
- The hood is a rounded bell with one ridge; the sheet's is more peaked and its tip bends toward the viewer.
- The face is simplified (a rounded plate with a painted face, no hair strands between it and the hood's edge except
  two locks); the flowers are flat five-point stars, not layered petals; the hands are small blocks; the bird is a
  few flat shapes; no sparkles, no floating moon, no gem and plant things in the pockets beyond three blobs.
- The vest is boxy, the pockets plain; no medallions on the cloak.
- In the room the hair reads golden-brown, not orange: the actor light there is dim and warm (`actor_light`,
  `actor_sun` in `painted_room.gd`, not touched here); the lit-up render (`room_psx_lit`) is closer.
- Her cast shadow and the raccoon: the hem is wider than the old witch's (radius 0.46 m), so the raccoon's idle
  spot beside her now overlaps her skirt a little; `SHADOW_RADIUS` for the witch (0.32) is smaller than the hem.

The sections below describe the painted-hat witch (superseded by the section above: read their witch parts as history,
and `python tools/characters/witch_painted.py` now writes `witch_painted.glb`) and the raccoon.

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

## The raccoon of the new references

This section supersedes everything above about the raccoon (the four-legged, dark painted one). The user generated a
new turnaround sheet and a hero render of the pair (not in the repository; derived assets only), and asked for the
characters again from those. The raccoon is now **chubby and upright on two legs, arms crossed on the chest**,
grey-beige faceted fur, a dark bandit mask with half-lidded grumpy eyes and a short pale muzzle, a big tail with
seven dark and cream bands and a dark tip, and a small purple pointed hat (crooked, the tip flopped back, a
crescent moon and gold stars) perched between small upright ears. No image generation was used: the sheet is already
a turnaround (spend USD 0).

```sh
python tools/characters/raccoon.py --out assets/characters [--preview DIR]
python tools/characters/raccoon_compare.py SHEET.png OUT.png [--overlay OVERLAY.png] [--sizes 300 160 100]
```

| | raccoon.glb |
|---|---|
| triangles (budget 3,000) | 1,714 |
| surfaces after `CharacterModels` folds flat colours | 1 (20 palette materials, vertex-coloured) |
| bones | 22, the same names as before: `root hips spine chest head hat hat_tip ear.L/R upper_arm.L/R forearm.L/R hand.L/R leg.L/R foot.L/R tail1..3` |
| clips | idle 4.0 s, walk 0.7 s, talk 2.4 s, watch 4.0 s (the file names and clip names are unchanged; `watch` is still the painted room's idle) |
| height | 0.76 m with the hat (was 0.70: an upright body needs the room; `test_character_models.gd` allows 0.62-0.78) |
| origin | feet on y = 0, under the middle of the body; the tail trails behind (-Z), the model faces +Z |

**How it was built.** The model is authored in the sheet's own pixels (the figure is 235 px tall, hat tip included;
`Y(r)` and `Zs(dx)` in `raccoon.py` turn a height fraction and a side-view offset into model units), so every number
can be checked against the sheet. The silhouette profiles (torso rings: half width, front z, back z per height; the
head's six rings; the tail's band boundaries, axis and radius; the hat's path) were read off the front, side and back
views and then fitted with `raccoon_compare.py --overlay`, which overlays the sheet's silhouette and the GLB's, origin
aligned and without fitting: intersection over union 0.90 front, 0.87 side, 0.92 back (the sheet's own dark
shadow sides sit close to its background, so the numbers are a floor).

- **Body.** A pear: a 12-sided loft (narrow at the shoulders, widest at the belly), thick short legs with big flat
  feet that toe out, a notch between the legs through which the tail shows (as on the sheet). The arms are tubes: the
  upper arms hang from the shoulders to elbow blobs at the sides, the forearms rise across the chest and cross
  (the right arm lies over the left), each ending in a flat dark paw. Chest and belly facets pick one of three tones
  by position; the belly front is lighter. Vertex jitter of about 1 px (a sheet pixel) breaks the loft's regular grid.
- **Head.** A hexagon in front view (cheek points at the widest ring, a narrow chin), a sloping crown, a short muzzle
  with a dark nose, a frown, pale wedge between the mask lobes. The mask lobes are decals laid on the skull (24 x 5
  grid each, fine enough that no triangle bridges a ridge of the 12-sided skull); the eyes are a pale lens under a
  flat dark lid, lower toward the nose.
- **Hat.** A cone that follows a bent path (straight for the lower third, then flopped back, the tip flicking up),
  a thin wide brim tipped back, a moon and stars decal-projected on the cone, front and back. `hat_tip` carries the
  upper cone, so it lags in every clip.
- **Tail.** An 8-sided tube whose rings sit exactly on the band boundaries (dark root, cream, dark, cream, dark,
  cream, dark tip), so each band is one flat colour and, from behind, the ridge on top makes the stacked chevrons of
  the sheet. Skinned to `tail1..3`, which sway against the hips.
- **Clips.** Rotations are about the rest-pose world axes, as before. `idle` breathes through the spine, sways the
  tail and twitches the left ear; `walk` is an upright waddle (hips roll and yaw, legs swing, feet lift, the tail
  swings against the hips, the arms ride the chest and stay crossed); `talk` beats the head and lifts the left forearm
  off the chest ("now listen") while the right stays crossed; `watch` turns the head 50 degrees to its left.
- **Colour.** Albedo only. The room lights characters with a gold key and a purple fill (`painted_room.gd`), so a
  warm beige albedo goes orange and a violet hat goes red: the fur is a bright near-neutral grey-beige and the hat is
  blue-heavy (0.52, 0.26, 0.78). Judged in the room, not on the sheet's own pinkish light.

### Tests

`tests/render/test_raccoon_model.gd` (headless): upright on two legs with the tail behind and drooping; arms crossed
(each hand on the opposite side, in front of the chest, at chest height; elbows out); chubby (width about 0.4 of the
height), a tail that makes it over 0.5 m long, at most 2 surfaces and 3,000 triangles; and each clip moves the right
bones (walk the legs and hips, talk the left forearm only, watch the head, idle the tail). The shared
`test_character_models.gd` still checks loading, clips, height, floor and bone names.

### Still different from the references

- **Facets.** The sheet's body is a few large irregular planes; the model's torso and head are lofts, so the facet
  pattern is visibly a grid of triangles (it reads as a regular diagonal pattern in the flat-lit preview, much less
  under the room's banded key light). A hand-modelled mesh would have fewer, larger planes.
- **Colour.** The sheet's lit planes are pinkish with purple shadows; ours depend on the room's light. In the room
  the lower body sits in the floor's shade and goes dark olive; `actor_light` 1.7 (the fourth column of
  `compare_painted.py`) makes it read like the sheet. That is a room setting, not an albedo.
- **Face.** The mask is two decal lobes, not facet-aligned; the eyes are a few pixels of cream; the brow ruff and
  the cheek tufts of the sheet's face are not modelled. The hero render's fur strands and the hat's embroidered moon
  texture are not reproduced (one flat colour per facet).
- **Hat.** The tip flop is a polyline bend; from behind the sheet's tip curls toward the viewer in a lobe, ours bends
  straight back. The hat is a single mesh (no wire in the brim).
- **Hands.** The paws are flat blobs; there are no fingers.
- **Scale.** The sheet's raccoon is about 71 % of the witch's height; at 0.76 m against a 1.3 m witch it is 58 %.
  `HEIGHT` in `raccoon.py` and `HEIGHTS` in the test change together if the coordinator wants it taller.
- **Walk.** The waddle at the room's 2.4 m/s slides its feet (0.7 s cycle, legs 0.15 m long); it is a cartoon walk.


### Hat and tail (revised by the user's request)

The hat is a straight upright cone (the sheet's, not the crooked one), and the tail sweeps out to the side and curls up
like the sheet's: `TAIL_SIDE` in `tools/characters/raccoon.py` is -1 (out to the raccoon's right, which is the left of the
sheet's front view); +1 puts it on his left. In the painted room he looks toward the witch, so with -1 the tail shows to the
screen's right and with +1 it points at the camera.
