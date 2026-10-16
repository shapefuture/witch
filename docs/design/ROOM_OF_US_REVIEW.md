# What to take from "Room of Us"

Review, 2026-10-15. "Room of Us" is a different product: a Telegram chat archive compiled into an evidence-backed
point-and-click room (Python pipeline, SQLite/FTS5, embeddings, LLM insight compiler, Phaser). This page sorts its
feature list by what transfers to *Witch You Were Here*. The test for each item: does it raise discovery per tap
in a Godot game with an authored, deterministic world and no runtime AI?

## Verdict in one paragraph

Its data pipeline does not transfer (we have no corpus, and the plan excludes a generative runtime). Its
**epistemic and presentation ideas do**, and several are things we already built under other names: the
hash-linked Mirror log is its provenance model, Mirror's claims and hypotheses are its evidence model, and the
Minds layer's "what two minds agree on sticks" is its Third Mind. The useful imports are how it *shows*
knowledge: evidence you can open, reveals in layers, beliefs labelled by how they are known, and a room whose
objects are each a different way of finding things out.

## Already ours (no work)

| Room of Us | Ours |
|---|---|
| G5 event-sourced discovery state | Mirror's event log; every store is a replay (invariant 5) |
| A3 provenance, #4 content hashes, #15 semantic checksum | hash-linked log, save checksum (engine format 7), catalog fingerprint |
| G2 knowledge as the key; old objects gain new meaning | invariants 2 and 10 |
| H5 no reductive profiling, frequency is not affection | invariant 3: expectations, no trust score |
| D4 Third Mind: meaning that belongs to neither person alone | `rule.hall.name` and conventions (a shared reading becomes a custom) |
| J1 offline compilation, byte-identical rebuild | the world compiler (REQ-07) and the deterministic sim |
| L4 no dead ends, every reveal reachable | the H2 validators: reachability, route redundancy, progress-safe responses |
| Sec. 6 "one source, many views" | "Mirror owns meaning": presentation never holds truth |

## Worth implementing

Ordered by value for the cost. **Now** means non-narrative infrastructure; **freeze** means it waits for the
design answers.

1. **Beliefs labelled by how they are known (D5, H1). Now.** The witch's notebook (the satchel, SC1) marks each
   entry as *seen*, *told by someone* or *guessed*, with competing readings side by side and open questions left
   open (`UNRESOLVED_BY_DESIGN` stays visible). Mirror already separates claims from hypotheses; this is a view.
   It makes "revise a model" something the player can see happening.
2. **Every notebook entry can open its evidence (H1). Now.** Tapping an entry recalls the moment it came from:
   the line, who said it, the shot. Each entry carries the event id that produced it, and a test checks that every
   displayed entry resolves to an event (their L2 "every source reference resolves").
3. **Reveals in layers (H2). Now, as a presentation rule.** An object first gets one evocative line, then a
   surprise, then the supporting memory, then the connection. Keeps 480 x 360 plaques readable and paces the "aha".
4. **Each object is a way of finding out (cluster F). Freeze.** Their room gives every fixture a distinct
   epistemic job (library: what is known; telescope: distant links; archaeology: origins; laboratory: combining;
   shrine: shared symbols; mirror: me versus us). The archive hall already has the cast for it: shelves, a globe,
   a statue, the eye glyph. Assign each hall object one discovery mode, so tapping different things feels like
   using different instruments. Decided with HALL and DQ3.
5. **How a custom formed (B3, E3, "evolution wall"). Freeze, engine ready now.** Conventions already move through
   `adopted / stalled / retired / forgotten`. Show the witch the history: the first poke, the reading that flipped,
   the day it became a custom, and earlier meanings kept rather than overwritten. Retroactive meaning made visible.
6. **Failure explained by the world (G3). Now, as a rule.** A wrong SHOW or CAST gets an answer in the world's
   own logic (who objects and why), never "that doesn't work". Cheap, informative failure.
7. **The witch and the raccoon as a Third Mind (D4). Freeze, NQ-c.** Their shared customs (things neither does
   alone) are the game's warmest material and fit the title. A narrative offer, not a decision.
8. **Absurd statistics from the log (G6). Later.** Playful counts drawn from real events ("the globe has been
   poked seven times; the statue now considers this a ritual"). Causal humour, free from the event log, and must
   be marked as a joke, not a claim.
9. **Accessibility (K3). Now.** Settings has volume only (`game/ui/settings_menu_ui.gd`). Add text size, a
   reduced-effects switch for the PSX wobble and the CRT pass (SC6 turns every effect on), and the rule that no
   meaning travels only by animation or sound. That rule matters more for us than for them: `regard` speaks through
   gaze, so a gaze cue needs a subtitle or notebook trace too.
10. **Latency budget as a test (J4). Now.** Their target is under 50 ms for an ordinary interaction. Our action
    cost grows with the event log (save and load about 6 to 7 s at 5,466 events, `docs/engine/BENCH.md`). Put a
    tap-to-commit budget into the bench so it fails a build before it fails a phone.

## Not taking

- The whole ingestion stack (Telegram, GCF, Rust scanner, SQLite/FTS5, embeddings, episode segmentation): no
  corpus to ingest.
- The Oracle telephone and live AI (F8, M1, M6): the plan excludes a generative runtime from the shipped core, and
  open questions break the authored, testable world.
- Phaser and React: we are on Godot, with diegetic 3D slabs, not overlays.
- A separate feature registry: the requirement register and beads already do that job.
- Privacy and curation workflow: no personal data in this game.

## The one principle worth keeping above the rest

Their closing line fits us exactly: make the intelligence invisible enough that the room feels alive, and keep the
evidence reachable enough that its discoveries can be trusted. For us, the Minds layer is the invisible
intelligence, and the notebook with openable evidence is how its discoveries become trustworthy.

## The code: `shapefuture/room_engine` (reviewed 2026-10-16, commit 15d9159)

The implementation is a zero-dependency Node compiler (Telegram JSON to a sealed, content-addressed "cartridge"),
a canvas room, a 41-check behavioural gauntlet, and optional embedding enrichment. Read, not run. What it adds
beyond the feature list above:

### Take

1. **A theater audit of our own tests. Now.** Its QA report names "theater": checks that pass without testing the
   behaviour (source-grep checks, a smoke test that exercised nothing, a cap the fixtures never exceeded so a
   critical bug hid behind it). We have found two of these ourselves this week: the character test that asserted
   nothing, and the hair test whose "orange" predicate matched the skirt's gold stars. A fresh agent should sweep
   the 51 suites for assertions that can pass vacuously, fixtures that never reach a cap or limit, and checks that
   read source instead of behaviour.
2. **Negative tests for emergence. Now (small).** Its hard rule: shared meaning needs evidence from *both* voices,
   and a corpus with two speakers but no overlap must yield zero emergence candidates. Our counterpart is
   `rule.hall.name` (one mind repeating changes nothing) and the statue custom that stalls forever. Make the
   negative explicit across the Minds data: for every convention, a sim in which only one mind reads it, which
   must leave the convention unformed. Cheap, and it guards the property that makes customs mean something.
3. **Discovery classes with a diversity rule. Now, as data and a linter.** It types every discovery (humour,
   curiosity, relationship, contradiction, evolution, memory, lore, emergence, echo, ...) and selects
   round-robin by class so the shown set is never ten of one kind. For us: a `class` field on authored
   hypotheses and reveals, a per-room report of which classes exist (meaning density, `ALIVENESS.md` section 5),
   and a pacing rule for the notebook so it surfaces a mix.
4. **Echoes as rhymes across distance. Later, authored.** Its "echo" is two moments far apart (five or more
   days) that share meaning but almost no words. Our hall echo is the same move made later in the same room. A
   deterministic version fits Mirror: authored motif tags on events; when the player meets a motif again in a
   different room and form, the notebook notes the rhyme. Retroactive meaning without any runtime AI.
5. **Recover the valid prefix, and say so. Engine, check first.** Its compiler salvages complete records from a
   truncated export, marks the result `truncated`, and refuses under `--strict`. Our event log is hash-linked, so
   the longest valid prefix is well defined. If a damaged save and its `.bak` both fail today, loading that prefix
   with a visible "recovered" state is better than losing the game. Check `docs/engine/HARDENING.md` for what H1
   already does before building it.
6. **The tool for the tone study.** The compiler already reads this exact export format (Telegram Desktop JSON,
   Russian stemming, a background-word model, episodes by cohesion, humour and recurring-phrase candidates). For
   the private tone reference (option c), run it in the scratchpad on the archive and read its candidates; its
   output never enters this repository.

### Already ours

Content addressing and fail-closed loading (the catalog fingerprint binds saves), byte-identical recompiles (the
world compiler's REQ-07 acceptance), behavioural gauntlet and honest "not executed" labels (the gate, the CI note
before its first run), a knowledge-gated door (invariant 10).

### Not taking

GCF sidecars and sharded boot (our catalog is small), the embedding providers (no runtime AI, and the tone study
can run the compiler as is), the service worker and PWA, and the canvas room.
