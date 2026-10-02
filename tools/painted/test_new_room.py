#!/usr/bin/env python3
"""Offline checks for new_room.py (no network, no depth model): python3 tools/painted/test_new_room.py"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_painted as bp  # noqa: E402
import new_room as nr  # noqa: E402


def synthetic_disparity(horizon, a=22.0, b=0.5):
    """The depth model's disparity for a bare floor seen from a camera whose horizon is `horizon`."""
    bp.HORIZON_FRAC = horizon
    f, pitch = bp.camera()
    ys, xs = np.mgrid[0:bp.H, 0:bp.W].astype(np.float64)
    d = bp.rays(xs, ys, f, pitch)
    inv = np.where(d[..., 1] < -0.02, -d[..., 1] / bp.EYE_H, 0.02)
    return a * inv + b


def test_floor_fit_recovers_the_depth_calibration():
    disp = synthetic_disparity(0.62)
    a, b, res = nr.fit_floor(disp, 0.62)
    assert abs(a - 22.0) < 0.05 and abs(b - 0.5) < 0.02 and res < 0.001, (a, b, res)


def test_floor_box_is_below_the_horizon_and_inside_the_frame():
    for h in (0.55, 0.62, 0.70):
        x0, y0, x1, y1 = nr.floor_box_for(h)
        assert y0 > h * bp.H and y1 <= bp.H and 0 <= x0 < x1 <= bp.W


def test_find_lights_classifies_a_window_a_candle_and_a_crystal():
    a = np.full((bp.H, bp.W, 3), 30, np.uint8)
    yy, xx = np.mgrid[0:bp.H, 0:bp.W]
    a[(xx - 300) ** 2 + (yy - 150) ** 2 < 40 ** 2] = (255, 240, 190)      # a big warm window above the horizon
    a[(xx - 900) ** 2 + (yy - 380) ** 2 < 7 ** 2] = (255, 200, 110)       # a candle
    a[(xx - 700) ** 2 + (yy - 300) ** 2 < 7 ** 2] = (180, 120, 255)       # a violet crystal
    lights = nr.find_lights(Image.fromarray(a), 0.62)
    kinds = {l["flicker"]["kind"] for l in lights}
    assert kinds == {"breath", "candle", "magic"}, kinds
    assert [l for l in lights if l["_big"]][0]["pixel"][0] in range(290, 311)


def test_life_has_a_beam_only_when_there_is_a_large_source():
    a = np.full((bp.H, bp.W, 3), 30, np.uint8)
    yy, xx = np.mgrid[0:bp.H, 0:bp.W]
    a[(xx - 900) ** 2 + (yy - 380) ** 2 < 7 ** 2] = (255, 200, 110)
    life, source = nr.make_life(Image.fromarray(a), 0.62, (640, 600))
    assert source is None and "beam" not in life and len(life["lights"]) == 1
    a[(xx - 300) ** 2 + (yy - 150) ** 2 < 40 ** 2] = (255, 240, 190)
    life, source = nr.make_life(Image.fromarray(a), 0.62, (640, 600))
    assert source is not None and life["beam"]["source"] == source["id"]
    assert all(len(poly) >= 4 for poly in (life["beam"]["shaft"]["polygon"], life["beam"]["pool"]["polygon"]))


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            try:
                fn()
                print("ok   " + name)
            except AssertionError as e:
                failed += 1
                print("FAIL " + name, e)
            finally:
                bp.HORIZON_FRAC = 612.0 / 941.0
    sys.exit(1 if failed else 0)
