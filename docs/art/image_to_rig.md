# Six views to a mesh, a rig and parts (`tools/characters/image2rig.py`)

The next stage after `multiview.py` (`docs/art/character_views.md`): the four canonical views (front, left, back, right) become a 3D mesh, a rigged
mesh, and parts, on free Hugging Face Spaces and the Tripo API. Adapted from the user's draft; tests: `python3 tools/characters/test_image2rig.py`.

```sh
pip install -r tools/characters/requirements-3d.txt
python tools/characters/image2rig.py doctor                                   # keys set or not, account, GPU quota, Tripo credits, Spaces up
python tools/characters/image2rig.py run witch_green_t2 --shape-only --steps 30           # geometry from the 4 views (Hunyuan3D-2mv, free Space)
python tools/characters/image2rig.py run witch_green_t2 --shape-only --steps 30 --rig anigen          # + a skinned, textured mesh (front view only)
python tools/characters/image2rig.py run NAME --geometry tripo --rig tripo --max-credits 60            # Tripo: credits, not quota
python tools/characters/image2rig.py inspect a.glb      # triangles, surfaces, joints, textures, size, and the gap to the game's budget
python tools/characters/image2rig.py preview a.glb out.png                   # four flat-shaded views (textured if it has a texture)
```

`decimate` (local, free, quadric via `fast_simplification`) shrinks a mesh to about N triangles: the 573k-triangle Hunyuan shape becomes about 30k in seconds with its outline intact.

`NAME` is a `multiview.py` result under `build/views/` (or a folder); the 3/4 views are not used (the services take four). Output goes to
`build/rigs/NAME/` with `manifest.json` (inputs, settings, files, seconds, GPU seconds or credits really spent). A stage whose inputs and settings did not
change is kept, not run again (`--force`). Keys: `HF_TOKEN` (Hugging Face; not the Higgsfield `HF_KEY`) and `TRIPO_API_KEY`, from the environment or
the git-ignored `.env.local`; never printed, not even in part (`redact()` covers every message).

## The two budgets

* **Spaces are for sampling.** A free account has 300 GPU-seconds and 8 runs a day, rolling 24 h from the first call (read live from
  `/api/spaces/zero-gpu/quota`). Every Space call is checked first (`--min-gpu`, default 90 s) and the seconds it cost are written to the manifest. A
  provider that refuses a call for its GPU duration says so (`QuotaError`): lower `--steps` / `--octree`, or wait.
* **Tripo is for volume.** The balance must cover `--max-credits` (default 60: multiview about 30, rig about 25) before anything is sent; the spend is measured.

## The test: the witch's T-pose views (`build/views/witch_green_t2`, from the user's own picture)

| Stage | Result |
|---|---|
| Hunyuan3D-2mv, shape only, 30 steps (4 views) | Worked: a clean, recognisable T-pose witch (hood with the flower crown, curls, jacket with pockets, skirt, shoes), 515,770 triangles, 9 GPU-seconds, 1 run. |
| Hunyuan3D-2mv, textured | **Failed three times inside the Space** (`PyMeshLabException` in its own post-processing: 5 steps, 30 steps, octree 192 and 256). Not ours to fix: use `--shape-only` and texture elsewhere. The 5-step Turbo mode is not the cause. |
| AniGen (front view only) | Worked technically: one skinned mesh, 26 joints, 15,115 triangles, one 1024 px texture; 84 GPU-seconds, 2 runs. **The result is worse than our `assets/characters/witch.glb`** (the user's verdict, and a side-by-side shows it): it sees only the front, so the back is an invented dark mass, the texture is noisy triangle mottling, and the joints are anonymous (`joint_0` ... `joint_25`). Useful only as a skeleton-topology reference. |
| SkinTokens (rigs a mesh) | **Refused up front**: it asks the Space for 450 GPU-seconds in one call, above this account's per-call cap, so it cannot run on the free tier (nothing spent). Wired (`--rig skintokens`, decimates to 30k triangles first) and tested offline only. |
| Make-It-Animatable (rigs a mesh) | **Does not work through the API.** Tried twice (two accounts): `/pipeline` answers nine empty Gradio updates, no model. Its endpoints are a web-UI event chain with thirteen unnamed parameters and its `app.py` is a stub that loads the real code at runtime, so the sequence the UI performs cannot be read from here. The provider was removed (it is in the git history of this file). |
| Hunyuan3D-Part | Not run (quota). |
| Tripo | **Not run: this key's balance is 0 credits** (checked on both API versions, v2 `/user/balance` and v3 `/account/balance`). The code path is written against the vendor SDK and untested live; the signup credits do not appear on this key. |

With the **legless** T-pose views (`multiview.py --pose t --no-legs`, see `docs/art/character_views.md`) the same shape stage gives a clean bell of a body with the
T-pose arms and nothing below the hem: 572,922 triangles, 9 GPU-seconds, 1 run (`build/rigs/witch_t_nolegs`). That is the geometry to model and rig from: no legs, so no leg animation.

Quota after the first account's tests: **148 s but 0 runs left**: the 8 runs a day were the limit that bit, not the seconds, and a run that fails inside the Space (the three texture attempts) still counts.
Budget the runs: a validation day is about eight calls.

## What was changed from the draft, and why

* **Transport.** `gradio_client` for Spaces (queue, uploads, sessions, ZeroGPU token) and the vendor `tripo3d` SDK, instead of about 700 lines of hand-rolled HTTP,
  cookies and SSE. The draft's Tripo paths (`/v3/upload/open`, `/generation/...`, `/rig`) could not be checked against any readable documentation; the SDK uses the documented
  v2 API (`/task` with a `type`).
* **Bugs.** Tripo's rig was given a file path where it needs the geometry task's id (so `--rig tripo` now needs `--geometry tripo`); AniGen's rigged mesh is the
  FIRST file of `/extract_glb`, the second is a skeleton picture; `num_chunks=0` is below the Space's minimum (8000); the single `image` was sent together with the
  four views; Hunyuan answers a file as a Gradio update dict (`{'value': path, '__type__': 'update'}`); the draft printed the first and last characters of a
  token; `cmd_rank` did not exist and the self-test had code after `sys.exit`.
* **Guards.** Nothing paid or quota-bound is sent without a live check; the defaults run the free geometry stage only (`--rig` and `--parts` are opt-in); a Space failure ends in a
  one-line `STOPPED:` and exit code 2.
* **Dropped.** The single-view providers (Pixal3D, TRELLIS.2, Unique3D, the rigged-image Space): they exist and answer, but only Hunyuan3D-2mv uses all four views and AniGen is
  the rig; Unique3D asks for 300 s of GPU and is rejected outright. Also the PNG codec and sheet splitting (`multiview.py` cuts the views), and view synthesis on Tripo (`multiview.py` does it for
  about USD 0.10).

## What the result is, and is not

Judged against our own witch (the same four views of both, rendered by `preview`): **ours is the better character**. The one strong generated result is the Hunyuan3D-2mv
*shape*: a cleaner sculpt than ours (face, curls, skirt folds, pockets) from the four views, but untextured and 515k triangles. The mesh is a **reference or a rigged base**, not a game asset. The game's characters are at most 9,000 triangles in 2 surfaces with a 256 px atlas and a fixed skeleton
(`tests/render/test_character_models.gd`, `docs/art/characters_painted.md`); AniGen's mesh is 15k triangles with a 1024 px texture and anonymous joints. `inspect` prints each gap.
To use one: decimate, bake the texture down to the atlas, and retarget the joints onto the game's bones by topology. None of that is built.

Worth doing next, if at all: texture the Hunyuan shape (through Tripo once the account has credits, or by projecting the four views onto it), rig it (Tripo, whose SDK has `import_model`,
or a retarget of our own skeleton by weight transfer), then decimate and bake to the game's budget. Until then the shape is a sculpt to model from, and `--rig anigen` is not recommended for
the look. The free Space route stays the place to validate a character before spending credits.

## Other routes (from the user's research of free tiers; first-party quotes there, NOT checked by me except where marked)

| Route | What it is for | Status here |
|---|---|---|
| **Tencent Hunyuan3D API** ("HY3D": 200 credits per user, valid 1 year; geometry-only 15, normal 25, LowPoly 30, +MultiView 10, +PBR 10, **Auto Rigging only 10**, 3D Part Generation 30, Smart Topology 50; failed tasks are not charged) | The best fit: official Hunyuan3D, so textured output from the four views where the Space's texture stage crashes, a LowPoly mode for our 9,000-triangle budget, and rigging for 10 credits. About 8 textured or 20 untextured results from the free credits. | Not wired: needs an account and key, and I have not seen its API. First candidate for the next provider. |
| **Tripo** (2,000 signup credits, first-party but from 2024: verify the balance on key creation) | Volume: multiview to model, rig. | The user's key shows a balance of **0 credits** (checked), consistent with that caveat. Code written against the SDK, untested live. |
| **PiAPI** ($0.50 signup credit; Trellis, Pixal3D and Skin Tokens APIs) | A fully API-driven route: Pixal3D for the mesh, Skin Tokens for skeleton and skin weights. | Not wired. |
| **Modal** ($30 a month, T4 about USD 0.59 an hour; the credit does not cover Shared Endpoints) | Host Hunyuan3D-2mv or Pixal3D (`TencentARC/Pixal3D` has `inference_mv.py`, a multi-view script) ourselves: no ZeroGPU day limit and no dependence on the Space's broken texture stage. | Not wired; the natural home if the Spaces stay too tight. |
| Hugging Face Spaces (300 GPU-seconds and 8 runs a day: **measured here**) | Sampling and validation. | Wired (this file). |
| Meshy free (100 credits a month, no API on the free plan), Colab free (its terms forbid automation) | | Not usable by a script. |

Licences (user's research): AniGen, TRELLIS, UniRig and Pixal3D are MIT.

## The Spaces census (from the user's research; the two rigging Spaces were probed and tried here)

| Stage | Space | Notes |
|---|---|---|
| Rig a mesh | VAST-AI/SkinTokens | Takes a mesh, so the best geometry can be the one rigged. Needs 450 s of GPU per call: **refused on the free tier**. |
| Rig and retarget | jasongzy/Make-It-Animatable | Not usable by script (see above): drive it in the browser. |
| Rig, from an image | VAST-AI/AniGen, kirikir13/image-to-rigged-3d | AniGen wired and tried: worse than our own witch. |
| Mesh from the four views | tencent/Hunyuan3D-2mv | Wired: the shape works, the texture stage crashes. |
| Mesh from one view | TencentARC/Pixal3D (best), microsoft/TRELLIS.2, stabilityai/stable-fast-3d, Wuvin/Unique3D, LGM | Single view: they would ignore three of our four views. Not wired. |
| Multi-view from one view | TencentARC/InstantMesh | Not needed: `multiview.py` makes the views. |
| Parts | tencent/Hunyuan3D-Part | Wired, not run. |
| Unusable (user's census) | microsoft/TRELLIS (broken), tencent/Hunyuan3D-2.1 (running, no API), Step1X-3D, PartCrafter, Direct3D-S2, TripoSR, UniRig (Space) | Do not spend time. |

The census's suggested ensemble (three mesh generators scored automatically, then SkinTokens, Part, Make-It-Animatable) does not fit the budget measured here: one bucket of
8 runs and 300 GPU-seconds a day, and the generators it would ensemble are single-view. Hunyuan3D-2mv already uses all four views. What would change the picture is a rig that
runs inside the budget (Tripo's credits, Tencent's API at 10 credits, or SkinTokens on a GPU we own: Modal's $30 a month).

## Keys, and two accounts

A real environment variable wins over `.env.local` (the repo's convention, as in `hf.py`), and `doctor` says where each key comes from. The user gave a second Hugging Face token
(another free account, with its own 300 GPU-seconds and 8 runs a day) after the first account's runs were spent; if the cloud environment still carries the old token as a variable,
unset it or update it, or the file's new token is ignored. Each account's quota is its own: the tool does not rotate between accounts.
