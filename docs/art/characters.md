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

## The town's crude models

Built by `tools/characters/npc_crude.py`: `python3 tools/characters/npc_crude.py --out assets/characters [--only ID] [--preview DIR]`.
House pattern of `tomas_crude2.py`: low-poly, one flat colour per part (one 128 px swatch atlas, one surface), feet at
the origin, facing +Z, metres at game scale. Skinned on the witch kit's skeleton: the body blends with
`template_rig.py`'s distance weights and its neutral arm pose; the legs, boots, hats and props are rigid on one bone
each. Clips idle, walk and talk, from `witch.clip_set`. Shadow (`shadow.glb`) is unchanged.

Only Miron is committed. The other five are built by the same script, but their GLBs, figure atlases, the town test and
the lineup image are held out of the repository until the integrator decides. The table keeps their sizes from the last
build.

| id | character | silhouette | measured height | triangles |
|---|---|---|---|---|
| `miron` | Miron (First Love) | tall and slender; a long camel coat to mid-calf, the collar up at the back, short brown hair, a rust scarf, a small magenta sigil beside the scarf | 1.72 m | 728 |
| `elian` | Elian | a slim young man; a short blue jacket, grey trousers, a plum flat cap held in the left hand | 1.60 m | 680 |
| `vera` | Vera | the widest silhouette: a moss-green bell dress to the floor, a plum shawl, cream wide sleeves, a rust headscarf, a brown braid over one shoulder, a bandolier with three bottles | 1.59 m | 832 |
| `ilya` | Ilya | short and round; a puffed blue coat, a gold scarf, a big round head with grey hair and round gold spectacles, a brass telescope in the left hand | 1.47 m | 728 |
| `janitor` | Janitor | tall and thin; a blue uniform with brass buttons and a dark belt, a peaked cap, a grey moustache, a broom in the right hand to the floor, a bucket in the left | 1.72 m | 840 |
| `concierge` | Concierge, a bird | about 0.83 m: a grey-white head with a yellow beak, a red pillbox hat, a dark red coat with a gold crescent, grey wings, yellow legs | 0.83 m | 632 |

The builder's H values (1.80, 1.68, 1.66, 1.52, 1.76, 0.90 m) are nominal; the measured heights are the highest vertex,
lower where the hair or the hat stops short of H. Each model is one surface and one 128 px atlas, far inside the actor
budgets of `tests/render/test_character_models.gd` (9,000 triangles, two surfaces, a 256 px atlas). The town test
(`test_npc_models.gd`, held out with the other five) checks every `npc_state` id that has a model: it loads, is skinned,
has idle, walk and talk, and stays in budget.

The front of each model, from the six-view preview (numpy, not the game's renderer), is held out with them: the
silhouettes are the check, and the game's own frames are still to come.

Guesses, where the bible gives no looks (it gives behaviour only):

- Miron's long coat and chest sigil come from reference 16 (a man in a long coat, a faint sigil on his chest); his rust
  scarf from act I, where his scarf is left on a branch at the Fog's edge. The collar is a back piece, not a ring: a
  ring closed over the chin and read as a beard. Commit b010282 has the ring; this change replaces it. The boots are
  boxes that reach the floor: b010282's ellipsoid boots stopped 4 cm above it.
- Elian's blue jacket and grey trousers are guesses; his plum cap is from act II, where he comes in cap in hand.
- Vera's dress, shawl, headscarf, braid and bandolier are the design the repo already had for her
  (`docs/art/new_character_and_props.md`, the sheet prompt in `tools/characters/ref/views/vera_t`).
- Ilya's build, telescope and round spectacles are guesses from "wonder without utility" and the observatory.
- The janitor's blue uniform, peaked cap, broom and bucket are reference 17's janitor; he is tall to read as the town
  at work.
- The concierge is the bird of reference 04: white head, yellow beak, a red pillbox hat, a dark red coat with a crescent.
- Palette: the sheet's (03) jewel tones with the violet, blue and magenta and the gold and red accents of X39.

Known gaps, for the next pass: the figures are rigid toys, so the walk only swings the legs; the arms and the hair do not
move on their own; the faces are two dark eyes on a flat head (the spectacles of Ilya are the only other feature).
