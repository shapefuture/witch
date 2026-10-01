# Critic prompt (blind A/B)

For the lead, not the critic. Prepare the pair, then hand a **fresh** subagent the text between the
two `---8<---` lines with `{{A}}` and `{{B}}` replaced by absolute paths. This does both:

    python tools/visual_gauntlet/blind_ab.py ours.png bar.png /scratch/abN --print-prompt

Keep it blind:
- Use a clean frame: no speech bubble, plaque or other UI. UI alone gives the source away.
- Add nothing to the prompt: no project name, round number, earlier verdicts, art notes, or file
  names other than `A.png` / `B.png`. Do not say which is which, or that one of them is a target.
- The key (`<out_dir>_KEY.json`) stays out of the critic's folder; read it only after the verdict.
- One critic per pair. A critic that has seen an earlier pair is no longer blind.
- `blind_ab.py --selftest` checks this prompt for words that would give a source away.

Parse the JSON block at the end of the reply. A region score is 1-10; `portfolio_pick` is "A" or "B".

---8<---
You are judging two still images, A and B, as a senior art director who also sits on real-time
graphics juries. Judge only what is in the pictures. Do not try to work out where either image came
from or how it was made, and do not let a guess change your scores.

Open exactly these two files and nothing else (no other files, no metadata, no web):

  A: {{A}}
  B: {{B}}

Look at each image at full size. Then squint, or imagine each one as a thumbnail, and look again:
the big value shapes matter as much as the detail.

Both show a similar interior. Score each image from 1 to 10 in five regions (1 = broken,
4 = amateur, 6 = competent, 8 = portfolio grade, 10 = best in class). Positions are for a 16:9 frame:

- frame: the outer ring along all four edges. Does it hold the eye inside the picture, with
  foreground masses and depth, or is it empty, flat, noisy or cut off?
- shelves: the tall walls in the left and right thirds. Readable forms, believable material,
  rhythm, value grouping, how they sit back in space.
- arch_passage: the pointed arch left of centre and the space seen through it. Depth, atmosphere,
  a believable place beyond.
- beam: the shaft of light from the opening in the vault and where it lands. Does it read as light
  (volume, falloff, scattering, a glow where it lands), or as a flat shape stuck on top?
- statue: the tall hooded figure right of centre. Silhouette, form, how it sits in the light.

If a region is missing or unreadable in an image, score it 1 and say so in one line.

Then answer:

1. Portfolio pick: if you could put only one of the two in a portfolio, which one? A or B. No ties,
   no "it depends".
2. The single biggest gap of the image you did not pick: the one change that would most narrow the
   distance to the other. Be concrete (where in the frame, what is wrong, what it should become).
   One gap, not a list.
3. For each image: would a SIGGRAPH real-time-graphics jury accept this frame? Answer yes or no.
   If no, why not: the specific artistic and technical reasons a juror would give.

Be blunt and specific. Do not hedge, and do not assume either image is finished or unfinished.

End your reply with exactly one JSON block of this shape:

```json
{"scores": {"A": {"frame": 0, "shelves": 0, "arch_passage": 0, "beam": 0, "statue": 0},
            "B": {"frame": 0, "shelves": 0, "arch_passage": 0, "beam": 0, "statue": 0}},
 "portfolio_pick": "A or B",
 "loser_biggest_gap": "one concrete sentence",
 "siggraph": {"A": {"accept": false, "why_not": "..."},
              "B": {"accept": false, "why_not": "..."}}}
```
---8<---
