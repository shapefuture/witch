#!/usr/bin/env python3
"""Prepares a BLIND A/B for a critic: two images of the same size, labels randomised, names stripped.

    python tools/visual_gauntlet/blind_ab.py ours.png bar.png out_dir [--seed N]

Writes out_dir/A.png, out_dir/B.png and out_dir/KEY.json (which is which: the critic never sees it).
Both are letterboxed to the same size so size alone cannot give the game away.
"""
import json
import os
import random
import sys

from PIL import Image


def fit(img, size):
    img = img.convert("RGB")
    scale = min(size[0] / img.width, size[1] / img.height)
    resized = img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGB", size, (0, 0, 0))
    canvas.paste(resized, ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2))
    return canvas


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else random.SystemRandom().randrange(1 << 30)
    ours, bar, out = args[0], args[1], args[2]
    os.makedirs(out, exist_ok=True)
    size = (1280, 720)
    pair = [("ours", fit(Image.open(ours), size)), ("bar", fit(Image.open(bar), size))]
    random.Random(seed).shuffle(pair)
    pair[0][1].save(os.path.join(out, "A.png"))
    pair[1][1].save(os.path.join(out, "B.png"))
    with open(os.path.join(out, "KEY.json"), "w") as f:
        json.dump({"A": pair[0][0], "B": pair[1][0], "seed": seed}, f)
    print("wrote", out, "(KEY.json is for the lead only)")


if __name__ == "__main__":
    main()
