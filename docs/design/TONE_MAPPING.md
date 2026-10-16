# Tone onto systems

How `TONE_GUIDE.md` lands in the game, 2026-10-16. Everything marked **guess** is an educated guess made on the
user's instruction, to confirm or change at the design freeze (`docs/PLAN.md`, decisions X13 to X20).

## 1. The fit

The guide's core claim is that chemistry is *shared possibility made visible*, and that in-jokes become customs by
a fixed path: candidate, activated (the other plays along), stabilised (reused), crystallised (repertoire). The
Minds layer already models exactly that path: a reading, a second mind sharing it, repeated readings, a
convention (`rule.hall.name`: what two minds agree on sticks). So the tone is not a coat of paint: it is the
content model for the conventions the engine already runs.

## 2. Cast and voices (guesses)

| Guide | Game | Status |
|---|---|---|
| The pair, two voices with rotating straight-man role | **the witch and the raccoon** | guess (X15) |
| Offering voice (thesis-bearer, feeder of material) | the witch: she pokes, casts, proposes | guess |
| Answering voice (prober, crown-giver, archivist) | the raccoon: repeats the poke, crowns it, remembers it | guess |
| The Oracle, a third player in the straight-man slot | **the hooded statue** in the hall (consulted, teased, blamed); any room may have one | guess (X16) |
| Warmth asymmetry (anticipation versus respect-granting) | the witch pre-answers; the raccoon grants esteem in its own body language | guess |

The raccoon's planned tele-somatic channel (NQ-c) then has a job: it is how the Answering voice *crowns* a bit and
how the player sees another mind's feeling without exposition.

## 3. Customs onto the Minds layer

The guide's fifteen customs (section 13) become candidate conventions in `data/mirror/minds/conventions.json`
after the design freeze. Each needs an origin (event kinds), a reading two minds can share, and a bound
(the four laws). Shape of the mapping, not content:

| Custom | Event it grows from | What the convention changes |
|---|---|---|
| The Coinage Rite | the witch names an object | the name sticks; options and lines use it |
| The Tribunal of Words | the witch and the raccoon disagree about a word | a one-word verdict line; laughter closes it |
| The Petty Bureaucracy | a repeated small act (the same prop poked daily) | the room treats it as an official rite |
| The Dispute Rite | a contested reading between two minds | resolves by shared laughter within about four beats, never by one mind conceding |
| The Repair Rite | a misfire (an unwelcome cast) | marker, self-irony, laughter; raises tolerance for the next risk |
| The Oracle | the statue consulted | the statue holds the straight-man slot |
| The Two Clocks | any convention | sprint customs return in days, bell customs in months, each may resurrect once |

## 4. Rules that become engine or presentation work (non-narrative, now)

1. **Convention clocks.** Conventions get a cadence class (sprint or bell), a dormancy after which they fade, and
   at most one unexplained revival. The engine already has `forgotten`; this adds the clock and the revival.
2. **Never explain a callback on revival.** When a dormant custom returns, no line restates its origin. The
   notebook may hold the history (`ROOM_OF_US_REVIEW.md` item 5); the scene does not.
3. **No verbal concession.** NPC response policy has no "you were right" outcome; disputes end in a shared beat.
   Checked by a linter over dialogue keys and response contracts once content exists.
4. **Warmth after the laugh.** Presentation orders a reaction's beats: the comic beat first, the warm beat one
   beat after, never in the same line.
5. **Goof, never roast.** Every teasing line needs a visible safety catch (a play frame); a review rule for authors.
6. **Mode, not topic.** Any object can be the play-object: every tappable object should admit one playful and one
   serious reading (feeds the aliveness linter).

## 5. Other guesses taken now

| ID | Guess | Why |
|---|---|---|
| X13 | The archive hall is the testbed for the live coordinator and the aliveness work now; whether it ships stays a freeze question | the coordinator talks to the room slot, so the work moves with it |
| X17 | The witch's brows are repainted in the face tile to match the ash-blond hair | the photo tile still carries the old orange |
| X18 | Embeddings are offline tools only (NIM, `tools/embeddings/`), never in the shipped game | the no-runtime-AI rule |
| X19 | The tone guide's customs become Minds content after the freeze | content waits for the narrative; the engine rules above do not |
| X20 | The non-narrative tasks from `ALIVENESS.md`, `ROOM_OF_US_REVIEW.md` and this page proceed now | the user asked for the plan executed |

## 6. Built (stream L, 2026-10-16)

| Rule | Status | Where |
|---|---|---|
| 1. Convention clocks | built: cadence (sprint, bell; guessed values), dormancy, one revival | `game/mirror/minds/convention_book.gd`, `data/mirror/minds/minds.json` clocks, `tests/mirror/test_minds_clocks.gd` |
| 2. Never explain a callback on revival | built for the engine: the revived change carries only its id and kind, and writes no new claim; the origin is kept, not re-announced. The presentation of a dormant custom's return is content | `tests/mirror/test_minds_clocks.gd` |
| 3. No verbal concession | linter over every string of the authored catalog (`ToneLint`); a dispute ends in a shared beat, by content rule | `game/mirror/minds/tone_lint.gd`, `tests/mirror/test_tone.gd` |
| 4. Warmth after the laugh | the beat order and its checker (`ReactionBeats`); live dialogue does not use it yet (no reaction beats are authored) | `game/presentation/reaction_beats.gd`, `tests/presentation/test_reaction_beats.gd` |
| 5. Goof, never roast | an author rule: every teasing line needs a visible play frame. No teasing lines are authored yet, so nothing can be checked | (author review, at content time) |
| 6. Mode, not topic | an author rule, to feed the aliveness linter; the linter's "answers" rule already requires a response per tappable; the playful and serious readings are content | `game/mirror/aliveness_lint.gd` |

Customs (the fifteen in section 13 of TONE_GUIDE) and the voices (the raccoon answers, the statue is the Oracle) are
content and wait for DESIGN-FREEZE (X19); the engine above is ready for them.

