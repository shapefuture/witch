# Tomas crude trial against the crude references

Compared: `tomas_crude.png` (the trial: 2,277 triangles, 32 px face texture) with references 11 and 12 (third-party
PS1 captures, kept for personal reference only), and the current Tomas on the concept sheet (03).

## What the trial is

The same skeleton, clips and palette as the current Tomas. It has fewer rings and sides, a coarser face grid and a
32 px face texture. Nothing is reshaped. That is the right mechanism under R13, but it is not enough.

## Where it falls short

1. **The face loses its expression.** At 32 px the brows, eyes and mouth blur into a few blocks, and the frown that
   defines Tomas is no longer readable.
2. **The palette is the current muted one** (cream shirt, dusty plum vest, olive trousers). The crude references use
   saturated, separated colour blocks, and SC7 is a saturated jewel palette. The cream shirt and the trousers are close
   in value, so they merge.
3. **The silhouette is unchanged:** thin arms, small hands, the hair as a helmet. Fewer polygons added no shape
   decisions.
4. **The density is uniform.** The references spend their polygons on the shapes that identify a character.

## Why the references work

- **Legible at low resolution.** Few, high-contrast features read even when the face texture is blurred. Reference
  11 is recognisable from hair colour, glasses, hat and robe, not from the face. References 8 and 9 show the failure
  mode: blurred features and muddy colour. The trial's face is heading that way.
- **Colour blocking.** Each garment is a distinct saturated block (reference 12: the red coat, the green robe, the
  white beard), so the shapes separate.
- **Silhouette first.** Hair, hats, props and proportions are chosen to be recognisable at small size.
- **Limits, not distortion.** The crudeness comes from polygon and texel budgets, spent on identity shapes. Nothing is
  deformed for effect, which is what R13 requires.

## Next trial (not yet built)

- A face texture of 64 to 96 px, with the brows, eyes and mouth drawn at high contrast rather than averaged.
- Polygons kept on the head, hair, hands and props; torso and limb rings reduced.
- Saturated colour blocks per garment, within SC7.
- Proportions and shape unchanged (R13 holds).
- Judged against references 11 and 12, not the concept sheet.

## Second trial (built 2026-10-14)

`tools/characters/tomas_crude2.py` writes `assets/characters/trial/tomas_crude2.glb`, which the game does not load.
Preview: `docs/art/crude_trial/tomas_crude2.png` (four rows: concept sheet, current, trial 1, trial 2).

- **Size:** 3,404 triangles (the shipped model has 4,466), 2 surfaces, 21 bones, 4 clips, height 1.547 m.
- **Density:** head, hair, hands and the wrench at the shipped density; the belt and torso at 0.6; the arms at 0.7;
  the legs at 0.5.
- **Face:** the sheet's own 64 px crop, with contrast raised 1.45 and a light unsharp mask. The brows, eyes and mouth
  read, and the frown survives.
- **Palette:** saturated colour blocks within SC7: violet vest, lemon-gold shirt, moss-green trousers, burnt-orange
  boots, mustard pouches. The shipped values are unchanged in `tomas.py`.

Still unlike the references: the hair is still a helmet, the silhouette is unchanged (R13), and the trousers read a
little bright. The face is smoother than reference 11's blurred textures, on purpose, so the expression stays readable.
The judgement is against references 11 and 12.

### Face, second pass

The first 64 px face was a soft photo crop, so the brows and mouth blurred. The face now takes the features from the
sheet's own darkest 6% of the central face, in one feature colour, and posterises the skin to 8 levels per channel
(the references' few-tone faces). A thicker feature (a one-texel dilation) read as a moustache under the nose, so it is
not used. The eyes are still smaller than in references 11 and 12.
