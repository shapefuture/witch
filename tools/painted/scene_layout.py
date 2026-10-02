#!/usr/bin/env python3
"""A layout guide for a generation: a white canvas with labeled coloured shapes where each important element goes.

    python tools/painted/scene_layout.py shop_layout.json out.png            # render a guide (free; look at it before paying)
    python tools/painted/scene_layout.py shop_layout.json out.png --check plate.png --check-out check.png   # shapes over a result

An image generator told "a shop with a window on the right and a counter on the left" decides the composition itself; shown a guide it
puts things where the shapes are. new_scene.py sends the guide as the first reference with a note saying how to read it, then
writes a check image (the guide's shapes drawn over the result) so a misplacement is seen at once.

Layout JSON (all coordinates are fractions of the frame, x to the right, y down, 0..1):

    {"elements": [{"label": "round window, warm light", "at": [0.74, 0.10, 0.92, 0.52], "shape": "ellipse", "layer": "mid"},
                  {"label": "staircase", "shape": "poly", "points": [[0.35,0.72],[0.45,0.72],[0.62,0.20],[0.55,0.20]], "layer": "bg"},
                  {"label": "path", "shape": "line", "points": [[0.4,0.9],[0.5,0.7]], "layer": "ground"}],
     "ground": [0.26, 0.68, 0.74, 0.98],          # the empty open floor the characters will stand on (default: the kind's floor)
     "horizon": 0.62}                              # where the ground meets the far wall (default: the kind's)

`layer`: fg (red, toward the viewer), mid (blue), bg (green, far), ground (yellow, flat on the floor). `shape`: rect (default), ellipse, poly, line.
"""
import argparse
import json
import sys
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = (1920, 1080)
# Colours are for the check image (and `colour=True`). The guide itself is GREY by default: an image generator echoes a guide's flat
# colours as objects (a first try with red, blue and yellow boxes put red, blue and yellow gems all over the floor).
LAYERS = {"fg": (255, 150, 140), "mid": (140, 185, 255), "bg": (150, 220, 150), "ground": (255, 235, 130)}
GREYS = {"fg": (170, 170, 170), "mid": (200, 200, 200), "bg": (226, 226, 226), "ground": (242, 242, 242)}
TAGS = {"fg": "FG", "mid": "MID", "bg": "BG", "ground": "GROUND"}
ORDER = ["bg", "mid", "ground", "fg"]            # drawn back to front
GROUND_LABEL = "GROUND: open empty ground"

NOTE = ("The FIRST reference image is a LAYOUT GUIDE, not a picture to copy and not a colour or style reference: a white canvas whose "
        "labeled grey boxes and shapes mark where each element of the scene goes and roughly how big it is. Each label begins with its "
        "depth: FG = foreground (nearest the viewer), MID = middle ground, BG = background. The big pale box labeled GROUND is empty open "
        "ground: leave it empty. The black dashed line is the horizon. Paint every labeled element at its shape's position and size, in "
        "the style and palette described below, and fill the rest of the picture with the scene's architecture. Do NOT draw the guide's "
        "boxes, outlines, grey shapes, dashed line or labels, do NOT print any text, and do not let the guide's greys or white colour the "
        "picture. ")


def _font(size):
    return ImageFont.load_default(size=size)


def validate(layout):
    """Raises ValueError on a malformed layout; returns it."""
    elements = layout.get("elements")
    if not isinstance(elements, list) or not elements:
        raise ValueError("layout needs a non-empty 'elements' list")
    for e in elements:
        if not e.get("label"):
            raise ValueError("every element needs a label: %r" % (e,))
        if e.get("layer", "mid") not in LAYERS:
            raise ValueError("%s: layer must be one of %s" % (e["label"], sorted(LAYERS)))
        shape = e.get("shape", "rect")
        if shape in ("rect", "ellipse"):
            box = e.get("at")
            if not box or len(box) != 4 or not (0 <= box[0] < box[2] <= 1 and 0 <= box[1] < box[3] <= 1):
                raise ValueError("%s: 'at' must be [x0, y0, x1, y1] fractions with x0<x1, y0<y1" % e["label"])
        elif shape in ("poly", "line"):
            pts = e.get("points")
            if not pts or len(pts) < 2 or not all(0 <= x <= 1 and 0 <= y <= 1 for x, y in pts):
                raise ValueError("%s: 'points' must be 2+ [x, y] fractions" % e["label"])
        else:
            raise ValueError("%s: unknown shape %r" % (e["label"], shape))
    return layout


def with_defaults(layout, spec=None):
    """Fills `ground` and `horizon` from the scene's kind when the layout does not say."""
    out = dict(layout)
    spec = spec or {}
    horizon = out.get("horizon", spec.get("horizon", 0.62))
    out["horizon"] = horizon
    if "ground" not in out:
        floor = spec.get("floor") or {"x": [0.26, 0.74], "from": 0.40, "to": 0.98}
        out["ground"] = [floor["x"][0], horizon + 0.35 * (1 - horizon), floor["x"][1], floor["to"]]
    return out


def _px(box, size):
    return [box[0] * size[0], box[1] * size[1], box[2] * size[0], box[3] * size[1]]


def _bbox(e):
    if "at" in e:
        return e["at"]
    xs, ys = [p[0] for p in e["points"]], [p[1] for p in e["points"]]
    return [min(xs), min(ys), max(xs), max(ys)]


def _fit(text, w, h, biggest=34, smallest=11):
    """The largest font size at which `text`, wrapped, fits a w x h box; returns (font, lines, size)."""
    for fs in range(biggest, smallest - 1, -1):
        font = _font(fs)
        words, lines, line = text.split(), [], ""
        for word in words:
            trial = (line + " " + word).strip()
            if font.getlength(trial) <= w - 14 or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
        if len(lines) * fs * 1.12 <= h - 8 and max(font.getlength(l) for l in lines) <= w - 10:
            return font, lines, fs
    return _font(smallest), textwrap.wrap(text, 12), smallest


def _label(draw, box_px, text, size, fill=(0, 0, 0)):
    w, h = box_px[2] - box_px[0], box_px[3] - box_px[1]
    font, lines, fs = _fit(text, w, h)
    y = box_px[1] + 5
    for line in lines:
        draw.text((box_px[0] + 7, y), line, fill=fill, font=font)
        y += fs * 1.12


def render(layout, size=SIZE, colour=False):
    """The guide image (RGB, white): grey shapes tagged FG / MID / BG by their labels (colour=True: tinted by layer)."""
    palette = LAYERS if colour else GREYS
    layout = validate(layout)
    img = Image.new("RGBA", size, (255, 255, 255, 255))
    over = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    elements = sorted(layout["elements"], key=lambda e: ORDER.index(e.get("layer", "mid")))
    ground = layout.get("ground")
    if ground:
        gp = _px(ground, size)
        d.rectangle(gp, fill=palette["ground"] + (255,), outline=(90, 90, 90, 255), width=4)
    for e in elements:
        shade = palette[e.get("layer", "mid")]
        edge = tuple(int(c * 0.45) for c in shade) + (255,)
        shape = e.get("shape", "rect")
        if shape == "rect":
            d.rectangle(_px(e["at"], size), fill=shade + (255,), outline=edge, width=4)
        elif shape == "ellipse":
            d.ellipse(_px(e["at"], size), fill=shade + (255,), outline=edge, width=4)
        elif shape == "poly":
            d.polygon([(x * size[0], y * size[1]) for x, y in e["points"]], fill=shade + (255,), outline=edge)
        else:
            d.line([(x * size[0], y * size[1]) for x, y in e["points"]], fill=edge, width=18)
    img = Image.alpha_composite(img, over).convert("RGB")
    d = ImageDraw.Draw(img)
    if ground:
        _label(d, _px(ground, size)[:2] + [_px(ground, size)[2], _px(ground, size)[1] + 80], GROUND_LABEL, size, (70, 70, 70))
    for e in elements:
        _label(d, _px(_bbox(e), size), "%s: %s" % (TAGS[e.get("layer", "mid")], e["label"]), size)
    y = layout["horizon"] * size[1]
    for x in range(0, size[0], 36):                                       # the dashed horizon
        d.line([(x, y), (x + 20, y)], fill=(0, 0, 0), width=3)
    d.text((10, y - 26), "HORIZON", fill=(0, 0, 0), font=_font(22))
    return img


def check_image(layout, plate, size=(1280, 720)):
    """The guide's outlines and labels drawn over the result, beside the result, to see what landed where."""
    layout = with_defaults(validate(layout))
    base = plate.convert("RGB").resize(size)
    d = ImageDraw.Draw(base)
    font = _font(18)
    for e in layout["elements"]:
        colour = LAYERS[e.get("layer", "mid")]
        shape = e.get("shape", "rect")
        if shape in ("poly", "line"):
            d.line([(x * size[0], y * size[1]) for x, y in e["points"]] + ([(e["points"][0][0] * size[0], e["points"][0][1] * size[1])] if shape == "poly" else []),
                   fill=colour, width=3)
        elif shape == "ellipse":
            d.ellipse(_px(e["at"], size), outline=colour, width=3)
        else:
            d.rectangle(_px(e["at"], size), outline=colour, width=3)
        b = _px(_bbox(e), size)
        d.text((b[0] + 4, b[1] + 2), e["label"][:34], fill=colour, font=font, stroke_width=2, stroke_fill=(0, 0, 0))
    d.rectangle(_px(layout["ground"], size), outline=LAYERS["ground"], width=3)
    y = layout["horizon"] * size[1]
    for x in range(0, size[0], 30):
        d.line([(x, y), (x + 14, y)], fill=(255, 255, 255), width=2)
    return base


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("layout", help="layout JSON")
    ap.add_argument("out", help="the guide PNG to write")
    ap.add_argument("--check", help="a generated plate to draw the shapes over")
    ap.add_argument("--check-out", default="layout_check.png")
    args = ap.parse_args(argv)
    layout = with_defaults(json.loads(Path(args.layout).read_text(encoding="utf-8")))
    render(layout).save(args.out)
    print("guide: %s" % args.out)
    if args.check:
        check_image(layout, Image.open(args.check)).save(args.check_out)
        print("check: %s" % args.check_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
