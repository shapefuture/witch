# Making the game alive

Analysis, 2026-10-15. The lens is the "alive experiences" synthesis the user supplied
(`docs/design/references/alive_experiences_skill.md`: Humongous, LucasArts, Myst, Outer Wilds, The Sims, Animal
Crossing, Psychonauts, Journey and others). It is read against the game as it is built, not as a wish list.
Pre-production: nothing here is built yet. Items marked **now** are non-narrative infrastructure. Items marked
**freeze** need the design and narrative answers (`PREPRODUCTION.md`).

## 1. The finding in one paragraph

The game already owns the hard part. The skill's thesis, "the strongest progression is a changing mental model",
is this repo's founding rule (`DESIGN_INVARIANTS.md` 2 and 10: knowledge changes what an action means; you revise
a model, you do not obtain a key). Mirror is a player-model engine: claims, hypotheses, a discrepancy vector. The
Minds layer is a world-autonomy engine: witnesses, per-mind readings, consequences that fall due later, and
customs that form from repeated readings. The hall's three rules (echo, regard, name) recombine, which is the
Sims lesson in miniature. So aliveness will not fail for lack of theory or systems. It will fail at three
places: **the systems are not running in live play, their state is invisible, and there are too few things to
notice.** Fix those three, in that order.

## 2. What we already have, mapped to the skill

| Skill mechanism | Ours | Where |
|---|---|---|
| Knowledge as progression (Outer Wilds) | options unlock from revised models, never from items | invariants 2, 10; `requires_models` |
| The world answers back | `rule.hall.regard`: whatever moves is looked at, at once | `data/mirror/minds/world_rules.json` |
| Continuity, autonomy | deferred consequences on the Mirror clock; `rule.hall.echo` answers late | `MINDS.md` 3 |
| Emergence (The Sims) | rules whose consequences trigger each other (regard x echo, name x echo) | `MINDS.md`, the hall rules |
| Player-made culture (Animal Crossing, Goose) | a shared reading becomes a custom; customs patch rules | `conventions.json`, `rule.hall.name` |
| Characters with needs, not scores | expectations (`EXPECT_MAGIC`, `EXPECT_PERMISSION`...), no trust number | invariant 3 |
| Cheap, informative failure | every wrong path has a way back; a contradiction is a model revision | invariant 9 |
| Cheap action, expensive understanding | magic raises outcome certainty and lowers motive certainty | invariant 8 |
| Small verbs, rich consequence | six hidden verbs, shown as sentences | invariant 1, DQ2 |
| Environment as evidence (Myst) | fixed camera over painted plates, Alone in the Dark lineage | `NAVIGATION.md` |
| An open question | `why_tomas_withdrew` is `UNRESOLVED_BY_DESIGN` | invariant 8 |

Checked against the skill's "minimum viable alive experience" (section 95), the hall is close: one place, a
handful of entities (witch, raccoon, Tomas, globe, statue), one open question, three learnable rules, a persistent
change (a custom), one relationship. Missing: a retroactive revelation and an emotionally meaningful consequence.

## 3. The three gaps

### Gap 1: the engine is offline in play

The Minds layer runs in tests and in the headless sim (`data/sim/hall_rules.json`), not in the game.
`LiveHallCoordinator` is built; its wiring into `game_root.gd` is not (REQ-01, beads witch-29y.9.1). Until it is
wired, the player meets Mirror's actions and Tomas, and none of the echo, regard or customs. **This is the single
largest aliveness lever, and it costs the least design.** It is gated by HALL and DESIGN-FREEZE only because the
hall may not survive. Proposal: wire it into the hall as the demo now, since the coordinator talks to the room
slot and moves to whatever room replaces the hall.

### Gap 2: the state is invisible

A mind's reading ("tampering", "play", "blame") lives in the event log. The skill's failure tree names this "a
system without soul": systems generate possibilities, characters make them mean something. Invariant 6 already
requires that important effects are observable; aliveness needs more than that. **The player must see minds
disagree.** Channels we have or can build cheaply:

- **Gaze.** The `regard` rule needs a look-at: heads (and the statue) turn toward what moved. We have no head
  look-at today (the models have idle, walk, talk and one clip of their own: cast, work or watch). For crude PS1 faces, gaze and posture
  carry nearly all the expression, so this is the highest-value presentation feature in the game.
- **Attributed late answers.** An echo that lands three ticks later reads as random unless the player can trace
  it back ("unexpected but earned", section 24). Cue the cause when a deferred consequence falls due: someone
  looks at the origin, and the same sound motif returns.
- **The satchel as the witch's notebook.** SC1's letter cabinet should hold her hypotheses and surprises in her
  voice ("Tomas went quiet when I fixed it. Why?"), never tasks. Mirror's claims, hypotheses and discrepancy
  vector are exactly that content. The rule from the skill (section 58): no quest list.
- **Options that change wording.** Invariant 2 already rewrites an option when knowledge changes ("Look more
  closely" becomes "Look at the gear Tomas described"). That rewrite *is* the "aha" made visible. Design for it
  on purpose: every important object gets at least one option that rewrites itself.
- **The raccoon (NQ-c).** The planned tele-somatic channel is the natural instrument for showing hidden mental
  states without exposition: the raccoon's body reacts to what others feel (Psychonauts: an inner state made into
  something you can see). This is a narrative call, offered here as the strongest option.

### Gap 3: there are too few things to notice

One demo room and one authored hypothesis (`data/mirror/hypotheses.json` holds one entry) give a small
possibility space. The cure is not more content but more links between a few things (sections 25, 114):
twelve objects that relate to each other beat a hundred that do not.

## 4. Rules to adopt (proposed design invariants)

1. **Every tap answers.** Anything tappable gives an immediate reaction (a Humongous clickpoint) without opening
   a menu. Option plaques are kept for real choices. The first happening is already "poke a prop" (X7).
2. **Taps should teach.** Prefer reactions that are expressive *and* informative (skill section 5: action,
   reaction, information). A reaction that teaches nothing is allowed only if it is short and characterful.
3. **Nothing mutable is painted.** Plates cannot change, so anything the world can change (props, light,
   doors) is a real-time object. Otherwise the room looks alive and nothing can matter (the hollow world).
4. **Waiting is a discovery verb.** WAIT ("Hang back and watch") is our LEGO Island and Animal Crossing verb.
   Rooms keep routines on the Mirror clock, so watching reveals what poking cannot.
5. **Late answers are traceable.** Any deferred consequence that the player sees carries a cue to its cause.
6. **The notebook holds questions, not tasks.**
7. **Every important object has a knowledge-gated rewrite**, and at least one link to another entity.
8. **Weirdness is local.** A legible room with one wrong thing in it, not a strange room (safe weirdness,
   section 55). This also fits the jewel palette: the anomaly carries the most saturated colour.

## 5. Measure it like the budgets

The repo turns quality into tests (triangle budgets, the four-laws linter, golden transcripts, the visual
gauntlet). Aliveness can be measured the same way, from the deterministic sim, with no new runtime:

| Metric | Definition (computable from a sim transcript) |
|---|---|
| Possibility density | tappable things in a room x share with at least two distinct responses |
| Attention return | share of taps that change a claim, an option wording, a mind's reading or the world |
| Link density | authored edges between entities (rule roles, hypothesis evidence, option prerequisites) per entity |
| Retroactive links | discoveries that rewrite an option or note on an object met earlier |
| Dead taps | taps that change nothing and teach nothing (should trend to zero) |

A linter in the style of the four laws can check rules 1, 5 and 7 on the catalog. A report from the sims can
track the rest per room, the way `BAR.md` tracks the hall's light.

## 6. What to do

### Now (non-narrative infrastructure)

1. Head and eye look-at for every character and the statue, driven by `regard` (procedural bone rotation; no
   new clips).
2. A cue for deferred consequences (look at the origin, reuse the sound motif).
3. The satchel's notebook view as a presentation of Mirror's claims, hypotheses and discrepancies.
4. An "aliveness linter" over the catalog (every tappable object answers, has a knowledge-gated rewrite, and
   links to another entity) and the metrics report from the sims.
5. Ambient routines on the Mirror clock, so WAIT has something to reveal (the engine side; the routines
   themselves are content).
6. Wire the live coordinator into the hall as the demo (needs a yes on HALL being used as the testbed).

### At the design freeze (feeds the open questions)

- **DQ1 and NQ-a**: state the world question as something the player can *investigate*, not be told.
- **DQ3 and NQ-g**: plan the rooms as a curiosity cascade: each room answers one question and opens a larger one.
- **DQ4**: an ending that re-reads earlier moments. The path-out contract (the world stays unresolved, the camera
  stays) already fits Kentucky Route Zero's "agency as interpretation".
- **NQ-b**: give Tomas, Vera, Elian and Ilya a *need* each, not a function. Helping is progression (section 17).
- **NQ-c**: the raccoon as the channel that shows feelings (above).
- **NQ-f**: tone. Humour should be causal (the witch's pokes, the customs she starts), not jokes in dialogue.

## 7. What to avoid

- **False interactivity**: a line for every object that teaches nothing teaches that nothing matters.
- **Quest-list colonisation** of the satchel.
- **Over-explaining**: `UNRESOLVED_BY_DESIGN` is a feature; keep some motives unresolved.
- **Animation instead of state**: idle loops on the plates do not make the room alive; state, memory and
  response do.
- **Scale before links**: a second room before the hall's dozen objects link up spreads the same thinness wider.
