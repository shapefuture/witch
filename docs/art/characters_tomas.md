# Tomas (character model)

Tomas is the young mechanic who fixes the brass machine. This model replaces the primitive
`Placeholders.tomas()` once it is wired in (it is not wired in yet). The source is the concept
sheet's bottom-right three views, which are **not** in the repo:
- brown hair and a grumpy face;
- a white shirt with rolled sleeves and a purple vest;
- a leather tool belt with pouches, and olive trousers;
- brown boots and a large wrench.

```
tools/characters/tomas.py          the model: numpy geometry, skin, animations, glTF writer, face cutter
tools/characters/tomas_face.json   where the face was cut from the sheet (mirror axis, box, scale)
tools/characters/tomas_preview.py  numpy rasteriser for the review sheets (not shipped)
assets/characters/tomas.glb        the built asset (texture embedded)
assets/characters/tomas_face.png   the face texture, 192 px, 5-bit: rebuilds need no sheet
```

```sh
python tools/characters/tomas.py --out assets/characters                    # rebuild from the committed face
python tools/characters/tomas.py --out assets/characters --sheet SHEET.webp # also re-cut the face
python tools/characters/tomas_preview.py --out /tmp/tomas --sheet SHEET.webp
godot --headless --path . --import                                          # then the gate
```

It needs only numpy, Pillow and scipy (scipy is only used for the face cut). Blender is not used.

## What it is

- **Size and orientation:** root at the feet, facing +Z (his left, +X, holds the wrench), 1.547 m
  tall.
- **Budget:** 4,466 triangles, 2 surfaces, 21 bones. Every triangle has its own corners and its face
  normal, so it is faceted.
- **Proportions:** measured off the sheet at 187.1 px/m. The head is big (chin 1.13, hair 1.55) and
  the shoulders are high and square.
- **`tomas_body`:** base colour white, colour in `COLOR_0`. Each facet gets a ±5 % tone (the hall's
  mosaic). Godot imports `COLOR_0` unconverted (checked), so the values are display-referred, which
  is what `psx_lit_actor` (`COLOR * albedoTex`) expects.
- **`tomas_face`:** a relief plate over the front of the head, with orthographic UVs from the sheet's
  front view. Its vertex colour is white and its sampler is nearest/clamp.
- **Palette:** muted values in `PALETTE` (cream shirt, dusty plum vest, olive trousers, tan
  pouches, brown boots, steel wrench) so he sits in the olive/ochre hall with the vest as the purple
  accent.

### The face

The face is about 57 x 55 px on the sheet. `cut_face` does the following:
1. Finds the mirror axis (x = 728.0).
2. Upscales a 64 px box x3 with Lanczos.
3. Mirrors the key-lit half (the sheet's light comes from the image right).
4. Keeps every pixel between the outermost skin pixels of each row, so the eyes, brows and frown
   survive.
5. Pulls only the broad colour (Gaussian, 6 px) to `PALETTE['skin']`, so the plate meets the
   vertex-coloured head without a seam.
6. Fills the area outside the face with hair or skin colour.
7. Applies a mild unsharp mask and quantises to 5 bits per channel.

The plate's relief (nose, brow ridge, sockets, lips, chin, cheekbones) sits on the head's
super-ellipse surface. The plate must keep the sheet's scale, `SHEET_PPM`/`FACE_BOX`, or the
texture slides off the features.

### Skeleton

```
root > hips > spine > chest > neck > head
                     chest > shoulder_l/_r > upper_arm > forearm > hand_l > wrench
                                                                   hand_r
       hips > thigh_l/_r > shin > foot
```

Rest rotations are identity, so every key is an Euler angle in the parent's frame.

- `hips` and `wrench` also carry translation keys. **Every animation keys every bone**, and the import
  keeps immutable tracks, so switching animations never leaves a stale pose.
- The wrench is skinned to the `wrench` bone at the fist. To hide it or swap it, hide that part of
  the skin, or scale the bone to zero.

### Animations (15 keys/s, linear, all four imported as looping)

| name | length | what |
|---|---|---|
| `idle` | 3.2 s | breath, weight sway, head drift; the wrench hangs at his side |
| `walk` | 1.0 s | in place (no root motion): legs, counter-swinging arms, two bobs |
| `talk` | 2.4 s | the free right hand makes two points, nods, a grumpy shrug at the end |
| `work` | 1.2 s | elbow-pivot chop: the wrench is raised beside his head, then the jaw meets the machine at chest height, about 0.5 m in front (0.06, 0.96, 0.50); the right hand braces on the machine at (-0.1, 0.98, 0.40) |

Holding the wrench by its middle (as the sheet shows), his arm is too short to strike at chest
height. So `work` *chokes up*: the wrench bone slides 10 cm and turns 30 degrees in the fist
(`WORK_CHOKE`, `WORK_TURN`), and the other loops leave it centred. A crossfade between `work` and
anything else therefore shows him re-gripping. `wrench_tip()` prints where the jaw is in any pose:
use it when retuning the keys.

## Import (`tomas.glb.import`)

- `gltf/embedded_image_handling=3` keeps the face texture embedded and uncompressed. The default
  extracts it to a stray `tomas_tomas_face.png`.
- `animation/remove_immutable_tracks=false`.
- `_subresources` sets `settings/loop_mode=1` on each animation. Godot expands this into about 8,000
  lines of empty slice settings; that is its normal output.

## Wiring it in (not done here)

1. Instance the GLB as the NPC's visual.
2. Give the `tomas_body` surface `PSXMaterials.actor(Color.WHITE)`.
3. Give `tomas_face` the same material with `use_texture = true` and `albedoTex` set to the face
   texture.
4. Drive the `AnimationPlayer` from the NPC's pose: `working`/`partnered` → `work`, moves → `walk`,
   speech → `talk`, otherwise `idle`.

`NPC._reset_limbs`/`_process` currently animate the placeholder's `ArmL`/`ArmR`/`Body` nodes; those do
not exist on this model.

## Still off

- The hair is a rounded helmet; the sheet's has a squarer, peaked top and a sharper forward quiff.
- The hands are smaller than the sheet's, and the fingers are simple tubes.
- The belt tools are token sticks (the sheet has a ring spanner and pliers).
- The face texture keeps the sheet's soft painted shading; under the actor shader's light this can
  read a little dark at the jaw.
- The previews use a simple key/fill light, not the game's light map. Judge the in-game look with
  `tools/visual_gauntlet` once he is wired in.
