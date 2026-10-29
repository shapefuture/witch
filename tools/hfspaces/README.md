# Hugging Face Spaces (free ZeroGPU): room plates

`plate.py` makes a painted room plate from a prompt on a free, public Hugging Face Space, and edits a plate for a
variant, through `gradio_client`. Every picture is written as `NAME.png` with `NAME.json` beside it (provenance).
It is the free alternative to `tools/higgsfield` for the painted-room pipeline (`docs/art/painted_room.md`).

**Verdict of the first spike (2026-10-29, the Fog's edge):** free ZeroGPU Spaces **do** make plates the pipeline takes whole: one
Qwen-Image-2512 picture became `assets/painted/fog_edge/` (depth, camera, walkable floor, lights) with the witch standing in it, for
nothing. They do **not** reach the look of `docs/art/references/13_marsh_clocks_night.jpg`: every model drew a smooth, clean picture
(a 2D cartoon, a glossy mobile render, a Pixar-like one), never crude PS1 3D under dithered texels, and an edit asking for that
made it worse. They are good for layout and content; the crudeness has to come from somewhere else (the engine's PSX pass gives
some of it, see the capture). Ceiling: 8 pictures a day per free account, and only one of them from Qwen.

```sh
pip install --user gradio_client                       # (huggingface_hub comes with it)
python tools/hfspaces/plate.py doctor                  # token set or not, account tier, ZeroGPU quota, the Spaces up or down (free)
python tools/hfspaces/plate.py gen --prompt-file P.txt --out build/hfspaces/fog/a --seed 7        # schnell, then qwen, then dev
python tools/hfspaces/plate.py gen "PROMPT" --out DIR/NAME --space qwen --steps 30 --dry-run       # checks only: sends nothing
python tools/hfspaces/plate.py edit plate.png "INSTRUCTION" --out DIR/NAME --space kontext         # a variant, same camera
python tools/hfspaces/plate.py fit DIR/NAME.png plate_1280.png                                     # centre-crop to 16:9, 1280x720 (local)
python tools/hfspaces/plate.py erase in.png out.png --box 170,213,186,228 --darker 0.75 --grow 3   # paint out stray numerals (local)
python tools/hfspaces/test_plate.py                    # offline tests (no network)
```

Then the painted pipeline, from the picture: `python tools/painted/new_scene.py NAME --image plate_1280.png --godot $GODOT`
(`docs/art/scenes.md`); give the brief a `horizon` when the picture's is not its kind's.

**Token**: `HUGGINGFACE_TOKEN` from the environment, else from `.env.local` at the repo root; `HF_ENV_FILE=/path/.env.local`
names another file (a git worktree has no `.env.local` of its own: point it at the main checkout's). The token goes only to
huggingface.co and to the Space, as the ZeroGPU identity (`x-hf-authorization`); it is never printed, logged or written, and
error messages are scrubbed of it. Gradio's telemetry is switched off.

**Free only.** Only ZeroGPU Spaces, never Inference Providers. A free account cannot be billed (`canPay: false`): past the quota a
call is refused, not charged.

## Spaces

| key | Space | does | asks ZeroGPU for | licence of the model |
|---|---|---|---|---|
| `schnell` | `black-forest-labs/FLUX.1-schnell` | text to image, any size to 2048 (multiples of 32), 4 steps | 60 s (default) | Apache-2.0 |
| `qwen` | `Qwen/Qwen-Image-2512` | text to image, 16:9 is 1664x928, 50 steps (`--steps` lowers it) | 120 s on `xlarge`: counts **2x** | Apache-2.0 |
| `dev` | `black-forest-labs/FLUX.1-dev` | text to image, any size to 2048, 28 steps | 75 s | FLUX.1 [dev] non-commercial; its Outputs clause allows any use |
| `kontext` | `black-forest-labs/FLUX.1-Kontext-Dev` | image edit, 28 steps; picks its own size (1280x720 in, 1360x768 out) | 60 s (default) | as dev |
| `qwen-edit` | `Qwen/Qwen-Image-Edit` | image edit, 50 steps (not run yet) | 120 s | Apache-2.0 |

`--space auto` (gen's default) tries schnell, then qwen, then dev, once each, and stops at the first picture; what each refusal or
failure said goes into `NAME.json`. What each Space asks for was read from its `app.py` (`@spaces.GPU(...)`), which `doctor` re-reads
live and compares with `plate.py`. The call is refused here, before anything is sent, when the quota left is below that. Things found
in the sources (2026-10-29) that would waste a run:

- The Qwen Spaces default to **rewriting the prompt through Alibaba's DashScope API** (`prompt_enhance` / `rewrite_prompt`), in a
  `while not success` loop that never ends without the key: the call would sit until the GPU time runs out. `plate.py` always
  sends `False`.
- `Qwen/Qwen-Image` (the original) has its pipeline loading commented out: its `infer` would fail on an undefined `pipe`. Not used.
- `Qwen/Qwen-Image-2.1` (newer; text to image and edits, and cheap: about 33 s asked for at 1536x864) is under the **Qwen research
  licence, non-commercial only**: not wired, since a plate is shipped art. `Qwen/Qwen-Image-Edit-2509` asks for 300 s (the whole day)
  and `-2511` for 180 s.
- Outputs come back as **WebP** (Gradio's default image format, lossy) from all four Spaces used; `plate.py` converts to PNG and keeps
  the WebP beside it; the provenance records the format. The lossy edges ring around dark marks (see `erase`).

## Quota (observed)

The free tier: **300 GPU-seconds and 8 runs a day**, rolling 24 h from the first call (`GET /api/spaces/zero-gpu/quota`; the
docs say 5 minutes and that `xlarge` counts double; the run limit is not in the docs but is in the API's answer and is the one that bites).
A run is one GPU call, whether it succeeds or not.

Measured on 2026-10-29 (one window, opened by the first call at 11:23 UTC; `resetsAt` appears in the answer only after it):

| call | Space | wall time | quota charged | runs |
|---|---|---|---|---|
| text to image, 1536x864, 4 steps | FLUX.1-schnell (asks 60 s) | 7.1 s | 4.2 s | 1 |
| text to image, 1664x928, 30 steps | Qwen-Image-2512 (asks 120 s, `xlarge`) | 37.5 s | 69.2 s | 1 |
| text to image, 1536x864, 28 steps | FLUX.1-dev (asks 75 s) | 39.1 s | 34.2 s | 1 |
| edit, 1280x720 in, 1360x768 out, 28 steps | FLUX.1-Kontext-dev (asks 60 s) | 30.4 s | 26.9 s | 1 |

- The quota is charged on the **GPU time actually used**, not on what the Space asks for (schnell asked for 60 s and cost 4.2 s);
  what it asks for only has to fit in what is left. `xlarge` is charged double (Qwen: about 35 s of GPU, 69.2 s of quota), so a
  120 s `xlarge` Space needs 240 s left: **one Qwen-Image-2512 picture per day**, and only early in the window.
- Every call costs exactly one run. With 8 runs a day, **8 pictures a day is the ceiling** whatever the seconds say; schnell alone
  would use 34 s for all eight.
- Nothing was refused and nothing queued noticeably: wall time is GPU time plus a few seconds of upload and download.
- The four calls used 134.5 s and 4 runs (165.5 s and 4 runs left); the window resets 24 h after its first call.

## The Fog's edge spike (2026-10-29)

The prompts (`prompt_a.txt`, `prompt_a2.txt`, `prompt_b_edit.txt`), every candidate and every record are in `build/hfspaces/fog_edge/`
(git-ignored); the pick's record is committed as `assets/painted/fog_edge/job_room.json`.

- Quota at the start: 300 of 300 s, 8 of 8 runs, no window open. Account: free (`isPro: false`, `canPay: false`).
- Spaces checked (all `RUNNING` on ZeroGPU): FLUX.1-schnell, Qwen-Image, Qwen-Image-2512, Qwen-Image-2.1, FLUX.1-dev, FLUX.1-Kontext-Dev,
  Qwen-Image-Edit, -2509, -2511.
- a1, `schnell`, prompt A, seed 1301, 1536x864, 4 steps: **worked**, 7.1 s wall, 4.2 GPU-s, 1 run (295.8 s, 7 runs left).
  Verdict: glossy modern mobile-game render, nothing of PS1 (no texels, no dither, smooth gradients); the clock is a pocket watch
  with numerals, lanterns are Chinese paper lanterns, no eyeball flowers, no yellow tiles. Walkable path in the lower middle, eye and
  arrow sign without letters. Prompt A2 spells out what it misread (Qwen gets one shot a day, so it got the corrected prompt).
- a2, `qwen` (Qwen-Image-2512), prompt A2, seed 1302, 16:9 (1664x928), 30 steps: **worked**, 37.5 s wall, **69.2 quota-seconds**
  (about 35 s of GPU at the `xlarge` 2x rate), 1 run (226.6 s, 6 runs left).
  Verdict: the best composition for a plate: an open bare clearing in the lower middle, mossy bank, yellow-tile-and-plank path zigzagging
  over black water into a fog wall, eyeball flowers (magenta petals), the dead closed bud beside the path, eye-and-arrow sign without
  letters, cattails, lily pads. Misses: the smiling clock has numerals (text), paper lanterns rather than moons, the fog reads as a
  waterfall, and the look is a smooth 2D cartoon background, not crude PS1 3D (no texels, no dither).
- a3, `dev` (FLUX.1-dev), prompt A2, seed 1303, 1536x864, 28 steps: **worked**, 39.1 s wall, 34.2 GPU-s, 1 run (192.4 s, 5 runs left).
  Verdict: **fails the contract**: the signpost carries gibberish letters and the clock numerals; no fog bank (clouds and a moon); a
  glossy Pixar-like render with depth-of-field softness; the eyeball flowers are tiny.
- Round 1 ranking: a2 > a1 > a3. All three Spaces of the chain work on the free tier.
- The candidates next to reference 13 (same height; `tools/visual_gauntlet/metrics.py` plus a pixel-scale high-frequency share, `hf`:
  the mean of |luma - its 3 px box blur|, which dither and hard texel steps raise):

  | | median luma | mean sat | purple | magenta | gold | green | facet gradient | hf |
  |---|---|---|---|---|---|---|---|---|
  | reference 13 | 0.191 | 0.52 | 0.114 | 0.086 | 0.065 | 0.034 | 2.76 | 1.72 |
  | a1 schnell | 0.195 | 0.71 | 0.420 | 0.078 | 0.069 | 0.033 | 3.12 | 2.22 |
  | a2 qwen | 0.263 | 0.52 | 0.077 | 0.034 | 0.094 | 0.068 | 2.18 | 1.38 |
  | a3 dev | 0.244 | 0.59 | 0.089 | 0.073 | 0.025 | 0.028 | 1.87 | 1.38 |
  | b1 kontext (round 2) | 0.099 | 0.86 | 0.219 | 0.021 | 0.076 | 0.123 | 1.37 | 0.90 |

  **Biggest gap: the rendering.** a2 is a smooth, outlined 2D cartoon background; reference 13 is crude low-poly 3D under chunky dithered
  texels (facet gradient 2.18 against 2.76, `hf` 1.38 against 1.72). Then: the fog wall is a huge bright cloud (median luma 0.263 against
  0.191) that reads as a waterfall, magenta is under half the reference's, and the clock has numerals. (a1's higher `hf` is glossy
  detail, not texels: it is the least PS1 of the three to the eye.)
- Round 2 could not be Qwen again (it needs 240 s of quota; 192 s were left), so the changed prompt was an **edit of a2** on `kontext`:
  restyle to crude PS1 3D, keep the composition, fix the clock, the fog and the lanterns.
- b1, `kontext` edit of a2 (fitted to 1280x720), seed 1304, 28 steps: **worked**, 30.4 s wall, 26.9 GPU-s, 1 run (165.5 s, 4 runs left).
  It answered **1360x768** for a 1280x720 input: `fit` it before use. Verdict: **did not close the gap**: the composition held and the
  sky darkened toward the reference's night, but the look got flatter (vector-like, outlined: facet gradient 1.37, `hf` 0.90, both
  further from the reference than a2), it overshot (median luma 0.099, saturation 0.86), the numerals and paper lanterns stayed, and it
  **erased the fog bank**, the place's identity. One instruction carrying five changes was too much for it, and no prompt bought PS1
  crudeness from these models.
- **Pick: a2.** Fitted to 1280x720 (`fit`) and the clock's four numerals painted out locally (`erase`, four boxes, `--darker 0.75
  --grow 3`: 673 pixels, everything else byte-identical; the first try at `--darker 0.5 --grow 1` left the WebP's light ringing as
  ghosts) so the plate carries no writing. Its horizon is about 0.46 of the height (where the water meets the fog and the path
  vanishes), not the threshold kind's 0.58: the brief (`tools/painted/scenes/fog_edge.json`) now says so and describes this marsh.
- Pipeline: `python tools/painted/new_scene.py fog_edge --image build/hfspaces/fog_edge/plate_fog_edge.png` (no generation, no
  spheres, no toys: the brief has no layout). Depth Anything V2 Small on the CPU; horizon 0.46 with a floor-fit residual of **0.024**
  (the warning level is 0.15), floor box (384, 545, 896, 705) on the bare clearing, `disparity = 14.327 / z - 0.853`. `walkable.py`:
  36x35 cells of 0.25 m, **413 standable**. The kind's actor spots (76 % of the way from the horizon down) put the witch 3.0 m from the
  camera under this high horizon, a giant in the frame, and the raccoon on an edge cell: the brief places them at 60 % and 64 %
  (witch 3.8 m, the street room's is 4.4 m; raccoon to her right), both on standable cells. The drafted `life.json` took eyeball
  flowers, tiles, a water lily and the sign's eye for lamps and found 2 of the 5 lanterns: rewritten by hand (5 lantern candles, the
  fog breathing, the moon's glint on the water). Provenance: `assets/painted/fog_edge/job_room.json`.
- Capture (`capture_painted.gd ... views`, xvfb, Godot 4.6.3 Compatibility): the witch stands on the clearing at the head of the path,
  facing the fog, the raccoon beside her; feet grounded, occlusion right, no script errors. In the PSX view the faceted 3D characters
  are closer to reference 13 than the plate is: the plate's smooth cartoon paint is the gap. Steps of 35 and 80 cm smear the tree's
  edges and show void at the right edge (no overscan margin), as in the other rooms.
- Limit seen: `walkable.py` takes the still black water beside the path, near the bank, for floor (flat, at floor height, under
  11 m): the witch can walk a little way onto the water. It has no notion of water; a colour mask or a "not floor" polygon would fix it.
