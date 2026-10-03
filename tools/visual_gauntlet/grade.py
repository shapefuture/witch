#!/usr/bin/env python3
"""A colour grade that moves our plate's colour statistics toward the reference's, as a 3D LUT.

    python tools/visual_gauntlet/grade.py fit REF.png OURS.png lut.png [--strength 0.6] [--size 17] [--preview graded.png]
    python tools/visual_gauntlet/grade.py apply FRAME.png lut.png out.png
    python tools/visual_gauntlet/grade.py --selftest

`fit` looks only at the two images' per-channel histograms in CIE Lab (L, a, b separately), never at
where anything is, so it can match tone and palette but cannot copy the picture: shuffling the
reference's pixels gives the same LUT (the selftest checks it). For each channel it maps every
quantile of ours onto the same quantile of the reference, smooths the offset (Gaussian, 2.5 Lab
units), blends it with the identity by `strength` (0 = no change, 1 = full match) and keeps the curve
monotonic with a slope of at least 1 - strength, so the grade cannot invert, crush or band values.
The curves are then baked into a size^3 RGB LUT over display-referred colour (what our shaders
write and what the PNG frames hold).

In memory a LUT is float32 [size, size, size, 3] indexed lut[r, g, b] (input levels i / (size - 1)).

The strip PNG (`save_strip` / `load_strip`) is the usual LUT-strip layout (Unreal, Unity, Godot):
    width = size * size, height = size, 8-bit RGB, top-left pixel = output for black;
    pixel (x, y) holds the output for  r = x % size,  g = y,  b = x // size   (each / (size - 1)),
i.e. `size` square tiles left to right, one per blue level; inside a tile red grows rightward and
green grows DOWNWARD. In Godot import it as Texture3D with Slices Horizontal = size, Vertical = 1
(slice = blue, u = red, v = green) and use it as Environment.adjustment_color_correction, or sample it
in a shader at (c * (size - 1) + 0.5) / size per axis. A sampler that maps 0..1 straight to the
texture edges (no half-texel inset) is off by up to half a cell: use --size 33 there.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import metrics  # noqa: E402

QUANTILES = np.linspace(0.005, 0.995, 199)
DOMAIN = ((0.0, 100.0), (-128.0, 128.0), (-128.0, 128.0))  # L, a, b
SMOOTH = 2.5  # Lab units

# sRGB (D65) <-> CIE Lab, written out so the gamut test below can see unclipped linear RGB
RGB_TO_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                       [0.2126729, 0.7151522, 0.0721750],
                       [0.0193339, 0.1191920, 0.9503041]])
XYZ_TO_RGB = np.linalg.inv(RGB_TO_XYZ)
WHITE = RGB_TO_XYZ.sum(axis=1)
EPS = 6.0 / 29.0


def rgb_to_lab(rgb):
    c = np.asarray(rgb, dtype=np.float64)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    t = (lin @ RGB_TO_XYZ.T) / WHITE
    f = np.where(t > EPS ** 3, np.cbrt(t), t / (3 * EPS * EPS) + 4.0 / 29.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])], axis=-1)


def _lab_to_linear(L, a, b):
    fy = (L + 16.0) / 116.0
    f = np.stack([fy + a / 500.0, fy, fy - b / 200.0], axis=-1)
    t = np.where(f > EPS, f ** 3, 3 * EPS * EPS * (f - 4.0 / 29.0))
    return (t * WHITE) @ XYZ_TO_RGB.T


def lab_to_rgb(lab):
    """Lab -> display sRGB. A colour outside the sRGB gamut keeps its lightness and hue and loses chroma
    until it fits, instead of having channels clipped (which shifts hue and can make lightness fall)."""
    L = np.clip(lab[..., 0], 0.0, 100.0)
    a, b = lab[..., 1], lab[..., 2]

    def fits(k):
        lin = _lab_to_linear(L, a * k, b * k)
        return np.all((lin > -1e-7) & (lin < 1 + 1e-7), axis=-1)

    lo, hi = np.zeros_like(L), np.ones_like(L)
    inside = fits(hi)
    for _ in range(24):
        mid = (lo + hi) / 2
        ok = fits(mid)
        lo, hi = np.where(ok, mid, lo), np.where(ok, hi, mid)
    k = np.where(inside, 1.0, lo)
    lin = np.clip(_lab_to_linear(L, a * k, b * k), 0.0, 1.0)
    return np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1 / 2.4) - 0.055)


def _lab(src):
    return rgb_to_lab(metrics.rgb(src).reshape(-1, 3))


def channel_curve(src, ref, strength, lo, hi, samples=513):
    """A monotonic curve on a uniform grid over [lo, hi]: x -> x + strength * smoothed(ref_q - src_q)."""
    x, y = np.quantile(src, QUANTILES), np.quantile(ref, QUANTILES)
    # ties in ours (a flat black, say) become one point: the mean of the reference levels they cover
    xu, inv = np.unique(x, return_inverse=True)
    yu = np.bincount(inv, weights=y) / np.bincount(inv)
    grid = np.linspace(lo, hi, samples)
    # the offset is held constant beyond our range: the curve continues with slope 1
    offset = np.interp(grid, xu, yu - xu)
    sigma = SMOOTH / (grid[1] - grid[0])
    offset = ndimage.gaussian_filter1d(offset, sigma, mode="nearest")
    curve = grid + strength * offset
    # smoothing a monotonic curve keeps it monotonic; this guards the edges and float noise
    min_step = (1.0 - strength) * (grid[1] - grid[0]) * 0.999
    steps = np.maximum(np.diff(curve), min_step)
    curve = np.concatenate([[curve[0]], curve[0] + np.cumsum(steps)])
    return grid, curve


def fit_curves(ref_img, src_img, strength=0.6):
    ref, src = _lab(ref_img), _lab(src_img)
    return [channel_curve(src[:, c], ref[:, c], strength, *DOMAIN[c]) for c in range(3)]


def identity(size):
    levels = np.linspace(0.0, 1.0, size, dtype=np.float32)
    r, g, b = np.meshgrid(levels, levels, levels, indexing="ij")
    return np.stack([r, g, b], axis=-1)


def bake(curves, size):
    lab = rgb_to_lab(identity(size).reshape(-1, 3))
    for c, (grid, curve) in enumerate(curves):
        lab[:, c] = np.interp(lab[:, c], grid, curve)
    return lab_to_rgb(lab).reshape(size, size, size, 3).astype(np.float32)


def fit(ref_img, src_img, strength=0.6, size=17):
    """3D LUT that moves src's colour statistics `strength` of the way toward ref's."""
    return bake(fit_curves(ref_img, src_img, strength), size)


def apply(img, lut):
    """Trilinear lookup. Returns the same kind it was given: PIL -> PIL, uint8 -> uint8, float -> float32
    (a path returns a PIL image)."""
    a = metrics.rgb(img)
    n = lut.shape[0]
    p = a * (n - 1)
    i0 = np.clip(np.floor(p).astype(np.int32), 0, n - 2)
    f = p - i0
    out = np.zeros_like(a)
    for dr in (0, 1):
        wr = f[..., 0] if dr else 1.0 - f[..., 0]
        for dg in (0, 1):
            wg = f[..., 1] if dg else 1.0 - f[..., 1]
            for db in (0, 1):
                wb = f[..., 2] if db else 1.0 - f[..., 2]
                out += (wr * wg * wb)[..., None] * lut[i0[..., 0] + dr, i0[..., 1] + dg, i0[..., 2] + db]
    if isinstance(img, np.ndarray):
        return out if img.dtype != np.uint8 else np.round(out * 255).astype(np.uint8)
    return Image.fromarray(np.round(out * 255).astype(np.uint8))


def to_strip(lut):
    n = lut.shape[0]
    return lut.transpose(1, 2, 0, 3).reshape(n, n * n, 3)  # [g, b * n + r]


def save_strip(lut, path):
    Image.fromarray(np.round(np.clip(to_strip(lut), 0, 1) * 255).astype(np.uint8)).save(path)


def load_strip(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    n = a.shape[0]
    if a.shape[1] != n * n:
        raise ValueError("%s is %dx%d, not a LUT strip (width must be height squared)" % (path, a.shape[1], n))
    return a.reshape(n, n, n, 3).transpose(2, 0, 1, 3)  # [g, b, r] -> [r, g, b]


def summary(src):
    lab = _lab(src)
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    return {"L_median": round(float(np.median(lab[:, 0])), 1), "L_p99": round(float(np.percentile(lab[:, 0], 99)), 1),
            "a_median": round(float(np.median(lab[:, 1])), 1), "b_median": round(float(np.median(lab[:, 2])), 1),
            "chroma_mean": round(float(chroma.mean()), 1)}


def selftest():
    import tempfile
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from squint import _scene
    rng = np.random.RandomState(3)
    ref = _scene(320, 180) * 0.7  # darker and olive
    src = np.clip(_scene(320, 180, seed=5)[:, ::-1, ::-1] * 1.2 + 0.05, 0, 1)  # brighter, bluish, other layout
    ident = identity(17)

    # the colour maths agrees with skimage, and the in-gamut round trip is exact
    from skimage import color
    probe = rng.rand(4096, 3)
    assert np.abs(rgb_to_lab(probe) - color.rgb2lab(probe.reshape(-1, 1, 3)).reshape(-1, 3)).max() < 0.05
    assert np.abs(lab_to_rgb(rgb_to_lab(probe)) - probe).max() < 1e-5
    # out of gamut: lightness and hue survive, chroma gives way
    wild = np.array([[60.0, 110.0, -90.0], [90.0, -100.0, 100.0]])
    back = rgb_to_lab(lab_to_rgb(wild))
    assert np.abs(back[:, 0] - wild[:, 0]).max() < 0.05
    assert np.abs(np.arctan2(back[:, 2], back[:, 1]) - np.arctan2(wild[:, 2], wild[:, 1])).max() < 0.02

    # matching an image to itself, or at strength 0, changes nothing
    for lut in (fit(src, src), fit(ref, src, strength=0.0)):
        assert np.abs(lut - ident).max() < 1e-4, np.abs(lut - ident).max()

    lut = fit(ref, src, strength=0.6)
    # monotonic: lightness never falls along the grey ramp or along any axis of the cube
    lightness = rgb_to_lab(lut)[..., 0]
    assert np.all(np.diff(lightness[np.arange(17), np.arange(17), np.arange(17)]) > 0)
    for axis in range(3):
        assert np.diff(lightness, axis=axis).min() > -0.01, (axis, np.diff(lightness, axis=axis).min())

    # the curves move the statistics part of the way (strength 0.6), not all the way
    curves, lab = fit_curves(ref, src), _lab(src)
    exact = lab_to_rgb(np.stack([np.interp(lab[:, c], *curves[c]) for c in range(3)], -1)).reshape(src.shape)
    s, r, g = summary(src), summary(ref), summary(exact)
    for k in ("L_median", "a_median", "b_median"):
        moved = (g[k] - s[k]) / (r[k] - s[k])
        assert 0.4 < moved < 0.85, (k, s[k], r[k], g[k])

    # only statistics: a pixel-shuffled reference gives the same grade
    shuffled = ref.reshape(-1, 3)[rng.permutation(ref.shape[0] * ref.shape[1])].reshape(ref.shape)
    assert np.abs(fit(shuffled, src) - lut).max() < 1e-6

    # apply: identity is lossless, types round-trip, the baked LUT stays close to the exact curves
    u8 = np.round(src * 255).astype(np.uint8)
    assert np.abs(apply(u8, ident).astype(int) - u8).max() <= 1
    assert isinstance(apply(Image.fromarray(u8), lut), Image.Image) and apply(src, lut).dtype == np.float32
    err = np.abs(apply(src, lut) - exact)
    assert err.mean() < 2 / 255 and err.max() < 8 / 255, (err.mean() * 255, err.max() * 255)

    # strip: the documented layout, and a lossless round trip at 8 bits
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "lut.png")
        save_strip(ident, p)
        img = np.asarray(Image.open(p))
        assert img.shape == (17, 289, 3)
        for x, y in ((0, 0), (288, 16), (5 * 17 + 3, 9), (16, 0), (17, 0)):
            want = np.round(np.array([x % 17, y, x // 17]) / 16 * 255)
            assert np.array_equal(img[y, x], want), (x, y, img[y, x], want)
        save_strip(lut, p)
        assert np.abs(load_strip(p) - lut).max() <= 0.5 / 255 + 1e-6
    print("grade selftest OK", json.dumps({"src": s, "ref": r, "graded": g}))


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true")
    sub = ap.add_subparsers(dest="cmd")
    f = sub.add_parser("fit", help="fit a LUT strip that grades SRC toward REF")
    f.add_argument("ref")
    f.add_argument("src")
    f.add_argument("out")
    f.add_argument("--strength", type=float, default=0.6)
    f.add_argument("--size", type=int, default=17)
    f.add_argument("--preview", help="also write SRC graded through the LUT")
    a = sub.add_parser("apply", help="grade an image through a LUT strip")
    a.add_argument("image")
    a.add_argument("lut")
    a.add_argument("out")
    args = ap.parse_args()
    if args.selftest:
        selftest()
    elif args.cmd == "fit":
        lut = fit(args.ref, args.src, args.strength, args.size)
        save_strip(lut, args.out)
        report = {"lut": args.out, "size": args.size, "strength": args.strength, "ref": summary(args.ref), "src": summary(args.src)}
        if args.preview:
            graded = apply(args.src, load_strip(args.out))
            graded.save(args.preview)
            report["graded"] = summary(graded)
        print(json.dumps(report, indent=1))
    elif args.cmd == "apply":
        apply(args.image, load_strip(args.lut)).save(args.out)
        print("wrote", args.out)
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
