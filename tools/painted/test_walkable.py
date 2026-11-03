#!/usr/bin/env python3
"""Offline checks for walkable.py's not_floor.json (water and voids are not floor): python3 tools/painted/test_walkable.py"""
import json
import sys
import tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import walkable  # noqa: E402

H, W = 60, 80


def flat_floor():
    """A camera 1.3 m up looking down at a flat floor (y = 0), as the depth lift gives it: points and rays per pixel."""
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.stack([(xs - W / 2) / W * 0.4, -(0.2 + 0.5 * ys / H), -np.ones_like(xs)], -1).astype(np.float32)
    rays = d / np.linalg.norm(d, axis=-1, keepdims=True)
    t = 1.3 / -rays[..., 1]
    points = np.array([0.0, 1.3, 0.0], np.float32) + rays * t[..., None]
    return points, rays


def test_no_file_means_no_exclusion():
    with tempfile.TemporaryDirectory() as tmp:
        mask = walkable.not_floor_mask(Path(tmp), (W, H))
    assert mask.shape == (H, W) and not mask.any()


def test_a_polygon_is_not_floor_and_the_rest_of_the_floor_stays():
    points, rays = flat_floor()
    room = {"actors": {"witch": {"pixel": [60, 50]}}}
    with tempfile.TemporaryDirectory() as tmp:
        room_dir = Path(tmp)
        (room_dir / "not_floor.json").write_text(json.dumps({"polygons": [[[0, 0], [30, 0], [30, 30], [0, 30]]]}), encoding="utf-8")
        mask = walkable.not_floor_mask(room_dir, (W, H))
    assert mask[10, 10] and not mask[50, 70], "the polygon covers its own corner and not the far corner"
    floor_without, _ = walkable.floor_pixels(room, None, points, rays, [], None)
    assert floor_without[10, 10], "without the file the flat pond counts as floor (the known gap)"
    floor, _ = walkable.floor_pixels(room, None, points, rays, [], mask)
    assert not floor[10, 10], "the pond is not floor"
    assert floor[50, 60], "the witch's feet stay on floor"
    assert floor[40, 60], "the floor beside the pond stays floor"


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
    sys.exit(1 if failed else 0)
