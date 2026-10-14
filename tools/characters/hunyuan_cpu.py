#!/usr/bin/env python3
"""Hunyuan3D-2mv-turbo on a CPU: three views of a character to a shape (.glb), no GPU, no account, no quota.

    python hunyuan_cpu.py setup  DIR                      # once: the source (a Hugging Face Space) and the weights (about 6 GB) into DIR
    python hunyuan_cpu.py run    DIR VIEWS OUT.glb        # VIEWS = a folder with front.png, left.png, back.png (multiview.py's views/)
    python hunyuan_cpu.py batch  DIR OUT_DIR NAME=VIEWS ...   # one model load, one mesh per NAME (OUT_DIR/NAME.glb): the load is 100 s, a mesh 200 s

Run it with the Python of a virtualenv made for it (docs/art/cpu_pipeline.md): the checkpoint's DINOv2 key names only load under transformers 4.x, which wants
huggingface-hub below 1.0, which gradio_client (image2rig.py) refuses. Needed there: torch (cpu), torchvision, transformers==4.51.3, huggingface-hub<1.0, diffusers,
einops, omegaconf, pyyaml, trimesh, opencv-python-headless, pymeshlab, scikit-image, pillow, numpy.

The working point measured on a 4 vCPU Xeon (AVX-512 VNNI, no bf16) with 14 GB: dynamic int8 on every Linear, Tencent's turbo VAE with the FlashVDM decoder, 3 steps, octree 128:
133 s to load, then 211 s a mesh (fp32 with the plain decoder and 5 steps: 809 s). Peak memory is 13.5 GB of 14: the weights are read in fp16, built in fp16, converted to fp32 and quantised
in place. Do not run anything else large beside it. Fewer than 3 steps degrade the shape; fewer than 3 views lose the side silhouettes.
The licence of the model is the Tencent Hunyuan community licence.
"""
import argparse
import gc
import sys
import time
from pathlib import Path

SPACE, MODEL, VAE_REPO = "tencent/Hunyuan3D-2mv", "hunyuan3d-dit-v2-mv-turbo", "hunyuan3d-vae-v2-0-turbo"
VIEW_NAMES = ("front", "left", "back")


def setup(root):
    from huggingface_hub import snapshot_download
    root = Path(root)
    snapshot_download(SPACE, repo_type="space", allow_patterns=["hy3dgen/**"], local_dir=root / "space")
    snapshot_download(SPACE, allow_patterns=[MODEL + "/config.yaml", MODEL + "/model.fp16.safetensors"], local_dir=root / "weights")
    snapshot_download("tencent/Hunyuan3D-2", allow_patterns=[VAE_REPO + "/config.yaml", VAE_REPO + "/model.fp16.safetensors"], local_dir=root / "weights_vae")
    print("ready in", root)


def enable_merge(pipe, n):
    """Average the DINOv2 condition tokens in n x n blocks of each view's 37 x 37 patch grid (the class token stays): the DiT attends over the views' tokens joined to its 3,072
    latents, so 4,110 + 3,072 tokens become 1,086 + 3,072 for n = 2. Measured on the witch: 98 s a mesh instead of 211 s, silhouette IoU 0.853 against 0.866 (the seed-to-seed
    noise floor of the shape distance is 0.0082, this costs 0.0108). On the generated jug it changed nothing (IoU 0.845 against 0.849); on Vera it cost 0.07 to 0.08 of front and back
    silhouette IoU: use it for props and drafts, not for characters. Dropping background tokens, or keeping the figure at full resolution and merging only the background, was much worse."""
    import torch
    F = torch.nn.functional
    orig = pipe.encode_cond

    def merged(image, additional_cond_inputs, do_classifier_free_guidance, dual_guidance):
        cond = dict(orig(image, additional_cond_inputs, do_classifier_free_guidance, dual_guidance))
        main = cond["main"]
        views = image.shape[1]
        per = main.shape[1] // views
        side = int(round((per - 1) ** 0.5))
        out = []
        for v in range(views):
            t = main[0, v * per:(v + 1) * per]
            grid = t[1:].reshape(side, side, -1).permute(2, 0, 1)[None]
            pad = (-side) % n
            grid = F.pad(grid, (0, pad, 0, pad), mode="replicate")
            out += [t[:1], F.avg_pool2d(grid, n)[0].permute(1, 2, 0).reshape(-1, t.shape[-1])]
        cond["main"] = torch.cat(out, 0)[None]
        return cond
    pipe.encode_cond = merged


def load(root, int8=True, flash=True, log=print, merge=0):
    """The pipeline, fp32 on the CPU, with the turbo VAE and int8 Linear layers unless switched off."""
    root = Path(root)
    sys.path.insert(0, str(root / "space"))
    import torch
    torch.set_num_threads(__import__("os").cpu_count() or 4)
    from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline
    from hy3dgen.shapegen.models import ShapeVAE
    torch.set_default_dtype(torch.float16)                      # build in fp16 (half the memory), convert after the weights are in
    pipe = Hunyuan3DDiTFlowMatchingPipeline.from_single_file(
        str(root / "weights" / MODEL / "model.fp16.safetensors"), str(root / "weights" / MODEL / "config.yaml"),
        device="cpu", dtype=torch.float32, use_safetensors=True)
    torch.set_default_dtype(torch.float32)
    for m in (pipe.model, pipe.vae, pipe.conditioner):
        m.float()                                               # no bf16 units on most CPUs: emulation is hundreds of times slower
    if flash:
        pipe.vae = ShapeVAE.from_single_file(str(root / "weights_vae" / VAE_REPO / "model.fp16.safetensors"), str(root / "weights_vae" / VAE_REPO / "config.yaml"),
                                             device="cpu", dtype=torch.float32, use_safetensors=True)
        pipe.vae.enable_flashvdm_decoder(enabled=True, adaptive_kv_selection=True, topk_mode="mean", mc_algo="mc")
    if int8:
        from torch.ao.quantization import quantize_dynamic
        gc.collect()
        pipe.model = quantize_dynamic(pipe.model, {torch.nn.Linear}, dtype=torch.qint8, inplace=True)   # inplace: a copy would be killed at the 14 GB limit
        pipe.conditioner = quantize_dynamic(pipe.conditioner, {torch.nn.Linear}, dtype=torch.qint8, inplace=True)
        gc.collect()
    if merge > 1:
        enable_merge(pipe, merge)
    log("pipeline ready (int8=%s, flashvdm=%s, token merge=%s)" % (int8, flash, merge or "off"))
    return pipe


def shape(pipe, views, steps=3, octree=128, seed=1234, log=print):
    """A trimesh from `views` (a folder or a {name: path} mapping of front, left, back cut-outs with alpha)."""
    import torch
    from PIL import Image
    if not isinstance(views, dict):
        views = {n: Path(views) / (n + ".png") for n in VIEW_NAMES}
    images = {n: Image.open(p).convert("RGBA") for n, p in views.items()}
    t = time.time()
    out = pipe(image=images, num_inference_steps=steps, guidance_scale=5.0, octree_resolution=octree, num_chunks=20000, mc_algo="mc",
               generator=torch.Generator("cpu").manual_seed(seed), enable_pbar=False)
    mesh = out[0][0] if isinstance(out[0], list) else out[0]
    log("shape: %d faces in %.0f s" % (len(mesh.faces), time.time() - t))
    return mesh


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("setup").add_argument("dir")
    r = sub.add_parser("run")
    r.add_argument("dir")
    r.add_argument("views")
    r.add_argument("out")
    r.add_argument("--steps", type=int, default=3)
    r.add_argument("--octree", type=int, default=128)
    r.add_argument("--seed", type=int, default=1234)
    r.add_argument("--fp32", action="store_true", help="no int8 (about 2.5 x slower)")
    r.add_argument("--no-flash", action="store_true", help="the plain volume decoder (about 5 minutes more)")
    r.add_argument("--merge", type=int, default=0, help="average the condition tokens in n x n blocks (2: twice as fast; fine for props, costly for characters: see enable_merge)")
    b = sub.add_parser("batch")
    b.add_argument("dir")
    b.add_argument("out_dir")
    b.add_argument("jobs", nargs="+", help="NAME=VIEWS_FOLDER")
    b.add_argument("--steps", type=int, default=3)
    b.add_argument("--octree", type=int, default=128)
    b.add_argument("--seed", type=int, default=1234)
    b.add_argument("--merge", type=int, default=0, help="average the condition tokens in n x n blocks (2: twice as fast; fine for props, costly for characters: see enable_merge)")
    a = ap.parse_args(argv)
    if a.cmd == "batch":
        t0 = time.time()
        pipe = load(a.dir, merge=a.merge)
        print("loaded in %.0f s" % (time.time() - t0), flush=True)
        for job in a.jobs:
            name, _, views = job.partition("=")
            mesh = shape(pipe, views, a.steps, a.octree, a.seed)
            dest = Path(a.out_dir) / (name + ".glb")
            dest.parent.mkdir(parents=True, exist_ok=True)
            mesh.export(dest)
            print("%s written, %.0f s since the start" % (dest, time.time() - t0), flush=True)
        return 0
    if a.cmd == "setup":
        setup(a.dir)
        return 0
    t0 = time.time()
    pipe = load(a.dir, int8=not a.fp32, flash=not a.no_flash, merge=a.merge)
    print("loaded in %.0f s" % (time.time() - t0))
    mesh = shape(pipe, a.views, a.steps, a.octree, a.seed)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    mesh.export(a.out)
    print("%s written, %.0f s in all" % (a.out, time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
