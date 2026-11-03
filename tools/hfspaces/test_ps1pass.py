#!/usr/bin/env python3
"""Offline checks for ps1pass.py (no network, no GPU): python3 tools/hfspaces/test_ps1pass.py"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ps1pass  # noqa: E402


def gradient_png(path, w=40, h=30):
    """A smooth colour ramp, so every texel block differs from its neighbours."""
    ys, xs = np.mgrid[0:h, 0:w]
    arr = np.stack([xs * 255 / (w - 1), ys * 255 / (h - 1), (xs + ys) * 255 / (w + h - 2)], -1).astype(np.uint8)
    Image.fromarray(arr).save(path)
    return Path(path)


class PS1PassTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_texels_are_flat_blocks_of_the_same_size(self):
        src = gradient_png(self.dir / "in.png")
        dst = self.dir / "out.png"
        prov = ps1pass.apply(src, dst, texel=5, transfer_to=0.0, dither=0.0)
        out = np.asarray(Image.open(dst).convert("RGB"))
        self.assertEqual(out.shape[:2], (30, 40))
        self.assertEqual(prov["grid"], [8, 6])
        for gy in range(6):
            for gx in range(8):
                block = out[gy * 5:(gy + 1) * 5, gx * 5:(gx + 1) * 5].reshape(-1, 3)
                self.assertTrue((block == block[0]).all(), "texel (%d, %d) is not one colour" % (gx, gy))

    def test_palette_is_the_plates_own_colours_and_the_output_uses_only_them(self):
        src = gradient_png(self.dir / "in.png")
        dst = self.dir / "out.png"
        ps1pass.apply(src, dst, texel=5, palette="plate", colours=8, transfer_to=0.0, dither=0.6, refs=[])
        out = np.asarray(Image.open(dst).convert("RGB")).reshape(-1, 3)
        prov = json.loads(Path(str(dst) + ".json").read_text(encoding="utf-8"))
        self.assertEqual(prov["palette"], "plate")
        self.assertLessEqual(len(np.unique(out, axis=0)), 8)

    def test_same_input_gives_the_same_bytes(self):
        src = gradient_png(self.dir / "in.png")
        a, b = self.dir / "a.png", self.dir / "b.png"
        ps1pass.apply(src, a, texel=5, colours=12, transfer_to=0.0, refs=[])
        ps1pass.apply(src, b, texel=5, colours=12, transfer_to=0.0, refs=[])
        self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_provenance_names_the_input_and_the_output(self):
        src = gradient_png(self.dir / "in.png")
        dst = self.dir / "out.png"
        prov = ps1pass.apply(src, dst, texel=5, colours=8, transfer_to=0.0, refs=[], cool=0.3, gamma=0.8, hi=(1.0, 0.8, 0.4),
                             hi_amount=0.5)
        self.assertEqual(prov["source_sha256"], ps1pass.sha256_file(src))
        self.assertEqual(prov["out_sha256"], ps1pass.sha256_file(dst))
        self.assertEqual(prov["size"], [40, 30])
        self.assertEqual(prov["split_tone"]["hi_amount"], 0.5)

    def test_dither_mixes_two_colours_in_the_texel_grid(self):
        grey = np.full((5 * 40, 5 * 40, 3), 0.5, np.float32)
        grid, _ = ps1pass.texels(grey, 5)
        palette = np.array([[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]], np.float32)
        quant = ps1pass.palette_map(grid, palette, dither=1.0)
        white = float((quant[..., 0] > 0.5).mean())
        self.assertGreater(white, 0.3)
        self.assertLess(white, 0.7)
        none = ps1pass.palette_map(grid, palette, dither=0.0)
        self.assertEqual(len(np.unique(none.reshape(-1, 3), axis=0)), 1)

    def test_split_tone_keeps_luminance_where_it_applies(self):
        mid = np.full((4, 4, 3), 0.6, np.float32)                          # not so bright that the tint clips
        out = ps1pass.split_tone(mid, hi=(1.0, 0.8, 0.4), hi_amount=1.0)
        self.assertAlmostEqual(float((out @ ps1pass.LUMA).mean()), 0.6, places=3)
        self.assertGreater(out[..., 0].mean(), out[..., 2].mean())         # warm: gold, not grey
        untouched = ps1pass.split_tone(mid, hi=None, hi_amount=1.0)
        np.testing.assert_allclose(untouched, mid)

    def test_cool_shadows_move_dark_texels_toward_blue_and_away_from_green(self):
        dark = np.full((2, 2, 3), 0.2, np.float32)
        out = ps1pass.cool_shadows(dark, 1.0)
        self.assertGreater(out[0, 0, 2], dark[0, 0, 2])
        self.assertLess(out[0, 0, 1], dark[0, 0, 1])
        lit = np.full((2, 2, 3), 0.9, np.float32)
        np.testing.assert_allclose(ps1pass.cool_shadows(lit, 1.0), lit)

    def test_transfer_at_zero_is_identity_and_at_one_takes_the_reference_mean(self):
        rng = np.random.default_rng(3)
        rgb = rng.uniform(0.0, 1.0, (20, 20, 3)).astype(np.float32)
        np.testing.assert_allclose(ps1pass.transfer(rgb, np.array([50.0, 0, 0]), np.array([10.0, 10, 10]), 0.0), rgb)
        mu_ref = np.array([35.0, 5.0, -5.0])
        moved = ps1pass.transfer(rgb, mu_ref, np.array([20.0, 20, 20]), 1.0)
        self.assertLess(abs(float(ps1pass.to_lab(moved).reshape(-1, 3).mean(0)[0]) - 35.0), 2.0)

    def test_fifteen_bit_mode_uses_five_bits_a_channel(self):
        src = gradient_png(self.dir / "in.png")
        dst = self.dir / "out.png"
        ps1pass.apply(src, dst, texel=5, palette="15bit", transfer_to=0.0, dither=0.0)
        out = np.asarray(Image.open(dst).convert("RGB"))
        levels = {round(i * 255 / 31) for i in range(32)}
        for c in range(3):
            self.assertTrue(set(np.unique(out[..., c]).tolist()) <= levels, "channel %d has more than 32 levels" % c)

    def test_measure_reports_the_gauntlet_numbers(self):
        src = gradient_png(self.dir / "in.png", 64, 48)
        row = ps1pass.measure_one(src)
        for key in ("median_luma", "mean_sat", "purple", "magenta", "gold", "green", "blue", "facet_gradient", "hf", "dark_share"):
            self.assertIn(key, row)


if __name__ == "__main__":
    unittest.main(verbosity=1)
