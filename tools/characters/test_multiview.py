#!/usr/bin/env python3
"""Offline checks for multiview.py (no network, nothing charged): python3 tools/characters/test_multiview.py"""
import json
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import multiview as mv  # noqa: E402

SHEET = (2352, 1568)
PALE = (246, 246, 246)


def _figure(d, cx, top, h, w, hole=(255, 255, 255)):
    """A stand-in character: skirt, torso, head, a THIN wand, a near-white pendant on the torso, and a ring whose hole is real background."""
    d.polygon([(cx - w * .2, top + h * .55), (cx + w * .2, top + h * .55), (cx + w * .5, top + h), (cx - w * .5, top + h)], fill=(110, 40, 150))
    d.rectangle((cx - w * .2, top + h * .2, cx + w * .2, top + h * .55), fill=(120, 80, 60))
    d.ellipse((cx - w * .15, top, cx + w * .15, top + h * .22), fill=(230, 190, 150))
    d.line((cx + w * .3, top + h * .3, cx + w * .45, top + h * .05), fill=(200, 60, 120), width=10)
    d.ellipse((cx - 14, top + h * .35, cx + 14, top + h * .35 + 28), fill=PALE)
    rx, ry = cx - w * .2 - 80, top + h * .3
    d.ellipse((rx, ry, rx + 130, ry + 130), fill=(150, 90, 40))
    d.ellipse((rx + 35, ry + 35, rx + 95, ry + 95), fill=hole)


def sheet(offsets=None, scale=None, skip=(), frames=True, bg=(255, 255, 255), hole=(255, 255, 255)):
    """Six figures, a little off their cells' centres (as a generator draws them)."""
    img = Image.new("RGB", SHEET, bg)
    d = ImageDraw.Draw(img)
    cw, ch = SHEET[0] / 3, SHEET[1] / 2
    rng = np.random.default_rng(3)
    boxes = {}
    for i in range(6):
        x0, y0 = (i % 3) * cw, (i // 3) * ch
        if frames:
            d.rectangle((x0 + 6, y0 + 6, x0 + cw - 7, y0 + ch - 7), outline=(205, 205, 205), width=3)
            d.text((x0 + 24, y0 + 18), "3 RIGHT SIDE", fill=(150, 150, 150))
        if i in skip:
            continue
        k = (scale or {}).get(i, 1.0)
        h = ch * 0.72 * k * (1 + rng.uniform(-.06, .06))
        w = h * 0.55
        dx, dy = (offsets or {}).get(i, (rng.uniform(-.05, .05) * cw, rng.uniform(-.03, .03) * ch))
        cx, top = x0 + cw / 2 + dx, y0 + (ch - h) / 2 + dy
        _figure(d, cx, top, h, w, hole)
        boxes[i] = (cx, top, h, w)
    return img, boxes


def _crop(img, **kw):
    tmp = Path(tempfile.mkdtemp())
    img.save(tmp / "sheet.png")
    return mv.crop(tmp / "sheet.png", tmp / "out", **kw), tmp / "out"


def _alpha_box(path):
    a = np.asarray(Image.open(path))[..., 3]
    ys, xs = np.nonzero(a > 128)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1, a


def test_the_guide_is_a_white_3_by_2_sheet_with_six_cells():
    g = mv.guide(key="white")
    assert g.size[0] * 2 == g.size[1] * 3, g.size
    a = np.asarray(g).astype(int)
    assert (a > 250).mean() > 0.9, "mostly white"
    assert a.max() == 255 and a[:, :, 0].min() > 100, "only pale greys: a generator echoes strong colours as objects"


def test_the_prompt_names_every_view_and_reads_the_references_in_order():
    p = mv.compose("", ref=True, use_guide=True, key="white")
    assert "FIRST reference" in p and "SECOND reference" in p and "pure white" in p
    for _, _, words, _ in mv.VIEWS:
        assert words in p, words
    q = mv.compose("a fox in a red coat", ref=False, use_guide=False, key="white")
    assert "FIRST" not in q and "three columns by two rows" in q and "The character: a fox in a red coat." in q
    assert "reference image" not in q


def test_crop_writes_six_square_views_of_one_height_centred():
    img, boxes = sheet()
    report, out = _crop(img, size=1024)
    assert report["problems"] == [], report["problems"]
    assert list(report["views"]) == mv.NAMES
    heights = []
    for name in mv.NAMES:
        x0, y0, x1, y1, a = _alpha_box(out / "views" / (name + ".png"))
        assert a.shape == (1024, 1024)
        heights.append(y1 - y0)
        assert abs((x0 + x1) / 2 - 512) < 4 and abs((y0 + y1) / 2 - 512) < 4, (name, x0, y0, x1, y1)
        white = np.asarray(Image.open(out / "white" / (name + ".png")))
        assert white.shape == (1024, 1024, 3) and white[0, 0].tolist() == [255, 255, 255]
    assert max(heights) - min(heights) <= 5, heights
    assert abs(heights[0] - 1024 * mv.FILL) <= 6, heights
    assert (out / "contact.png").exists() and (out / "sheet_boxes.png").exists() and (out / "views.json").exists()


def test_the_frame_lines_and_labels_of_the_guide_do_not_count():
    with_frames, _ = _crop(sheet(frames=True)[0])
    without, _ = _crop(sheet(frames=False)[0])
    assert with_frames["views"] == without["views"], "a drawn frame must not widen a figure's box"


def test_pale_parts_inside_a_figure_stay_and_a_real_gap_is_transparent():
    img, boxes = sheet(offsets={i: (0, 0) for i in range(6)}, scale={i: 1.0 for i in range(6)})
    report, out = _crop(img, size=1024)
    x0, y0, x1, y1, a = _alpha_box(out / "views" / "front.png")
    cx, top, h, w = boxes[0]
    k = (y1 - y0) / h                                             # sheet px -> output px
    px = lambda sx, sy: a[int(512 + (sy - (top + h / 2)) * k), int(512 + (sx - cx) * k)]   # noqa: E731
    assert px(cx, top + h * .35 + 14) > 250, "the white pendant is part of the figure"
    rx, ry = cx - w * .2 - 80, top + h * .3
    assert px(rx + 65, ry + 65) < 5, "the ring's hole is background"


def test_problems_are_reported_not_hidden():
    r, _ = _crop(sheet(skip=(4,))[0])
    assert any("back34: nothing found" in p for p in r["problems"]), r["problems"]
    r, _ = _crop(sheet(offsets={0: (0, -130)})[0])
    assert any(p.startswith("front:") and "cut off" in p for p in r["problems"]), r["problems"]
    r, _ = _crop(sheet(offsets={0: (0, 600)})[0])
    assert any("nothing found" in p or "spills" in p or "two figures" in p for p in r["problems"]), "a figure fallen into the next cell is flagged"
    r, out = _crop(sheet(scale={2: 0.6})[0], size=1024)
    assert any("right:" in p and "smaller" in p for p in r["problems"]), r["problems"]
    x0, y0, x1, y1, _a = _alpha_box(out / "views" / "right.png")
    assert abs((y1 - y0) - 1024 * mv.FILL) <= 6, "still normalised to the common height"
    r, _ = _crop(sheet(bg=(200, 200, 205))[0], key="white")
    assert any("not white" in p for p in r["problems"]), r["problems"]


def test_on_a_key_colour_every_key_pixel_is_a_hole_and_the_edge_is_despilled():
    img, boxes = sheet(offsets={i: (0, 0) for i in range(6)}, bg=(0, 240, 5), hole=(10, 200, 20))      # the key between the curls is darker
    d = ImageDraw.Draw(img)
    cx, top, h, w = boxes[0]
    d.ellipse((cx - 10, top + h * .75, cx + 10, top + h * .75 + 20), fill=(0, 240, 5))      # a 20 px hole: too small to tell from a pale pixel on white
    report, out = _crop(img, size=1024, key="green")
    assert report["problems"] == [], report["problems"]
    x0, y0, x1, y1, a = _alpha_box(out / "views" / "front.png")
    k = (y1 - y0) / h
    px = lambda sx, sy: a[int(512 + (sy - (top + h / 2)) * k), int(512 + (sx - cx) * k)]   # noqa: E731
    assert px(cx, top + h * .35 + 14) > 250, "the pale pendant stays"
    assert px(cx, top + h * .75 + 10) < 5, "a small enclosed hole of the key is transparent"
    rx, ry = cx - w * .2 - 80, top + h * .3
    assert px(rx + 65, ry + 65) < 5, "the key counts as key where it is shaded darker, enclosed or not"
    r, _ = _crop(sheet(bg=(255, 255, 255))[0], key="green")
    assert any("not green" in p for p in r["problems"]), r["problems"]
    win = np.zeros((40, 40, 3)) + [0, 255, 0]
    win[10:30, 10:30] = [110, 40, 150]
    win[10:30, 10:12] = [55, 147, 75]                                                         # the edge, half green
    mask = mv.difference(win, np.array([0, 255, 0.])) > mv.TOL
    alpha, rgb = mv.matte(win, np.array([0, 255, 0.]), mask)
    assert rgb[20, 10, 1] <= (rgb[20, 10, 0] + rgb[20, 10, 2]) / 2 + 1, "no green left on the edge"
    assert alpha[20, 20] == 1 and alpha[2, 2] == 0


def test_the_guide_and_the_prompt_follow_the_key():
    g = np.asarray(mv.guide(key="green")).astype(int)
    assert g[3, 700, 1] == 255 and g[3, 700, 0] == 0 and g[3, 700, 2] == 0, "the canvas is the key colour"
    assert g[..., 0].max() == 0 and g[..., 2].max() == 0, "only darker greens: no other colour to copy"
    assert "chroma-key green" in mv.compose("", key="green") and "pure white" in mv.compose("", key="white")


def test_a_rigging_pose_is_asked_for_and_drawn_on_the_guide():
    t = mv.compose("", pose="t", key="white")
    assert "T-pose" in t and "EMPTY" in t and "T-pose" not in mv.compose("", pose="keep") and "A-pose" in mv.compose("", pose="a")
    row = int(mv.GUIDE_SIZE[1] / 2 * mv.SHOULDER)
    flat, shoulders = np.asarray(mv.guide(key="white", pose="keep")), np.asarray(mv.guide(key="white", pose="t"))
    assert (flat[row - 2:row + 3] < 255).sum() < (shoulders[row - 2:row + 3] < 255).sum(), "the shoulder line is only in the T guide"


def test_make_sends_the_guide_first_then_the_character_and_crops_the_result():
    sent = {}
    tmp = Path(tempfile.mkdtemp())

    def fake_run_hf(model, args, refs, max_usd, out_dir):
        sent.update(model=model, args=args, refs=[Path(r).name for r in refs], max_usd=max_usd)
        job = tmp / "job"
        job.mkdir()
        sheet()[0].save(job / "image_0.png")
        (job / "job.json").write_text(json.dumps({"estimate": {"usd": "0.123"}}), encoding="utf-8")
        return job

    real, mv.run_hf = mv.run_hf, fake_run_hf
    try:
        ref = tmp / "ref.png"
        Image.new("RGB", (50, 80), (120, 40, 150)).save(ref)
        report = mv.make("t", ref=ref, out=tmp / "t", max_usd=0.2, key="white")
    finally:
        mv.run_hf = real
    assert sent["refs"] == ["guide.png", "ref.png"], sent["refs"]
    assert sent["model"] == "marketing-studio/image" and sent["args"]["aspect_ratio"] == "3:2" and sent["max_usd"] == 0.2
    assert report["cost_usd"] == 0.123 and report["problems"] == [] and len(report["views"]) == 6
    assert (tmp / "t" / "views" / "front.png").exists() and (tmp / "t" / "job_views.json").exists()


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
