#!/usr/bin/env python3
"""Gives a painted room (tools/painted/build_painted.py) the depth for its extended plate (extend_plate.py).

    python tools/painted/extend_room.py --room assets/painted/hall_clean \
        --plate-ext plate_ext.png --plate-empty-ext plate_empty_ext.png

Writes <room>/overscan.json, which game/world/painted/painted_room.gd reads beside room.json (or as an inline
"overscan" object in room.json). The camera model does not change: the same eye, pitch and centre of projection
(the middle of the ORIGINAL 1280x720 frame), so the extended frame is simply a wider field of view of the same
camera, and every pixel coordinate elsewhere (props, actors) keeps its meaning. Depth:

1. Depth Anything V2 runs on the extended plate.
2. Its relative inverse depth is mapped onto the room's own (the calibrated depth already in room.json) by a
   robust affine fit over the plate region, so the margin lives in the same metres.
3. The difference between the two along the seam is carried outward and fades with distance, so the mesh has no
   step where the margin begins.
4. Inside the plate the room's own depth grid is kept exactly (the middle of the mesh does not move).
"""
import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_painted as bp  # noqa: E402
import extend_plate as ep  # noqa: E402


def room_disparity(room, width, height):
    """The room's own depth grid, as inverse depth in the Depth Anything scale (the calibration a/z + b), at
    pixel resolution over the original frame."""
    gw, gh = room["grid_size"]
    z = np.array(room["depth_grid"], np.float64).reshape(gh, gw)
    a, b = room["calibration"]["a"], room["calibration"]["b"]
    step = room["grid_step"]
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)
    zs = ndimage.map_coordinates(z, [yy / step, xx / step], order=1, mode="nearest")
    return a / zs + b


def robust_affine(x, y, trim=0.8, rounds=4):
    keep = np.ones(x.shape, bool)
    for _ in range(rounds):
        alpha, beta = np.polyfit(x[keep], y[keep], 1)
        r = np.abs(y - (alpha * x + beta))
        keep = r <= np.quantile(r, trim)
    return float(alpha), float(beta)


def extend(room_dir, plate_ext, mx, my, reach=60.0):
    room = json.loads((room_dir / "room.json").read_text())
    w, h = room["image_size"]
    step = room["grid_step"]
    a, b = room["calibration"]["a"], room["calibration"]["b"]
    d_room = room_disparity(room, w, h)

    d_ext = bp.run_depth(plate_ext, (w + 2 * mx, h + 2 * my)).astype(np.float64)
    inner = d_ext[my:my + h, mx:mx + w]
    trim = 24
    alpha, beta = robust_affine(inner[trim:-trim:3, trim:-trim:3].ravel(), d_room[trim:-trim:3, trim:-trim:3].ravel())
    fitted = alpha * d_ext + beta

    # The metres of the fit inside the plate: how well the extended image's depth agrees with the room's own.
    z_fit_in = bp.depth_metres(fitted[my:my + h, mx:mx + w], a, b)
    z_room = bp.depth_metres(d_room, a, b)
    rel = np.abs(z_fit_in / z_room - 1.0)

    # The seam: the margin starts from the room's depth and returns to the fit's own with distance.
    reference = fitted.copy()
    reference[my:my + h, mx:mx + w] = d_room
    snapped = ep.snap_colour(fitted[..., None].astype(np.float32), reference[..., None].astype(np.float32),
                             ep.inner_box(mx, my, (w, h)), depth=24, reach=reach)[..., 0].astype(np.float64)
    snapped[my:my + h, mx:mx + w] = d_room
    z_ext = bp.depth_metres(snapped, a, b)

    # The grid keeps the room's own sample positions (multiples of grid_step) and runs on past the frame; its
    # outermost vertices are clamped to the plate's edge by the loader.
    gx0 = -int(math.ceil(mx / step)) * step
    gy0 = -int(math.ceil(my / step)) * step
    nx = (w + int(math.ceil(mx / step)) * step - gx0) // step + 1
    ny = (h + int(math.ceil(my / step)) * step - gy0) // step + 1
    px = np.clip(gx0 + np.arange(nx) * step, -mx, w + mx - 1) + mx
    py = np.clip(gy0 + np.arange(ny) * step, -my, h + my - 1) + my
    grid = z_ext[np.ix_(py.astype(int), px.astype(int))]
    old = np.array(room["depth_grid"], np.float64).reshape(room["grid_size"][1], room["grid_size"][0])
    ox, oy = -gx0 // step, -gy0 // step
    grid[oy:oy + old.shape[0], ox:ox + old.shape[1]] = old
    fov_ext = math.degrees(2 * math.atan(math.tan(math.radians(room["fov_v"]) / 2) * (h + 2 * my) / h))

    overscan = {
        "margin": [mx, my],
        "plate": "plate_ext.png",
        "grid_origin": [gx0, gy0],
        "grid_size": [nx, ny],
        "depth_grid": [round(float(v), 3) for v in grid.ravel()],
        "fov_v_extended": round(fov_ext, 3),
        "fit": {"alpha": alpha, "beta": beta, "median_rel_depth_error_in_plate": float(np.median(rel)),
                "p90_rel_depth_error_in_plate": float(np.quantile(rel, 0.9))},
    }
    preview = (1.0 - np.clip(np.log(z_ext / 0.4) / np.log(40.0 / 0.4), 0, 1)) * 255
    Image.fromarray(preview.astype(np.uint8)).save(room_dir / "depth_preview_ext.png")
    return overscan, z_ext, z_room


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--room", required=True, help="a room directory holding room.json")
    parser.add_argument("--plate-ext", default="plate_ext.png", help="the extended plate, relative to --room")
    parser.add_argument("--plate-empty-ext", default="", help="the extended plate with props lifted out")
    parser.add_argument("--reach", type=float, default=60.0, help="px over which the seam correction fades")
    args = parser.parse_args(argv)
    room_dir = Path(args.room)
    room = json.loads((room_dir / "room.json").read_text())
    plate_ext = Image.open(room_dir / args.plate_ext).convert("RGB")
    w, h = room["image_size"]
    if (plate_ext.width - w) % 2 or (plate_ext.height - h) % 2:
        raise SystemExit("the extended plate must be the plate plus the same margin on both sides")
    mx, my = (plate_ext.width - w) // 2, (plate_ext.height - h) // 2
    overscan, z_ext, z_room = extend(room_dir, plate_ext, mx, my, args.reach)
    overscan["plate"] = args.plate_ext
    if args.plate_empty_ext:
        overscan["plate_empty"] = args.plate_empty_ext
    overscan["source"] = "tools/painted/extend_room.py: Depth Anything V2 on %s, fitted to room.json's depth" % args.plate_ext
    (room_dir / "overscan.json").write_text(json.dumps(overscan) + "\n", encoding="utf-8")
    g = overscan["grid_size"]
    print("wrote %s: margin %s px, %dx%d grid, extended fov %.1f deg, fit %s" % (
        room_dir / "overscan.json", overscan["margin"], g[0], g[1], overscan["fov_v_extended"], overscan["fit"]))
    margin_z = np.concatenate([z_ext[:my].ravel(), z_ext[-my:].ravel(), z_ext[my:-my, :mx].ravel(), z_ext[my:-my, -mx:].ravel()])
    print("margin depth: median %.2f m, range %.2f..%.2f m (plate: median %.2f m)" % (
        np.median(margin_z), margin_z.min(), margin_z.max(), np.median(z_room)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
