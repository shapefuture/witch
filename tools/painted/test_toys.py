#!/usr/bin/env python3
"""Offline checks for toys.py and the sphere finder (no network, no depth model): python3 tools/painted/test_toys.py"""
import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scene_layout as sl  # noqa: E402
import sphere_probe as sp  # noqa: E402
import toys  # noqa: E402

HERE = Path(__file__).resolve().parent


def _texture(seed, size=(720, 1280)):
    """A saturated, mottled picture: the kind of ground a generated plate has (nothing like a flat grey)."""
    rng = np.random.default_rng(seed)
    a = np.stack([ndimage.gaussian_filter(rng.random(size), 6.0) for _ in range(3)], -1)
    a = (a - a.min()) / (a.max() - a.min())
    return (60 + 170 * a * np.array([1.0, 0.8, 0.35])).astype(np.uint8)


def _garden_layout():
    brief = json.loads((HERE / "scenes" / "garden.json").read_text(encoding="utf-8"))
    return sl.with_defaults(brief["layout"], {"horizon": 0.6})


def test_the_gardens_marks_become_toys_with_the_right_kinds():
    t = {x["id"]: x for x in toys.toys_of(_garden_layout())}
    assert set(t) == {"tree", "bell", "window", "lantern", "bench", "sundial", "wheelbarrow", "watering_can"}, sorted(t)
    assert [i for i, x in t.items() if x["kind"] == "cutout"] == ["bell", "lantern", "sundial", "wheelbarrow", "watering_can"]
    assert all(x["kind"] == "hotspot" for i, x in t.items() if i in ("tree", "window", "bench"))


def test_every_toy_type_uses_the_engines_words_and_sounds():
    words, sounds = toys.vocabulary(), {p.stem for p in toys.SFX_DIR.glob("*.wav")}
    for name, spec in toys.load_types().items():
        assert spec["kind"] in ("cutout", "hotspot"), name
        assert len(spec["press"]) >= 2, "%s: a poke answers differently the second time" % name
        for r in spec["press"]:
            assert r["do"] in words and r["sound"] in sounds, (name, r)
        if spec["kind"] == "cutout":
            assert spec.get("noun") and spec.get("pivot") in ("base", "top", "centre"), name


def test_the_edit_prompt_names_the_cutouts_and_the_spheres_and_forbids_nothing():
    layout = _garden_layout()
    t = toys.toys_of(layout)
    prompt = toys.edit_prompt(t, layout, spheres=True)
    for noun in ("wheelbarrow", "watering can", "sundial", "hanging lantern", "small bell"):
        assert noun in prompt, noun
    for hotspot_only in ("pear", "bench", "window"):
        assert hotspot_only not in prompt.lower(), "a hotspot is not taken away: %s" % hotspot_only
    assert "mirror-polished chrome sphere" in prompt and "matte mid-grey sphere" in prompt
    low = " " + prompt.lower().replace(",", " ").replace(".", " ") + " "
    for negative in (" no ", " not ", " never ", " without ", " don't ", " avoid "):
        assert negative not in low, "a prompt that forbids things may make the model draw them: %r" % negative
    only_objects = toys.edit_prompt(t, layout, spheres=False)
    assert "sphere" not in only_objects and "taken away" in only_objects
    try:
        toys.edit_prompt([], layout, spheres=False)
        raise AssertionError("an edit with nothing to do must be refused")
    except ValueError:
        pass


def test_a_wrong_toy_type_is_refused():
    layout = {"elements": [{"label": "X", "at": [0.1, 0.1, 0.2, 0.2], "toy": "no_such_thing"}]}
    try:
        toys.toys_of(layout)
        raise AssertionError("expected ValueError")
    except ValueError as e:
        assert "no_such_thing" in str(e)


def test_registration_sees_a_shift_and_a_stretch_and_passes_an_exact_edit():
    plate = Image.fromarray(_texture(1))
    assert (toys.registration(plate, plate) or 0.0) <= 0.5
    shifted = Image.fromarray(np.roll(np.asarray(plate), 9, axis=1))
    assert toys.registration(shifted, plate) >= 6.0
    stretched = plate.resize((1296, 720)).crop((0, 0, 1280, 720))        # 1.25 % wider: drifts toward the right edge, as Qwen's did
    assert toys.registration(stretched, plate) > toys.MAX_SHIFT


def _synthetic_edit(circles=True):
    """A plate; an edit that took a barrel and a lamp away (their places redrawn), redrew a big area elsewhere, and added the two balls."""
    plate_a = _texture(2)
    edit_a = plate_a.copy()
    plate_a[500:600, 100:260] = (150, 60, 40)                       # a barrel standing on the ground
    plate_a[100:180, 600:640] = (240, 220, 90)                      # a lamp
    plate_a[300:380, 900:980] = (30, 120, 200)                      # a crate the edit leaves alone
    edit_a[300:380, 900:980] = (30, 120, 200)                       # (the edit keeps it)
    edit_a[500:600, 100:260] = _texture(3)[500:600, 100:260]
    edit_a[100:180, 600:640] = _texture(4)[100:180, 600:640]
    edit_a[40:140, 1000:1260] = _texture(5)[40:140, 1000:1260]       # the edit redrew a stretch of the scene nobody asked about
    yy, xx = np.mgrid[0:720, 0:1280]
    grey = (xx - 480) ** 2 + (yy - 560) ** 2 < 70 ** 2
    shade = 200 - 90 * np.clip(((xx - 450) + (yy - 520)) / 140.0, 0, 1)
    edit_a[grey] = np.stack([shade, shade, shade], -1)[grey].astype(np.uint8)
    chrome = (xx - 700) ** 2 + (yy - 560) ** 2 < 70 ** 2
    rr = np.sqrt((xx - 700) ** 2 + (yy - 560) ** 2)
    pattern = (128 + 120 * np.sin(rr / 4.0 + 0.04 * (xx - 700))).clip(0, 255)
    edit_a[chrome] = np.stack([pattern, pattern * 0.95, pattern], -1)[chrome].astype(np.uint8)
    return Image.fromarray(plate_a), Image.fromarray(edit_a)


def test_the_sphere_finder_ignores_what_else_the_edit_changed():
    plate, edit = _synthetic_edit()
    grey, chrome = sp.find_spheres(edit, plate, zone=(0.2, 0.5, 0.8, 1.0))
    assert abs(grey[0] - 480) <= 6 and abs(grey[1] - 560) <= 6 and abs(grey[2] - 70) <= 8, grey
    assert abs(chrome[0] - 700) <= 14 and abs(chrome[1] - 560) <= 14 and abs(chrome[2] - 70) <= 10, chrome


def _room(tmp, plate):
    room = Path(tmp) / "room"
    room.mkdir()
    plate.save(room / "plate.png")
    return room


def test_lift_makes_cutouts_of_what_was_taken_away_and_hotspots_of_the_rest():
    plate, edit = _synthetic_edit()
    layout = {"ground": [0.3, 0.7, 0.7, 0.98], "horizon": 0.5, "elements": [
        {"label": "BARREL", "at": [0.06, 0.66, 0.24, 0.88], "toy": "crate"},
        {"label": "LAMP", "at": [0.455, 0.12, 0.505, 0.27], "toy": "lantern"},
        {"label": "CRATE the edit left alone", "at": [0.69, 0.40, 0.78, 0.55], "toy": "crate"},
        {"label": "BENCH", "at": [0.80, 0.55, 0.95, 0.70], "toy": "bench"}]}
    with tempfile.TemporaryDirectory() as tmp:
        room = _room(tmp, plate)
        edit_path = Path(tmp) / "edit.png"
        edit.save(edit_path)
        report = {r["id"]: r for r in toys.lift(room, edit_path, toys.toys_of(layout), circles=[(480, 560, 70), (700, 560, 70)], scratch=Path(tmp) / "s")}
        assert report["crate"]["kind"] == "cutout" and report["lantern"]["kind"] == "cutout", report
        assert report["crate_2"]["kind"] == "hotspot" and "did not take it away" in report["crate_2"]["why"], report
        assert report["bench"]["kind"] == "hotspot", report
        props = {p["id"]: p for p in json.loads((room / "props.json").read_text(encoding="utf-8"))["props"]}
        x, y, w, h = props["crate"]["rect"]
        assert x <= 100 and x + w >= 260 and y <= 500 and y + h >= 600, props["crate"]["rect"]       # the barrel's place is inside its card
        assert w < 260 and h < 160, "the card is the barrel, not the area the edit redrew nearby"
        for p in props.values():
            if p["kind"] == "cutout":
                assert p["rect"][0] % 8 == 0 and p["rect"][2] % 8 == 0 and "pivot" in p
        assert toys.check(room) == [], toys.check(room)
        # the balls were not read as objects, and the stretch the edit redrew elsewhere is in no card
        for p in props.values():
            if p["kind"] == "cutout":
                rx, ry, rw, rh = p["rect"]
                assert not (rx < 700 + 70 and rx + rw > 480 - 70 and ry < 560 + 70 and ry + rh > 560 - 70), p["id"]


def test_lift_refuses_to_cut_from_an_edit_that_drifted():
    plate, edit = _synthetic_edit()
    drifted = edit.resize((1296, 720)).crop((0, 0, 1280, 720))
    layout = {"elements": [{"label": "BARREL", "at": [0.06, 0.66, 0.24, 0.88], "toy": "crate"}]}
    with tempfile.TemporaryDirectory() as tmp:
        room = _room(tmp, plate)
        edit_path = Path(tmp) / "edit.png"
        drifted.save(edit_path)
        report = toys.lift(room, edit_path, toys.toys_of(layout), scratch=Path(tmp) / "s")
        assert report[0]["kind"] == "hotspot" and "registered" in report[0]["why"], report


def test_check_catches_a_plate_empty_that_differs_outside_the_masks():
    plate, edit = _synthetic_edit()
    layout = {"elements": [{"label": "LAMP", "at": [0.455, 0.12, 0.505, 0.27], "toy": "lantern"}]}
    with tempfile.TemporaryDirectory() as tmp:
        room = _room(tmp, plate)
        edit_path = Path(tmp) / "edit.png"
        edit.save(edit_path)
        toys.lift(room, edit_path, toys.toys_of(layout), scratch=Path(tmp) / "s")
        assert toys.check(room) == []
        empty = np.asarray(Image.open(room / "plate_empty.png").convert("RGB")).copy()
        empty[10:20, 10:20] = 0
        Image.fromarray(empty).save(room / "plate_empty.png")
        assert any("plate_empty differs" in p for p in toys.check(room)), toys.check(room)


def test_the_whole_step_from_a_given_edit_lifts_and_measures_without_paying():
    plate, edit = _synthetic_edit()
    layout = {"ground": [0.3, 0.7, 0.7, 0.98], "horizon": 0.5, "elements": [
        {"label": "BARREL", "at": [0.06, 0.66, 0.24, 0.88], "toy": "crate"},
        {"label": "LAMP", "at": [0.455, 0.12, 0.505, 0.27], "toy": "lantern"}]}
    with tempfile.TemporaryDirectory() as tmp:
        room = _room(tmp, plate)
        edit_path = Path(tmp) / "edit.png"
        edit.save(edit_path)
        out = toys.run(room, Path(tmp) / "s", layout, spheres=True, edit=edit_path)
        assert out["cost"] == 0.0 and len(out["circles"]) == 2 and out["measured"] is not None, out
        assert {t["id"]: t["kind"] for t in out["toys"]} == {"crate": "cutout", "lantern": "cutout"}, out["toys"]
        assert out["problems"] == [], out["problems"]
        assert (Path(tmp) / "s" / "toys_preview.png").exists()
    assert toys.run(Path("."), Path("."), {"elements": [{"label": "X", "at": [0.1, 0.1, 0.2, 0.2]}]}, spheres=False) is None, "no toys and no spheres: nothing to do"


def test_the_gardens_toy_box_is_sound():
    assert toys.check(HERE.parents[1] / "assets/painted/garden") == []


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
