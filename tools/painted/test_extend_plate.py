#!/usr/bin/env python3
"""Offline checks for extend_plate.py (no network, no model): python3 tools/painted/test_extend_plate.py"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extend_plate as ep  # noqa: E402


def synthetic_plate(w=320, h=180, seed=3):
    rng = np.random.default_rng(seed)
    a = ndimage.gaussian_filter(rng.random((h, w, 3)) * 255, (3, 3, 0))
    a = (a - a.min()) / (a.max() - a.min()) * 255
    return Image.fromarray(a.astype(np.uint8))


def test_merge_recovers_a_drifted_result_and_keeps_the_core_exact():
    plate = synthetic_plate()
    mx, my = 40, 22
    canvas = ep.make_canvas(plate, mx, my, "mirror")
    # The "model": the canvas shifted by 5 px and scaled by 1 %, with a colour cast.
    ref = np.asarray(canvas, np.float32)
    drifted = ep._affine_warp(ref, (0.99, 0.99, -5.0, 2.0), ((ref.shape[1]) / 2, (ref.shape[0]) / 2)) * 0.95 + 6
    image, report = ep.merge(plate, Image.fromarray(np.clip(drifted, 0, 255).astype(np.uint8)), mx, my, feather=4)
    assert report["core_exact"] and report["core_max_abs_diff"] == 0, report
    assert abs(report["shift_px"][0] - 5.0) < 1.0 and abs(report["shift_px"][1] + 2.0) < 1.0, report["shift_px"]
    assert abs(report["scale_x"] - 1 / 0.99) < 0.01, report["scale_x"]
    raw = Image.fromarray(np.clip(drifted, 0, 255).astype(np.uint8))
    _, unsnapped = ep.merge(plate, raw, mx, my, feather=4, snap=False)
    assert report["seam_step_ratio"] < unsnapped["seam_step_ratio"], "snapping the colours to the plate narrows the seam step"
    hard, hard_report = ep.merge(plate, Image.fromarray(np.clip(drifted, 0, 255).astype(np.uint8)), mx, my, feather=0)
    assert hard_report["plate_changed_px"] == 0, "a hard paste leaves the whole plate untouched"


def test_the_gate_rejects_a_centre_that_moved_or_a_margin_left_blurry():
    base = {"shift_px": [1.0, 0.5], "scale_x": 1.0, "scale_y": 1.0, "seam_ring_mae_0_255": 4.0,
            "margin_sharpness_ratio": 0.6, "seam_step_ratio": 1.0}
    assert ep.accept(base)[0]
    assert not ep.accept(dict(base, shift_px=[12.0, 0.0]))[0]
    assert not ep.accept(dict(base, scale_x=1.06))[0]
    assert not ep.accept(dict(base, margin_sharpness_ratio=0.1))[0]
    assert not ep.accept(dict(base, seam_step_ratio=4.0))[0]


def test_geometry():
    assert ep.margins(0.125) == (160, 90)
    assert ep.inner_box(160, 90) == (160, 90, 1440, 810)
    boxes = ep.strip_boxes(160, 90)
    assert boxes["left"] == (0, 90, 560, 810) and boxes["top"] == (0, 0, 1600, 686)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
