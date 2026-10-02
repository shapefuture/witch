#!/usr/bin/env python3
"""Which image model follows our guidance best? One scene, one layout, one look, many models, scored blind.

    python tools/painted/compare_models.py plan   [--budget 1.0]            # the runs, their estimated prices (free)
    python tools/painted/compare_models.py run    NAME [--budget 1.0]       # generate every run (paid, capped as a whole), into build/compare/NAME/
    python tools/painted/compare_models.py blind  NAME                      # anonymised copies + critic instructions (free)
    python tools/painted/compare_models.py score  NAME critic1.json [critic2.json ...]   # the table

The guidance under test: the master prompt's style block (verbatim, trimmed only where a model's prompt limit forces it), a layout (the
brief's, scene_layout.py) given either as a GUIDE IMAGE (grey labeled boxes) or as WORDS ("the window: right, upper, large"), and the
house constraints (clear ground, nobody in it, no text). NO style-anchor picture: this is each model's native reading of the style.
Models that take a reference image get the guide; the others the words. Scores (layout_score.py) come from critics who never see the layout or the model: they locate each named element in the
anonymised picture and answer a checklist; their boxes are compared with the layout's.
"""
import argparse
import json
import random
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import scene_layout as sl  # noqa: E402
import layout_score as ls  # noqa: E402
import new_scene as ns  # noqa: E402

BRIEF, STYLE = "shop", "ps1"
GUIDE_NOTE = ("The reference image is a LAYOUT GUIDE, not a picture to copy: grey labeled boxes mark where each element goes and how big it is "
              "(FG = foreground, MID = middle ground, BG = background; GROUND = leave empty; dashed line = horizon). Paint each labeled element at its "
              "box's position and size; do not draw the boxes, grey shapes, dashed line or labels, and print no text. ")
PALETTE = ("Palette: jewel-toned theatrical daylight; shadows deep cobalt, violet-blue-black, plum, indigo (never gray); light incandescent amber and pale "
           "gold; ground and walls turquoise, teal, petrol; accents coral, hot-pink, cream; moss green, mustard, burnt orange; matte dry opaque pigment. ")
CAMERA = ("Fixed point-and-click stage-play camera with strong barrel curvature inside the geometry; no vignette, no frame, no outlines, no ink lines. ")
STYLE_REF_NOTE = ("The SECOND reference image shows the target look only (palette, rendering, mood, how surfaces and light are painted): "
                  "match that look, but do not copy its rooms, objects, characters or composition. ")
STYLE_REF = ROOT / "assets/painted/hall_clean/plate_empty.png"     # the original painting (characters removed): the first room
TAIL = "A large clear empty floor area fills the foreground. No people, no witch, no raccoon, no text, no letters."
SHORT_LOOK = ("Screenshot of a crude 1997 PS1-style low-poly point-and-click game: wedge and slab geometry, blunt facets, dry matte painted textures, "
              "no outlines, no bloom, not papercraft, not cute modern. Cobalt and plum shadows, teal walls, amber light, never gray. Crooked potion shop. ")
LIMITS = {"ideogram/v4.0": 2040, "z-image/turbo": 790}


# name, model, channel ("guide": the layout as an image (+ the look's anchor where the model takes several); "words": the layout in words;
# "words-short": the same for a model with an 800-character prompt), the field the images go in, and fixed arguments
RUNS = [
    dict(id="grok_guide", model="xai/grok-imagine-image-2.0", channel="guide", images="image_urls", args=dict(resolution="2k", quality="medium", aspect_ratio="16:9")),
    dict(id="grok_words", model="xai/grok-imagine-image-2.0", channel="words", args=dict(resolution="2k", quality="medium", aspect_ratio="16:9")),
    dict(id="qwen_edit_guide", model="alibaba/qwen-image-3/edit", channel="guide", images="image_urls", args=dict(resolution="2k", aspect_ratio="16:9", prompt_extend=True)),
    dict(id="qwen_words", model="alibaba/qwen-image-3/text-to-image", channel="words", args=dict(resolution="2k", aspect_ratio="16:9", prompt_extend=True)),
    dict(id="ideogram_guide", model="ideogram/v4.0", channel="guide", images="image_url", args=dict(aspect_ratio="16:9", image_weight=35, rendering_speed="DEFAULT")),
    dict(id="ideogram_words", model="ideogram/v4.0", channel="words", args=dict(aspect_ratio="16:9", rendering_speed="DEFAULT")),
    dict(id="marketing_guide", model="marketing-studio/image", channel="guide", images="image_urls", args=dict(resolution="1k", quality="medium", aspect_ratio="16:9")),
    dict(id="soul_i2i_guide", model="higgsfield-ai/soul/v2/image-to-image", channel="guide", images="image_url", args=dict(resolution="1080p", aspect_ratio="16:9")),
    dict(id="soul_words", model="higgsfield-ai/soul/v2/standard", channel="words", args=dict(resolution="1080p", aspect_ratio="16:9")),
    dict(id="recraft_words", model="recraft/v4.1/text-to-image", channel="words", args=dict(aspect_ratio="16:9")),
    dict(id="zimage_words", model="z-image/turbo", channel="words-short", args=dict(resolution="2k", aspect_ratio="16:9")),
]


# --set hall: the four models asked for, each with the layout guide (shapes) AND the original room painting as the style reference
HALL_SET = [
    dict(id="grok_both", model="xai/grok-imagine-image-2.0", channel="both", images="image_urls", args=dict(resolution="2k", quality="medium", aspect_ratio="16:9")),
    dict(id="grok_guide", model="xai/grok-imagine-image-2.0", channel="guide", images="image_urls", args=dict(resolution="2k", quality="medium", aspect_ratio="16:9")),
    dict(id="marketing_guide", model="marketing-studio/image", channel="guide", images="image_urls", args=dict(resolution="1k", quality="medium", aspect_ratio="16:9")),
    dict(id="qwen_edit_guide", model="alibaba/qwen-image-3/edit", channel="guide", images="image_urls", args=dict(resolution="2k", aspect_ratio="16:9", prompt_extend=True)),
]


def load():
    brief = ns.load_brief(BRIEF)
    spec = ns.resolve(brief["kind"], brief)
    layout = sl.with_defaults(brief["layout"], spec)
    return brief, spec, layout


def master_style():
    return ns.load_styles()[STYLE]["style_block"]


def fit(parts, limit):
    """Joins (name, text) parts; over the limit, drops the camera, then the palette, then cuts the style block at a sentence."""
    def join():
        return " ".join(t for _, t in parts if t).replace("  ", " ")
    if not limit or len(join()) <= limit:
        return join()
    for name in ("camera", "palette"):
        parts = [(n, "" if n == name else t) for n, t in parts]
        if len(join()) <= limit:
            return join()
    over = len(join()) - limit
    style = dict(parts)["style"]
    keep = style[: max(200, len(style) - over - 5)]
    keep = keep[: keep.rfind(", ")] + "." if ", " in keep else keep
    return " ".join(t for n, t in [(n, keep if n == "style" else t) for n, t in parts] if t)


def prompt_for(run, brief, layout, style_ref=False):
    """The prompt of one run (see the module docstring); every channel carries the same look, scene and constraints."""
    mine = brief["styles"][STYLE]
    labels = ", ".join(e["label"] for e in layout["elements"])
    scene = "Scene: %s, %s. Elements: %s." % (mine["title"], mine["prompt"].split(",")[0].strip(), labels)
    channel, limit = run["channel"], LIMITS.get(run["model"])
    if channel == "words-short":
        budget = 790 - len(SHORT_LOOK) - len(" Empty floor in the foreground. No people, no text.")
        parts = []
        for e in sorted(layout["elements"], key=lambda e: -ls.area(e)):
            text = "%s %s" % (e["label"].split(":")[0].split(",")[0].split("+")[0].strip().lower(), ls.where(e))
            if sum(len(p) + 2 for p in parts) + len(text) <= budget:
                parts.append(text)
        return SHORT_LOOK + "; ".join(parts) + ". Empty floor in the foreground. No people, no text."
    note = (GUIDE_NOTE + (STYLE_REF_NOTE if style_ref else "")) if channel in ("guide", "both") else ""
    placement = "" if channel == "guide" else "Placement of each element in the frame: " + ls.describe(layout)
    return fit([("note", note), ("style", master_style()), ("palette", PALETTE), ("camera", CAMERA), ("scene", scene),
                ("placement", placement), ("tail", TAIL)], limit)


def hf(run, prompt, guide, max_usd, out_dir, estimate_only=False, style_ref=None):
    out_dir.mkdir(parents=True, exist_ok=True)
    args = dict(run["args"], prompt=prompt)
    (out_dir / "args.json").write_text(json.dumps(args, indent=2) + "\n", encoding="utf-8")
    base = [sys.executable, str(ROOT / "tools/higgsfield/hf.py")]
    if estimate_only:
        probe = dict(args)
        if run.get("images"):
            probe[run["images"]] = ["https://example.com/a.png"] if run["images"] == "image_urls" else "https://example.com/a.png"
        proc = subprocess.run(base + ["estimate", run["model"], "--args", json.dumps(probe)], capture_output=True, text=True, cwd=ROOT)
        try:
            return float(json.loads(proc.stdout[proc.stdout.index("{"):])["usd"])
        except (ValueError, KeyError):
            return None
    cmd = base + ["run", run["model"], "--args-file", str(out_dir / "args.json"), "--max-usd", "%.3f" % max_usd, "--out", str(out_dir)]
    if run.get("images"):
        for pic in [guide] + ([style_ref] if style_ref else []):
            cmd += ["--upload", "%s=%s" % (run["images"], pic)]
    with open(ROOT / ".hf.lock", "w") as lock:
        try:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        except ImportError:
            pass
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    (ROOT / ".hf.lock").unlink(missing_ok=True)
    return proc


def find_image(run_dir):
    """The generated picture inside a run's folder (hf.py makes a job folder per run; layout.png and args.json are not it)."""
    for pattern in ("image_0.*", "*.png", "*.jpg", "*.jpeg", "*.webp"):
        found = [f for f in sorted(run_dir.rglob(pattern)) if f.name not in ("layout.png", "args.json")]
        if found:
            return found[0]
    return None


def job_usd(run_dir):
    for job in sorted(run_dir.rglob("job.json")):
        try:
            return float(json.loads(job.read_text())["estimate"]["usd"])
        except (OSError, KeyError, ValueError):
            pass
    return None


def cmd_plan(args):
    brief, spec, layout = load()
    total = 0.0
    for run in RUNS:
        prompt = prompt_for(run, brief, layout)
        usd = hf(run, prompt, None, 0, ROOT / "build/compare/_plan" / run["id"], estimate_only=True)
        total += usd or 0
        print("%-16s %-44s %-11s %5d chars  %s" % (run["id"], run["model"], run["channel"], len(prompt), "$%.3f" % usd if usd is not None else "estimate failed"))
    print("estimated total $%.2f (budget $%.2f)" % (total, args.budget))
    return 0


def cmd_run(args):
    brief, spec, layout = load()
    root = ROOT / "build/compare" / args.name
    guide = root / "layout.png"
    root.mkdir(parents=True, exist_ok=True)
    sl.render(layout).save(guide)
    (root / "layout.json").write_text(json.dumps(layout, indent=1) + "\n", encoding="utf-8")
    ref, tag = (STYLE_REF, "hall") if args.set == "hall" else (Path(args.style_ref) if args.style_ref else None, args.tag or "ref")
    hall = ref is not None
    base = HALL_SET if args.set == "hall" else [r for r in RUNS if r["id"] in (args.only.split(",") if args.only else [r["id"] for r in RUNS if "guide" in r["channel"]])]
    runs = [dict(r, id=r["id"] + "+" + tag) for r in base] if hall else RUNS
    if hall:
        (root / "style_ref.json").write_text(json.dumps({"path": str(ref), "tag": tag}) + "\n", encoding="utf-8")
    results = json.loads((root / "results.json").read_text()) if (root / "results.json").exists() else {}
    spent = sum(r.get("usd") or 0 for r in results.values())
    for run in runs:
        if run["id"] in results and results[run["id"]].get("image"):
            continue
        prompt = prompt_for(run, brief, layout, style_ref=hall)
        done = find_image(root / run["id"])
        if done:                                           # already generated (a crash after the paid call): keep it, do not pay again
            results[run["id"]] = {"image": str(done.relative_to(root)), "usd": job_usd(root / run["id"]), "chars": len(prompt)}
            spent += results[run["id"]]["usd"] or 0
            print("recovered %s" % run["id"])
            continue
        est = hf(run, prompt, guide, 0, root / run["id"], estimate_only=True, style_ref=ref)
        if est is None or spent + est > args.budget:
            print("skip %s (estimate %s, spent %.2f of %.2f)" % (run["id"], est, spent, args.budget))
            results[run["id"]] = {"skipped": True, "estimate": est}
            continue
        print("run %s ($%.3f) ..." % (run["id"], est), flush=True)
        proc = hf(run, prompt, guide, est * 1.5 + 0.01, root / run["id"], style_ref=ref)
        image = find_image(root / run["id"])
        if proc.returncode != 0 or not image:
            tail = (proc.stdout[-300:] + proc.stderr[-300:]).strip().replace("\n", " | ")
            print("  failed: %s" % tail)
            results[run["id"]] = {"failed": tail, "estimate": est}
        else:
            spent += est
            results[run["id"]] = {"image": str(image.relative_to(root)), "usd": est, "chars": len(prompt)}
            print("  ok %s" % image.name)
        (root / "results.json").write_text(json.dumps(results, indent=1) + "\n", encoding="utf-8")
    (root / "results.json").write_text(json.dumps(results, indent=1) + "\n", encoding="utf-8")
    print("spent about $%.2f" % spent)
    return 0


def cmd_blind(args):
    from PIL import Image
    root = ROOT / "build/compare" / args.name
    results = json.loads((root / "results.json").read_text())
    pics = {i: root / r["image"] for i, r in results.items() if r.get("image")}
    combined = {i: dict(r, image=str(pics[i])) for i, r in results.items() if r.get("image")}
    for spec_ in args.include_from or []:                         # earlier pictures to compare against: ROOT or ROOT:id,id
        name, _, only = spec_.partition(":")
        other = ROOT / "build/compare" / name
        for i, r in json.loads((other / "results.json").read_text()).items():
            if r.get("image") and (not only or i in only.split(",")):
                pics[i] = other / r["image"]
                combined[i] = dict(r, image=str(pics[i]))
    brief, spec, layout = load()
    ids = list(pics)
    random.Random(args.seed).shuffle(ids)
    blind = root / "blind"
    blind.mkdir(exist_ok=True)
    key = {}
    for n, i in enumerate(ids, 1):
        name = "pic_%02d.png" % n
        Image.open(pics[i]).convert("RGB").resize((1280, 720), Image.LANCZOS).save(blind / name)
        key[name] = i
    ref_path = args.reference if args.reference and args.reference is not True else None
    if args.reference is True and (root / "style_ref.json").exists():
        ref_path = json.loads((root / "style_ref.json").read_text())["path"]
    reference = bool(args.reference)
    if reference:
        ref_img = Image.open(ref_path or STYLE_REF).convert("RGB")
        ref_img.resize((1280, max(1, round(ref_img.height * 1280 / ref_img.width))), Image.LANCZOS).save(blind / "style_reference.png")
    (root / "blind_key.json").write_text(json.dumps(key, indent=1) + "\n", encoding="utf-8")
    (root / "blind_results.json").write_text(json.dumps(combined, indent=1) + "\n", encoding="utf-8")
    names = [e["label"].split(":")[0] if ":" in e["label"] else e["label"] for e in layout["elements"]]
    (blind / "INSTRUCTIONS.md").write_text(ls.critic_instructions(names, layout["ground"], sorted(key), reference), encoding="utf-8")
    print("blind set: %s (%d pictures)" % (blind, len(key)))
    return 0


def cmd_score(args):
    root = ROOT / "build/compare" / args.name
    brief, spec, layout = load()
    both = root / "blind_results.json"
    results = json.loads((both if both.exists() else root / "results.json").read_text())
    key = json.loads((root / "blind_key.json").read_text())
    rows = ls.score_all(layout, [json.loads(Path(c).read_text()) for c in args.critics], key, results)
    print(ls.table(rows))
    (root / "scores.json").write_text(json.dumps(rows, indent=1) + "\n", encoding="utf-8")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan"); p.add_argument("--budget", type=float, default=1.0); p.set_defaults(fn=cmd_plan)
    p = sub.add_parser("run"); p.add_argument("name"); p.add_argument("--set", choices=["hall"], help="hall: layout guide + the original room painting as style reference"); p.add_argument("--style-ref", help="a style reference image (with --tag): the guide runs of --only (default: every guide run) are redone with it"); p.add_argument("--tag"); p.add_argument("--only"); p.add_argument("--budget", type=float, default=1.0); p.set_defaults(fn=cmd_run)
    p = sub.add_parser("blind"); p.add_argument("name"); p.add_argument("--include-from", action="append"); p.add_argument("--only"); p.add_argument("--reference", nargs="?", const=True, help="critics also rate the style match to this image (default: the run's own style reference)"); p.add_argument("--seed", type=int, default=7); p.set_defaults(fn=cmd_blind)
    p = sub.add_parser("score"); p.add_argument("name"); p.add_argument("critics", nargs="+"); p.set_defaults(fn=cmd_score)
    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
