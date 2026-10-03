# A character from one picture on a CPU: the bottlenecks, and what dissolves them

Everything here was run on the session's box: **4 vCPU Xeon 2.8 GHz (AVX-512 with VNNI, no bf16/AMX), a 14 GB memory cgroup, no GPU**. "Measured" means a number from a run here;
"read" means taken from a README, a paper or a search result and not run. Tools: `silhouette_hull.py`, `template_rig.py`, `lowpoly_bake.py`, `image2rig.py` (all in `tools/characters/`,
offline tests `test_template_rig.py`, `test_image2rig.py`, `test_multiview.py`).

## The result first

The witch's own T-pose views (`multiview.py make witch --pose t --no-legs`, USD 0.10) went through, with **no GPU, no paid call after the sheet, no neural network after the shape**:

`Hunyuan3D-2mv-turbo on the CPU` (shape) → `image2rig.py paint` (colour from the views) → `template_rig.py` (decimate to 9,000, atlas, skeleton, skin) → a game `.glb` that plays the game's own `idle`, `walk`,
`talk`, `cast` on the fixed skeleton. Frames: `docs/art/cpu_rig/poses_hunyuan_shape.png` (rest T-pose, then idle, walk, talk, cast; the hull version is `poses_silhouette_hull.png` beside it). The face, the hair curls and the robe survive; the arms drop at the shoulders; nothing
crosses the body. 9,000 triangles, one surface, one 256 px atlas, 21 bones (the witch kit's, by name). **Loaded and checked in Godot 4.6.3** (the Linux binary from the engine's GitHub release; a copy of the file as `assets/characters/witch_cpu.glb`, since removed): through `CharacterModels.instantiate` it is 1.300 m tall, feet at 0.000, **1 surface, 8,998 triangles**, its material is the PSX actor shader sampling a 256 px atlas, it has the four clips and keeps the witch's bone names (28 assertions, the shipped rules of `tests/render/test_character_models.gd`). The runner's orphan-node check fails when a suite runs alone (the shipped `test_character_models` fails it the same way, 104 nodes): that is `queue_free` being deferred, not the file. The writer is the kit's own `witch_glb.export`.

And the zero-network floor under it: `silhouette_hull.py` carves the shape from the four silhouettes in **10 s on one core**, same rig on top. It is a blockout, not a character (see "What the cheap shape cannot do").

## Measured on this box

| Step | What | Time | Memory | Notes |
|---|---|---|---|---|
| Hunyuan3D-2mv-turbo, fp32, 3 views, 5 steps, octree 128 | the one heavy step: DINOv2-giant (1.14 B) on 3 views, DiT (1.11 B) x 5, VAE (0.21 B) volume decode | load 69 s, **878 s in all** (sampling about 85 s per step, decode 108 chunks at 3 s) | peak 12.5 GB of 14 (fp16 checkpoint 4.9 GB + fp32 models) | 92,832 faces; silhouette IoU against its own views 0.86 to 0.91 |
| the same, **dynamic int8 on every Linear** (`torch.ao.quantization.quantize_dynamic`, VNNI) and the **FlashVDM** decoder with Tencent's turbo VAE | DINOv2 on 3 views 16.8 s (fp32 about 65 s by subtraction), DiT 5 steps at 59 s (fp32 80 to 85 s), decode **16.5 s** (fp32 about 330 s) | load plus quantise 129 s, **460 s in all (1.9 x faster)** | peak **13.5 GB of 14**: the first try copied the model while quantising and was OOM-killed at 13.9 GB; `inplace=True` fixed it | 99,438 faces. Against the fp32 mesh, Chamfer distance mean 0.6 %, 95th percentile 1.4 %, max 7.3 % of the figure's height (the hull is 2.4 % / 7.1 % away from either); silhouette IoU against the views within 0.007. In the rigged frames (`poses_hunyuan_int8_flashvdm.png`) the face is a little softer than the fp32 one; one sample, one seed |
| silhouette hull (`silhouette_hull.py`) | 224 x 448 x 168 voxels, 4 silhouettes, marching cubes, Taubin, decimation | carve 6 s, mesh 4 s | under 1 GB | IoU against the views 0.91 (front, back) to 0.97 (sides) |
| `image2rig.py paint` | project the 4 views onto the mesh (triangle-id buffer, facing-weighted) | 2 s at 30k faces | | 12 % of vertices never seen (top of the head, under the arms) |
| `template_rig.py` | decimate to 9,000, xatlas, KD-tree atlas bake, skeleton, distance skin, export | **8 s** with five posed preview renders, one process | | atlas uses about half its texels (about 390 charts on a faceted mesh) |
| `lowpoly_bake.py` (Blender, `pip install bpy`) | decimate + smart UV + Cycles colour bake of a 15.8 MB Tencent texture mesh to 9,000 / 256 px | **4.4 s** | | 93 % texels used (it scales islands to fill the square; xatlas keeps one density) |

### The knobs, one model load, int8 + FlashVDM (octree 128, seed 1234 unless noted)

Time is per mesh once the model is loaded (load plus quantisation is another 133 s per process). IoU is the silhouette overlap of the painted mesh with its own four views (the fp32 five-step mesh scores 0.870). Chamfer is against that fp32 mesh, in figure heights; the same int8 model on another seed lands at 0.0082, which is the noise floor.

| Config | Time per mesh | Mean IoU | Chamfer mean / p95 | Reading |
|---|---|---|---|---|
| fp32, vanilla decode, 5 steps, 3 views | 809 s | 0.870 | (reference) | the baseline |
| int8, 5 steps, 3 views | 330 s | 0.866 | 0.0063 / 0.0143 | within seed noise of fp32 |
| int8, other seed (99) | 329 s | 0.862 | 0.0082 / 0.0190 | the noise floor |
| **int8, 3 steps, 3 views** | **211 s** | 0.866 | 0.0075 / 0.0186 | the same by these measures; the hair is a little more ragged to the eye (`poses_hunyuan_int8_3steps.png`) |
| int8, 2 steps, 3 views | 155 s | 0.752 | 0.0182 / 0.0487 | **degraded** (silhouettes 0.71 to 0.80): the turbo model needs about 3 steps |
| int8, 5 steps, front + back | 236 s | 0.833 | 0.0093 / 0.0243 | the side silhouettes drop to 0.78: the side view matters |
| int8, 5 steps, front only | 156 s | 0.828 | 0.0109 / 0.0333 | the model invents the sides; plausible, less faithful |

So the working point is **int8 + FlashVDM, 3 steps, 3 views: 211 s a mesh, 3.8 x faster than the fp32 baseline, 344 s from a cold start.** Views are worth keeping; steps below 3 are not.

## Where the cost is, from first principles

What is scarce on this box is **floating-point work, not memory and not disk**. One DiT step is about 2 x 1.1 B x 3,072 tokens = 6.8 TFLOP of dense matrix work; at 80 s that is about 85 GFLOP/s, a fraction of
the cores' fp32 peak. Everything that follows is a decision about which of that work to not do.

The second look is at what the game needs. The spec is 9,000 triangles, 2 surfaces, a 256 px atlas, one fixed skeleton, a 480 x 360 viewport (`CLAUDE.md`, `tests/render/test_character_models.gd`). A 92,832-face
sculpt, a 1024 px texture and a predicted skeleton are produced and then thrown away: **the generator is run at roughly a hundred times the information the screen can show**, and the one thing the game truly cannot get
from the picture (a skeleton with the game's names, and the clips) it already owns. Seen as a pipeline of information, only two places add anything the artist's picture did not hold: inventing the unseen views, and
guessing depth from appearance. Everything else (UV, skin, bake, decimation, painting, animation) is a deterministic function of those, and does not need a network.

The ideal final result, in TRIZ's phrasing: *the character is in the game, rigged, textured, in budget, playing the standard clips, and nothing was computed.* The resources that already exist at no cost are the
fixed skeleton and clips, the pose lines of the guide image (they fix where the shoulders will be), the views themselves (they are the texture), and the budget (it is the tolerance).

## Contradictions and how each one was resolved (TRIZ, with the far transfer where one helped)

| # | Improve | Without worsening | Principles | What was done, and the result |
|---|---|---|---|---|
| 1 | shape fidelity | CPU time (878 s) | **#35 parameter change** (precision), **#1 segmentation / #16 partial action** (fewer views, coarser grid, skip empty space), **#10 prior action** (embed the views once), **#24 intermediary** (borrow a GPU for this step only), **#27 cheap disposable copy** (the hull) | int8 and FlashVDM: measured above, 878 s to 460 s. The 1.14 B DINOv2 pass depends on the views only, so it can be cached across seeds. The hull is a 10 s look-before-you-spend. A free-quota GPU call for the DiT alone (about 100 GPU-s) leaves everything else on the CPU. Far transfer from **speculative decoding and video codecs** (a cheap draft, a heavy model that only corrects it): the obvious form, start the flow from the hull's latent at partial noise and run 2 steps, is **not possible with the released code**: Tencent's `ShapeVAE` has a decoder only (no `encode`). The form that can work is the hull as a spatial prior for the volume decode (query the grid only near the dilated hull): unmeasured. |
| 2 | automatic rigging of any new mesh | reliability, GPU, credits | **#13 inversion**, **#6 universality**, **#10 prior action**, **#3 local quality**, **#2 taking out**, **#23 feedback** | Do not fit a skeleton to the mesh: fit the mesh to the skeleton the game already has. The T-pose in the sheet is the prior action (the generator was told where the arms go); the front cut-out gives shoulder row, span and torso width; the witch kit's 21 bones are placed there by name, so `witch.clip_set` drives them unchanged. Weights are the distance to each bone segment, softened: a heat solver gives the same on a clean mesh and fails on a generated one (another project's skill file reached the same rule: "bone heat fails on generated meshes", `proc_weights.py` in the Higgsfield game-generation skill). Legs were taken out of the picture (`--no-legs`) so there are none to rig. Check by feedback: pose the result with each clip and look. |
| 3 | texture detail | the 9k / 256 px / 2-surface budget, and the texturing step's GPU or credits | **#2 taking out**, **#22 blessing in disguise**, **#28 replace the mechanism** | The views are the texture: the painter projects them (`paint`), then a nearest-vertex lookup fills the atlas. No texture model runs. A diffusion texturer that outputs 4 K that the budget then crushes to 256 px is work bought and thrown away. The PSX look makes the remaining softness part of the style. |
| 4 | consistency between views | number of generated views and their cost | **#5 merging** (one sheet), **#17 another dimension** (let a 3D object arbitrate), **#4 symmetry** | One generation draws all six. The hull is an arbiter: front and back views agree with their own hull to IoU 0.91 and the side views to 0.97, so the front and back are the ones that disagree most. Mirroring one view for its opposite is untested (the witch's flowers are asymmetric). |
| 5 | big model, free quota | 300 GPU-s a day, 450 to 600 s asked by some Spaces | **#19 periodic action**, **#34 discard and recover**, **#20 continuity**, **#1 segmentation** | Every stage caches its output (`image2rig.py run` keeps a stage whose inputs are unchanged); the guards read each Space's `@spaces.GPU(duration=)` and refuse before spending; a job is split across days; the CPU run needs no quota at all and can go overnight. |
| 6 | use many research tools | one consistent environment | **#1 segmentation**, **#24 intermediary** | One virtualenv per heavy tool, files as the contract (png, glb). Needed today: the Hunyuan checkpoint's DINOv2 key names only load under `transformers` 4.x (5.x renamed the attention modules), which wants `huggingface_hub` below 1.0, which `gradio_client` refuses: the main environment stays on hub 2.x and the CPU run lives in its own venv. |
| 7 | new characters | per-character animation effort | **#6 universality** | One skeleton, one clip set. The clips are functions of bone names (`arm_upper.L`, `spine`, `head`, `cape`...), not of a mesh. A new humanoid costs weights and an atlas, not animation. Bones with no vertices (cape, bird, hair, legs) stay so every clip still plays. |
| 8 | quality on a CPU | no GPU | **#28 replace the mechanism**, **#26 copying** | Silhouette carving, projection, KD-tree lookup, xatlas, distance skinning and a quadric decimator are geometry, not networks, and run in seconds. The network is kept for exactly one thing: depth the silhouettes cannot give (below). |
| 9 | run a large model | little fast memory | tiering, streaming, quantisation (far transfer from **colibri**, llama.cpp, DeepSpeed-style offload) | Colibri streams MoE experts from disk because most experts are idle on any one token. A dense DiT touches every weight every step, and here the limit is arithmetic, not memory, so streaming helps nothing; what transfers is **precision** and **skipping work**. Memory did bite once: a load plus an unneeded copy in `quantize_dynamic` was OOM-killed at 13.9 GB, fixed by quantising in place. |

Physical contradictions (the shape must be both detailed and cheap) were separated rather than traded: **in time** (a 10 s draft, the 15-minute model only if the draft fails the look), **in space** (detail where a player
looks: the face already has its own relief tool, `face_plate.py`; the body can stay coarse), **on condition** (spend the heavy run only when the silhouette IoU or the clip check fails), **in scale** (the global form from
silhouettes, relief from a network).

## Tricks for running a heavy model on weak hardware, and which apply to a dense DiT on 4 cores

| Trick | Source | Applies here? |
|---|---|---|
| Stream weights from disk by routing heat (MoE experts), one hierarchy VRAM, RAM, NVMe | colibri (JustVugg/colibri, 744 B to 2.8 T MoE LLMs, int4, pure C) | **No**: dense model, compute-bound. The principle (do not move or compute what is idle) is what we applied instead. |
| Layer-wise offload with prefetch (AirLLM, mmgp / Hunyuan3D-2GP, accelerate, diffusers `enable_sequential_cpu_offload`) | read | GPU-memory tricks; our CPU holds the whole model. They are the way to run the same DiT in 6 GB of VRAM if a small GPU is ever available. |
| Quantisation: GGUF Q8/Q4 for DiTs (ComfyUI-GGUF, stable-diffusion.cpp), torchao int8/int4, bitsandbytes, SVDQuant | read | GGUF and weight-only int8 save memory and dequantise on the fly (no help when compute-bound); **dynamic int8 on the VNNI units cuts the arithmetic** (measured: DINOv2 about 4 x, the DiT step 1.4 x, because attention and norms stay fp32). SVDQuant/nunchaku are GPU. |
| Do not use bf16 on a CPU without it | HY-Motion CPU docker: about 300 x slower than fp32 on AMD without bf16, 16 min to 22 s after `.float()` | **Yes, followed**: this box has no bf16 units; the loader instantiates in fp16 (half the RAM) and converts to fp32. |
| Fewer denoising steps (the turbo model is the distilled one); cache or skip (TeaCache, DeepCache, TGATE) | read: caching 1.5 to 2 x, training-free | **Measured: 3 steps equals 5 by silhouette IoU and Chamfer (211 s against 330 s); 2 steps fails.** Caching on top of 5 steps was not tried. |
| Fewer tokens: fewer views, lower DINO resolution, token merging | read | **Views measured:** front + back 236 s (-28 %), front only 156 s, but side IoU falls from 0.85 to 0.78 and 0.79. DINO resolution and token merging not tried. |
| Hierarchical or sparse volume decoding (FlashVDM) | Hunyuan3D-2 repo | **Measured: the volume decode fell from about 330 s to 16.5 s** with Tencent's turbo VAE (`hunyuan3d-vae-v2-0-turbo`, 0.8 GB). The biggest single saving. |
| OpenVINO / ONNX Runtime / `torch.compile` | read: Real-ESRGAN on OpenVINO 3.2 to 3.4 x faster than PyTorch on an i7 | Not tried on the DiT; likely the next 1.5 to 3 x. |
| Step distillation (turbo, LCM, SDXS) | the checkpoint we run is one | Already used. |

## Every stage of the pipeline, with CPU-friendly options

| Stage | CPU or near-CPU options | Notes |
|---|---|---|
| **Concept to six views** | Hosted: Marketing Studio via Higgsfield (USD 0.10 a sheet, what we use). Local: stable-diffusion.cpp runs SD, SDXL, FLUX schnell GGUF, Z-Image, FLUX.2-klein, Qwen Image on CPU (a 512 px SD image in about 2.3 GB; read). | Multi-view consistency locally needs a multi-view model (MV-Adapter, Apache-2.0, SDXL based; Zero123++): GPU class, not run. One consistent sheet is the cheap part to buy. |
| **Cut-out** | Our chroma-key matte (free, seconds). For an unkeyed picture: BiRefNet Swin-Tiny ONNX, 224 MB, about 4.3 s for 1024 px on an M1 Max CPU (read); `rembg` (U2-Net family, ONNX); RMBG-2.0 (check its licence first). | Keyed generation removes the need for a network here. |
| **Shape** | Hunyuan3D-2mv-turbo on CPU (measured above); TripoSR (MIT; under half a second on an A100 per its paper; run on this CPU earlier; the roughest); the hull (10 s); Hunyuan3D-2mini (0.6 B shape model, smaller DiT, not run); TRELLIS.2, Hi3DGen (GPU class). | Hunyuan's licence is the Tencent community one (check territory and commercial terms before shipping a model built from it). |
| **Texture** | Projection from the views (`paint`), seconds; Blender Cycles colour bake for an existing textured mesh (`lowpoly_bake.py`). | Diffusion texturers (Hunyuan3D-Paint, Paint3D, MV-Painter, Stable Projectorz) are GPU class and unnecessary at 256 px. |
| **Decimate, retopology, UV** | `fast_simplification` quadric decimation (used), Blender Decimate, QuadriFlow (in Blender, CPU), Instant Meshes (BSD), AutoRemesher; xatlas (MIT; used, `pip install xatlas`), Blender smart UV + pack. | For a rigged mesh that bends at the shoulders a quad retopo would matter; a triangle-decimated 9k mesh with a distance-skinned arm bends acceptably in the frames above. Tencent's retopology (50 credits) is not run. |
| **Skeleton and skin** | `template_rig.py`: the game's own skeleton placed from the silhouette, distance weights (this doc); Blender automatic weights (heat; fails on generated meshes, per the other project's note); donor weight transfer (measured to fail on a posed donor; fine from a T-pose donor); Pinocchio (the 2007 template-fitting rigger, C++, CPU; one fork's LICENSE is GPL-2, the original's terms are not checked); Make-It-Animatable (MIT, GPU Space). | Neural riggers: UniRig needs a CUDA GPU of 8 GB or more (model card); RigAnything is research-only licensed; SkinTokens is refused on the free tier. Tencent's rig (10 credits) works. |
| **Animation** | The game's own clips on the fixed skeleton (free). For new motions: MoMask (MIT; its WebUI runs on a CPU, README), HY-Motion-1.0-Lite (0.46 B; a community CPU docker runs it in 1 to 3 minutes after `.float()`, MIT wrapper), MDM; retarget with Blender. | Not run. |
| **Parts (wand, bird, hair)** | Not needed: they ride the head and hand bones as separate meshes in the kit. For automatic parts: P3-SAM (Hunyuan3D-Part), PartField, SAMesh, SAMPart3D (GPU class). | Not run. |
| **Upscale and normal maps** | Real-ESRGAN with OpenVINO (3.2 to 3.4 x over PyTorch on an i7: 1.2 s for 256 to 1024 px), Upscayl (ncnn, has a CPU flag), pure-CPU forks. | A 256 px atlas rarely needs it. |
| **Integration and budgets** | `tests/render/test_character_models.gd` (surfaces, triangles, atlas, clips, height, feet). | Our output passes the same rules in Godot 4.6.3 (above). A first full project import on this box took over 15 minutes; later runs of one suite take 2 s. |

## What the cheap shape cannot do

The hull is the intersection of silhouettes. It has no face relief and no concavities, and a hat brim comes out as the intersection of two outlines. Two silhouettes also cannot see how thin an arm is, so an arm comes out as
deep as the body. `silhouette_hull.py --arm-depth 0.05` makes the arms tubes by prior (TRIZ #3, local quality): measured, the sleeves get thinner and the silhouette IoU is unchanged. It does **not** fix the worst frame: when
the rig lowers the arms an X appears across the chest (`poses_silhouette_hull.png`), because the hair and ornament masses at the shoulder row are fused to the body in the hull, nearer an arm segment than the spine, and ride the
arm. Distance skinning needs a mesh whose parts are separate, and the Hunyuan shape is (its hair stays in place in the frames above). So: the hull is a blockout, a gate and a rig tester, not a character; the face and the
separated hair are what the 7-minute model buys.

## Next, in order of expected gain per hour

1. The working point is 3 steps at about 59 s each. Attention and norms stay fp32 under `quantize_dynamic`; ONNX Runtime or OpenVINO on the DiT (read: 1.5 to 3 x), a lower DINO resolution or two views instead of three are the next knobs. Seed noise (0.0082) is as large as the int8 difference (0.0063), so the softer face seen once is not evidence of a quantisation loss.
2. Hull as draft: restrict the volume decode to the dilated hull (the released VAE cannot encode, so a partial-noise start from the hull is out). Untested; speculative-decoding transfer.
3. Separate the hair and the head from the body in the hull before skinning (carve them from the views by colour or by the guide's head line), and face relief from `face_plate.py` (already in this repo, from the concept art); if the clip check then passes, the heavy model is only needed for hero characters.
4. Hair on the kit's `hairB`/`hairT` chain so it sways in the clips: a colour mask (vertices painted like the hair, beside or behind the face) was tried and **reverted**: the hair, the face and the sleeves overlap in colour after projection and the mask left stray spikes at the sleeve edges. It needs a geometric split of the hair from the body (a segmentation, or the hull-carving idea in item 3), not a palette.
5. A hips-only skirt: the legless skirt is skinned to the hips, so a walk clip does not swing it; split the skirt's weights along height for a gentle sway.
6. Add a generic check to `tests/render/test_character_models.gd` that runs the rules over every `assets/characters/*.glb`, so a character from this route is gated the day it ships.

## Reproduce

```sh
python tools/characters/multiview.py make witch --ref witch.png --pose t --no-legs       # the sheet (the one paid call, USD 0.10)
python tools/characters/silhouette_hull.py build/views/witch_t_nolegs/views hull.glb --faces 120000   # the free shape
# or the CPU Hunyuan shape (its own venv: transformers 4.51.3, huggingface-hub below 1.0, torch cpu, torchvision, opencv-headless, diffusers)
python tools/characters/template_rig.py build/views/witch_t_nolegs/views shape.glb witch_new.glb     # paint, decimate, atlas, skeleton, skin, clips
python3 tools/characters/test_template_rig.py                                              # offline checks
```
