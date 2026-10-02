#!/usr/bin/env python3
"""Scores how well a picture follows a layout (scene_layout.py), from blind critics' reports. Pure functions, tested offline.

A critic is shown a picture and the NAMES of the elements (never the layout, never the model) and returns, per picture:
    {"pic_01.png": {"elements": {"BOOKSHELF leaning over": {"present": true, "box": [x0, y0, x1, y1]}, ...},
                    "ground_objects": 0,        # how many objects stand in the ground area given to them (0 = empty)
                    "guide_leak": false,        # grey boxes, labels or a dashed line from a guide are visible in the picture
                    "text": false, "people": false,
                    "crude_3d": 7, "jewel_palette": 8, "cute_modern": 3}}    # 0..10; cute_modern: lower is better
"""
import json
import math
from statistics import mean

ORDER = [("left", 0.22), ("left", 0.40), ("centre", 0.60), ("right", 0.78), ("right", 1.01)]
HX = ["far left", "left", "centre", "right", "far right"]
VY = [(0.25, "top"), (0.45, "upper"), (0.65, "middle"), (0.85, "lower"), (1.01, "bottom")]


def bbox(e):
    if "at" in e:
        return list(e["at"])
    xs, ys = [p[0] for p in e["points"]], [p[1] for p in e["points"]]
    return [min(xs), min(ys), max(xs), max(ys)]


def area(e):
    b = bbox(e)
    return (b[2] - b[0]) * (b[3] - b[1])


def centre(b):
    return ((b[0] + b[2]) / 2.0, (b[1] + b[3]) / 2.0)


def where(e):
    """'right, upper, large': an element's place in words."""
    cx, cy = centre(bbox(e))
    h = HX[next(i for i, t in enumerate([0.2, 0.4, 0.6, 0.8, 1.01]) if cx < t)]
    v = next(w for t, w in VY if cy < t)
    a = area(e)
    size = "large" if a > 0.10 else "medium" if a > 0.035 else "small"
    return "%s, %s, %s" % (h, v, size)


def describe(layout):
    return "; ".join("%s: %s" % (e["label"].split(":")[0], where(e)) for e in layout["elements"]) + "."


def iou(a, b):
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def element_score(want, found):
    """0..1 for one element: present, and its centre close to the layout's (full marks within 0.06 of the frame, none past 0.30)."""
    if not found or not found.get("present") or not found.get("box"):
        return dict(found=False, score=0.0, dist=None, iou=0.0)
    d = math.dist(centre(want), centre(found["box"]))
    return dict(found=True, score=max(0.0, min(1.0, (0.30 - d) / 0.24)), dist=d, iou=iou(want, found["box"]))


def score_picture(layout, report):
    per = {}
    for e in layout["elements"]:
        name = e["label"].split(":")[0] if ":" in e["label"] else e["label"]
        per[name] = element_score(bbox(e), (report.get("elements") or {}).get(name))
    found = [v for v in per.values() if v["found"]]
    return dict(
        placement=mean(v["score"] for v in per.values()),                 # 0..1 over every element (a missing one scores 0)
        presence=len(found) / len(per),
        mean_dist=mean(v["dist"] for v in found) if found else None,
        mean_iou=mean(v["iou"] for v in found) if found else 0.0,
        per_element=per)


def score_all(layout, critics, key, results):
    """Averages the critics per picture; `key` maps a blind name to a run id."""
    rows = []
    for pic, run_id in sorted(key.items(), key=lambda kv: kv[1]):
        reports = [c[pic] for c in critics if pic in c]
        if not reports:
            continue
        s = [score_picture(layout, r) for r in reports]
        avg = lambda f: mean(f(x) for x in s)                                      # noqa: E731
        rows.append(dict(
            run=run_id, usd=results[run_id].get("usd"),
            placement=round(avg(lambda x: x["placement"]), 3), presence=round(avg(lambda x: x["presence"]), 3),
            mean_iou=round(avg(lambda x: x["mean_iou"]), 3),
            ground_objects=round(mean(r.get("ground_objects", 0) for r in reports), 1),
            guide_leak=sum(bool(r.get("guide_leak")) for r in reports), text=sum(bool(r.get("text")) for r in reports),
            people=sum(bool(r.get("people")) for r in reports), critics=len(reports),
            crude_3d=round(mean(r.get("crude_3d", 0) for r in reports), 1), jewel=round(mean(r.get("jewel_palette", 0) for r in reports), 1),
            cute_modern=round(mean(r.get("cute_modern", 0) for r in reports), 1)))
    return sorted(rows, key=lambda r: -r["placement"])


def table(rows):
    head = "%-16s %6s %9s %8s %7s %6s %5s %6s %5s %6s %9s" % (
        "run", "USD", "placement", "presence", "iou", "ground", "leak", "text", "crude", "jewel", "cute(lo=ok)")
    lines = [head, "-" * len(head)]
    for r in rows:
        lines.append("%-16s %6s %9.2f %8.2f %7.2f %6.1f %5d %6d %5.1f %6.1f %9.1f" % (
            r["run"], "%.3f" % r["usd"] if r["usd"] is not None else "?", r["placement"], r["presence"], r["mean_iou"], r["ground_objects"],
            r["guide_leak"], r["text"], r["crude_3d"], r["jewel"], r["cute_modern"]))
    return "\n".join(lines)


def critic_instructions(names, ground, pics):
    return """# Locating elements in generated pictures (blind)

For each picture below you will say where named things appear and answer a short checklist. You are not told anything about how or why the
pictures were made. Judge only what you see. Open each picture with the Read tool (they are 1280x720).

Pictures: %s

Elements to locate in EVERY picture: %s

For each element give `present` (true if you can see it, even small) and `box`: its bounding box [x0, y0, x1, y1] as fractions of the
picture's width and height (0 = left/top edge, 1 = right/bottom edge). If something appears twice, box the most prominent one. If it is
absent, `present` is false and `box` null.

Checklist per picture:
- `ground_objects`: how many separate objects (rocks, gems, props, animals) stand in the floor area x %.2f to %.2f, y %.2f to %.2f of the picture (0 = empty floor).
- `guide_leak`: true if flat grey boxes or shapes, a dashed horizontal line, or label-like blocks that are not part of a scene are visible.
- `text`: true if any readable letters or words are in the picture.
- `people`: true if any human figure is in the picture.
- `crude_3d` 0-10: how much it looks like crude early-1997 low-polygon 3D (blunt wedges, cubes, slabs, visible facets, dry matte painted textures) rather than polished modern art.
- `jewel_palette` 0-10: how much the colours are rich jewel tones (cobalt/plum/indigo shadows, teal walls, amber light) rather than muddy, grey or pastel.
- `cute_modern` 0-10: how much it looks like cute polished modern 3D / toy-like renders (10 = very much; lower is better here).

Write ONE JSON file (path given by the person who asked you) shaped like:
{"pic_01.png": {"elements": {"%s": {"present": true, "box": [0.1, 0.2, 0.3, 0.4]}, ...}, "ground_objects": 0, "guide_leak": false,
 "text": false, "people": false, "crude_3d": 6, "jewel_palette": 7, "cute_modern": 3}, "pic_02.png": {...}}
Use exactly the element names above. Estimate boxes carefully: this is a measurement.
""" % (", ".join(pics), "; ".join('"%s"' % n for n in names), ground[0], ground[2], ground[1], ground[3], names[0])
