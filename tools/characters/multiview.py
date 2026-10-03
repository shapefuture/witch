#!/usr/bin/env python3
"""One picture (or a few words) of a character to six views of her for image-to-3D tools: one generation, one sheet, six crops.

    python tools/characters/multiview.py guide [OUT.png]                       # draw the white guide (free: look at it first)
    python tools/characters/multiview.py make witch --ref front.png            # ONE paid generation, then the crop
    python tools/characters/multiview.py make fox --text "a fox in a red coat, faceted low-poly"   # from words only
    python tools/characters/multiview.py make witch --ref front.png --key white   # on white instead of chroma-key green (see 3.)
    python tools/characters/multiview.py make witch --ref front.png --pose t --no-legs   # in a T-pose, skirt to the ground, no legs to rig
    python tools/characters/multiview.py crop SHEET.png --out DIR              # only the crop: a sheet made elsewhere, or by hand

1. **Guide**: a canvas (the key colour, see 3.) of three columns by two rows, one framed cell per view with its label, a dashed head line, a dashed foot line,
   a centre line and a symbol for the way she faces. It goes to the generator as the FIRST reference (the character's picture is the second)
   with a note saying how to read it, exactly as scene_layout.py does for rooms: the model puts one figure in each cell, upright, at one
   scale, feet on the line. The cells are square (3:2 canvas) so a grid crop would already work; the crop below does not rely on it.
2. **Generate**: `hf.py run` (marketing-studio, grok or qwen), the prompt composed here, capped by --max-usd. Without --ref the text model is used.
3. **Crop**: the background colour is read off the sheet's border, a figure is whatever differs from it; thin things (frame lines, label
   strokes) are dropped, nearby parts (a wand, hair curls) are merged, and each group goes to the cell its centre is in. Every view is then
   cut out, scaled to the SAME HEIGHT, centred and written square. On WHITE (`--key white`) a pale pixel inside the figure (a pendant, a bird's breast) and a
   hole of background (between arm and body, inside a hair curl) look alike, so holes are told apart by size and by how exactly they are the
   background. On a KEY colour (`--key green`, the default: the guide, the prompt and the matte follow it) every pixel that is the key is a hole, wherever it
   is, the edge is despilled, and nothing needs guessing. Use white only for a character that has green in it. Outputs: `views/NAME.png` (transparent) and `white/NAME.png` (on pure white), `contact.png`, `sheet_boxes.png`, `views.json`.
   Problems are printed, never hidden: a cell with nothing in it, a figure cut by its cell or the sheet's edge, a figure that spills into the
   next cell, two figures in one cell, a view drawn much bigger or smaller than the rest, a background that is not white.

**Pose** (`--pose keep|t|a`): `keep` is the pose of the reference. `t` / `a` ask for a rigging pose (arms straight out / angled down about 40 degrees,
hands open and empty, head forward, legs straight; what she held is left out, so a wand or a bird becomes a separate piece), and the guide
gets a dashed shoulder line (T) so the span of the arms stays inside its cell. Auto-riggers (Mixamo, Meshy, Tripo) want one of the two.

`--no-legs` (for a character in a long skirt or robe, like the witch) asks for the hem on the ground and no legs, feet or shoes in any view: the legs are the
biggest animation burden of a rig and are never seen.

View names say which way she FACES in the picture: `right` = she faces the right edge, so we see her right side; `left` the other.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

COLS, ROWS = 3, 2
# name, the guide's label, what the prompt says, the symbols of the way she faces (toward / away: the viewer; left / right: the picture's edge)
VIEWS = (
    ("front", "1 FRONT", "front view, facing the viewer", ("toward",)),
    ("front34", "2 FRONT 3/4", "three-quarter front view, the whole body clearly turned a full 45 degrees, half way between the front view and the side view, so that her near shoulder is well in front of the far one, facing toward the lower right of the picture", ("toward", "right")),
    ("right", "3 RIGHT SIDE", "right side view in profile, facing the right edge of the picture", ("right",)),
    ("back", "4 BACK", "back view, facing directly away from the viewer", ("away",)),
    ("back34", "5 BACK 3/4", "three-quarter back view, the whole body clearly turned a full 45 degrees, half way between the back view and the side view, facing away and toward the left edge of the picture", ("away", "left")),
    ("left", "6 LEFT SIDE", "left side view in profile, facing the left edge of the picture", ("left",)),
)
NAMES = [v[0] for v in VIEWS]
MODELS = {
    "marketing": dict(edit="marketing-studio/image", text="marketing-studio/image",
                      args=dict(resolution="2k", quality="medium", aspect_ratio="3:2")),
    "grok": dict(edit="xai/grok-imagine-image-2.0", text="xai/grok-imagine-image-2.0",
                 args=dict(resolution="2k", quality="medium", aspect_ratio="3:2")),
    "qwen": dict(edit="alibaba/qwen-image-3/edit", text="alibaba/qwen-image-3/text-to-image",
                 args=dict(resolution="2k", aspect_ratio="3:2", prompt_extend=True)),
}
DEFAULT_MODEL = "marketing"
# the background to ask for: its colour, and how the prompt says it
KEYS = {"white": ((255, 255, 255), "pure white"), "green": ((0, 255, 0), "flat chroma-key green (#00FF00), perfectly even")}
DEFAULT_KEY = "green"
POSES = {"keep": "",
         "t": ("Pose, the same in every view: a T-pose for rigging. She stands upright and straight, the head facing forward, the arms stretched out "
               "horizontally to both sides at shoulder height with the hands open, palms down and EMPTY, the legs straight; anything she held "
               "is left out of the picture. "),
         "a": ("Pose, the same in every view: an A-pose for rigging. She stands upright and straight, the head facing forward, the arms angled "
               "down about 40 degrees from the body with the hands open and EMPTY, the legs straight; anything she held is left out of the "
               "picture. ")}
DEFAULT_POSE = "keep"
# for a character in a long skirt or robe: nothing to rig or animate below the hem (the legs are the biggest animation burden and would never be seen)
LEGLESS = ("The long skirt reaches all the way to the ground and covers the legs completely: the figure stands on its hem like a bell, and no legs, feet, "
           "shoes or boots are visible in any view. ")
SHOULDER = 0.30                  # the T-pose guide's shoulder line, as a fraction of a cell's height
GUIDE_SIZE = (1920, 1280)
HEAD, FOOT = 0.14, 0.92          # the head and foot lines, as fractions of a cell's height
FILL = 0.84                      # the figure's height in the output square
TOL = 24                         # a pixel this far (of 255) from the background belongs to a figure
S, GAP = 4, 3                    # the grouping runs at 1/S scale and joins parts closer than 2*GAP cells (24 px); bigger loose parts still join their cell's figure


# ---- 1. the guide --------------------------------------------------------------------------------------------------------
def _font(size):
    return ImageFont.load_default(size=size)


def _arrow(draw, c, direction, r, fill):
    x, y = c
    if direction in ("toward", "away"):               # the physicist's dot (an arrow coming at you) and cross (going away)
        draw.ellipse((x - r, y - r, x + r, y + r), outline=fill, width=4)
        if direction == "toward":
            draw.ellipse((x - r // 4, y - r // 4, x + r // 4, y + r // 4), fill=fill)
        else:
            k = int(r * 0.6)
            draw.line((x - k, y - k, x + k, y + k), fill=fill, width=4)
            draw.line((x - k, y + k, x + k, y - k), fill=fill, width=4)
        return
    s = 1 if direction == "right" else -1
    draw.line((x - s * 2 * r, y, x + s * 2 * r, y), fill=fill, width=5)
    draw.polygon([(x + s * 2.6 * r, y), (x + s * 1.6 * r, y - r * 0.8), (x + s * 1.6 * r, y + r * 0.8)], fill=fill)


def guide(size=GUIDE_SIZE, key=DEFAULT_KEY, pose=DEFAULT_POSE):
    """The layout guide: the grid of cells with their labels, centre lines, head and foot lines and facing symbols, on the background to ask for
    (white by default: the lines are the background darkened, so a green guide has only dark-green lines and no new colour for the model to copy)."""
    W, H = size
    base = KEYS[key][0]

    def ink(level):
        return tuple(int(c * (1 - 0.45 * level)) for c in base)
    img = Image.new("RGB", size, base)
    d = ImageDraw.Draw(img)
    cw, ch = W / COLS, H / ROWS
    for i, (_, label, _, facing) in enumerate(VIEWS):
        x0, y0 = (i % COLS) * cw, (i // COLS) * ch
        d.rectangle((x0 + 6, y0 + 6, x0 + cw - 7, y0 + ch - 7), outline=ink(0.45), width=3)
        for y in (HEAD, FOOT):                                         # dashed head and foot lines
            for x in range(int(x0 + 40), int(x0 + cw - 40), 36):
                d.line((x, y0 + y * ch, x + 18, y0 + y * ch), fill=ink(0.55), width=3)
        if pose == "t":                                                # the arms' span
            for x in range(int(x0 + 40), int(x0 + cw - 40), 36):
                d.line((x, y0 + SHOULDER * ch, x + 18, y0 + SHOULDER * ch), fill=ink(0.4), width=3)
        for y in range(int(y0 + 40), int(y0 + ch - 40), 36):         # the centre line
            d.line((x0 + cw / 2, y, x0 + cw / 2, y + 18), fill=ink(0.3), width=3)
        d.text((x0 + 24, y0 + 18), label, fill=ink(1), font=_font(int(ch * 0.05)))
        for k, direction in enumerate(facing):
            _arrow(d, (x0 + cw - 70 - k * 110, y0 + 52), direction, 18, ink(1))
    return img


# ---- 2. generate ---------------------------------------------------------------------------------------------------------
NOTE = ("The FIRST reference image is a LAYOUT GUIDE, not a picture to copy: a {bg} canvas of six framed cells, each with a label, a "
        "dashed head line near the top, a dashed foot line near the bottom, a dotted centre line and a symbol for the way the character faces. "
        "Draw one view of the character in each cell, the whole character from head to foot, centred on the centre line, the head just under "
        "the head line and the feet on the foot line, so that all six are the same size. Use the guide for placement only: the frames, "
        "lines, labels and symbols stay out of the picture, and the background stays {bg} and empty. ")
SHOULDERS = ("A dashed line across each cell at shoulder height marks where the outstretched arms go, hands included, inside the cell. ")
GRID = ("A grid of three columns by two rows of equal cells. ")


STYLE = ("The %s reference image shows only the RENDERING STYLE to match: soft faceted low-poly modelling, painted surfaces, a muted palette with purple accents, "
         "gentle even lighting. Take its style and nothing else: do not copy its characters or objects. ")
ORDINAL = {2: "SECOND", 3: "THIRD", 4: "FOURTH"}
OBJECT_WORDS = (("A character model sheet", "An object model sheet"), ("the SAME character", "the SAME object"), ("the whole character", "the whole object"),
                ("one and the same character", "one and the same object"), ("the character", "the object"), ("The character", "The object"),
                ("head line", "top line"), ("foot line", "base line"), ("from head to foot", "from top to bottom"), ("the head just under the top line and the feet on the base line",
                 "the top just under the top line and the base on the base line"), ("same face, hair, clothes, colours", "same shape, parts, colours"))


def compose(subject, ref=True, use_guide=True, look="", key=DEFAULT_KEY, pose=DEFAULT_POSE, legless=False, kind="character", style_n=0):
    """`subject`: the character (or object) in words (with a reference it adds to the picture). `kind` "object": a prop, no pose, "object" words.
    `style_n`: the position (2, 3, ...) of a style-only reference image among the references, or 0 for none. Returns the prompt."""
    if kind == "object":
        pose, legless = "keep", False
    bg = KEYS[key][1]
    rows = ["Top row, left to right: " + "; ".join(v[2] for v in VIEWS[:3]) + ". ",
            "Bottom row, left to right: " + "; ".join(v[2] for v in VIEWS[3:]) + ". "]
    who = ("The character is the one in the %s reference image: keep its design, proportions, colours and rendering style exactly, and invent "
           "the sides it does not show in the same style. " % ("SECOND" if use_guide else "")) if ref else ""
    if subject.strip():
        who += "The character: %s. " % subject.strip().rstrip(".")
    prompt = ("A character model sheet for 3D modelling: the SAME character shown six times on one %s background. " % bg
              + (NOTE.format(bg=bg) + (SHOULDERS if pose == "t" else "") if use_guide else GRID) + "".join(rows) + who + POSES[pose] + (LEGLESS if legless else "")
              + "All six views show one and the same character in the same pose, with the same face, hair, clothes, colours and rendering "
              "style, at the same scale like an orthographic turntable, in flat even neutral-white lighting that lets no light of the background colour "
              "fall on the character, with no cast shadows, no floor and no ground, and a clear gap of background around every figure. "
              + (STYLE % ORDINAL[style_n] if style_n else "") + look.strip()).strip()
    if kind == "object":
        for a, b in OBJECT_WORDS:
            prompt = prompt.replace(a, b)
        prompt = prompt.replace("in the same pose, ", "").replace("one and the same object in the same pose", "one and the same object")
    return prompt


def run_hf(model, args, refs, max_usd, out_dir):
    """Runs hf.py (one job at a time: the account runs two). Returns the job's folder."""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "args.json").write_text(json.dumps(args, indent=2) + "\n", encoding="utf-8")
    cmd = [sys.executable, str(ROOT / "tools/higgsfield/hf.py"), "run", model, "--args-file", str(out_dir / "args.json"), "--max-usd", str(max_usd)]
    for ref in refs:
        cmd += ["--upload", "image_urls=%s" % ref]
    print("generating the sheet (%s, at most USD %.2f, %d references) ..." % (model, max_usd, len(refs)))
    with open(ROOT / ".hf.lock", "w") as lock:
        try:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        except ImportError:
            pass
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    (ROOT / ".hf.lock").unlink(missing_ok=True)
    m = re.search(r"^job (\S+)$", proc.stdout, re.M)
    if proc.returncode != 0 or not m or not (Path(m.group(1)) / "image_0.png").exists():
        sys.exit("generation failed:\n" + proc.stdout[-800:] + proc.stderr[-800:])
    return Path(m.group(1))


def job_cost(job):
    try:
        return float(json.loads((Path(job) / "job.json").read_text(encoding="utf-8"))["estimate"]["usd"])
    except (OSError, KeyError, ValueError):
        return 0.0


# ---- 3. crop -------------------------------------------------------------------------------------------------------------
def background(a):
    """The sheet's background colour: the median of its outer frame."""
    h, w = a.shape[:2]
    m = max(2, int(0.01 * min(h, w)))
    ring = np.concatenate([a[:m].reshape(-1, 3), a[-m:].reshape(-1, 3), a[:, :m].reshape(-1, 3), a[:, -m:].reshape(-1, 3)])
    return np.median(ring, axis=0)


def difference(a, bg):
    """0..255, how far each pixel is from the background. Against white: the largest channel difference. Against a key colour: how little the
    pixel is the key (its key channel over the other two, as a share of the background's), so a key that is shaded between hair curls still
    counts as key."""
    if np.ptp(bg) < 100:
        return np.abs(a - bg).max(axis=2)
    ch = int(np.argmax(bg))
    share = (a[..., ch] - np.delete(a, ch, axis=2).max(axis=2)) / max(float(bg[ch] - np.delete(bg, ch).max()), 1.0)
    return 255 * np.clip(1 - share / 0.6, 0, 1)


def find_figures(a, bg, cols=COLS, rows=ROWS):
    """{cell index: bool mask of its figure} (a cell with nothing is absent), and the problems found on the way."""
    h, w = a.shape[:2]
    fg = difference(a, bg) > TOL
    hs, ws = h // S, w // S
    small = fg[:hs * S, :ws * S].reshape(hs, S, ws, S).max(axis=(1, 3))
    small = ndimage.binary_opening(small, np.ones((3, 3)))                  # frame lines and label strokes are thinner than 3 cells
    lab, n = ndimage.label(ndimage.binary_dilation(small, np.ones((3, 3)), iterations=GAP))
    problems, per_cell = [], {}
    for i in range(1, n + 1):
        part = (lab == i) & small
        area = int(part.sum())
        cy, cx = ndimage.center_of_mass(part)
        cell = min(rows - 1, int(cy / hs * rows)) * cols + min(cols - 1, int(cx / ws * cols))
        per_cell.setdefault(cell, []).append((area, i))
    figures = {}
    for cell, groups in per_cell.items():
        groups.sort(reverse=True)
        top = groups[0][0]
        if len(groups) > 1 and groups[1][0] >= 0.25 * top:
            problems.append("%s: two figures in the cell" % NAMES[cell])
        keep = [g for a_, g in groups if a_ >= 0.04 * top]
        sel = np.kron(np.isin(lab, keep), np.ones((S, S), bool))
        full = np.zeros((h, w), bool)
        full[:sel.shape[0], :sel.shape[1]] = sel
        figures[cell] = fg & full
    return figures, problems


def matte(a, bg, mask):
    """(alpha 0..1, colours) of a figure in a window. Against a key colour every pixel that is the key is a hole, enclosed or not, and the
    figure's edge, and any pixel with a quarter of the key's strength or more, is despilled (the key's channel held to the mean of the other two). Against white a hole is a gap of background at least
    0.04 % of the window whose median is within 6 of the background: a pale pixel of the figure (a pendant) stays."""
    d = difference(a, bg)
    rgb = a.clip(0, 255)
    if np.ptp(bg) >= 100:
        inner = ndimage.binary_erosion(mask, iterations=3)
        rim = ndimage.binary_dilation(mask, iterations=2) & ~inner
        alpha = np.where(inner, 1.0, np.where(rim, np.clip((d - 10) / 90.0, 0, 1), 0.0)).astype(np.float32)
        ch = int(np.argmax(bg))
        zone = rim | (mask & ~ndimage.binary_erosion(mask, iterations=6)) | (d < 149)      # 149: a quarter of the key's strength, or more
        other = np.delete(rgb, ch, axis=2).mean(axis=2)
        rgb = rgb.copy()
        rgb[..., ch] = np.where(zone, np.minimum(rgb[..., ch], other), rgb[..., ch])
        return alpha, rgb
    filled = ndimage.binary_fill_holes(mask)
    holes, n = ndimage.label(filled & ~mask)
    if n:
        idx = np.arange(1, n + 1)
        size = ndimage.sum(np.ones(holes.shape), holes, idx)
        median = ndimage.median(d, holes, idx)
        filled &= ~np.isin(holes, idx[(size >= 0.0004 * mask.size) & (median <= 6)])
    return ndimage.gaussian_filter(ndimage.binary_erosion(filled).astype(np.float32), 0.8), rgb


def crop(sheet_path, out_dir, size=1024, cols=COLS, rows=ROWS, key=None):
    """Cuts the sheet into the six normalised views. Returns the report dict (also written as views.json).
    `key`: the background that was asked for (a problem if the sheet has another); None: take the sheet's own."""
    out_dir = Path(out_dir)
    for sub in ("views", "white"):
        (out_dir / sub).mkdir(parents=True, exist_ok=True)
    sheet = Image.open(sheet_path).convert("RGB")
    a = np.asarray(sheet).astype(np.int16)
    h, w = a.shape[:2]
    bg = background(a)
    problems = []
    if key and np.abs(bg - KEYS[key][0]).max() > (20 if key == "white" else 60):
        problems.append("the background is not %s: %s" % (key, bg.astype(int).tolist()))
    figures, more = find_figures(a, bg, cols, rows)
    problems += more
    boxes = {}
    for cell, mask in sorted(figures.items()):
        ys, xs = np.nonzero(mask)
        boxes[cell] = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    heights = [b[3] - b[1] for b in boxes.values()]
    median = float(np.median(heights)) if heights else 0.0
    cw, ch = w / cols, h / rows
    scales, items = {}, {}
    for cell in range(len(VIEWS)):
        name = NAMES[cell]
        if cell not in boxes:
            problems.append("%s: nothing found in the cell" % name)
            continue
        x0, y0, x1, y1 = boxes[cell]
        cx0, cy0 = (cell % cols) * cw, (cell // cols) * ch
        if x0 < cx0 - 0.03 * cw or x1 > cx0 + cw * 1.03 or y0 < cy0 - 0.03 * ch or y1 > cy0 + ch * 1.03:
            problems.append("%s: the figure spills out of its cell" % name)
        if min(x0, y0, w - x1, h - y1) <= 0.005 * min(w, h):
            problems.append("%s: the figure touches the sheet's edge (cut off)" % name)
        if abs((y1 - y0) / median - 1) > 0.2:
            problems.append("%s: drawn %d %% %s than the others (all views are scaled to one height)"
                            % (name, abs(round(((y1 - y0) / median - 1) * 100)), "bigger" if y1 - y0 > median else "smaller"))
        pad = 4
        win = (max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + pad), min(h, y1 + pad))
        sub = a[win[1]:win[3], win[0]:win[2]]
        alpha, sub = matte(sub, bg, figures[cell][win[1]:win[3], win[0]:win[2]])
        scales[cell] = size * FILL / (y1 - y0)
        items[cell] = (sub, alpha, win)
    shrink = 1.0
    if scales:                                              # one shrink for all if the widest figure would not fit the square
        shrink = min(1.0, min(0.96 * size / ((it[2][2] - it[2][0]) * scales[c]) for c, it in items.items()))
    contact = []
    for cell, (sub, alpha, win) in sorted(items.items()):
        name = NAMES[cell]
        k = scales[cell] * shrink
        rgba = np.dstack([sub.clip(0, 255).astype(np.uint8), (alpha * 255).astype(np.uint8)])
        im = Image.fromarray(rgba).resize((max(1, round(rgba.shape[1] * k)), max(1, round(rgba.shape[0] * k))), Image.LANCZOS)
        square = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        square.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
        white = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        white.alpha_composite(square)
        square.save(out_dir / "views" / (name + ".png"))
        white.convert("RGB").save(out_dir / "white" / (name + ".png"))
        contact.append(white.convert("RGB").resize((256, 256), Image.LANCZOS))
    if contact:
        strip = Image.new("RGB", (len(contact) * 257, 256), (200, 200, 200))
        for i, im in enumerate(contact):
            strip.paste(im, (i * 257, 0))
        strip.save(out_dir / "contact.png")
    marked = sheet.copy()
    d = ImageDraw.Draw(marked)
    for cell, b in boxes.items():
        d.rectangle(b, outline=(255, 40, 40), width=4)
    for r in range(1, rows):
        d.line((0, r * ch, w, r * ch), fill=(120, 160, 255), width=2)
    for c in range(1, cols):
        d.line((c * cw, 0, c * cw, h), fill=(120, 160, 255), width=2)
    marked.save(out_dir / "sheet_boxes.png")
    before = out_dir / "views.json"                          # what a re-crop must not lose: the cost and the prompt of the generation
    kept = {k: v for k, v in json.loads(before.read_text(encoding="utf-8")).items() if k in ("cost_usd", "prompt")} if before.exists() else {}
    report = dict(kept, sheet=str(sheet_path), sheet_size=[w, h], background=bg.astype(int).tolist(), size=size, fill=FILL, problems=problems,
                  views={NAMES[c]: dict(box=list(b), height=b[3] - b[1], width=b[2] - b[0]) for c, b in sorted(boxes.items())})
    (out_dir / "views.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


# ---- the whole thing -----------------------------------------------------------------------------------------------------
def make(name, ref=None, text="", model=DEFAULT_MODEL, use_guide=True, look="", out=None, max_usd=0.35, size=1024, key=DEFAULT_KEY, pose=DEFAULT_POSE, legless=False,
         style=None, kind="character"):
    out = Path(out or ROOT / "build/views" / name)
    out.mkdir(parents=True, exist_ok=True)
    gen = MODELS[model]
    refs = []
    if use_guide:
        guide(GUIDE_SIZE, key, pose).save(out / "guide.png")
        refs.append(out / "guide.png")
    if ref:
        refs.append(Path(ref))
    if style:
        refs.append(Path(style))
    prompt = compose(text, ref=bool(ref), use_guide=use_guide, look=look, key=key, pose=pose, legless=legless, kind=kind, style_n=len(refs) if style else 0)
    args = dict(gen["args"], prompt=prompt)
    job = run_hf(gen["edit"] if refs else gen["text"], args, refs, max_usd, out)
    (out / "sheet.png").write_bytes((job / "image_0.png").read_bytes())
    (out / "job_views.json").write_text((job / "job.json").read_text(encoding="utf-8"), encoding="utf-8")
    report = crop(out / "sheet.png", out, size=size, key=key)
    report["cost_usd"] = job_cost(job)
    report["prompt"] = prompt
    (out / "views.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("guide")
    g.add_argument("out", nargs="?", default="build/views/guide.png")
    g.add_argument("--key", choices=sorted(KEYS), default=DEFAULT_KEY)
    g.add_argument("--pose", choices=sorted(POSES), default=DEFAULT_POSE)
    m = sub.add_parser("make")
    m.add_argument("name")
    m.add_argument("--ref", help="a picture of the character (the front is best)")
    m.add_argument("--text", default="", help="the character in words (with --ref it adds to the picture)")
    m.add_argument("--model", choices=sorted(MODELS), default=DEFAULT_MODEL)
    m.add_argument("--key", choices=sorted(KEYS), default=DEFAULT_KEY, help="the background to ask for: chroma-key green (cleaner cut-out) or white (for a character with green in it)")
    m.add_argument("--pose", choices=sorted(POSES), default=DEFAULT_POSE, help="keep the reference's pose, or ask for a T-pose / A-pose for rigging")
    m.add_argument("--no-legs", action="store_true", help="a long skirt or robe to the ground: no legs, feet or shoes drawn (nothing to rig below the hem)")
    m.add_argument("--no-guide", action="store_true", help="describe the grid in words only (to compare)")
    m.add_argument("--style", help="a picture whose RENDERING STYLE to match (sent as an extra reference; its characters and objects are not to be copied)")
    m.add_argument("--kind", choices=("character", "object"), default="character", help="object: a prop (no pose, 'object' wording; --pose and --no-legs are ignored)")
    m.add_argument("--look", default="", help="more style words appended to the prompt")
    m.add_argument("--out")
    m.add_argument("--size", type=int, default=1024)
    m.add_argument("--max-usd", type=float, default=0.35)
    c = sub.add_parser("crop")
    c.add_argument("sheet")
    c.add_argument("--out", required=True)
    c.add_argument("--size", type=int, default=1024)
    c.add_argument("--key", choices=sorted(KEYS), help="the background the sheet was asked to have (reports it if different)")
    a = ap.parse_args(argv)
    if a.cmd == "guide":
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        guide(key=a.key, pose=a.pose).save(a.out)
        print(a.out)
        return 0
    if a.cmd == "make":
        if not a.ref and not a.text:
            sys.exit("give --ref or --text")
        report = make(a.name, a.ref, a.text, a.model, not a.no_guide, a.look, a.out, a.max_usd, a.size, a.key, a.pose, a.no_legs, a.style, a.kind)
    else:
        report = crop(a.sheet, a.out, a.size, key=a.key)
    print("%d views -> %s" % (len(report["views"]), a.out or ROOT / "build/views" / a.name))
    for p in report["problems"]:
        print("PROBLEM " + p)
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    sys.exit(main())
