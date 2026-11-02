#!/usr/bin/env python3
"""The PS1 pass: gives a smooth plate the crude look of the references, with no GPU and no quota.

A generator paints smooth gradients and outlines. The references (docs/art/references/13, 15, 16, 17, 04) are low-poly 3D
drawn with chunky texels, a small palette and dither that sits inside each texel. The pass does, in order:

  1. texels: area-average the plate onto a grid of `texel` x `texel` pixel blocks (a 1280x720 plate at texel 5 is 256x144 texels);
  2. cool shadows (`--cool`): dark texels shift toward indigo and plum;
  3. grade: `--sat`, `--gamma` (a tone curve: a dark plate's mids lift), `--lift`; split tone (`--hi`, `--lo`): highlights take a
     gold tint and shadows an indigo one, each keeping its texel's luminance;
  4. the references' hue bias (`--transfer`): a Reinhard transfer in Lab toward the references' mean and spread (0 is none);
  5. palette: the texture's own colour table, as a PS1 CLUT: k-means over the plate's texels (`--colours` minus 24) plus 24
     colours from the references, so rare references' hues (gold, green) are never lost to the plate's clusters;
     each texel takes its nearest colour in CIE Lab, after the Bayer 4x4 ordered dither (`--dither`) is added to the TEXEL,
     so the dither lives inside the texture, not per screen pixel;
  6. the texel grid is scaled back up with nearest neighbour: every texel is a flat block of one colour.

    python tools/hfspaces/ps1pass.py apply IN.png OUT.png [--texel 5] [--palette plate|FILE.json|15bit] [--colours 48]
                 [--transfer 0.6] [--dither 0.6] [--cool 0.0] [--sat 1.0] [--gamma 1.0] [--lift 1.0]
                 [--hi '#f2b441' --hi-amount 0.5] [--lo '#2a1f5c' --lo-amount 0.4]
    python tools/hfspaces/ps1pass.py measure A.png [B.png ...]     # the numbers of docs/art/ps1pass.md (free)

`apply` writes OUT.png and OUT.png.json (the parameters, the input's and the output's hashes). Needs numpy, Pillow and scipy.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "visual_gauntlet"))
REFERENCES = [ROOT / "docs/art/references" / name for name in (
    "13_marsh_clocks_night.jpg", "15_clock_tower_stairs.jpg", "16_shop_window_fog.jpg", "17_crooked_doors_footprints.jpg",
    "04_hotel_beyond_lobby.png")]
BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16.0 - 0.5
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)
SRGB_TO_XYZ = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], np.float32)
WHITE = np.array([0.95047, 1.0, 1.08883], np.float32)


# ---- colour ------------------------------------------------------------------------------------------------------------------
def to_lab(rgb):
    """sRGB floats in [0, 1], shape (..., 3) -> CIE Lab (..., 3). Lab distances are what the eye sees, so the palette lookup uses them."""
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    t = (lin @ SRGB_TO_XYZ.T) / WHITE
    f = np.where(t > (6 / 29) ** 3, np.cbrt(t), t / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def sha256_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_rgb(path):
    with Image.open(path) as im:
        return np.asarray(im.convert("RGB"), np.float32) / 255.0


# ---- the palette -----------------------------------------------------------------------------------------------------------------
def texel_samples(path, texel_width):
    """A reference at the plate's texel scale: resized so its width is `texel_width` texels (area average), as float RGB."""
    with Image.open(path) as im:
        w, h = im.size
        small = im.convert("RGB").resize((texel_width, max(1, round(h * texel_width / w))), Image.BOX)
    return np.asarray(small, np.float32).reshape(-1, 3) / 255.0


def kmeans(points, k, seed=7, iterations=40):
    """Plain k-means on Lab points, seeded (the same palette every time). Returns the centres in Lab."""
    rng = np.random.default_rng(seed)
    centres = points[rng.choice(len(points), k, replace=False)].copy()
    sq = (points ** 2).sum(1)[:, None]
    for _ in range(iterations):
        d = sq + (centres ** 2).sum(1)[None, :] - 2.0 * points @ centres.T
        label = d.argmin(1)
        for j in range(k):
            members = points[label == j]
            if len(members):
                centres[j] = members.mean(0)
    return centres


def reference_stats(refs, texel_width=256):
    """Mean and spread of the references' texels in Lab (all references pooled): the colour a plate is pulled toward."""
    lab = to_lab(np.concatenate([texel_samples(r, texel_width) for r in refs]))
    return lab.mean(0), lab.std(0)


def transfer(rgb, mu_ref, sd_ref, strength, chroma=None):
    """Reinhard colour transfer in Lab: the plate's texels take the references' mean and spread, by `strength` (0 to 1) for
    lightness and by `chroma` (default: the same) for the a and b axes. The chroma pull moves a plate's hues toward the
    references' pooled mean, which is violet-magenta: a violet plate gets more magenta, and its blues drift to violet, so a
    smaller chroma pull keeps the blues the references have."""
    if strength <= 0:
        return rgb
    chroma = strength if chroma is None else chroma
    lab = to_lab(rgb)
    mu = lab.reshape(-1, 3).mean(0)
    sd = np.maximum(lab.reshape(-1, 3).std(0), 1e-3)
    scale = np.clip(sd_ref / sd, 0.5, 2.0)
    moved = (lab - mu) * scale + mu_ref
    weight = np.array([strength, chroma, chroma], np.float32)
    return np.clip(lab_to_rgb(lab * (1 - weight) + moved * weight), 0.0, 1.0)


def plate_palette(rgb, colours=48, refs=None, ref_colours=24, seed=7):
    """The colour table: the plate's own colours (k-means over its texels in Lab, so its hues survive), plus `ref_colours` from
    the references pooled (so a rare gold or green is never lost to a purple plate's clusters). SRGB floats, dark first."""
    lab = to_lab(rgb.reshape(-1, 3))
    if refs:
        ref_colours = min(ref_colours, colours // 2)
    own = colours - (ref_colours if refs else 0)
    centres = kmeans(lab, max(1, min(own, len(np.unique(lab.round(2), axis=0)))), seed=seed)
    if refs:
        ref_lab = to_lab(np.concatenate([texel_samples(r, 256) for r in refs]))
        centres = np.concatenate([centres, kmeans(ref_lab, ref_colours, seed=seed)])
    out = np.clip(lab_to_rgb(centres), 0.0, 1.0)
    return out[np.argsort(to_lab(out)[:, 0])]


def lab_to_rgb(lab):
    fy = (lab[..., 0] + 16) / 116
    fx = fy + lab[..., 1] / 500
    fz = fy - lab[..., 2] / 200
    f = np.stack([fx, fy, fz], -1)
    t = np.where(f > 6 / 29, f ** 3, 3 * (6 / 29) ** 2 * (f - 4 / 29))
    xyz = t * WHITE
    inv = np.linalg.inv(SRGB_TO_XYZ)
    lin = xyz @ inv.T
    lin = np.clip(lin, 0.0, None)
    srgb = np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    return srgb


# ---- the pass --------------------------------------------------------------------------------------------------------------
def texels(img, texel):
    """Area-average the image onto a texel grid. The grid is cropped to whole texels first (the rest is at most texel - 1 px)."""
    h, w = img.shape[:2]
    gw, gh = w // texel, h // texel
    cropped = img[:gh * texel, :gw * texel]
    return cropped.reshape(gh, texel, gw, texel, 3).mean(axis=(1, 3)), (gw, gh)


def cool_shadows(rgb, amount, cool_lum=0.45):
    """Dark texels move toward indigo and plum (more red and blue, less green); lit texels are untouched."""
    if amount <= 0:
        return rgb
    lum = rgb @ LUMA
    s = np.clip((cool_lum - lum) / cool_lum, 0.0, 1.0)[..., None] * amount
    return np.clip(rgb * (1 - s) + rgb * np.array([1.06, 0.84, 1.14], np.float32) * s, 0.0, 1.0)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def split_tone(rgb, hi=None, hi_amount=0.0, lo=None, lo_amount=0.0):
    """Split toning that keeps each texel's luminance: highlights take the colour `hi` (gold, for the references' accents),
    shadows take `lo` (indigo or plum, the cool shadows). Each tint is normalised to luminance 1 first."""
    lum = rgb @ LUMA
    out = rgb
    for tint, amount, w in ((lo, lo_amount, (1 - smoothstep(0.08, 0.40, lum)) * lo_amount),
                            (hi, hi_amount, smoothstep(0.35, 0.80, lum) * hi_amount)):
        if tint is None or amount <= 0:
            continue
        t = np.asarray(tint, np.float32)
        t = t / max(float(t @ LUMA), 1e-3)
        out = out * (1 - w[..., None]) + (lum[..., None] * t) * w[..., None]
    return np.clip(out, 0.0, 1.0)


def hex_colour(text):
    text = text.strip().lstrip("#")
    if len(text) != 6:
        raise argparse.ArgumentTypeError("a colour is #RRGGBB")
    return tuple(int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def grade(rgb, sat=1.0, lift=1.0, gamma=1.0):
    """Saturation, then a tone curve (gamma below 1 lifts the mids of a dark plate; the references are not black), then a gain."""
    if sat != 1.0:
        lum = (rgb @ LUMA)[..., None]
        rgb = lum + (rgb - lum) * sat
    if gamma != 1.0:
        rgb = np.power(np.clip(rgb, 0.0, 1.0), gamma)
    if lift != 1.0:
        rgb = rgb * lift
    return np.clip(rgb, 0.0, 1.0)


def palette_map(rgb, palette_rgb, dither):
    """Nearest palette colour per texel (Lab), after the Bayer 4x4 dither is added to each texel (its amplitude is `dither` times
    the palette's average spacing, so the dither lives inside the texture and is per texel)."""
    k = len(palette_rgb)
    spacing = 1.0 / (k ** (1 / 3))
    gh, gw = rgb.shape[:2]
    ys, xs = np.mgrid[0:gh, 0:gw]
    offset = BAYER4[ys % 4, xs % 4][..., None] * dither * spacing
    lab = to_lab(np.clip(rgb + offset, 0.0, 1.0))
    pal_lab = to_lab(palette_rgb)
    d = ((lab[:, :, None, :] - pal_lab[None, None, :, :]) ** 2).sum(-1)
    return palette_rgb[d.argmin(-1)]


def bits_map(rgb, bits=5, dither=1.0):
    """The PS1's 15-bit colour: each channel to `bits` bits with the same Bayer dither (no palette)."""
    levels = (1 << bits) - 1
    gh, gw = rgb.shape[:2]
    ys, xs = np.mgrid[0:gh, 0:gw]
    t = BAYER4[ys % 4, xs % 4][..., None] * dither
    return np.clip(np.round(rgb * levels + t), 0, levels) / levels


def apply(src, dst, *, texel=5, palette="plate", colours=48, transfer_to=0.6, chroma=None, dither=0.6, cool=0.0, sat=1.0, lift=1.0,
          gamma=1.0, hi=None, hi_amount=0.0, lo=None, lo_amount=0.0, use_palette=True, refs=None):
    """Runs the pass; writes DST (PNG at the input's size) and DST.json; returns the provenance dict.

    palette: "plate" (the plate's own colour table, k-means on its texels after the reference transfer), or a JSON file of
    colours (e.g. the references' palette from `palette`), or "15bit" (no table: 5 bits a channel, as the PS1 framebuffer)."""
    img = load_rgb(src)
    h, w = img.shape[:2]
    grid, (gw, gh) = texels(img, texel)
    grid = cool_shadows(grid, cool)
    grid = grade(grid, sat=sat, lift=lift, gamma=gamma)
    grid = split_tone(grid, hi=hi, hi_amount=hi_amount, lo=lo, lo_amount=lo_amount)
    provenance = {"tool": "tools/hfspaces/ps1pass.py apply", "source": str(src), "source_sha256": sha256_file(src),
                  "size": [w, h], "texel": texel, "grid": [gw, gh], "dither": dither, "cool": cool, "sat": sat, "lift": lift,
                  "gamma": gamma, "transfer_to_references": transfer_to,
                  "transfer_chroma": transfer_to if chroma is None else chroma,
                  "split_tone": {"hi": hi, "hi_amount": hi_amount, "lo": lo, "lo_amount": lo_amount}}
    if transfer_to > 0:
        mu_ref, sd_ref = reference_stats([Path(r) for r in (REFERENCES if refs is None else refs)])
        grid = transfer(grid, mu_ref, sd_ref, transfer_to, chroma=chroma)
    if palette == "15bit" or not use_palette:
        quant = bits_map(grid, 5, dither)
        provenance.update(palette=None, bits=5)
    else:
        if palette == "plate":
            palette_rgb = plate_palette(grid, colours, refs=[Path(r) for r in (REFERENCES if refs is None else refs)])
            provenance.update(palette="plate", colours=len(palette_rgb), palette_refs_colours=24)
        else:
            pal = json.loads(Path(palette).read_text(encoding="utf-8"))
            palette_rgb = np.asarray(pal["colours"], np.float32) / 255.0
            provenance.update(palette=str(Path(palette).name), palette_sha256=sha256_file(palette), colours=len(palette_rgb))
        quant = palette_map(grid, palette_rgb, dither)
    out = np.repeat(np.repeat(quant, texel, axis=0), texel, axis=1)
    if out.shape[0] < h or out.shape[1] < w:                     # the crop's remainder: nearest, like the rest
        out = np.asarray(Image.fromarray(np.round(out * 255).astype(np.uint8)).resize((w, h), Image.NEAREST), np.float32) / 255.0
    out = np.round(np.clip(out[:h, :w], 0, 1) * 255).astype(np.uint8)
    Image.fromarray(out).save(dst)
    provenance["out_sha256"] = sha256_file(dst)
    Path(str(dst) + ".json").write_text(json.dumps(provenance, indent=1) + "\n", encoding="utf-8")
    return provenance


# ---- measurements (the gauntlet's numbers, plus the texel high-frequency share) --------------------------------------------------
def measure_one(path):
    import metrics
    from scipy import ndimage
    m = metrics.analyse(str(path))
    a = metrics.rgb(str(path))
    lum = metrics.luma(a)
    hf = float(np.abs(lum - ndimage.uniform_filter(lum, size=3)).mean() * 100)
    sat, hue, mx = metrics.sat_hue(a.reshape(-1, 3))
    lit = ((mx > 0.18) & (sat > 0.12)).reshape(lum.shape)
    hue = hue.reshape(lum.shape)

    def share(lo, hi):
        return round(float((lit & (hue >= lo) & (hue < hi)).mean()), 3)
    return {"file": str(path), "median_luma": round(float(np.median(lum)), 3), "mean_sat": m["mean_saturation"],
            "purple": share(255, 300), "magenta": share(300, 345), "gold": share(30, 65), "green": share(70, 160),
            "blue": share(190, 255), "facet_gradient": m["facet_gradient"], "hf": round(hf, 2),
            "dark_share": m["dark_frame_share_lt_0.12"], "distinct_colours": m["distinct_colours"]}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("apply", help="the pass: IN.png -> OUT.png (+ OUT.png.json)")
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--texel", type=int, default=5, help="block size in pixels (5 on a 1280x720 plate: 256x144 texels)")
    p.add_argument("--palette", default="plate", help="'plate' (its own colour table, the default), 'FILE.json' (a fixed table of "
                                                     "{\"colours\": [[r,g,b] 0-255, ...]}), or '15bit'")
    p.add_argument("--colours", type=int, default=48, help="size of the plate's colour table")
    p.add_argument("--transfer", type=float, default=0.6, help="pull lightness toward the references' Lab mean and spread (0 to 1)")
    p.add_argument("--chroma", type=float, default=None, help="pull the hues too (0 to 1; default: as --transfer)")
    p.add_argument("--dither", type=float, default=0.6, help="Bayer amplitude in palette spacings (0 is none)")
    p.add_argument("--cool", type=float, default=0.0, help="how far dark texels move toward indigo and plum (0 to 1)")
    p.add_argument("--sat", type=float, default=1.0)
    p.add_argument("--lift", type=float, default=1.0)
    p.add_argument("--gamma", type=float, default=1.0, help="tone curve: below 1 lifts the mids (a dark plate: about 0.5 to 0.7)")
    p.add_argument("--hi", type=hex_colour, default=None, help="highlight tint #RRGGBB (the references' gold accents)")
    p.add_argument("--hi-amount", type=float, default=0.0)
    p.add_argument("--lo", type=hex_colour, default=None, help="shadow tint #RRGGBB (indigo or plum)")
    p.add_argument("--lo-amount", type=float, default=0.0)
    p = sub.add_parser("measure", help="the gauntlet's numbers for PNG files (JSON on stdout)")
    p.add_argument("files", nargs="+")
    args = ap.parse_args(argv)
    if args.cmd == "apply":
        prov = apply(args.src, args.dst, texel=args.texel, palette=args.palette, colours=args.colours, transfer_to=args.transfer,
                     chroma=args.chroma, dither=args.dither, cool=args.cool, sat=args.sat, lift=args.lift, gamma=args.gamma, hi=args.hi,
                     hi_amount=args.hi_amount, lo=args.lo, lo_amount=args.lo_amount)
        print("wrote %s (texel %d, grid %dx%d, %s)" % (args.dst, prov["texel"], prov["grid"][0], prov["grid"][1],
                                                     "%d colours" % prov["colours"] if prov.get("colours") else "15-bit"))
        return 0
    print(json.dumps([measure_one(f) for f in args.files], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
