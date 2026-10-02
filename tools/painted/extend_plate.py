#!/usr/bin/env python3
"""Gives a painted plate a margin, so a rolled or wide camera shows more painting instead of zooming in.

There is no mask/inpaint model on Higgsfield (tools/higgsfield/catalog/CATALOG.md): every edit is a prompt plus a
picture, and the model re-draws the whole frame. So the margin is made in three steps, and the middle is never
trusted to the model:

    canvas   put the plate in the middle of a larger canvas; fill the border with a seed (mirrored, blurred) that
             tells the edit model where the painting must continue                      -> canvas.png (+ strips)
    (hf.py)  ask the edit model to continue the painting out to the canvas edge        -> build/higgsfield/<job>/
    merge    register the result to the canvas (the model shifts and rescales things by a few pixels), measure how
             far the centre drifted, snap the margin to the original along the seam, then paste the ORIGINAL back:
             the plate stays pixel-exact inside the seam                                -> plate_ext.png + report

    python tools/painted/extend_plate.py canvas --plate assets/painted/hall_clean/plate.png --out DIR [--margin 0.125]
    python tools/painted/extend_plate.py merge  --plate P --generated GEN.png --out DIR [--margin 0.125]
    python tools/painted/extend_plate.py strips ... / merge-strips ...   (four edits, one per side)

A margin is a fraction of the plate (0.125 -> 160 px left/right, 90 px top/bottom, a 1600x900 canvas, still 16:9,
which the edit model accepts) or `--margin-px X,Y`. Pixel coordinates elsewhere (props, actors, room.json) stay
those of the ORIGINAL plate; the margin is just negative coordinates and coordinates past the plate's size.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage, optimize

W, H = 1280, 720
PROMPT = (
    "This is a painting of a faceted low-poly papercraft library hall, olive, ochre and purple, with one shaft "
    "of warm light. The middle of the picture is the finished painting. Around it is a rough, blurred placeholder "
    "border. Paint the border as the natural continuation of the painting out to the very edge of the frame: "
    "continue the shelves, the arches, the stone walls, the carpet and the light in exactly the same style, "
    "lighting and colours, as if the camera had a wider lens. Keep the middle of the picture exactly as it is: "
    "do not change, move, enlarge or repaint anything in it. No frame, no border line, no vignette, no text.")
PROMPT_FLAT = (
    "This is a painting of a faceted low-poly papercraft library hall, olive, ochre and purple, with one shaft of "
    "warm light. It sits in the middle of a larger canvas whose border is flat empty grey. Paint the whole grey "
    "border: continue the painting outward to the very edge of the canvas with new, sharp, detailed content in "
    "exactly the same style, lighting and colours: more leaning bookshelves with scrolls and boxes on the left and "
    "right, more faceted stone walls and vaulted ceiling above, more spiral carpet and stone floor below, as if "
    "the camera had a wider lens. Keep the painted middle exactly as it is: do not change, move, enlarge or "
    "repaint anything in it. No grey left, no frame, no border line, no vignette, no text.")
PROMPT_MAGENTA = (
    "Outpaint this image. The painting in the middle is a faceted low-poly papercraft library hall in olive, "
    "ochre and purple with one shaft of warm light. The bright magenta border is empty space outside the "
    "painting: replace every magenta pixel with new painting that continues the scene outward from the painting's "
    "own edges, in exactly the same style, lighting and colours (shelves, stone vaults, carpet and floor running "
    "on past the edge, as if the camera had a wider lens). The result must fill the whole frame with no magenta "
    "left, no frame and no border. Keep the painted middle exactly as it is, unchanged and at the same size and "
    "position.")
PROMPT_SHARPEN = (
    "This is a painting of a faceted low-poly papercraft library hall in olive, ochre and purple with one shaft "
    "of warm light, shown at the same framing as given. The outer band of the picture, all around the edges, is "
    "out of focus and smeared: repaint that whole outer band as crisp, sharp, fully detailed painting in exactly "
    "the same faceted style, lighting and colours as the middle, following the lines and shapes already there "
    "(shelves with scrolls and boxes, stone vaults, spiral carpet and floor continuing past the middle "
    "of the picture). Do not zoom or crop: keep the same composition, framing and aspect ratio, and keep the "
    "sharp middle of the picture exactly as it is. No frame, no border, no text.")
PROMPT_SHARPEN2 = PROMPT_SHARPEN.replace(
    "No frame, no border, no text.",
    "Never repeat or mirror an object that is already in the picture (no second globe, no second light hole, "
    "no second card): continue each shelf, wall and the floor outward with new objects. No frame, no border, "
    "no text.")
PROMPT_FIX = (
    "This is a wide painting of a faceted low-poly papercraft library hall. Fix four artefacts in its outer band, "
    "and change nothing else: (1) at the far left edge a second purple globe duplicates the real globe: replace "
    "the duplicate with the bookshelf and stone wall continuing past the real globe; (2) in the ceiling there are "
    "two light holes one above the other: remove the upper one and continue the faceted stone ceiling; (3) at the "
    "bottom the paper card with the square symbol is reflected a second time below itself: remove the reflection "
    "and continue the floor carpet; (4) the far left and far right bands repeat the shelves as a mirror image: "
    "repaint them as new bookshelves, scrolls and boxes that continue the perspective. Keep the same composition, "
    "framing, size, colours and style, and keep the whole middle of the picture exactly as it is.")
def strip_prompt(side):
    where = {"left": "left-hand", "right": "right-hand", "top": "top", "bottom": "bottom"}[side]
    return PROMPT_SHARPEN2.replace("The outer band of the picture, all around the edges, is",
                                   "The %s band of the picture, along its %s edge, is" % (where, side)).replace(
        "repaint that whole outer band", "repaint that whole band")


NEGATIVE = ("frame, picture frame, border line, vignette, white border, black bar, text, letters, watermark, "
            "people, characters, blurry, photorealistic, smooth")


# ---- geometry --------------------------------------------------------------------------------------------

def margins(fraction=0.125, px=None, size=(W, H)):
    """(mx, my) in pixels of the original plate."""
    if px:
        return int(px[0]), int(px[1])
    return int(round(size[0] * fraction)), int(round(size[1] * fraction))


def inner_box(mx, my, size=(W, H)):
    """The original plate's rectangle in canvas pixels: (x0, y0, x1, y1)."""
    return mx, my, mx + size[0], my + size[1]


# ---- the seed canvas -------------------------------------------------------------------------------------

def make_canvas(plate, mx, my, fill="mirror", blur=(2, 6)):
    """The plate in the middle of a larger canvas. Fill: `mirror` (reflected content, blurred more the further
    out it goes: the painting's own structure continues, softly), `smear` (edge pixels stretched outward, blurred)
    or `grey` (the plate's mean colour)."""
    a = np.asarray(plate.convert("RGB"), np.float32)
    h, w = a.shape[:2]
    if fill in ("grey", "magenta"):
        out = np.empty((h + 2 * my, w + 2 * mx, 3), np.float32)
        out[:] = a.reshape(-1, 3).mean(axis=0) if fill == "grey" else (255, 0, 255)
    else:
        out = np.pad(a, ((my, my), (mx, mx), (0, 0)), mode="reflect" if fill == "mirror" else "edge")
        # Distance (px) outside the plate, for a blur that grows with it.
        yy, xx = np.mgrid[0:out.shape[0], 0:out.shape[1]]
        dist = np.maximum.reduce([mx - xx, xx - (mx + w - 1), my - yy, yy - (my + h - 1), np.zeros_like(xx)])
        near = ndimage.gaussian_filter(out, (blur[0], blur[0], 0))
        far = ndimage.gaussian_filter(out, (blur[1], blur[1], 0))
        t = np.clip(dist / float(max(mx, my)), 0, 1)[..., None]
        out = np.where(dist[..., None] > 0, near * (1 - t) + far * t, out)
    out[my:my + h, mx:mx + w] = a
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))


STRIP_ASPECTS = {"left": "7:9", "right": "7:9", "top": "21:9", "bottom": "21:9"}


def strip_boxes(mx, my, size=(W, H)):
    """Per side: the crop of the canvas sent to the edit model (x0, y0, x1, y1) and the aspect ratio asked for.
    The side strips hold the margin, the full height of the plate and enough context to be recognised
    (7:9); the top and bottom strips are full-width 21:9 crops (the widest ratio the model takes)."""
    cw, ch = size[0] + 2 * mx, size[1] + 2 * my
    side_w = int(round(size[1] * 7 / 9.0 * 1.0))              # 7:9 of the plate's own height
    top_h = int(round(cw * 9 / 21.0))
    return {
        "left": (0, my, side_w, my + size[1]),
        "right": (cw - side_w, my, cw, my + size[1]),
        "top": (0, 0, cw, top_h),
        "bottom": (0, ch - top_h, cw, ch),
    }


# ---- registration ----------------------------------------------------------------------------------------

def _luma(a):
    return a @ np.array([0.299, 0.587, 0.114], np.float32)


def _highpass(a, sigma=1.5):
    g = _luma(a)
    return g - ndimage.gaussian_filter(g, sigma * 6)


def _affine_warp(img, params, centre):
    """Samples `img` (H,W,3 float) at x' = c + s*(x - c) + t  for scale/shift params (sx, sy, tx, ty)."""
    sx, sy, tx, ty = params
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    sxs = centre[0] + sx * (xx - centre[0]) + tx
    sys_ = centre[1] + sy * (yy - centre[1]) + ty
    out = np.empty_like(img)
    for c in range(img.shape[2]):
        out[..., c] = ndimage.map_coordinates(img[..., c], [sys_, sxs], order=1, mode="nearest")
    return out


def register(gen, ref, box, margin_trim=48):
    """Finds (sx, sy, tx, ty) so that gen sampled by it matches ref (the seed canvas, whose middle is the true
    plate) inside `box` shrunk by margin_trim, by minimising the high-pass difference. Returns (params, warped)."""
    x0, y0, x1, y1 = box
    x0, y0, x1, y1 = x0 + margin_trim, y0 + margin_trim, x1 - margin_trim, y1 - margin_trim
    ref_hp = _highpass(ref)[y0:y1:2, x0:x1:2]
    gen_hp_full = _highpass(gen)
    centre = ((box[0] + box[2]) / 2.0, (box[1] + box[3]) / 2.0)
    ys, xs = np.mgrid[y0:y1:2, x0:x1:2].astype(np.float32)

    def cost(p):
        sx, sy, tx, ty = p
        sxs = centre[0] + sx * (xs - centre[0]) + tx
        sys_ = centre[1] + sy * (ys - centre[1]) + ty
        sample = ndimage.map_coordinates(gen_hp_full, [sys_, sxs], order=1, mode="nearest")
        return float(np.mean(np.abs(sample - ref_hp)))

    # A coarse translation search first (the cost is not convex), then a local refine of all four.
    best = (cost((1, 1, 0, 0)), (1.0, 1.0, 0.0, 0.0))
    for ty in range(-24, 25, 4):
        for tx in range(-24, 25, 4):
            c = cost((1.0, 1.0, tx, ty))
            if c < best[0]:
                best = (c, (1.0, 1.0, float(tx), float(ty)))
    bounds = [(0.93, 1.07), (0.93, 1.07), (-40, 40), (-40, 40)]
    result = optimize.minimize(cost, best[1], method="Powell", bounds=bounds,
                               options={"xtol": 1e-3, "ftol": 1e-5, "maxiter": 40})
    params = tuple(float(v) for v in result.x)
    return params, _affine_warp(gen, params, centre), centre


# ---- measuring -------------------------------------------------------------------------------------------

def band(shape, box, inside, outside=0):
    """Mask of the ring between `inside` px inside the box edge and `outside` px beyond it."""
    x0, y0, x1, y1 = box
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    in_outer = (xx >= x0 - outside) & (xx < x1 + outside) & (yy >= y0 - outside) & (yy < y1 + outside)
    in_inner = (xx >= x0 + inside) & (xx < x1 - inside) & (yy >= y0 + inside) & (yy < y1 - inside)
    return in_outer & ~in_inner


def drift_report(gen_aligned, canvas, params, box):
    """How far the model's centre is from the plate, after alignment (what the seam has to live with)."""
    x0, y0, x1, y1 = box
    diff = np.abs(gen_aligned - canvas).mean(axis=2)
    centre = np.zeros(diff.shape, bool)
    centre[y0 + 48:y1 - 48, x0 + 48:x1 - 48] = True
    ring = band(diff.shape, box, 32)
    ring[:y0] = False
    ring[y1:] = False
    ring[:, :x0] = False
    ring[:, x1:] = False
    return {
        "scale_x": params[0], "scale_y": params[1], "shift_px": [params[2], params[3]],
        "centre_mae_0_255": float(diff[centre].mean()),
        "seam_ring_mae_0_255": float(diff[ring].mean()),
    }


def sharpness(img, mask):
    """Mean |Laplacian of Gaussian| of the luma over `mask`: how much fine detail the pixels carry."""
    lap = np.abs(ndimage.gaussian_laplace(_luma(img), 1.0))
    return float(lap[mask].mean())


def margin_sharpness_ratio(final, box, trim=8):
    """Detail in the new margin relative to the detail in the plate's own outer ring of the same width (1.0 = as
    crisp as the painting; the edit model often leaves the seed's blur in place, which reads well below 0.6)."""
    x0, y0, x1, y1 = box
    h, w = final.shape[:2]
    outside = np.ones((h, w), bool)
    outside[max(y0 - trim, 0):y1 + trim, max(x0 - trim, 0):x1 + trim] = False
    mx, my = x0, y0
    ring = np.zeros((h, w), bool)
    ring[y0:y1, x0:x1] = True
    ring[y0 + my:y1 - my, x0 + mx:x1 - mx] = False
    f = final.astype(np.float32)
    return sharpness(f, outside) / max(sharpness(f, ring), 1e-6)


def seam_step_ratio(final, box):
    """How much bigger the step across the seam is than the steps between neighbouring pixels of the plate itself,
    averaged over the four sides (1.0 = the seam is as smooth as the painting; a visible crease reads well above 1.5)."""
    x0, y0, x1, y1 = box
    f = final.astype(np.float32)
    pairs = [  # (outside line, inside line, inside+1 line) as arrays of shape (n, 3)
        (f[y0:y1, x0 - 1], f[y0:y1, x0], f[y0:y1, x0 + 1]),
        (f[y0:y1, x1], f[y0:y1, x1 - 1], f[y0:y1, x1 - 2]),
        (f[y0 - 1, x0:x1], f[y0, x0:x1], f[y0 + 1, x0:x1]),
        (f[y1, x0:x1], f[y1 - 1, x0:x1], f[y1 - 2, x0:x1]),
    ]
    across = np.mean([np.abs(o - i).mean() for o, i, _ in pairs])
    within = np.mean([np.abs(i - j).mean() for _, i, j in pairs])
    return float(across / max(within, 1e-6))


# ---- making the margin fit the plate ------------------------------------------------------------------------

def snap_colour(gen, canvas, box, depth=24, reach=90.0):
    """Adds to the margin the difference (plate - model's version of the plate) measured in a ring just inside the
    seam, extended outward and fading with distance: the margin starts at exactly the plate's colour at the seam
    and returns to the model's own colour `reach` px away."""
    x0, y0, x1, y1 = box
    h, w = gen.shape[:2]
    diff = canvas - gen
    # Per-pixel the ring just inside the edge, spread outward by edge replication, then blurred.
    ring = np.zeros((h, w, 1), np.float32)
    inside = np.zeros((h, w), bool)
    inside[y0:y1, x0:x1] = True
    inside[y0 + depth:y1 - depth, x0 + depth:x1 - depth] = False
    ring[..., 0] = inside
    smooth = ndimage.gaussian_filter(diff * ring, (10, 10, 0)) / np.maximum(ndimage.gaussian_filter(ring, (10, 10, 0)), 1e-3)
    # Replicate the ring outward: nearest ring pixel for every margin pixel.
    _, idx = ndimage.distance_transform_edt(~inside | (np.zeros_like(inside)), return_indices=True)
    nearest_ring = smooth[idx[0], idx[1]]
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.maximum.reduce([x0 - xx, xx - (x1 - 1), y0 - yy, yy - (y1 - 1), np.zeros_like(xx)]).astype(np.float32)
    fade = np.exp(-dist / reach)[..., None]
    return gen + nearest_ring * fade


def paste_original(canvas, merged, box, feather=12):
    """The plate itself goes back inside the seam. `feather` px of the plate's outer ring blend toward the merged
    image so the seam has no step (0 = a hard paste: the whole plate stays exact)."""
    x0, y0, x1, y1 = box
    out = merged.copy()
    alpha = np.zeros(merged.shape[:2], np.float32)
    alpha[y0:y1, x0:x1] = 1.0
    if feather > 0:
        d = ndimage.distance_transform_edt(alpha > 0)
        alpha = np.clip(d / float(feather), 0, 1) ** 1.0
        alpha = alpha * alpha * (3 - 2 * alpha)
    out = merged * (1 - alpha[..., None]) + canvas * alpha[..., None]
    return out, alpha


def merge(plate, generated, mx, my, feather=4, snap=True, reach=90.0, fill="mirror", canvas=None):
    """`canvas` is what the model was given (default: the seed canvas); any image whose middle is the plate works,
    so a second, corrective pass can be merged against the first pass's result."""
    box = inner_box(mx, my, plate.size)
    cw, ch = plate.width + 2 * mx, plate.height + 2 * my
    if canvas is None:
        canvas = make_canvas(plate, mx, my, fill)
    ref = np.asarray(canvas, np.float32)
    gen = np.asarray(generated.convert("RGB").resize((cw, ch), Image.LANCZOS), np.float32)
    params, aligned, centre = register(gen, ref, box)
    report = drift_report(aligned, ref, params, box)
    merged = snap_colour(aligned, ref, box, reach=reach) if snap else aligned
    final, alpha = paste_original(ref, merged, box, feather)
    final = np.clip(final + 0.5, 0, 255).astype(np.uint8)
    # The pixel-exact claim, measured: inside the seam (minus the feather) nothing changed at all.
    plate_a = np.asarray(plate.convert("RGB"), np.uint8)
    f = max(feather, 0)
    core = final[my + f:my + plate.height - f, mx + f:mx + plate.width - f]
    ref_core = plate_a[f:plate.height - f, f:plate.width - f]
    report["core_exact"] = bool(np.array_equal(core, ref_core))
    report["core_max_abs_diff"] = int(np.abs(core.astype(int) - ref_core.astype(int)).max())
    ring_diff = np.abs(final[my:my + plate.height, mx:mx + plate.width].astype(int) - plate_a.astype(int)).mean(axis=2)
    report["plate_changed_px"] = int((ring_diff > 0).sum())
    report["plate_max_abs_diff"] = int(ring_diff.max())
    report["margin_px"] = [mx, my]
    report["feather_px"] = feather
    report["margin_sharpness_ratio"] = margin_sharpness_ratio(final, box)
    report["seam_step_ratio"] = seam_step_ratio(final, box)
    return Image.fromarray(final), report


def paste_centre(extended, centre, mx, my, feather=4):
    """A variant of the plate (the one with props lifted out, say) for the extended frame: the margin of `extended`
    around `centre`, which replaces the middle except for the seam ring the merge already blended."""
    out = np.asarray(extended.convert("RGB"), np.uint8).copy()
    c = np.asarray(centre.convert("RGB"), np.uint8)
    f = max(feather, 0)
    h, w = c.shape[:2]
    out[my + f:my + h - f, mx + f:mx + w - f] = c[f:h - f, f:w - f]
    return Image.fromarray(out)


def accept(report, max_shift=8.0, max_scale=0.02, max_seam_mae=12.0, min_sharpness=0.3):
    """The drift gate: a result whose centre moved or rescaled too much, or whose seam ring disagrees with the
    plate by more than max_seam_mae grey levels, is not used."""
    reasons = []
    if max(abs(report["shift_px"][0]), abs(report["shift_px"][1])) > max_shift:
        reasons.append("shift %.1f px" % max(abs(report["shift_px"][0]), abs(report["shift_px"][1])))
    if max(abs(report["scale_x"] - 1), abs(report["scale_y"] - 1)) > max_scale:
        reasons.append("scale %.3f/%.3f" % (report["scale_x"], report["scale_y"]))
    if report["seam_ring_mae_0_255"] > max_seam_mae:
        reasons.append("seam ring MAE %.1f" % report["seam_ring_mae_0_255"])
    if report.get("margin_sharpness_ratio", 1.0) < min_sharpness:
        reasons.append("margin still blurry (%.2f of the plate's detail)" % report["margin_sharpness_ratio"])
    if report.get("seam_step_ratio", 1.0) > 2.5:
        reasons.append("seam step %.1fx the painting's own" % report["seam_step_ratio"])
    return not reasons, reasons


def evaluate_strip(plate, side, generated, mx, my, fill="mirror", blur=(2, 6)):
    """The same drift numbers for one strip edit (see strip_boxes), measured on the strip's own crop."""
    canvas = make_canvas(plate, mx, my, fill, blur)
    bx0, by0, bx1, by1 = strip_boxes(mx, my, plate.size)[side]
    seed = np.asarray(canvas.crop((bx0, by0, bx1, by1)), np.float32)
    gen = np.asarray(generated.convert("RGB").resize(seed.shape[1::-1], Image.LANCZOS), np.float32)
    px0, py0, px1, py1 = inner_box(mx, my, plate.size)
    box = (max(px0, bx0) - bx0, max(py0, by0) - by0, min(px1, bx1) - bx0, min(py1, by1) - by0)
    params, aligned, _ = register(gen, seed, box)
    report = drift_report(aligned, seed, params, box)
    # The margin part of this strip: left of the plate for left, right of it for right, above/below for top/bottom.
    mask = np.zeros(seed.shape[:2], bool)
    if side == "left":
        mask[:, :mx - 8] = True
    elif side == "right":
        mask[:, px0 + plate.width - bx0 + 8:] = True
    elif side == "top":
        mask[:my - 8, :] = True
    else:
        mask[py0 + plate.height - by0 + 8:, :] = True
    ring = np.zeros(seed.shape[:2], bool)
    ring[box[1]:box[3], box[0]:box[2]] = True
    ring[box[1] + 90:box[3] - 90, box[0] + 90:box[2] - 90] = False
    report["margin_sharpness_ratio"] = sharpness(aligned, mask) / max(sharpness(aligned, ring), 1e-6)
    report["seed_sharpness_ratio"] = sharpness(seed, mask) / max(sharpness(seed, ring), 1e-6)
    return report


# ---- command line ------------------------------------------------------------------------------------------

def _margin_args(args, plate):
    px = [int(v) for v in args.margin_px.split(",")] if args.margin_px else None
    return margins(args.margin, px, plate.size)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("canvas", "strips", "merge", "strip-report", "paste"):
        p = sub.add_parser(name)
        p.add_argument("--plate", required=True)
        p.add_argument("--out", required=True)
        p.add_argument("--margin", type=float, default=0.125, help="fraction of the plate on each side")
        p.add_argument("--margin-px", default="", help="X,Y in pixels (overrides --margin)")
        p.add_argument("--fill", default="mirror", choices=("mirror", "smear", "grey", "magenta"))
        p.add_argument("--blur", default="2,6", help="seed blur sigma next to the plate and at the canvas edge (px)")
        if name == "merge":
            p.add_argument("--feather", type=int, default=4, help="px of the plate's outer ring blended into the margin (0: a hard paste, the whole plate exact)")
            p.add_argument("--reach", type=float, default=90.0)
            p.add_argument("--no-snap", action="store_true")
            p.add_argument("--base", default="", help="what the model was given, if not the seed canvas")
        if name == "merge":
            p.add_argument("--generated", required=True)
        if name == "paste":
            p.add_argument("--extended", required=True, help="the extended plate (plate_ext.png)")
            p.add_argument("--centre", required=True, help="an image of the original plate's size to put in the middle")
            p.add_argument("--feather", type=int, default=4)
        if name == "strip-report":
            p.add_argument("--generated", required=True, help="a JSON {left,right,top,bottom: image path}")
    args = parser.parse_args(argv)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    plate = Image.open(args.plate).convert("RGB")
    mx, my = _margin_args(args, plate)
    blur = tuple(float(v) for v in args.blur.split(","))
    if args.command == "canvas":
        canvas = make_canvas(plate, mx, my, args.fill, blur)
        canvas.save(out / ("canvas_%s.png" % args.fill))
        print("canvas %dx%d (margin %d,%d) fill=%s -> %s" % (canvas.width, canvas.height, mx, my, args.fill, out))
        return 0
    if args.command == "strips":
        canvas = make_canvas(plate, mx, my, args.fill, blur)
        for side, box in strip_boxes(mx, my, plate.size).items():
            canvas.crop(box).save(out / ("strip_%s.png" % side))
            print("strip %s %s aspect %s" % (side, box, STRIP_ASPECTS[side]))
        return 0
    if args.command == "merge":
        generated = Image.open(args.generated)
        base = Image.open(args.base).convert("RGB") if args.base else None
        image, report = merge(plate, generated, mx, my, args.feather, not args.no_snap, args.reach, args.fill, base)
        image.save(out / "plate_ext.png")
        good, reasons = accept(report)
        report["accepted"] = good
        report["reasons"] = reasons
        (out / "merge_report.json").write_text(json.dumps(report, indent=1) + "\n")
        print(json.dumps(report, indent=1))
        return 0 if good else 2
    if args.command == "paste":
        image = paste_centre(Image.open(args.extended), Image.open(args.centre), mx, my, args.feather)
        image.save(out / "plate_empty_ext.png")
        print("wrote %s (%dx%d)" % (out / "plate_empty_ext.png", image.width, image.height))
        return 0
    if args.command == "strip-report":
        paths = json.loads(Path(args.generated).read_text())
        reports = {side: evaluate_strip(plate, side, Image.open(path), mx, my, args.fill, blur)
                   for side, path in paths.items()}
        (out / "strip_report.json").write_text(json.dumps(reports, indent=1) + "\n")
        print(json.dumps(reports, indent=1))
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
