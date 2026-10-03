#!/usr/bin/env python3
"""Offline checks for new_scene.py (no network, no depth model): python3 tools/painted/test_new_scene.py"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_painted as bp  # noqa: E402
import new_scene as nr  # noqa: E402
import scene_layout as sl  # noqa: E402
import layout_score as ls  # noqa: E402
import compare_models as cm  # noqa: E402
import sphere_probe as sp  # noqa: E402
import relight as rl  # noqa: E402


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
        for kind in nr.load_kinds().values():
            x0, y0, x1, y1 = nr.floor_box_for(h, kind["floor"])
            assert y0 > h * bp.H and y1 <= bp.H and 0 <= x0 < x1 <= bp.W and y1 > y0


def test_every_brief_names_a_kind_and_the_kinds_are_complete():
    kinds = nr.load_kinds()
    needed = {"composition", "horizon", "floor", "actors", "sun", "beam", "life"}
    for name, kind in kinds.items():
        assert needed <= set(kind), (name, needed - set(kind))
        assert 0.4 < kind["horizon"] < 0.8
        assert kind["sun"]["mode"] in ("source", "fixed") and (kind["sun"]["mode"] == "source" or len(kind["sun"]["dir"]) == 3)
    briefs = nr.list_briefs()
    assert len(briefs) >= 6
    for b in briefs:
        assert b["kind"] in kinds and b["prompt"] and b["title"], b["id"]
        assert b["id"] == nr.load_brief(b["id"])["id"]
        for v, change in b.get("variants", {}).items():
            assert change and v.isidentifier(), (b["id"], v)


def test_scene_files_are_english_only():
    # player text lives in data/text/ru.json and nowhere else (tests/mirror/test_text_single_source.gd)
    for path in nr.SCENES.glob("*.json"):
        assert not any("\u0400" <= ch <= "\u04ff" for ch in path.read_text(encoding="utf-8")), path.name


def test_prompts_carry_the_hard_constraints():
    for b in nr.list_briefs():
        spec = nr.resolve(b["kind"], b)
        text = nr.compose_prompt(spec, b["prompt"])
        for must in ("NO black outline", "16:9", "No people", "no text"):
            assert must in text, (b["id"], must)
        assert "%d percent" % round(spec["horizon"] * 100) in text
        for v, change in b.get("variants", {}).items():
            vt = nr.compose_variant_prompt(change)
            assert "exactly the same camera" in vt and "no black outline" in vt


def test_the_ps1_master_prompt_fills_for_every_brief_and_keeps_its_laws():
    styles = nr.load_styles()
    assert {"hall", "ps1"} <= set(styles) and styles["ps1"]["refs"] == ["tools/painted/scenes/anchors/ps1.jpg"] and styles["ps1"]["frame"] == {"strength": 0.0}
    for b in nr.list_briefs():
        spec = nr.resolve(b["kind"], b)
        text = nr.compose_prompt(spec, b["prompt"], "ps1", b)
        assert "{" not in text and "}" not in text, b["id"]                  # every field of the template was filled
        for must in ("Catastrophically crude early-3D", "NOT papercraft", "no vignette", "no witch, no raccoon", "NO 2D",
                     "%d percent" % round(spec["horizon"] * 100), "Palette: jewel-toned"):
            assert must in text, (b["id"], must)
    shop = nr.load_brief("shop")
    assert "Bigger Inside" in nr.compose_prompt(nr.resolve("interior", shop), shop["prompt"], "ps1", shop)


LAYOUT = {"horizon": 0.6, "ground": [0.3, 0.7, 0.7, 0.98], "elements": [
    {"label": "WINDOW: warm", "at": [0.7, 0.1, 0.9, 0.5], "shape": "ellipse", "layer": "mid"},
    {"label": "COUNTER", "at": [0.05, 0.5, 0.4, 0.8], "layer": "fg"},
    {"label": "STAIRS", "shape": "poly", "points": [[0.4, 0.6], [0.5, 0.6], [0.6, 0.2], [0.5, 0.2]], "layer": "bg"}]}


def test_layout_validates_and_renders_a_grey_guide():
    sl.validate(LAYOUT)
    img = sl.render(LAYOUT, (480, 270))
    assert img.size == (480, 270) and img.getpixel((2, 2)) == (255, 255, 255)
    px = img.getpixel((int(0.8 * 480), int(0.3 * 270)))                       # inside the window: a grey, never a colour
    assert px[0] == px[1] == px[2] and px[0] < 255, px
    for bad in ({"elements": []}, {"elements": [{"label": "x", "at": [0.5, 0.5, 0.4, 0.6]}]},
                {"elements": [{"label": "x", "at": [0, 0, 1, 1], "layer": "sky"}]}, {"elements": [{"label": "", "at": [0, 0, 1, 1]}]}):
        try:
            sl.validate(bad)
        except ValueError:
            continue
        raise AssertionError("accepted %r" % (bad,))


def test_layout_words_and_scoring():
    assert ls.where(LAYOUT["elements"][0]) == "far right, upper, medium"
    perfect = {"elements": {"WINDOW": {"present": True, "box": [0.7, 0.1, 0.9, 0.5]}, "COUNTER": {"present": True, "box": [0.05, 0.5, 0.4, 0.8]},
                            "STAIRS": {"present": True, "box": [0.4, 0.2, 0.6, 0.6]}}}
    s = ls.score_picture(LAYOUT, perfect)
    assert s["placement"] == 1.0 and s["presence"] == 1.0 and s["mean_iou"] > 0.99
    off = {"elements": {"WINDOW": {"present": True, "box": [0.1, 0.1, 0.3, 0.5]}, "COUNTER": {"present": False, "box": None}}}
    s = ls.score_picture(LAYOUT, off)
    assert s["placement"] == 0.0 and abs(s["presence"] - 1 / 3) < 1e-9
    rows = ls.score_all(LAYOUT, [{"pic_01.png": perfect}], {"pic_01.png": "run_a"}, {"run_a": {"usd": 0.1}})
    assert rows[0]["run"] == "run_a" and rows[0]["placement"] == 1.0 and "run_a" in ls.table(rows)


def test_benchmark_prompts_fit_each_model_and_carry_no_anchor():
    brief, spec, layout = cm.load()
    for run in cm.RUNS:
        text = cm.prompt_for(run, brief, layout)
        assert len(text) <= cm.LIMITS.get(run["model"], 5000), (run["id"], len(text))
        assert ("LAYOUT GUIDE" in text) == (run["channel"] == "guide"), run["id"]
        assert ("Placement of each element" in text) == (run["channel"] == "words"), run["id"]
        assert "no text" in text.lower() and "No people" in text or run["channel"] == "words-short", run["id"]
        assert "second reference" not in text, run["id"]                       # no style anchor: the model's own reading of the style
    full = cm.prompt_for([r for r in cm.RUNS if r["id"] == "grok_words"][0], brief, layout)
    assert cm.master_style() in full                                            # the master prompt's style block, verbatim


def test_the_positive_master_prompt_forbids_nothing():
    import re
    forbidding = r"\b(no|not|never|without|avoid|don't|do not|none|nothing|nobody|cannot)\b"
    for b in nr.list_briefs():
        if "ps1p" not in (b.get("styles") or {}):
            continue
        spec = nr.resolve(b["kind"], b)
        text = nr.compose_prompt(spec, b["prompt"], "ps1p", b)
        assert "{" not in text and not re.findall(forbidding, text, flags=re.I), (b["id"], re.findall(forbidding, text, flags=re.I))
    brief, spec, layout = cm.load()
    for note in (cm.GUIDE_NOTE_POS, cm.STYLE_REF_NOTE_POS, sl.GROUND_LABEL):
        assert not re.findall(forbidding, note, flags=re.I), note


def test_the_default_recipe_is_the_one_that_won():
    assert nr.DEFAULT_MODEL == "marketing" and nr.DEFAULT_STYLE == "ps1p" and nr.GEN == "marketing"
    assert nr.MODELS["marketing"]["edit"] == "marketing-studio/image"
    assert nr.load_styles()[nr.DEFAULT_STYLE]["refs"] == []                 # no style-reference picture: references leak their objects


def _synthetic_spheres(sun, sky=(0.20, 0.28, 0.50), sun_rgb=(1.0, 0.8, 0.5), albedo=0.5):
    """A grey ball and a chrome ball (camera space) in an environment of one sun and a flat sky, as sRGB images."""
    size = 400
    img = np.zeros((size, size, 3))
    yy, xx = np.mgrid[0:size, 0:size]
    for (cx, kind) in ((100, "grey"), (300, "chrome")):
        nx, ny = (xx - cx) / 90.0, -(yy - 200) / 90.0
        rr = nx ** 2 + ny ** 2
        m = rr < 1
        nz = np.sqrt(np.clip(1 - rr, 0, 1))
        N = np.stack([nx, ny, nz], -1)
        if kind == "grey":
            lam = np.maximum(0, N @ sun)
            col = albedo * (np.array(sky) + np.array(sun_rgb)[None, None, :] * 1.2 * lam[..., None])
        else:
            R = np.stack([2 * nz * nx, 2 * nz * ny, 2 * nz * nz - 1], -1)
            hit = (R @ sun) > np.cos(np.radians(12))
            col = 0.85 * (np.array(sky)[None, None, :] + np.array(sun_rgb)[None, None, :] * 1.2 * hit[..., None])
        img[m] = col[m]
    lin = np.clip(img, 0, 1)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    return Image.fromarray((srgb * 255).astype(np.uint8))


def test_sphere_probe_recovers_a_known_light():
    sun = np.array([0.55, 0.6, -0.1]); sun /= np.linalg.norm(sun)
    res = sp.measure(_synthetic_spheres(sun), (100, 200, 90), (300, 200, 90))
    assert res["angle_between_deg"] < 12, res                                      # the grey ball's key direction and the chrome ball's sun agree
    got = np.array(res["sun_direction_from_chrome"])
    assert np.degrees(np.arccos(np.clip(got @ sun, -1, 1))) < 12, res
    assert res["grey_vs_chrome_correlation"] > 0.9 and res["grey_fit_r2"] > 0.9, res
    assert res["sun_color"][0] >= res["sun_color"][2] and res["sky_color"][2] >= res["sky_color"][0], res   # warm sun, cool sky


def test_the_sphere_cross_check_stays_small_for_big_balls():
    import resource
    rng = np.random.default_rng(3)
    lin = rng.random((400, 900, 3))
    c = sp.cross_check(lin, (150, 200, 140), (700, 200, 140))          # 60k pixels against 60k pixels would be about 30 GB unsampled
    assert np.isfinite(c)
    assert resource.getrusage(resource.RUSAGE_SELF).ru_maxrss < 2_000_000, "the cross-check allocated a pixel-by-pixel matrix"   # KB


def test_relight_world_conversion_and_blocks():
    assert np.allclose(rl.to_world((0.3, 0.5, 0.2), 0.0), np.array([0.3, 0.5, 0.2]) / np.linalg.norm([0.3, 0.5, 0.2]))
    up = rl.to_world((0.0, 1.0, 0.0), 90.0)                       # a camera looking straight up: its "up" is the world's toward-the-camera axis
    assert np.allclose(up, [0, 0, 1], atol=1e-9)
    room = {"pitch_deg": 6.0, "lit_range": [0.3, 0.6], "horizon": 0.6, "sun_dir": [0.3, 0.8, -0.5]}
    measured = {"key_direction_from_grey": [0.76, 0.65, 0.02], "key_color": [1, 0.66, 0.42], "sky_color": [0.89, 0.86, 1.0],
                "ground_color": [1.0, 0.59, 0.22], "fill_to_key": 0.1, "angle_between_deg": 12.0}
    b = rl.from_spheres(room, measured)
    assert abs(np.linalg.norm(b["key_dir"]) - 1) < 1e-2 and b["source"] == "spheres"
    assert b["key_color"][0] == 1.0 and b["key_color"][2] < b["key_color"][0] and b["sky_color"][2] == 1.0
    assert 0.25 <= b["fill_level"] <= 0.5 and len(b["shadow_tint"]) == 3 and max(b["shadow_tint"]) <= 0.8


def test_relight_from_the_plate_finds_a_cool_sky_and_a_warm_ground():
    a = np.zeros((720, 1280, 3), np.uint8)
    a[:300] = (110, 140, 210)                                      # blue sky
    a[300:] = (150, 110, 60)                                       # warm ground
    a[560:600, 400:700] = (240, 190, 110)                          # a sunlit patch on it
    from PIL import Image as _I
    b = rl.from_plate({"horizon": 0.45, "sun_dir": [0.3, 0.8, -0.5], "lit_range": [0.3, 0.6]}, _I.fromarray(a))
    assert b["sky_color"][2] > b["sky_color"][0] and b["ground_color"][0] > b["ground_color"][2] and b["key_color"][0] > b["key_color"][2]
    assert b["source"] == "plate" and b["key_dir"] == [0.3, 0.8, -0.5]


def test_resolve_overrides_in_order_kind_brief_explicit():
    spec = nr.resolve("street", {"palette": "night", "sun": {"mode": "fixed", "dir": [0, 1, 0]}}, horizon=0.55)
    assert spec["palette"] == "night" and spec["sun"]["dir"] == [0, 1, 0] and spec["horizon"] == 0.55
    assert nr.resolve("street")["horizon"] == nr.load_kinds()["street"]["horizon"]


def test_a_sky_too_large_to_be_a_lamp_is_ignored():
    a = np.full((bp.H, bp.W, 3), 30, np.uint8)
    a[:200] = (230, 220, 200)                                              # the whole upper band is bright sky
    yy, xx = np.mgrid[0:bp.H, 0:bp.W]
    a[(xx - 600) ** 2 + (yy - 330) ** 2 < 7 ** 2] = (255, 200, 110)       # a lantern below it
    lights = nr.find_lights(Image.fromarray(a), 0.6, nr.load_kinds()["street"]["life"])
    assert [l["pixel"][0] // 100 for l in lights] == [6], lights


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
