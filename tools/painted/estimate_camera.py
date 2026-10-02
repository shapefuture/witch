#!/usr/bin/env python3
"""Estimates the horizon (hence the pitch) of a painted view from its depth, for views whose camera is not known.

    python tools/painted/estimate_camera.py plate.png --floor-box 300,560,1000,715 [--fov 55] [--far-percentile 1]

On the floor, inverse depth is LINEAR in the image row v (a plane seen by a pinhole camera), whatever the pitch:
disparity(v) = alpha * v + beta. The row where it reaches the disparity of "infinity" is the horizon. Depth Anything's
disparity has an unknown shift, so "infinity" is taken as a low percentile of the whole map (the farthest things in
the picture); this is the weak point, and why the method is validated on the original plate (horizon known from the
Cycles layout: 65.0 % of the height, pitch 8.9 degrees) before it is trusted on a new one.
Prints the estimate as `--horizon FRAC` for build_painted.py. Floor pixels must be floor: pass a box that is.
"""
import argparse
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_painted as bp  # noqa: E402


def estimate(plate, floor_box, fov=bp.FOV_V, far_percentile=1.0):
    w, h = plate.size
    disparity = bp.run_depth(plate, (w, h))
    x0, y0, x1, y1 = floor_box
    rows = np.arange(y0, y1, 2)
    d_row = np.array([np.median(disparity[y, x0:x1]) for y in rows])
    keep = np.ones(rows.shape, bool)
    for _ in range(4):
        alpha, beta = np.polyfit(rows[keep], d_row[keep], 1)
        r = np.abs(d_row - (alpha * rows + beta))
        keep = r <= np.quantile(r, 0.8)
    d_inf = float(np.percentile(disparity, far_percentile))
    v_h = (d_inf - beta) / alpha
    f = (h / 2.0) / math.tan(math.radians(fov) / 2.0)
    pitch = math.degrees(math.atan((v_h - h / 2.0) / f))
    return {"horizon_row": v_h, "horizon_frac": v_h / h, "pitch_deg": pitch, "alpha": alpha, "beta": beta,
            "d_inf": d_inf, "floor_fit_rms": float(np.sqrt(np.mean((d_row[keep] - (alpha * rows[keep] + beta)) ** 2)))}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("plate")
    parser.add_argument("--floor-box", required=True, help="x0,y0,x1,y1 of pure floor, in the plate's 1280x720 frame")
    parser.add_argument("--fov", type=float, default=bp.FOV_V)
    parser.add_argument("--far-percentile", type=float, default=1.0)
    args = parser.parse_args(argv)
    plate = Image.open(args.plate).convert("RGB").resize((bp.W, bp.H), Image.LANCZOS)
    box = tuple(int(v) for v in args.floor_box.split(","))
    e = estimate(plate, box, args.fov, args.far_percentile)
    print("horizon row %.1f (%.3f of the height), pitch %.2f deg, floor fit rms %.3f" % (
        e["horizon_row"], e["horizon_frac"], e["pitch_deg"], e["floor_fit_rms"]))
    print("--horizon %.4f" % e["horizon_frac"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
