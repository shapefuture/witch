#!/usr/bin/env python3
"""Writes a room's `lighting` block: how its characters are lit (docs/art/lighting_from_image.md).

    python tools/painted/relight.py assets/painted/garden --spheres lighting.json   # measured: sphere_probe.py measure --out lighting.json
    python tools/painted/relight.py assets/painted/shop_ps1 --plate                  # derived from the plate's own colours (no spheres needed)
    python tools/painted/relight.py assets/painted/garden --remove                   # back to the floor-map light

The block (room.json `lighting`): `key_dir` (toward the light, world), `key_color` (display-referred, max 1), `sky_color` (the fill on top-facing
facets), `ground_color` (the bounce under them), `fill_level` (how strong that fill is against the key), `key_level`, `shadow_tint` (the colour the
floor goes to in a character's shadow), `source` ("spheres" or "plate"). The actor shader (`lighting_mode`) uses it in place of the floor's own
purple and the single beam tint.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

LUMA = np.array([0.3, 0.55, 0.15])
GRADE_STRENGTH = 0.5      # how much of the plate's colour cast the characters take
KEY_PER_LUMA = 1.5        # key_level = this x the floor's mean luma (the garden: 0.30 -> 0.45; a dark shop: 0.22 -> 0.33), times the actors' key_strength (2.6)


def to_world(v, pitch_deg):
    """A direction in the camera's frame (x right, y up, z toward the camera) in the room's world (the camera tilted up by the pitch)."""
    p = math.radians(pitch_deg)
    x, y, z = v
    w = np.array([x, y * math.cos(p) - z * math.sin(p), y * math.sin(p) + z * math.cos(p)])
    return w / np.linalg.norm(w)


def encode(c):
    """Linear light to the display-referred colour the shaders write, normalised to a maximum of 1."""
    c = np.asarray(c, float)
    c = c / max(c.max(), 1e-9)
    return np.clip(c, 0, 1) ** (1 / 2.2)


def _shadow_tint(room, sky):
    lit = room.get("lit_range", [0.3, 0.9])
    ratio = float(np.clip(lit[0] / max(lit[1], 1e-3), 0.35, 0.8))
    cool = 0.6 * np.asarray(sky) + 0.4 * np.array([0.6, 0.7, 1.0])
    return (cool / cool.max()) * ratio


def floor_luma(plate, room):
    """The mean luma of the plate's foreground floor band (display-referred): how bright this scene is where the characters stand."""
    a = np.asarray(plate.convert("RGB").resize((1280, 720)), np.float32) / 255.0
    H, W = a.shape[:2]
    h = float(room.get("horizon", 0.62))
    return float((a[int((h + 0.25 * (1 - h)) * H): int(0.98 * H), int(0.2 * W): int(0.8 * W)] @ LUMA).mean())


def plate_grade(plate, room):
    """The plate's colour cast: the floor band's mean colour over its own luma (display-referred), each channel kept within 0.6 to 1.4."""
    a = np.asarray(plate.convert("RGB").resize((1280, 720)), np.float32) / 255.0
    H, W = a.shape[:2]
    h = float(room.get("horizon", 0.62))
    band = a[int((h + 0.15 * (1 - h)) * H): int(0.98 * H), int(0.1 * W): int(0.9 * W)].reshape(-1, 3).mean(0)
    return np.clip(band / max(float(band @ LUMA), 1e-6), 0.6, 1.4)


def _block(room, source, key_dir, key, sky, ground, fill_to_key, extra=None, grade=None, key_level=0.45):
    fill_level = float(np.clip(3.0 * fill_to_key, 0.25, 0.5))      # shadows are kept readable: the measured ratio is harsher
    r = lambda v: [round(float(x), 3) for x in v]                  # noqa: E731
    block = dict(source=source, key_dir=r(key_dir), key_color=r(key), sky_color=r(sky), ground_color=r(ground),
                 fill_level=round(fill_level, 3), key_level=round(float(key_level), 3), shadow_tint=r(_shadow_tint(room, sky)))
    if grade is not None:
        block.update(grade=r(grade), grade_strength=GRADE_STRENGTH)
    block.update(extra or {})
    return block


def from_spheres(room, measured, plate=None):
    """`measured` is sphere_probe.py's lighting.json (camera space, linear colours)."""
    key_dir = to_world(measured["key_direction_from_grey"], room.get("pitch_deg", 0.0))
    return _block(room, "spheres", key_dir, encode(measured["key_color"]), encode(measured["sky_color"]), encode(measured["ground_color"]),
                  measured["fill_to_key"], extra=dict(measured_fill_to_key=measured["fill_to_key"], key_vs_chrome_deg=measured.get("angle_between_deg")),
                  grade=None if plate is None else plate_grade(plate, room),
                  key_level=0.45 if plate is None else float(np.clip(KEY_PER_LUMA * floor_luma(plate, room), 0.2, 0.6)))


def from_plate(room, plate):
    """The plate's own colours: the sky from its upper band, the ground from the floor band, the key from the floor's brightest patches."""
    a = np.asarray(plate.convert("RGB").resize((1280, 720)), np.float32) / 255.0
    H, W = a.shape[:2]
    h = float(room.get("horizon", 0.62))
    luma = a @ LUMA
    sky_rows = a[int(0.02 * H): max(int((h - 0.06) * H), int(0.1 * H))]
    sy = sky_rows @ LUMA
    sky = sky_rows[sy <= np.quantile(sy, 0.97)].mean(0)
    band = a[int((h + 0.25 * (1 - h)) * H): int(0.98 * H), int(0.2 * W): int(0.8 * W)]
    by = band @ LUMA
    ground = band[(by >= np.quantile(by, 0.1)) & (by <= np.quantile(by, 0.9))].mean(0)
    key = band[by >= np.quantile(by, 0.94)].mean(0)
    p10, p90 = np.quantile(by, 0.1), np.quantile(by, 0.9)
    shade_ratio = float(p10 / max(p90, 1e-3))
    norm = lambda c: c / max(c.max(), 1e-9)                         # noqa: E731
    return _block(room, "plate", room["sun_dir"], norm(key), norm(sky), norm(ground), shade_ratio / max(1 - shade_ratio, 0.2),
                  grade=plate_grade(plate, room), key_level=float(np.clip(KEY_PER_LUMA * floor_luma(plate, room), 0.2, 0.6)))


def apply(room_dir, spheres=None, plate=False, remove=False):
    path = Path(room_dir) / "room.json"
    room = json.loads(path.read_text(encoding="utf-8"))
    if remove:
        room.pop("lighting", None)
    elif spheres:
        room["lighting"] = from_spheres(room, json.loads(Path(spheres).read_text(encoding="utf-8")),
                                        Image.open(Path(room_dir) / room.get("plate", "plate.png")))
    elif plate:
        room["lighting"] = from_plate(room, Image.open(Path(room_dir) / room.get("plate", "plate.png")))
    path.write_text(json.dumps(room) + "\n", encoding="utf-8")
    return room.get("lighting")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("room_dir")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--spheres", help="lighting.json from sphere_probe.py measure")
    g.add_argument("--plate", action="store_true", help="derive it from the plate's colours")
    g.add_argument("--remove", action="store_true")
    a = ap.parse_args(argv)
    print(json.dumps(apply(a.room_dir, a.spheres, a.plate, a.remove), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
