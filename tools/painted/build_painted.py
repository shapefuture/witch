#!/usr/bin/env python3
"""Turns a painted still into a playable 2.5D room for game/world/painted/ (an experiment).

    pip install -r tools/painted/requirements.txt
    python tools/painted/build_painted.py --plate clean.png --out assets/painted/hall_clean \
        --actor witch=737,636 --actor raccoon=808,662

1. The plate is resized to 1280x720 (the camera below is defined on that frame).
2. Depth Anything V2 Small (ONNX, CPU, a few seconds) gives relative inverse depth.
3. It is calibrated to metres with the camera recovered from the reference (tools/blender/plates/layout.py):
   a 55 degree vertical lens, the eye 1.3 m above the floor, the horizon at 65 % of the height. Floor
   pixels have a known distance (where their ray meets y = 0), so fitting disparity = a / z + b on them
   fixes the scale of everything else.
4. A grid of camera-space depths (one vertex every 8 px) becomes the room's mesh in Godot; the plate is
   mapped onto it by screen position, so from the plate's own camera the picture is exactly the painting.
5. light_map.png is the painting's floor seen from above (blurred: the carpet's pattern is not light), which
   the actor shader reads as the light the characters stand in; sun_dir points from the brightest floor
   at the oculus.
6. --actor NAME=X,Y puts a character's feet on the floor under that pixel of the 1280x720 frame.
"""
import argparse
import json
import math
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
MODEL_URL = "https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/main/onnx/model.onnx"
MODEL_CACHE = ROOT / "build" / "models" / "depth_anything_v2_small.onnx"
W, H = 1280, 720
FOV_V = 55.0
EYE_H = 1.3
HORIZON_FRAC = 612.0 / 941.0          # tools/blender/plates/layout.py, on the 1672x941 original
GRID_STEP = 8
FLOOR_BOX = (300, 560, 1000, 715)     # carpet pixels used for the calibration (x0, y0, x1, y1)
LIGHT_RECT = (-6.0, -16.0, 6.0, -1.0)  # x0, z0, x1, z1 of the light map, metres
LIGHT_RES = 96


def camera():
    f = (H / 2.0) / math.tan(math.radians(FOV_V) / 2.0)
    pitch = math.atan((HORIZON_FRAC * H - H / 2.0) / f)
    return f, pitch


def rays(xs, ys, f, pitch):
    """World directions (camera at the origin, looking down -Z, tilted up by pitch) whose
    forward component is 1, so a point at camera depth z is z * ray."""
    dx = (xs - W / 2.0) / f
    dy = -(ys - H / 2.0) / f
    up = np.array([0.0, math.cos(pitch), math.sin(pitch)])
    fwd = np.array([0.0, math.sin(pitch), -math.cos(pitch)])
    right = np.array([1.0, 0.0, 0.0])
    return dx[..., None] * right + dy[..., None] * up + fwd


def run_depth(img, size=None):
    """Relative inverse depth of `img`, resized to `size` (default: the 1280x720 plate frame)."""
    import onnxruntime as ort
    if not MODEL_CACHE.exists():
        MODEL_CACHE.parent.mkdir(parents=True, exist_ok=True)
        print("downloading depth model to %s" % MODEL_CACHE)
        urllib.request.urlretrieve(MODEL_URL, MODEL_CACHE)
    session = ort.InferenceSession(str(MODEL_CACHE), providers=["CPUExecutionProvider"])
    h = 518
    w = int(round(h * img.width / img.height / 14.0)) * 14
    x = np.asarray(img.resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    x = (x - np.array([0.485, 0.456, 0.406])) / np.array([0.229, 0.224, 0.225])
    x = x.transpose(2, 0, 1)[None].astype(np.float32)
    disparity = session.run(None, {"pixel_values": x})[0][0]
    return np.asarray(Image.fromarray(disparity.astype(np.float32)).resize(size or (W, H), Image.BILINEAR))


def calibrate(disparity, f, pitch):
    x0, y0, x1, y1 = FLOOR_BOX
    ys, xs = np.mgrid[y0:y1:4, x0:x1:4].astype(np.float64)
    d = rays(xs, ys, f, pitch)
    z_floor = EYE_H / -d[..., 1]
    inv = (1.0 / z_floor).ravel()
    disp = disparity[ys.astype(int), xs.astype(int)].ravel()
    keep = np.ones_like(inv, dtype=bool)
    for _ in range(4):          # trimmed least squares: drop the worst fifth, refit
        a, b = np.polyfit(inv[keep], disp[keep], 1)
        residual = np.abs(disp - (a * inv + b))
        keep = residual <= np.quantile(residual, 0.8)
    return a, b


def depth_metres(disparity, a, b):
    z = a / np.maximum(disparity - b, 1e-3)
    return np.clip(z, 0.4, 40.0)


def floor_point(px, py, f, pitch):
    d = rays(np.array(float(px)), np.array(float(py)), f, pitch)
    t = EYE_H / -d[1]
    p = np.array([0.0, EYE_H, 0.0]) + d * t
    p[1] = 0.0
    return p


def light_map(plate, z, f, pitch):
    blurred = np.asarray(plate.filter(ImageFilter.GaussianBlur(28)), dtype=np.float32) / 255.0
    x0, z0, x1, z1 = LIGHT_RECT
    gx, gz = np.meshgrid(np.linspace(x0, x1, LIGHT_RES), np.linspace(z0, z1, LIGHT_RES))
    out = np.zeros((LIGHT_RES, LIGHT_RES, 3), np.float32)
    known = np.zeros((LIGHT_RES, LIGHT_RES), bool)
    up = np.array([0.0, math.cos(pitch), math.sin(pitch)])
    fwd = np.array([0.0, math.sin(pitch), -math.cos(pitch)])
    for j in range(LIGHT_RES):
        for i in range(LIGHT_RES):
            p = np.array([gx[j, i], -EYE_H, gz[j, i]])        # relative to the eye
            depth = p @ fwd
            if depth <= 0.3:
                continue
            px = W / 2.0 + f * p[0] / depth
            py = H / 2.0 - f * (p @ up) / depth
            if not (0 <= px < W and 0 <= py < H):
                continue
            if z[int(py), int(px)] < depth * 0.9:              # something stands in front of this floor
                continue
            out[j, i] = blurred[int(py), int(px)]
            known[j, i] = True
    # Unknown cells take the mean of the known ones, then everything is softened once more.
    out[~known] = out[known].mean(axis=0) if known.any() else 0.25
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    luma = np.asarray(img, np.float32) @ np.array([0.3, 0.55, 0.15]) / 255.0
    return img, known, luma


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--plate", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--actor", action="append", default=[], metavar="NAME=X,Y")
    parser.add_argument("--source", default="", help="provenance note written into room.json")
    parser.add_argument("--horizon", type=float, help="the horizon as a fraction of the height (default: the hall's 0.65)")
    parser.add_argument("--floor-box", type=int, nargs=4, metavar=("X0", "Y0", "X1", "Y1"),
                        help="bare floor pixels of the 1280x720 frame for the metric calibration")
    parser.add_argument("--sun", type=float, nargs=3, metavar=("X", "Y", "Z"),
                        help="the light's direction toward the sun (default: from the pool toward the brightest top pixel)")
    parser.add_argument("--sun-pixel", type=float, nargs=2, metavar=("X", "Y"),
                        help="the pixel of the light source (an oculus, a window) instead of the brightest in the top fifth")
    args = parser.parse_args(argv)
    global HORIZON_FRAC, FLOOR_BOX
    if args.horizon:
        HORIZON_FRAC = args.horizon
    if args.floor_box:
        FLOOR_BOX = tuple(args.floor_box)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    plate = Image.open(args.plate).convert("RGB").resize((W, H), Image.LANCZOS)
    plate.save(out / "plate.png")
    f, pitch = camera()

    disparity = run_depth(plate)
    a, b = calibrate(disparity, f, pitch)
    z = depth_metres(disparity, a, b)
    print("calibration: disparity = %.3f / z + %.3f" % (a, b))

    gx = np.arange(0, W + 1, GRID_STEP)
    gy = np.arange(0, H + 1, GRID_STEP)
    sample_x = np.clip(gx, 0, W - 1)
    sample_y = np.clip(gy, 0, H - 1)
    grid = z[np.ix_(sample_y, sample_x)]

    lm, known, luma = light_map(plate, z, f, pitch)
    lm.save(out / "light_map.png")
    lit_range = [float(np.quantile(luma, 0.3)), float(np.quantile(luma, 0.98))]
    j, i = np.unravel_index(np.argmax(luma), luma.shape)
    x0, z0, x1, z1 = LIGHT_RECT
    pool = np.array([x0 + (x1 - x0) * i / (LIGHT_RES - 1), 0.0, z0 + (z1 - z0) * j / (LIGHT_RES - 1)])
    # The oculus: the brightest pixel in the top fifth of the painting, at its estimated depth.
    top = np.asarray(plate, np.float32)[: H // 5].sum(axis=2)
    oy, ox = np.unravel_index(np.argmax(top), top.shape)
    if args.sun_pixel:
        ox, oy = (int(round(v)) for v in args.sun_pixel)
    oculus = rays(np.array(float(ox)), np.array(float(oy)), f, pitch) * min(z[oy, ox], 12.0) + [0, EYE_H, 0]
    sun_dir = (oculus - pool) / np.linalg.norm(oculus - pool)
    if args.sun:
        sun_dir = np.array(args.sun, float) / np.linalg.norm(args.sun)
    beam = np.asarray(plate, np.float32)[max(oy - 6, 0): oy + 6, max(ox - 6, 0): ox + 6].reshape(-1, 3).mean(axis=0) / 255.0

    actors = {}
    for spec in args.actor:
        name, _, xy = spec.partition("=")
        px, py = (float(v) for v in xy.split(","))
        p = floor_point(px, py, f, pitch)
        actors[name] = {"pixel": [px, py], "position": [round(float(c), 3) for c in p]}

    room = {
        "source": args.source,
        "image_size": [W, H],
        "fov_v": FOV_V,
        "horizon": round(HORIZON_FRAC, 4),
        "eye_height": EYE_H,
        "pitch_deg": round(math.degrees(pitch), 4),
        "grid_step": GRID_STEP,
        "grid_size": [len(gx), len(gy)],
        "depth_grid": [round(float(v), 3) for v in grid.ravel()],
        "calibration": {"a": float(a), "b": float(b), "floor_box": FLOOR_BOX},
        "light_rect": list(LIGHT_RECT),
        "lit_range": [round(v, 3) for v in lit_range],
        "sun_dir": [round(float(v), 3) for v in sun_dir],
        "sun_color": [round(float(v), 3) for v in beam],
        "pool": [round(float(v), 3) for v in pool],
        "actors": actors,
    }
    (out / "room.json").write_text(json.dumps(room) + "\n", encoding="utf-8")

    # A depth preview for people (near = bright).
    preview = (1.0 - np.clip(np.log(z / 0.4) / np.log(40.0 / 0.4), 0, 1)) * 255
    Image.fromarray(preview.astype(np.uint8)).save(out / "depth_preview.png")
    print("wrote %s: %dx%d grid, actors %s, sun_dir %s, lit_range %s" % (
        out, len(gx), len(gy), {k: v["position"] for k, v in actors.items()}, room["sun_dir"], room["lit_range"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
