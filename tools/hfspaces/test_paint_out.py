#!/usr/bin/env python3
"""Offline checks for paint_out.py (no network): python3 tools/hfspaces/test_paint_out.py"""
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import paint_out  # noqa: E402


def ramp(path, w=120, h=90):
    ys, xs = np.mgrid[0:h, 0:w]
    arr = np.stack([40 + xs * 0.9, 90 + ys * 0.8, 60 + (xs + ys) * 0.2], -1).clip(0, 255).astype(np.uint8)
    Image.fromarray(arr).save(path)
    return arr


class PaintOutTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_outside_the_polygon_nothing_changes(self):
        src = self.dir / "in.png"
        before = ramp(src)
        polygon = [(40, 30), (70, 30), (70, 60), (40, 60)]
        out = self.dir / "out.png"
        paint_out.paint_out(src, out, polygon, passes=200)
        after = np.asarray(Image.open(out).convert("RGB"))
        outside = np.ones(before.shape[:2], bool)
        outside[25:65, 35:75] = False                    # the polygon and its feather
        self.assertTrue((after[outside] == before[outside]).all())

    def test_inside_the_polygon_takes_the_colours_around_it(self):
        src = self.dir / "in.png"
        before = ramp(src)
        polygon = [(40, 30), (70, 30), (70, 60), (40, 60)]
        out = self.dir / "out.png"
        paint_out.paint_out(src, out, polygon, passes=400)
        after = np.asarray(Image.open(out).convert("RGB")).astype(float)
        inside = after[35:55, 45:65]
        lo, hi = before[20:70, 30:80].reshape(-1, 3).min(0) - 6, before[20:70, 30:80].reshape(-1, 3).max(0) + 6
        self.assertTrue(((inside >= lo) & (inside <= hi)).all())
        self.assertGreater(float(np.abs(inside - before[35:55, 45:65]).mean()), 1.0, "the polygon was not painted")

    def test_same_input_gives_the_same_bytes(self):
        src = self.dir / "in.png"
        ramp(src)
        polygon = [(10, 10), (30, 12), (25, 40)]
        a, b = self.dir / "a.png", self.dir / "b.png"
        paint_out.paint_out(src, a, polygon, passes=50)
        paint_out.paint_out(src, b, polygon, passes=50)
        self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_the_record_names_the_input_and_the_polygon(self):
        src = self.dir / "in.png"
        ramp(src)
        out = self.dir / "out.png"
        record = paint_out.paint_out(src, out, [(10, 10), (30, 12), (25, 40)], passes=10)
        self.assertEqual(record["source_sha256"], paint_out.sha256_file(src))
        self.assertEqual(record["out_sha256"], paint_out.sha256_file(out))
        self.assertEqual(record["polygon"], [[10, 10], [30, 12], [25, 40]])


if __name__ == "__main__":
    unittest.main(verbosity=1)
