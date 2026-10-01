# Characters: the raccoon wizard and the Shadow

Two characters from the concept sheet (`sheet_witch_raccoon_shadow_tomas`, top right and bottom
left), ported from the user's procedural numpy -> glTF models and reworked against the sheet. The
sheet and the reference photos are **not** in the repo.

| asset | height | triangles | bones | surfaces | clips (all loop) |
|---|---|---|---|---|---|
| `assets/characters/raccoon.glb` | 0.70 m with the hat | 1,942 | 22 | 12 | idle 4.0 s, walk 0.9 s, talk 2.4 s, watch 4.0 s |
| `assets/characters/shadow.glb` | 1.70 m with the hood | 5,200 | 22 | 25 | idle 4.0 s, walk 1.1 s, talk 2.4 s |
| `assets/characters/shadow_lady.glb` | 1.65 m | 4,847 | 23 | 16 | idle 4.0 s, walk 1.1 s, talk 2.4 s |

The sources were 1,630 triangles (raccoon, T-pose) and 4,895 (Lady, T-pose).

```sh
python tools/characters/raccoon.py --out assets/characters [--preview DIR]
python tools/characters/shadow.py  --out assets/characters [--face-tex face_tex.png] [--preview DIR]
python tools/characters/glb_preview.py assets/characters/raccoon.glb out.png   # six views from the file
```

- `glb.py`: geometry (rings, lofts, tubes, blobs, ray-cast decals), a skinned `Model` with dense
  weights, `pose_bind` (bakes a pose into the bind pose), animation `Clip`s sampled from functions of
  time, a glTF 2.0 binary writer and reader, and the Godot `.import` writer.
- `glb_preview.py`: reads the exported GLB back, poses it (rest or any clip frame) and rasterises
  flat-shaded orthographic views with numpy. Previews check the file, not the builder. Blender
  Workbench needs EGL, which this container lacks.
- Builds are deterministic (seeded jitter), so re-running gives byte-identical GLBs.

## Conventions the game can rely on

- glTF space: root bone at the feet origin, the character faces **+Z**, +X is its left. Bones are
  translation-only at rest, so a clip's rotations are in rest-pose world axes.
- One primitive per palette colour, named by the colour (`fur`, `mask`, `cloak`, `parch`, ...).
  Colours are display-referred, snapped to 5 bits per channel, and written as linear
  `baseColorFactor`. Godot's importer converts them back, so each surface's `albedo_color` is the
  authored display value. To draw with `psx_lit_actor`, set `modulate_color` to that albedo for each
  surface. The face surface (`face`) instead sets `use_texture` with its albedo texture.
- Normals are per-face (flat facets). The face plate alone has smooth normals so the photo relief
  stays soft.
- The `.import` files set every clip to loop (glTF has no loop flag). They also turn off LOD
  generation (it would melt the facets) and shadow meshes (the hall has no lights), and embed the
  face texture uncompressed. Godot reports the face material's `texture_filter` as NEAREST.
- Import check (Godot 4.6.3, `--headless --import` on a clean project): no errors or warnings;
  skeletons, skins, clips and loop modes are present as in the table.

## Raccoon: changes against the sheet

1. **Width.** The source's head and body were ~30% wider than the sheet (head 0.54 H against
   0.40 H). The head and body lofts are narrowed, and a silhouette overlay of the front, side and back
   views now matches the sheet within a few pixels. The body is deeper toward the back, where the sheet
   has a straight spine.
2. **Arms crossed, as drawn.** The source was a T-pose. The arms are now modelled crossed in the
   bind pose: upper arms down the sides, the left forearm over the right at 0.40–0.54 H, lying flat on
   the chest (not a shelf sticking out in profile). The left paw rests on the right bicep with three
   blunt fingers; the right paw is tucked under the left arm.
3. **Bandit mask.** It is now two lobes projected flush onto the head facets by ray casting, sweeping
   down and out to pointed cheek tufts, with a light bridge between them and light brows above. The
   source's band tilt used signed `s`, so one side rode up and the other down; that is fixed.
4. **Eyes.** They are half-lidded and grumpy: a heavy pale lid, a cream almond, a big pupil and a dark
   lid line. *Deliberate deviation:* the sheet draws closed lid-arcs, but open eyes read at game scale
   and give `watch` something to do.
5. **Muzzle.** It is shorter (the source's protruded ~0.04 H too far) and broad, with a dark wedge nose,
   philtrum and frown.
6. **Ears.** They are larger upright triangles at the top corners, with darker inner faces.
7. **Hat.** It is small, with a narrow brim. Its cone is lofted along a hooked path that leans back
   with the tip highest, as in the side view. It carries pale four-point stars and crescents on a
   spiral, and a `hat_tip` bone lets it wobble.
8. **Tail.** It is thick (the sheet's is about 0.19 H across), centred rather than off to the
   character's right, and leaves the rump at ~0.3 H. It lies along the floor behind, tip slightly up,
   with seven light/dark bands and a dark tip.
9. **Legs and feet.** Short separate legs below the pear body, with a gap where the tail shows from the
   front, as on the sheet. The feet are visible.
10. **Colour.** Warm pink-taupe fur, lighter belly, cream muzzle/brows, a brown-black mask and a muted
    purple hat (an accent against the olive/ochre hall). Everything is 5-bit.
11. **Clips.** `idle`: breath, slow head drift, an ear twitch, tail sway. `walk`: an in-place waddle
    with the arms still crossed, two steps per loop, hip bob and sway. `talk`: head beats, and the top
    (left) forearm opens forward in a "look here" gesture, chosen because it can swing clear of the
    other arm. `watch`: the head turns 52° to its left, holds with a suspicious nod, and returns.

## Shadow: changes against the sheet

1. **Proportions.** The sheet's Shadow is stocky. Hood and head take 27% of its height, shoulders
   0.42 H, hem ~0.47 H. Measured on the sheet, the Lady's body landmarks (waist 0.50 H, shoulders
   0.66 H, chin 0.73 H) already fit, so the head group (head, face plate, hair, hood, scarf) is scaled
   1.6x about the neck and the arms are set 4.5 cm wider. The source head was realistic; at 360 rows
   the bigger face also reads.
2. **Hood.** It is deep and pointed, with a faceted crown ridge and a peak behind the top. An outer
   shell, a near-black lining and a rim run round a face window that closes in a pointed arch. It
   frames the pale face in dark, as drawn.
3. **Face plate.** The photo-projected relief plate is kept and improved:
   - **Relief:** more rows through the eyes, and upper-lid ridges and a philtrum added to the
     nose/lips/brow/socket/cheekbone/chin terms.
   - **Crisp eyes:** the soft photo eyes are repainted at texel level with a small palette (sclera,
     two iris tones, pupil, catch-light, a 2 px lash line with an outer flick, a lower lid line).
   - **Symmetry:** the texture is mirrored about the face axis, then snapped to 5 bits.
   - **Lids:** the Shadow's texture lowers the upper lids and the gaze (the sheet's downcast,
     half-closed eyes). The Lady keeps hers open.
   - **Skin match:** the head/hand skin colour is sampled from the texture's cheek, so the plate's
     edge no longer shows.
4. **Hair.** It is darker, near-black as on the sheet. Inside the hood only the hair cap and the fringe
   over her right eye remain; the back mass is hidden and dropped, and curtains read as earmuffs.
5. **Layered ragged cloak:**
   - a bulky scarf/cowl under the chin;
   - a shoulder mantle to the elbows with big irregular points, open at the throat;
   - a long bell-shaped outer cloak, open wide at the front, with a longer, uneven back hem, torn
     teeth and four tattered strips down the back;
   - a navy robe with worn panels and a ragged hem, showing in the front opening;
   - a knotted grey sash at the waist.

   Cloth is two-sided (an outer shell plus a dark lining), because the game culls back faces.
6. **Arms.** The source arms are built in T-pose, then posed into the bind pose (`pose_bind`). The
   right arm hangs a little forward and out, its pale hand at the hip below a torn cloak sleeve. The
   left elbow comes forward so the hand grips the front of the scroll bundle. Forearms are grey wraps,
   and the fingertips have dark nails, as drawn.
7. **Scrolls.** Six parchment rolls (darker rolled ends) fan toward the left shoulder, tied with a
   leather band, with a dark quill among them. All are rigid to `hand.L`.
8. **Satchel.** A brown leather box with a darker flap and a brass buckle, low on the left hip. Its
   strap runs over the right shoulder and down the back. A drawstring pouch hangs on the right hip.
9. **Colour.** Dark slate-blue cloak and mantle, darker navy robe, a near-black lining that makes the
   pale face pop, warm leather and parchment as the only warm notes. Everything is 5-bit.
10. **Clips.** `idle`: breath, head drift, cloak sway on two cloak bones. `walk`: in place. The robe
    and the cloak's front panels are partly weighted to the thighs so the stride swings the hem
    instead of piercing it. The left arm keeps the scrolls; the right arm swings. `talk`: head beats
    and a right-hand gesture.

**The Lady** (`shadow_lady.glb`) is the source model with these changes:
- arms relaxed down (posed from the T-pose) instead of a T-pose;
- head 1.2x;
- crisp open eyes;
- darker hair;
- skirt partly weighted to the thighs;
- the same clips, with both arms swinging.

She keeps the source's realistic proportions (see below).

## Still off against the sheet

- **Shadow hood.** The sheet's hood is broader and drapes over the shoulders as one mass, and the
  sheet's sleeves are big bell shapes at the elbows. Ours are mostly hidden under the mantle, so the
  waist-level silhouette is narrower than drawn.
- **Shadow back.** The sheet's back strips are wider panels than our four strips.
- **Shadow face.** The photo face is more realistic than the sheet's painted one.
- **Lady proportions.** The Lady is not the Shadow's exact body: her head is 1.2x, the Shadow's 1.6x.
  This is a deliberate split between "per the sheet" and "the Lady the script builds".
- **Raccoon.** The sheet's eyes are closed arcs (ours are open, see 4). The sheet's hat tip kinks more
  sharply.
- **Skinning.** Weighting is simple linear blending. Large `talk` gestures and the Lady's long stride
  show some stretching at the shoulder and through the skirt.

## Face texture input

The face texture comes from the user's extractor (`face_tex.png`, 160x228, UVs from reference-photo
pixels). It is derived from a reference photo, so only the processed result lives in the repo, embedded
in the GLBs. `shadow.py --face-tex PATH` processes a fresh one. Without `--face-tex`, the build reuses
the processed textures already embedded in `--out`, so geometry and clip changes rebuild without the
photo.
