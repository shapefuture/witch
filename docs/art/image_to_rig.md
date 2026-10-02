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
| Hunyuan3D-Part | Not run (quota). |
| Tripo | **Not run: this key's balance is 0 credits** (checked on both API versions, v2 `/user/balance` and v3 `/account/balance`). The code path is written against the vendor SDK and untested live; the signup credits do not appear on this key. |

GPU quota after the tests: 165 s and 3 runs of the day.

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
