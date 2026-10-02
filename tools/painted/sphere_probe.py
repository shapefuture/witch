#!/usr/bin/env python3
"""Lighting from a generated plate, by calibration spheres (an experiment; docs/art/lighting_from_image.md).

Film crews photograph a matte grey ball and a chrome ball in the set to record its lighting. A generator that edits a plate can paint them
into it: the grey ball's shading gives the key direction, the fill and key colours; the chrome ball is a 360-degree picture of the light
around it. Everything is measured in the camera's frame (x right, y up, z toward the camera; the scene is at negative z).

    python tools/painted/sphere_probe.py make   plate.png OUTDIR [--model marketing|qwen]      # the edit (paid, about USD 0.07)
    python tools/painted/sphere_probe.py grid   edit.png grid.png --box X0 Y0 X1 Y1             # a grid to read the spheres' circles from
    python tools/painted/sphere_probe.py measure edit.png --grey X Y R --chrome X Y R [--plate plate.png] [--out lighting.json]
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
LUMA = np.array([0.2126, 0.7152, 0.0722])
PROMPT = ("The same scene from exactly the same camera position, angle and framing, with identical layout, objects, colours and light. Two large "
          "perfectly smooth, perfectly round spheres of exactly the same size rest on the ground in the foreground, in one row with a gap between "
          "them: on the left a matte mid-grey sphere with a chalky even surface, and on the right a mirror-polished chrome sphere that reflects its "
          "surroundings and the sky. Each sphere is about the size of a beach ball and sits in the same light as everything else, casting a soft "
          "shadow on the ground.")
MODELS = {"marketing": ("marketing-studio/image", dict(aspect_ratio="16:9", resolution="1k", quality="medium")),
          "qwen": ("alibaba/qwen-image-3/edit", dict(aspect_ratio="16:9", resolution="2k", prompt_extend=True))}


def srgb_to_linear(a):
    a = np.asarray(a, np.float64) / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def disk(shape, circle, inner=0.9):
    """Pixels inside the circle and their sphere normals (x right, y up, z toward the camera)."""
    x0, y0, r = circle
    ys, xs = np.mgrid[0:shape[0], 0:shape[1]]
    nx, ny = (xs - x0) / r, -(ys - y0) / r
    rr = nx ** 2 + ny ** 2
    m = rr < inner ** 2
    nz = np.sqrt(np.clip(1.0 - rr, 0.0, 1.0))
    return m, np.stack([nx[m], ny[m], nz[m]], 1)


def _directions(n=1600):
    """Roughly even directions on the sphere (a Fibonacci lattice)."""
    i = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * i / n)
    th = np.pi * (1 + 5 ** 0.5) * i
    return np.stack([np.cos(th) * np.sin(phi), np.sin(th) * np.sin(phi), np.cos(phi)], 1)


def fit_grey(lin, circle):
    """Lambert on the grey ball: I = ambient + key * max(0, n.l). The direction l is searched over a lattice of directions (a straight-line
    fit a + b.n is biased for a hard light), the ambient and key found by least squares for each; per channel for the colours."""
    m, N = disk(lin.shape[:2], circle)
    rgb = lin[m]
    y = rgb @ LUMA
    step = max(1, len(N) // 4000)
    Ns, ys = N[::step], y[::step]
    best = None
    for d in _directions():
        lam = np.maximum(0.0, Ns @ d)
        A = np.stack([np.ones_like(lam), lam], 1)
        c, res, _, _ = np.linalg.lstsq(A, ys, rcond=None)
        err = ((A @ c - ys) ** 2).sum()
        if c[1] > 0 and (best is None or err < best[0]):
            best = (err, d, c)
    err, d, c = best
    lam = np.maximum(0.0, N @ d)
    A = np.stack([np.ones_like(lam), lam], 1)
    fill, key = np.zeros(3), np.zeros(3)
    for ch in range(3):
        cc = np.linalg.lstsq(A, rgb[:, ch], rcond=None)[0]
        fill[ch], key[ch] = max(cc[0], 0.0), max(cc[1], 0.0)
    pred = A @ c
    r2 = 1.0 - ((y - pred) ** 2).sum() / max(((y - y.mean()) ** 2).sum(), 1e-12)
    return dict(fill=fill, key=key, direction=d, r2=float(r2), ambient_luma=float(c[0]), directional_luma=float(c[1]))


def chrome_environment(lin, circle, reflectance=0.85, inner=0.96):
    """Radiance (linear RGB) in the directions the chrome ball reflects. Every pixel covers the same solid angle (4 / r^2)."""
    m, N = disk(lin.shape[:2], circle, inner)
    R = np.stack([2 * N[:, 2] * N[:, 0], 2 * N[:, 2] * N[:, 1], 2 * N[:, 2] ** 2 - 1], 1)
    return R, lin[m] / reflectance, 4.0 / circle[2] ** 2


def environment_summary(R, L):
    y = L @ LUMA
    sun = y > np.quantile(y, 0.98)
    up = (R[:, 1] > 0.3) & ~sun
    down = R[:, 1] < -0.3
    d = R[sun].mean(0)
    unit = lambda v: v / max(v.max(), 1e-12)                                           # noqa: E731
    return dict(sun_direction=d / np.linalg.norm(d), sun_color=unit(L[sun].mean(0)), sky_color=unit(L[up].mean(0)),
                ground_color=unit(L[down].mean(0)), sun_to_sky=float(y[sun].mean() / max(y[up].mean(), 1e-12)))


def irradiance(R, L, dOm, normals):
    """Diffuse radiance (albedo 1) at each normal from the environment: sum of L * max(0, n.w) * dOmega / pi."""
    y = L @ LUMA
    return (y[None, :] * np.maximum(0.0, normals @ R.T)).sum(1) * dOm / np.pi


def cross_check(lin, grey_circle, chrome_circle):
    """How well the grey ball's shading follows the irradiance predicted from the chrome ball (correlation over the ball's normals)."""
    m, N = disk(lin.shape[:2], grey_circle)
    R, L, dOm = chrome_environment(lin, chrome_circle)
    pred = irradiance(R, L, dOm, N)
    return float(np.corrcoef(pred, lin[m] @ LUMA)[0, 1])


GOOD_FIT, GOOD_AGREEMENT = 0.85, 0.6           # a measurement is trusted when the grey ball is one-light Lambert and the two balls agree


def make_variant(plate, out, model="marketing", max_usd=0.12):
    """The paid edit: the plate with the two balls painted in. Returns the picture's path (None if the call failed)."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    slug, args = MODELS[model]
    (out / "args.json").write_text(json.dumps(dict(args, prompt=PROMPT)), encoding="utf-8")
    cmd = [sys.executable, str(ROOT / "tools/higgsfield/hf.py"), "run", slug, "--args-file", str(out / "args.json"), "--upload", "image_urls=%s" % plate,
           "--max-usd", str(max_usd), "--out", str(out)]
    subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    found = sorted(out.rglob("image_0.*"))
    return found[0] if found else None


def measure_auto(edit_path, plate_path):
    """Finds the balls and measures them; `ok` says whether to trust it (see GOOD_FIT / GOOD_AGREEMENT)."""
    plate = Image.open(plate_path)
    edit = Image.open(edit_path)
    try:
        grey, chrome = find_spheres(edit, plate)
    except ValueError as e:
        return dict(ok=False, why=str(e))
    res = measure(edit.resize(plate.size, Image.LANCZOS), grey, chrome)
    res.update(grey_circle=list(grey), chrome_circle=list(chrome))
    res["ok"] = bool(res["grey_fit_r2"] >= GOOD_FIT and res["grey_vs_chrome_correlation"] >= GOOD_AGREEMENT)
    if not res["ok"]:
        res["why"] = "the grey ball is not one-light Lambert (%.2f) or the balls disagree (%.2f)" % (res["grey_fit_r2"], res["grey_vs_chrome_correlation"])
    return res


def measure(image, grey, chrome):
    lin = srgb_to_linear(np.asarray(image.convert("RGB"), np.float32))
    g = fit_grey(lin, grey)
    R, L, _ = chrome_environment(lin, chrome)
    env = environment_summary(R, L)
    unit = lambda v: v / max(v.max(), 1e-12)                                           # noqa: E731
    ang = float(np.degrees(np.arccos(np.clip(g["direction"] @ env["sun_direction"], -1, 1))))
    f = lambda v: [round(float(x), 3) for x in v]                                      # noqa: E731
    return dict(camera_space="x right, y up, z toward the camera",
                key_direction_from_grey=f(g["direction"]), sun_direction_from_chrome=f(env["sun_direction"]), angle_between_deg=round(ang, 1),
                fill_color=f(unit(g["fill"])), key_color=f(unit(g["key"])), grey_fit_r2=round(g["r2"], 3),
                fill_to_key=round(g["ambient_luma"] / max(g["directional_luma"], 1e-12), 2),
                sun_color=f(env["sun_color"]), sky_color=f(env["sky_color"]), ground_color=f(env["ground_color"]), sun_to_sky=round(env["sun_to_sky"], 1),
                grey_vs_chrome_correlation=round(cross_check(lin, grey, chrome), 3))


def find_spheres(edit, plate, rmin=40, rmax=130):
    """The grey ball (left) and the chrome ball (right) in an edited plate, as (x, y, r) circles in the plate's pixels.
    Where the edit differs from the plate marks the new objects; a gradient-direction Hough vote over those edges finds the two circles."""
    from scipy import ndimage
    ed = edit.convert("RGB").resize(plate.size, Image.LANCZOS)
    e = np.asarray(ed, np.float32)
    diff = np.abs(e - np.asarray(plate.convert("RGB"), np.float32)).mean(2)
    region = ndimage.binary_dilation(ndimage.binary_opening(diff > 40, iterations=2), iterations=14)
    luma = ndimage.gaussian_filter(e.mean(2), 1.5)
    gx, gy = ndimage.sobel(luma, axis=1), ndimage.sobel(luma, axis=0)
    mag = np.hypot(gx, gy)
    ys, xs = np.nonzero(region & (mag > np.quantile(mag[region], 0.8)))
    ux, uy = gx[ys, xs] / mag[ys, xs], gy[ys, xs] / mag[ys, xs]
    H, W = luma.shape
    best = []
    for r in range(rmin, rmax + 1, 3):
        acc = np.zeros((H, W), np.float32)
        for sgn in (1, -1):                                   # the centre lies along the gradient, on either side
            cx = np.clip(np.round(xs + sgn * r * ux).astype(int), 0, W - 1)
            cy = np.clip(np.round(ys + sgn * r * uy).astype(int), 0, H - 1)
            np.add.at(acc, (cy, cx), 1.0)
        acc = ndimage.gaussian_filter(acc, 3.0)
        best.append((float(acc.max()) / (2 * np.pi * r) ** 0.5, r, acc))
    # the strongest peaks over all radii, not on top of each other
    cands = []
    for score, r, acc in best:
        a = acc.copy()
        for _ in range(3):
            iy, ix = np.unravel_index(np.argmax(a), a.shape)
            cands.append((float(a[iy, ix]) / r ** 0.5, ix, iy, r))
            a[max(iy - r // 2, 0): iy + r // 2, max(ix - r // 2, 0): ix + r // 2] = 0
    cands.sort(reverse=True)
    # a ball painted into the plate is made of pixels the edit changed: keep circles that are mostly new
    changed = ndimage.gaussian_filter((diff > 20).astype(np.float32), 2.0) > 0.5

    def coverage(c):
        m, _ = disk(luma.shape, (c[1], c[2], c[3]), 0.9)
        return float(changed[m].mean())
    cands = [c for c in cands if coverage(c) >= 0.5]
    if not cands:
        raise ValueError("found no sphere: draw the circles by hand (sphere_probe.py grid / measure)")
    first = cands[0]
    # the second ball: in the same row, a gap away, of about the same size. Its inside is a whole reflected scene (strong edges that fool a
    # vote), so it is found by the outline instead: the circle whose circumference lies on the strongest edge.
    r1 = first[3]
    gxs, gys = ndimage.gaussian_filter(gx, 1.0), ndimage.gaussian_filter(gy, 1.0)
    th = np.linspace(0, 2 * np.pi, 120, endpoint=False)
    ct, st = np.cos(th), np.sin(th)
    best = None
    for r in range(int(0.85 * r1), int(1.2 * r1) + 1, 3):
        for dy in range(-int(0.5 * r1), int(0.5 * r1) + 1, 4):
            for dx in range(int(1.8 * r1), int(4.2 * r1) + 1, 4):
                for sgn in (1,):                                   # to its right: the prompt puts the grey ball on the left
                    cx, cy = first[1] + sgn * dx, first[2] + dy
                    if not (r < cx < W - r and r < cy < H - r):
                        continue
                    yy_, xx_ = np.clip((cy + r * st).astype(int), 0, H - 1), np.clip((cx + r * ct).astype(int), 0, W - 1)
                    # edges that run along the circle (a ball's outline) count, edges that cross it (shelves, planks) do not
                    sc = float(np.abs(gxs[yy_, xx_] * ct + gys[yy_, xx_] * st).mean())
                    if best is None or sc > best[0]:
                        best = (sc, cx, cy, r)
    if best is None:
        raise ValueError("found one sphere, not two: draw the circles by hand (sphere_probe.py grid / measure)")
    second = (0, best[1], best[2], best[3])
    circles = [(int(first[1]), int(first[2]), int(first[3])), (int(second[1]), int(second[2]), int(second[3]))]
    # the chrome ball is the one with the busier inside (it holds a whole reflected scene); the grey ball is nearly flat
    def busy(c):
        m, _ = disk(luma.shape, c, 0.85)
        return float(luma[m].std())
    circles.sort(key=busy)
    return circles[0], circles[1]


def cmd_make(a):
    print(make_variant(a.plate, a.out, a.model, a.max_usd))


def cmd_grid(a):
    im = Image.open(a.edit).convert("RGB")
    b = a.box
    c = im.crop(b).resize(((b[2] - b[0]) * 2, (b[3] - b[1]) * 2))
    d = ImageDraw.Draw(c)
    for x in range(0, b[2] - b[0], 40):
        d.line([(x * 2, 0), (x * 2, c.height)], fill=(255, 255, 255)); d.text((x * 2 + 2, 2), str(b[0] + x), fill=(255, 255, 0))
    for y in range(0, b[3] - b[1], 40):
        d.line([(0, y * 2), (c.width, y * 2)], fill=(255, 255, 255)); d.text((2, y * 2 + 2), str(b[1] + y), fill=(255, 255, 0))
    c.save(a.out)


def cmd_measure(a):
    img = Image.open(a.edit)
    if a.plate:
        img = img.resize(Image.open(a.plate).size, Image.LANCZOS)
    grey, chrome = a.grey, a.chrome
    if not (grey and chrome):                                    # no circles given: find them (needs --plate)
        grey, chrome = find_spheres(img, Image.open(a.plate))
        print("found grey %s, chrome %s" % (grey, chrome), file=sys.stderr)
    res = measure(img, tuple(grey), tuple(chrome))
    res["ok"] = bool(res["grey_fit_r2"] >= GOOD_FIT and res["grey_vs_chrome_correlation"] >= GOOD_AGREEMENT)
    print(json.dumps(res, indent=1))
    if a.out:
        Path(a.out).write_text(json.dumps(res, indent=1) + "\n", encoding="utf-8")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("make"); p.add_argument("plate"); p.add_argument("out"); p.add_argument("--model", choices=sorted(MODELS), default="marketing"); p.add_argument("--max-usd", type=float, default=0.12); p.set_defaults(fn=cmd_make)
    p = sub.add_parser("grid"); p.add_argument("edit"); p.add_argument("out"); p.add_argument("--box", type=int, nargs=4, required=True); p.set_defaults(fn=cmd_grid)
    p = sub.add_parser("measure"); p.add_argument("edit"); p.add_argument("--grey", type=float, nargs=3); p.add_argument("--chrome", type=float, nargs=3); p.add_argument("--plate"); p.add_argument("--out"); p.set_defaults(fn=cmd_measure)
    a = ap.parse_args(argv)
    a.fn(a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
