# Which image model follows our guidance? (run r1, 2026-10-02)

**Setup.** The shop of `tools/painted/scenes/shop.json` (11 named elements, the brief's layout) in the master-prompt style: the draft's style
block verbatim (trimmed only where a model's prompt limit forced it: Ideogram 2048 characters, Z-Image 800), the house constraints (clear
floor, nobody in it, no text), and **no style-anchor picture**, so each model gives its own reading of the style. The layout went either as a
grey **guide image** (models that take a reference image) or as **words** ("window: far right, upper, medium"). One generation per run, 11 runs
over 8 models, USD 0.57 in all. Two critics who saw neither the layout nor the model located every element in anonymised pictures and answered
a checklist (`layout_score.py`); their boxes agreed to a median 0.003 of the frame over 114 shared boxes.

| run | USD | placement | presence | box overlap | objects on the empty ground | crude 3D (0-10) | jewel palette | cute modern (lower is better) |
|---|---|---|---|---|---|---|---|---|
| **qwen_edit_guide** (Qwen Image 3 Edit) | 0.075 | **0.90** | 1.00 | **0.50** | **0** | 6.0 | **9.0** | **3.5** |
| **grok_guide** (Grok Imagine 2.0) | 0.090 | 0.89 | 1.00 | 0.49 | 2 | **7.5** | 7.5 | 4.5 |
| grok_words | 0.080 | 0.88 | 1.00 | 0.37 | **0** | 6.0 | 9.0 | 4.0 |
| qwen_words (Qwen Image 3 text) | 0.075 | 0.84 | 1.00 | 0.30 | **0** | 6.5 | 8.5 | 4.0 |
| ideogram_words (Ideogram 4.0) | 0.060 | 0.82 | 1.00 | 0.27 | 3 | 3.0 | 3.0 | 7.5 |
| marketing_guide (Marketing Studio, 1k) | 0.065 | 0.79 | 1.00 | 0.31 | 1.5 | 6.5 | 6.5 | 3.5 |
| recraft_words (Recraft 4.1) | 0.035 | 0.66 | 1.00 | 0.18 | 2 | 3.5 | 7.0 | 3.5 |
| ideogram_guide | 0.060 | 0.61 | 1.00 | 0.23 | 4 | 1.0 | 4.5 | 6.5 |
| zimage_words (Z-Image Turbo, short prompt) | 0.015 | 0.61 | 0.91 | 0.25 | 3 | 3.5 | 4.5 | 9.0 |
| soul_words (Soul 2) | 0.006 | 0.37 | 0.77 | 0.20 | 3 | 3.0 | 7.5 | 5.5 |
| soul_i2i_guide (Soul 2 image-to-image) | 0.006 | 0.27 | 0.73 | 0.05 | 0.5 | 3.5 | 6.5 | 3.0 |

`placement` is 0-1 over every element (an absent one counts 0; full marks within 0.06 of the frame of the layout's centre, none past 0.30);
`presence` is the share of elements seen at all. No run had text or people, and no critic saw a guide's grey boxes (the guide leaked in a
subtler way: Ideogram's guide run came out as a flat cutaway on the guide's white).

## Reading

- **Qwen Image 3 Edit with the guide is the best fit for our guidance**: best placement, best box overlap, an empty floor, the richest jewel
  palette and the least "cute modern". Grok with the guide is as good at placement and the crudest-looking (7.5), at the price of two objects
  on the floor and a duller palette. Both are the models to use; `new_scene.py --model qwen|grok`.
- **For these two the guide image adds less than expected**: placement from words alone is within 0.06 of the guide's (grok 0.88 vs 0.89,
  qwen 0.84 vs 0.90). The guide mostly sharpens box overlap (qwen 0.30 to 0.50, grok 0.37 to 0.49). The cheap way to direct a scene is a good
  layout in either form.
- **Marketing Studio** (1k, medium) is decent and cheap but less jewel-toned; at 2k or high quality it costs several times as much.
- **Ideogram 4.0 does not read the style**: the closest to modern illustration (crude 1-3, cute 6.5-7.5), and its guide run copied the guide's
  white. **Z-Image Turbo** is cute and modern (9). **Recraft 4.1** looks grungy and photographic. **Soul 2** neither places (0.27-0.37) nor
  keeps every element; its image-to-image mode restyles the guide itself.
- Nobody reproduced the draft's "catastrophically crude" geometry fully (the best crude score is 7.5 of 10); the game's own PSX pass supplies
  the rest at runtime.

## Caveats

One scene, one layout, one generation per model: differences of a few hundredths in placement are noise. Both critics are the same model
family, so their agreement is not proof of accuracy. Qwen's `prompt_extend` is forced on for this account, so it may rewrite the prompt.
Ideogram's and Z-Image's prompts were shortened to their limits, and Marketing Studio ran at 1k; the others at 2k. A guide that costs a model
its style (as the first colour guide did) needs the anchor (`docs/art/scenes.md`), which this run deliberately left out.

Reproduce: `python tools/painted/compare_models.py run r1`, `blind r1`, then critics, then `score r1 a.json b.json`
(`build/compare/r1/` holds the pictures and is not committed).

# Run r2: with the original room painting as the style reference

**Setup.** Four models, each given the layout guide (grey shapes) **and** the original room painting (`assets/painted/hall_clean/plate_empty.png`,
the first room, characters removed) as a second reference image "for the look only", same master-prompt style block and layout as r1. Grok's
words run became `grok_both+hall` (guide, placement words and reference together). The no-reference pictures of r1 were scored again in the
same blind set, with a new question: `style` = how close the picture's *look* (palette, how surfaces are painted and faceted, light, mood) is
to the hall painting, 0-10, judged by critics who were shown the painting but not told which pictures had it. USD 0.32; 8 pictures, 2 critics
(median box distance 0.004 over 88 shared boxes; the critics' style marks differed by at most 1).

| run | USD | placement | box overlap | objects on ground | jewel palette | cute modern (lower is better) | **style match to the hall** |
|---|---|---|---|---|---|---|---|
| marketing_guide **+hall** | 0.066 | 0.74 | 0.25 | 2.5 | 6.5 | **3.0** | **7.5** |
| qwen_edit_guide **+hall** | 0.075 | 0.81 | 0.35 | 0.5 | **8.0** | 3.5 | 6.5 |
| marketing_guide | 0.065 | 0.79 | 0.30 | 1.0 | 5.0 | 4.5 | 6.0 |
| grok_words | 0.080 | 0.88 | 0.36 | 0.0 | 8.5 | 3.5 | 4.5 |
| qwen_edit_guide | 0.075 | **0.90** | **0.51** | 0.5 | 8.0 | 5.5 | 3.5 |
| grok_both **+hall** | 0.090 | **0.90** | 0.36 | 2.5 | 7.5 | 7.0 | 3.5 |
| grok_guide | 0.090 | 0.89 | 0.50 | 3.0 | 6.0 | 7.0 | 3.5 |
| grok_guide **+hall** | 0.090 | 0.75 | 0.29 | 2.0 | 6.0 | 6.0 | 3.5 |

What the reference changed, model by model (with minus without):

| model | placement | style match | cute modern | jewel palette |
|---|---|---|---|---|
| Qwen Image 3 Edit | -0.09 | **+3.0** | -2.0 | 0 |
| Marketing Studio (1k) | -0.05 | +1.5 | -1.5 | +1.5 |
| Grok guide | -0.14 | 0 | -1.0 | 0 |
| Grok (words vs guide + words) | +0.02 | -1.0 | +3.5 | -1.0 |

## Reading

- **Qwen Image 3 Edit takes the style reference best**: its look moves a long way toward the hall (style match 3.5 to 6.5, much less cute and toy-like)
  and it keeps most of its placement (0.90 to 0.81), an empty floor and its jewel colours. **Qwen with guide and reference is the best balance** for
  a scene that should look like the first room.
- **Marketing Studio matches the hall's look best** (7.5) and is the cheapest of the four, but its placement is the weakest (0.74) and it leaves
  objects on the floor (2.5).
- **Grok barely uses the reference**: its style match stays at 3.5 (a point lower with the guide, words and reference together) and its pictures
  stay in its own faceted pastel patchwork; adding the reference cost it placement (-0.14) and gained nothing. Use Grok for placement, not for
  matching a given look.
- **Every reference costs placement** (0.05-0.14): the model spends attention on the second image. If a placement is critical, state it in
  words as well, or generate without the reference and match the look afterwards.
- **For the master-prompt look, with no hall reference** (r1), Qwen Edit with the guide still leads. Which reference to use is a choice of look:
  the hall painting (olive, ochre, hazy light; style match up to 7.5) or none (jewel teal, plum and amber; the master prompt's own palette).
  The two look different, and the master prompt's "NOT papercraft" sits uneasily with a papercraft reference.

**Caveats.** One scene, one generation per model. Subjective marks are noisy: the same r1 pictures scored 1 to 2 points differently for `jewel`
and `cute modern` between the two critic pairs (placement agreed to within 0.01), so read those columns as direction, not value. `grok_both+hall`
changes three things at once against `grok_words`. Marketing Studio ran at 1k.

Reproduce: `compare_models.py run r2 --set hall`, `blind r2 --include-from r1 --only grok_words,grok_guide,marketing_guide,qwen_edit_guide
--reference`, then critics, then `score r2 a.json b.json`.

# Run r3: the engine render of the hall as the style reference

**Setup.** The three guide runs (Grok, Marketing Studio at 1k, Qwen Edit) redone with the layout guide and a *different* style reference: a render of the game's own
real-time hall (`1280x360`: two views side by side, one a distorted close-up; supplied by the user, not committed). Same master-prompt style
block and layout. 9 pictures were scored blind by two critics against that engine render: these three, their no-reference versions (r1) and their
original-room-painting versions (r2). USD 0.23 for the new runs.

| run | USD | placement | box overlap | objects on ground | jewel palette | cute modern (lower is better) | **style match to the engine render** |
|---|---|---|---|---|---|---|---|
| marketing_guide **+eng** | 0.066 | 0.68 | 0.18 | 0.5 | 8.5 | 3.5 | **7.0** |
| marketing_guide **+hall** | 0.066 | 0.74 | 0.27 | 2.0 | 6.5 | 3.5 | **7.0** |
| qwen_edit_guide **+hall** | 0.075 | 0.80 | 0.32 | 0.5 | 8.5 | 3.5 | 6.0 |
| marketing_guide | 0.065 | 0.80 | 0.32 | 1.0 | 6.5 | 4.0 | 6.0 |
| qwen_edit_guide **+eng** | 0.075 | 0.83 | 0.39 | 1.5 | 8.0 | 3.5 | 4.5 |
| qwen_edit_guide | 0.075 | **0.90** | 0.48 | 0.5 | 8.5 | 5.0 | 4.0 |
| grok_guide **+hall** | 0.090 | 0.76 | 0.29 | 1.0 | 6.5 | 6.5 | 4.0 |
| grok_guide **+eng** | 0.090 | 0.89 | 0.35 | **0.0** | 7.5 | 6.5 | 3.5 |
| grok_guide | 0.090 | **0.90** | **0.51** | 1.5 | 6.0 | 6.5 | 3.5 |

## Reading

- **The engine render did not transfer better than the original painting.** Marketing Studio scores 7.0 with either reference (6.0 with none);
  Qwen scores 4.5 with the engine render but 6.0 with the painting (4.0 with none); Grok stays at 3.5-4.0 whatever it is given. The painting
  and the engine render come from the same hall, so the critics saw them as close to each other; a wide strip with a distorted half is also a
  poor reference, and the models may have taken little from it.
- **What the engine reference did change**: Marketing Studio's picture got a richer jewel palette (8.5) and a darker, more textured room, at the
  cost of placement (0.80 to 0.68); Qwen lost a little placement (0.90 to 0.83) and moved only slightly toward it; Grok ignored it (0.89,
  an empty floor, the same faceted pastel look).
- **Best overall remains** Qwen Edit with the guide (placement 0.90) for control, and Qwen or Marketing Studio **with the original room painting**
  for a look matched to the first room. A reference's value depends on how typical it is: a clean, single-view image of the look would likely
  do better than this strip.
- **The critics disagreed on style here** by up to 4 points on a single picture (placement agreed to 0.004), so style differences under about
  1.5 points are noise.

Reproduce: `compare_models.py run r3 --style-ref IMAGE --tag eng --only grok_guide,marketing_guide,qwen_edit_guide`, `blind r3 --reference
--include-from r1:... --include-from r2:...`, critics, `score r3 a.json b.json`.

## Outcome (the user's choice)

After run r6 the user picked **Marketing Studio + the grey guide + the positive-only master prompt (`ps1p`), no style reference** as the best
result: all of the guide's elements in place, a clear path, golden-hour light, "wickedness" and a faceted low-poly look at a high finish. It is the
default of `new_scene.py`; `assets/painted/garden/` is the garden built from that picture.
