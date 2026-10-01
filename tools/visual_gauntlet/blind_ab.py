#!/usr/bin/env python3
"""Prepares a BLIND A/B for a critic: two images, labels randomised, names stripped.

    python tools/visual_gauntlet/blind_ab.py ours.png bar.png out_dir [--seed N] [--key PATH]
        [--mode matched|letterbox] [--size 1280x720] [--filter lanczos|bicubic|nearest] [--print-prompt]
    python tools/visual_gauntlet/blind_ab.py --selftest

Writes out_dir/A.png and out_dir/B.png (plain RGB, no metadata) and a private key (which is which,
the seed, the mode) to <out_dir>_KEY.json BESIDE the folder, not in it, so a critic handed the
folder cannot read it; --key puts it elsewhere. Only the lead reads the key.

  matched (default)  both are centre-cropped to the output's aspect, brought down to ONE working
                     resolution (the lower of the two after the crop, capped at the output size) and
                     scaled up to the output size with the same filter. Crop, size, sharpness and
                     pixel scale are then identical, so resolution cannot decide a blind pick.
  letterbox          each image fitted whole inside the output with black bars (the old behaviour).

--print-prompt prints critic_prompt.md's prompt with the two absolute paths filled in, ready to hand
to a fresh critic subagent.
"""
import json
import os
import random
import re
import sys

from PIL import Image, PngImagePlugin

HERE = os.path.dirname(os.path.abspath(__file__))
FILTERS = {"lanczos": Image.LANCZOS, "bicubic": Image.BICUBIC, "nearest": Image.NEAREST}
PROMPT_CUT = "---8<---"
# words that would tell the critic where an image came from (checked by --selftest)
TELLS = ("game", "ours", "our ", "reference", "target", "godot", "psx", "engine", "screenshot", "painting",
         "painted", "illustration", "concept", "original", "copy", "witch", "raccoon", "round", "iteration", "player")


def fit(img, size):
    """Letterbox: the whole image inside `size`, black bars."""
    img = img.convert("RGB")
    scale = min(size[0] / img.width, size[1] / img.height)
    resized = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGB", size, (0, 0, 0))
    canvas.paste(resized, ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2))
    return canvas


def crop_box(w, h, aspect):
    """The largest centred box of `aspect` inside a w x h image."""
    if w / h > aspect:
        cw = max(1, int(round(h * aspect)))
        return ((w - cw) // 2, 0, (w - cw) // 2 + cw, h)
    ch = max(1, int(round(w / aspect)))
    return (0, (h - ch) // 2, w, (h - ch) // 2 + ch)


def matched(images, size, resample=Image.LANCZOS):
    """Same crop, same working resolution, same upscale for every image. Returns (images, info)."""
    aspect = size[0] / size[1]
    crops = [img.convert("RGB").crop(crop_box(img.width, img.height, aspect)) for img in images]
    work_h = min([c.height for c in crops] + [size[1]])
    work = (max(1, int(round(work_h * aspect))), work_h)
    out = []
    for c in crops:
        c = c.resize(work, Image.LANCZOS) if c.size != work else c
        out.append(c.resize(size, resample) if work != size else c)
    return out, {"working_size": list(work)}


def critic_prompt(a_path, b_path):
    lines = open(os.path.join(HERE, "critic_prompt.md"), encoding="utf-8").read().splitlines()
    cuts = [i for i, line in enumerate(lines) if line.strip() == PROMPT_CUT]
    if len(cuts) != 2:
        raise ValueError("critic_prompt.md must hold the prompt between two %s lines" % PROMPT_CUT)
    body = "\n".join(lines[cuts[0] + 1:cuts[1]]).strip("\n")
    return body.replace("{{A}}", os.path.abspath(a_path)).replace("{{B}}", os.path.abspath(b_path)) + "\n"


def prepare(ours, bar, out, seed=None, key=None, mode="matched", size=(1280, 720), resample="lanczos"):
    if seed is None:
        seed = random.SystemRandom().randrange(1 << 30)
    os.makedirs(out, exist_ok=True)
    srcs = [Image.open(ours), Image.open(bar)]
    if mode == "matched":
        imgs, info = matched(srcs, size, FILTERS[resample])
    elif mode == "letterbox":
        imgs, info = [fit(s, size) for s in srcs], {}
    else:
        raise ValueError("mode is matched or letterbox, not %r" % mode)
    pair = [("ours", imgs[0], ours), ("bar", imgs[1], bar)]
    random.Random(seed).shuffle(pair)
    paths = [os.path.join(out, "A.png"), os.path.join(out, "B.png")]
    for (_, img, _), p in zip(pair, paths):
        # rebuilt from raw pixels: no ICC profile, text chunk or gamma tag survives to give a source away
        Image.frombytes("RGB", img.size, img.convert("RGB").tobytes()).save(p)
    key = key or os.path.normpath(out) + "_KEY.json"
    record = {"A": pair[0][0], "B": pair[1][0], "seed": seed, "mode": mode, "size": list(size), "filter": resample,
              "sources": {"A": pair[0][2], "B": pair[1][2]}}
    record.update(info)
    with open(key, "w") as f:
        json.dump(record, f, indent=1)
    return paths, key, record


def selftest():
    import tempfile
    import numpy as np
    sys.path.insert(0, HERE)
    import squint
    with tempfile.TemporaryDirectory() as d:
        # one picture at two resolutions: 1672x941 RGB and 640x360 RGBA
        scene = (squint._scene(1672, 941) * 255).astype(np.uint8)
        bar = os.path.join(d, "bar.png")
        ours = os.path.join(d, "ours.png")
        tags = PngImagePlugin.PngInfo()
        tags.add_text("Software", "a tell")
        Image.fromarray(scene).save(bar, pnginfo=tags, icc_profile=b"a tell", gamma=0.45)
        Image.fromarray(scene).resize((640, 360), Image.LANCZOS).convert("RGBA").save(ours, pnginfo=tags)
        diff = lambda x, y: np.abs(np.asarray(x, dtype=np.float32) - np.asarray(y, dtype=np.float32)).mean()  # noqa: E731
        labels = set()
        for seed in range(8):
            out = os.path.join(d, "ab%d" % seed)
            paths, key, rec = prepare(ours, bar, out, seed=seed)
            assert key == out + "_KEY.json" and not os.path.exists(os.path.join(out, "KEY.json"))
            assert sorted(os.listdir(out)) == ["A.png", "B.png"]
            a, b = Image.open(paths[0]), Image.open(paths[1])
            assert a.size == b.size == (1280, 720) and a.mode == b.mode == "RGB" and a.info == b.info == {}, (a.info, b.info)
            assert rec["working_size"] == [640, 360], rec
            assert {rec["A"], rec["B"]} == {"ours", "bar"}
            labels.add(rec["A"])
            # same seed, same labels
            assert prepare(ours, bar, out + "x", seed=seed)[2]["A"] == rec["A"]
            # matched really matches: the same picture at two resolutions comes out the same
            matched_gap = diff(a, b)
            assert matched_gap < 1.0, matched_gap
        assert labels == {"ours", "bar"}, "labels never swap"
        # letterbox (the old mode) keeps the resolution gap that matched mode closes
        paths, _, rec = prepare(ours, bar, os.path.join(d, "lb"), seed=1, mode="letterbox", key=os.path.join(d, "k.json"))
        assert os.path.exists(os.path.join(d, "k.json")) and "working_size" not in rec
        assert diff(Image.open(paths[0]), Image.open(paths[1])) > 2 * matched_gap
        # a 4:3 output crops both to 4:3: the same middle of the picture
        paths, _, rec = prepare(ours, bar, os.path.join(d, "43"), seed=2, size=(960, 720))
        assert rec["working_size"] == [480, 360] and Image.open(paths[0]).size == (960, 720)
        assert squint.score(Image.open(paths[0]), Image.open(paths[1]))["ssim_64x36"] > 0.95
    # the critic prompt is fillable and does not say where either image comes from
    prompt = critic_prompt("x/A.png", "x/B.png")
    assert "{{" not in prompt and os.path.abspath("x/A.png") in prompt and os.path.abspath("x/B.png") in prompt
    body = prompt.lower().replace(os.path.abspath("x").lower(), "")
    found = [w for w in TELLS if re.search(r"\b" + re.escape(w.strip()) + (r"\b" if not w.endswith(" ") else r"\s"), body)]
    assert not found, "critic prompt gives away the source: %s" % found
    print("blind_ab selftest OK")


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="*", help="ours.png bar.png out_dir")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--key", help="where the private key goes (default: <out_dir>_KEY.json)")
    ap.add_argument("--mode", choices=("matched", "letterbox"), default="matched")
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--filter", choices=sorted(FILTERS), default="lanczos")
    ap.add_argument("--print-prompt", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return
    if len(args.files) != 3:
        ap.error("give ours.png bar.png out_dir")
    size = tuple(int(v) for v in args.size.lower().split("x"))
    paths, key, rec = prepare(args.files[0], args.files[1], args.files[2], args.seed, args.key, args.mode, size, args.filter)
    print("wrote", args.files[2], "(%s, %dx%d); the key is %s, for the lead only" % (args.mode, size[0], size[1], key), file=sys.stderr)
    if args.print_prompt:
        print(critic_prompt(*paths))


if __name__ == "__main__":
    main()
