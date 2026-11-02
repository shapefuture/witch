# Characters: the witch's look (X23) and the town's crude models

Scope: GAME_SPEC section 7, the CHARS row. Decisions are numbered as in `docs/design/GAME_SPEC.md`.

## The witch (X23)

X23: copper-ginger hair, blue-grey eyes and a violet hood made pointed so it reads like the references' hat. This
reverses the earlier russet (ash-blond) hair.

| | before | after |
|---|---|---|
| hair | ash-blond (`hair` family base 0.80, 0.69, 0.48) | copper-ginger (base 0.86, 0.48, 0.22; the same four tones) |
| eyes | sky blue, as cut from the user's close-up | blue-grey: the blue-dominant iris texels keep their tone and lose most of their saturation (`grey_eyes` in `witch_ref.py`) |
| hood | a dome with a peak folded back below its top | a cone above the brow ring that ends in a point bent back over the hood (`HOOD_ROWS` rows 4 to 7, `HOOD_TIP`) |
| `hat_tip` bone | (0, 1.10, -0.22) | (0, 1.10, -0.06): the pivot moved in with the hood's back |
| height | 1.33 m (scale 0.993 per unit) | 1.36 m (scale 0.993 per unit, so the curls keep their width: the test wants 0.9 m to 1.15 m) |

Unchanged: the rig (22 bones, the same names and parents), the clips (idle, walk, talk, cast), the triangle budget (6,344
of 6,500), one 256 px atlas, one surface. The builder reproduces the shipped file byte for byte from the same source
(`python tools/characters/witch_ref.py --out assets/characters`), so a rebuild is reviewable.

Frames (`tools/characters/capture_witch.gd`, the painted room and the studio, PSX on):
`docs/art/characters/witch_before_studio_front.png`, `witch_after_studio_front.png`,
`witch_before_room_back34.png`, `witch_after_room_back34.png`, `witch_after_room_front.png`.

Test change: `tests/render/test_character_models.gd` checked for ash-blond hair with a band that also took the face's
shadow tones (about 3,900 texels in the old atlas). The check is now the copper band, which counts about 490 texels of
hair; its floor is 300 texels.

Guesses (X23 leaves them open): the hat's height (about 0.2 m above the brim, read from references 13 and 17 and the
sheet's back view); the eye tint (lightness kept, saturation cut by about 60%); the hat's bend (about 5 cm back at the
tip). The brows are unchanged (a light warm brown from the earlier tint); they are one or two texels at game size.
