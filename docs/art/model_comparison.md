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
