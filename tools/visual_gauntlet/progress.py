#!/usr/bin/env python3
"""Builds the self-contained progress page for the visual gauntlet (images embedded as data URIs).

    python tools/visual_gauntlet/progress.py docs/visual-gauntlet out.html [--reference ref.png --ours ours.png]

Reads docs/visual-gauntlet/rounds.json: [{"round": 2, "dir": "r02", "verdict": "NO", "gap": "...",
"fixed": ["..."], "next": ["..."]}], the frames in rounds/<dir>/ and the phone frames in
rounds/<dir>/phone/ if present. Needs Pillow.
"""
import base64
import html
import io
import json
import os
import sys

from PIL import Image


def data_uri(path, width=720, quality=82):
    img = Image.open(path).convert("RGB")
    if img.width > width:
        img = img.resize((width, int(img.height * width / img.width)), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def metric_row(m):
    cells = [("saturation", m["mean_saturation"]), ("olive-gold", m["olive_gold_share"]), ("orange", m["orange_share"]),
             ("purple", m["purple_share"]), ("dark frame", m["dark_frame_share_lt_0.12"]), ("bright pool", m["bright_pool_share_gt_0.75"]),
             ("contrast", m["contrast_p95_over_p5"])]
    return "".join("<div><dt>%s</dt><dd>%s</dd></div>" % (html.escape(k), v) for k, v in cells)


def bar_section(reference, ours):
    """Side by side with the real reference image and its measured numbers (metrics.py), if given."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import metrics
    tmp = os.path.join(os.path.dirname(os.path.abspath(ours)), "_ref_640.png")
    Image.open(reference).convert("RGB").resize((640, 360), Image.LANCZOS).save(tmp)
    ref_m, our_m = metrics.analyse(tmp), metrics.analyse(ours)
    os.remove(tmp)
    rows = [("median luma", "luma_pct_1_5_25_50_75_95_99", 3), ("95th percentile luma", "luma_pct_1_5_25_50_75_95_99", 5), ("99th percentile luma", "luma_pct_1_5_25_50_75_95_99", 6),
            ("dark frame (<0.12)", "dark_frame_share_lt_0.12", None), ("blown out (>0.75)", "bright_pool_share_gt_0.75", None), ("saturation", "mean_saturation", None),
            ("facet noise", "facet_gradient", None), ("corner / centre", "vignette_corner_over_centre", None)]
    body = ""
    for label, key, idx in rows:
        a = ref_m[key][idx] if idx is not None else ref_m[key]
        b = our_m[key][idx] if idx is not None else our_m[key]
        body += "<tr><th scope='row'>%s</th><td>%s</td><td>%s</td></tr>" % (html.escape(label), a, b)
    return """
<section class="barcmp">
  <h2>Against your reference</h2>
  <p class="lede">The reference, measured with the same tool as our frames (both at 640x360). It is a low-key picture: dark, rich, soft light, large calm facets.</p>
  <div class="pair"><figure><img alt="The reference still" src="%s"><figcaption>reference</figcaption></figure><figure><img alt="Our master shot" src="%s"><figcaption>ours</figcaption></figure></div>
  <div class="tablewrap"><table><thead><tr><th></th><th>reference</th><th>ours</th></tr></thead><tbody>%s</tbody></table></div>
</section>""" % (data_uri(reference, 960), data_uri(ours, 960), body)


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--reference")
    ap.add_argument("--ours")
    parsed = ap.parse_args()
    opts = {"--reference": parsed.reference, "--ours": parsed.ours} if parsed.reference and parsed.ours else {}
    args = [parsed.root, parsed.out]
    root, out = args[0], args[1]
    rounds = json.load(open(os.path.join(root, "rounds.json")))
    cards = []
    for r in rounds:
        d = os.path.join(root, "rounds", r["dir"])
        wide = os.path.join(d, "wide_169.png")
        metrics = None
        mpath = os.path.join(d, "metrics.json")
        if os.path.exists(mpath):
            for m in json.load(open(mpath)):
                if m["file"].endswith("wide_169.png"):
                    metrics = m
        extra = ""
        for name, label in (("conversation", "cut"), ("magic", "spell"), ("options_machine", "plaques")):
            p = os.path.join(d, name + ".png")
            if os.path.exists(p):
                extra += '<figure><img alt="%s frame, round %s" src="%s"><figcaption>%s</figcaption></figure>' % (label, r["round"], data_uri(p, 420, 78), label)
        verdict = r.get("verdict") or "pending"
        cls = {"NO": "no", "YES": "yes"}.get(verdict, "wait")
        fixed = "".join("<li>%s</li>" % html.escape(x) for x in r.get("fixed", []))
        nxt = "".join("<li>%s</li>" % html.escape(x) for x in r.get("next", []))
        cards.append("""
<section class="round">
  <header><h2>Round %s</h2><span class="chip %s">critic: %s</span></header>
  <p class="gap">%s</p>
  <img class="hero" alt="Master shot, round %s" src="%s">
  %s
  <div class="extra">%s</div>
  <div class="lists"><div><h3>Changed before this round</h3><ul>%s</ul></div><div><h3>Still open</h3><ul>%s</ul></div></div>
</section>""" % (r["round"], cls, html.escape(verdict), html.escape(r.get("gap", "")), r["round"], data_uri(wide, 960),
                 '<dl class="metrics">%s</dl>' % metric_row(metrics) if metrics else "", extra, fixed or "<li>First build</li>", nxt or "<li>-</li>"))
    phone = ""
    pdir = os.path.join(root, "phone")
    if os.path.isdir(pdir):
        for name in sorted(os.listdir(pdir)):
            if name.endswith((".png", ".jpg")):
                phone += '<figure><img alt="%s" src="%s"><figcaption>%s</figcaption></figure>' % (name, data_uri(os.path.join(pdir, name), 900, 78), html.escape(os.path.splitext(name)[0].replace("_", " ")))
    page = open(os.path.join(os.path.dirname(__file__), "progress_template.html"), encoding="utf-8").read()
    bar = bar_section(opts["--reference"], opts["--ours"]) if "--reference" in opts and "--ours" in opts else ""
    page = page.replace("{{BAR}}", bar).replace("{{ROUNDS}}", "".join(cards)).replace("{{PHONE}}", phone)
    open(out, "w", encoding="utf-8").write(page)
    print("wrote", out, len(page) // 1024, "KB")


if __name__ == "__main__":
    main()
