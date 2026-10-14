# Witch You Were Here: plan of record

Status: working plan, not committed. **Task status lives in beads only** (`bd ready`, `bd list`, `bd show <id>`).
This file holds the requirements, the decisions, the workcell boundaries and the integration rules. It holds no
status, so it cannot drift from the tracker.

Baseline: branch `claude/loving-brown-whtlm0` at `243230b` (main). Gate at baseline: red on one vacuous test (REQ-20).

Tracker: beads root epic `witch-29y`, with ten stream epics and 60 items in all, 63 dependency edges. Run
`bd ready` for the next work. At creation, batch 1 is ready: A1, H1, H2, B1, D3, G1.

## 1. Outcome

A playable, Russian-only diorama adventure in which the Minds layer runs during live play. The player goes
hall (room 1) → painted room (room 2) → path out, with a main menu, a full ending, and the cast placed in rooms.

Done means: the gate passes on a clean checkout, the playthrough above works through the UI, every REQ below is
accepted with recorded evidence, and the open decisions are closed.

## 2. Requirement register

Each REQ maps to one or more beads tasks through the `req:REQ-nn` label. A REQ closes only when every mapped task
closes with evidence and the integrated gate passes.

| REQ | Requirement | Source | Today |
|---|---|---|---|
| REQ-01 | Minds coordinator live in the hall (happenings reach `Mirror.minds.perceive`) | CLAUDE.md, MINDS.md | not built: `PropEvents.attach` used only by tests |
| REQ-02 | Gossip: interpretation rules read other witnesses' accounts | MINDS.md | not built |
| REQ-03 | Conventions spread between communities | MINDS.md | not built |
| REQ-04 | UI for the witch's knowledge of a custom | MINDS.md | not built |
| REQ-05 | Raccoon tele-somatic perception channel | CLAUDE.md, MINDS.md | empty anchor `placeholders.gd:78` |
| REQ-06 | Town graph | CLAUDE.md | not built |
| REQ-07 | World compiler from place resources | CLAUDE.md | not built |
| REQ-08 | LimboAI | CLAUDE.md | decision X1 |
| REQ-09 | On-device mobile profiling | CLAUDE.md | headless probe only; needs a phone |
| REQ-10 | Main menu (diegetic, pointer only) | CLAUDE.md | not built; game boots into the hall |
| REQ-11 | Full ending (`go_path_out` → ending → credits → menu) | CLAUDE.md, DESIGN_INVARIANTS | only the path-out action exists |
| REQ-12 | Shadow, shadow_lady and witch_antler placed in a room | CLAUDE.md | built as GLBs, not placed |
| REQ-13 | Vera, Elian and Ilya | CLAUDE.md | Vera: generated design in `docs/art`, not in game; Elian and Ilya: none |
| REQ-14 | Painted room runs as room 2 with PropEvents reactions | CLAUDE.md | `walked` is emitted; the room is not in the game |
| REQ-15 | Round 9: grade pass on the hall plates | `docs/visual-gauntlet/rounds.json` | not started |
| REQ-16 | Round 9: wider nave, vault, nested arches, lit stair | same | not started; needs decision X6 |
| REQ-17 | Reference hall image in the repo | CLAUDE.md, BAR.md | **missing: user input** |
| REQ-18 | `pixel.ttf` licence recorded | CLAUDE.md | **unknown: user input** |
| REQ-19 | Delete the quarantined `Scenes/` | CLAUDE.md | pending |
| REQ-20 | Gate green at HEAD | GAUNTLET.md | red: `test_a_character_added_later…` makes no assertions |
| REQ-21 | Continuous gate (CI) | none in repo | no `.github/` |
| REQ-22 | Engine hardening (saves, validators, test depth, bench) | draft mirror-engine upload | not started |
| REQ-23 | Stale docs corrected to match code | audit | pending (see section 9) |
| REQ-24 | Character "still off" items | `docs/art/characters_*.md` | pending; judgement needs REQ-26 |
| REQ-25 | `claude/upbeat-fermi-trp4xm` merged or dropped | git | 2 commits unmerged, tools and docs only, flag off |
| REQ-26 | Concept sheets in the repo as judging bars | characters docs | **missing: user input** |

Explicit exclusions (none chosen yet): a generative AI runtime (the spec forbids it in the shipped core); Popochiu
(the draft lists it as unexercised; we don't use it).

## 3. Decisions

Each decision is a beads item of type `decision` (epic `witch-29y.10`). The default is what proceeds if you say
nothing, and a decision whose default proceeds **does not block work**. Only three gate anything: X4 (blocks G4, the
blind verdict), X5 (blocks shipping) and X11 (blocks any push).

| ID | Question | Default (proceeds) | Alternative |
|---|---|---|---|
| X1 | LimboAI | **defer**; the Minds layer and Mirror decide NPC behaviour; document in ARCHITECTURE | vendor 1.8.1 (the draft has a runtime-tested blackboard guard, but its binaries are Linux x86_64 only and the game is mobile-first) |
| X2 | Vera's design | **keep** the generated design and its rig (8,998 triangles, two surfaces, jug on `hand.L`) | new design |
| X3 | Elian and Ilya's canon | **start from** the draft's fixture behaviour (Elian accepts help; Ilya is friendly when asked, and is startled by an unasked CAST), marked as placeholder canon | write your own |
| X4 | Reference hall image and the concept sheets (REQ-26) | supply `docs/visual-gauntlet/bar/reference_hall.png` and the sheets | none: the blind verdicts stay pending |
| X5 | `pixel.ttf` licence | supply the provenance | none: blocks shipping, not development |
| X6 | Hall geometry route (G2) | **re-bake** in Blender (exact occlusion, about 40 s) | paint the new art over the existing proxy (faster, occlusion fitted by hand) |
| X7 | First happening in the live hall | **poke a prop**, with echo, regard and name as the three hall rules | another verb |
| X8 | Raccoon eyes | **keep open** (deliberate deviation from the sheet, per the characters doc) | closed arcs as drawn |
| X9 | Painted room | **room 2**, reached by a GO edge from the hall | cut it |
| X10 | Upbeat branch (REQ-25) | **merge** (tools and docs only, flag off) | drop |
| X11 | Persistence of beads state (see section 10) | **commit a JSONL export** of the tracker with the work | Dolt remote push, or keep local only |
| X12 | Full `full-plan-delivery` bundle | **not installed**: practices only, from the references | install the bundle (writes AGENTS.md, Claude hooks, a Python package) |

## 4. How the work runs

- **One task authority:** beads, prefix `witch`, embedded Dolt. No markdown task list anywhere.
- **Coordinator-only tracker writes:** workers report back; the coordinator records status, evidence and candidate
  identity in beads. Workers never write the tracker. (AAA 11A.3: task events are append-only, written by one party.)
- **Workcell per stream:** a git worktree at a pinned base commit, under `/home/user/witch-wt/<stream>`, on branch
  `wc/<stream>`. Shared checkout is not used for parallel work: two agents in one tree is the failure mode AAA
  forbids (11A.3). Each worktree gets its own `.godot/` cache, so the first import per worktree is slower.
- **Write set declared up front** (section 5). A worker writes only inside its write set. Anything else goes to the
  integrator as a request.
- **Candidate-only integration:** the integrator (the coordinator) merges candidates in dependency order into the
  integration branch. No worker writes there (AAA 11D).
- **Independent verification:** a fresh subagent that did not build the candidate runs the gate in a clean worktree,
  checks the diff against the acceptance text, and reports. Builder and reviewer are never the same agent.
- **Verification rung declared per task** (AAA 22): unit or contract (4), property (5), contract compatibility (6),
  replay or golden (7), deterministic sim (9), independent evidence (15). A task states which rungs it needs.
- **Gate:** `GODOT=<4.6.3> ./tests/run_tests.sh` must print `GATE PASS`. Never trust exit codes (CLAUDE.md).
- **Visual and character work uses the gauntlet loop** (section 6): a named, fetchable bar; a blind pairwise pick
  by a harsh critic with fresh context; exit when the critic picks ours; no round count.
- **Text:** workers add keys to their own fragment file (`data/text/ru.<stream>.json`). The integrator merges them
  into `data/text/ru.json`. No Cyrillic outside that file (`test_text_single_source`).
- **Goldens:** workers never regenerate goldens. The integrator regenerates once, after all behaviour changes, and
  reviews the diff, because a golden change is a statement about game behaviour.

## 5. Workcells and write sets

| Stream | Write set | Reads | Notes |
|---|---|---|---|
| A Gate and housekeeping | `tests/render/test_character_models.gd`, `Scenes/`, `.github/workflows/`, doc files named in section 9 | everything | owns the stale-doc edits; CLAUDE.md edits go to the integrator |
| H Engine hardening | `addons/mirror_engine/**`, `game/save/**`, `tests/save/**`, `tests/mirror/test_engine_*`, `tools/bench.gd`, `tools/soak.gd` | `data/mirror/**` | save format changes reset old saves (acceptable before release) |
| B Live coordinator | `game/world/archive/**` (not `game_root.gd`), `game/mirror/prop_events.gd`, `game/mirror/coordinator.gd` (new), `tests/mirror/test_live_hall*` (new) | `game/mirror/minds/**` | hall rules: echo, regard, name |
| C Minds gaps | `game/mirror/minds/**`, `data/mirror/minds/**`, `game/ui/knowledge_*` (new), the RaccoonLink anchor in `game/world/placeholders.gd`, `tests/mirror/test_minds_*` | B's coordinator | four-laws linter must pass |
| D World | `game/world/town/**` (new), `data/world/**` (new), `game/world/room_slot*` (new), `game/world/painted/**`, `data/mirror/actions/go.json`, `data/mirror/world.json` | H's validators | D is the only writer of catalog files; it changes the fingerprint |
| E Cast | `game/npc/**`, `tools/characters/**`, `assets/characters/**`, `data/text/ru.E.json` | D's room anchors | E4 (budgets test) waits for A1 |
| F Shell | `game/ui/main_menu*` (new), `game/main/ending*` (new), `data/text/ru.F.json` | D's GO edge, C3's diegetic base (read-only) | |
| G Art | `tools/blender/**`, `assets/archive/**`, `tools/visual_gauntlet/**`, `docs/visual-gauntlet/**`, `tools/grade_plates.py` (new) | `docs/visual-gauntlet/BAR.md` | section 6 |
| I Integrator | `game/main/game_root.gd`, `data/text/ru.json`, `tests/golden/**`, `project.godot`, `export_presets.cfg`, `CLAUDE.md`, `docs/ARCHITECTURE.md`, `.github/` (merge) | all | only the coordinator writes here |

**Parallel batches.** Batch 1 starts now: A, H, B, G1 and D3 (the slot contract, which touches no shared file).
C's units start with B. D1 waits for H2 (validators). Batch 2: C1–C4 once B1 lands; D2 and D4 once D1 and D3
land; E1–E3 after D4; F1 now, F2 after D4. Batch 3: G2–G4 after the decision and the reference image.

**Integration order:** A → H → B → C → D → E → F → G3 and G4 → I1–I5.

**Room slot (AAA P13).** The room is a component slot. Its contract: `walked(pixel, world)`, walkable mask,
occluders, anchors, reaction requests, cut shots, and the Mirror room id. `ArchiveHall` and `PaintedRoom` both
implement it. A compatibility suite runs both. `game_root.gd` is the only composition root that names a concrete
room.

## 6. Revised stream G (art)

The Blender bake is needed only for the geometry, so the work splits.

- **G1: grade pass, no bake.** Darken and olive-grade the existing plates with a 2D colour script
  (`tools/grade_plates.py`), re-import, and capture the standard frames (`tools/visual_gauntlet/capture.sh`).
  Measure against the numbers in `BAR.md`: median luma 0.16, 99th percentile 0.63, saturation 0.58. This runs now.
  The blind critic's verdict stays **pending** until X4 supplies the reference image. The numbers are a proxy and
  must not be reported as a win.
- **G2: decision X6** (re-bake or paint over the proxy). Default is re-bake.
- **G3: geometry** (wider nave, vault visible, nested arches, lit stair) by the chosen route. Re-bake regenerates
  plates, proxy and anchors together, so the walk mask and occlusion cannot drift apart. Then the gate, and the walk
  and anchor tests.
- **G4: gauntlet exit.** A fresh-context harsh critic gets our frame and the reference, labels stripped, and picks
  the better one, then names the single biggest gap. The builder fixes that gap. Repeat per piece (grade, nave,
  vault, arches, stair) until the critic picks ours. No round count. Log each round in `docs/visual-gauntlet/rounds.json`.

## 7. What the three references changed

- **robonuggets/gauntlet-loop.** Adopted: a named, fetchable bar; a separate harsh critic with fresh context; blind
  A/B with labels stripped; a binary pick; the exit is winning the comparison, not a round count; a live progress
  record. Applied to G and to E4. Blocked on X4 and REQ-26, because the repo has the rules but not the images, and
  CLAUDE.md says to judge against the image, not a description.
- **shapefuture/ArchetypeAI, `full-plan-delivery`.** Adopted: the requirement register mapped to tracker tasks; a
  declared acceptance record per task (evidence reference, candidate identity, a reviewer who is not the builder);
  coordinator-only tracker writes; a handoff note at every session boundary; the rule that a markdown task list is
  never kept; a plan file that holds specification, not status. Not adopted: installing the bundle (X12). It is a
  Python package that writes AGENTS.md and hooks, and I'd ask before doing that.
- **shapefuture/AAA-Architecture, AAA v7.1.** Adopted as principles: no shared mutable workspace (worktrees per
  stream); a write set per workcell and a conflict check before parallel work; candidate-only integration;
  independent verification in a clean environment; the verification ladder as acceptance rungs; the room as a
  swappable slot (P13); complexity that must pay rent (P11), which is why LimboAI is deferred and the engine split
  is deferred. Not adopted: the starter schema and YAML manifests, which the spec itself calls a starter, not a
  validator.

## 8. Engine hardening (REQ-22), from the draft upload

The draft passed its own suite on Godot 4.6.3: 426 tests and 3 Dialogue Manager tests, all green. Port the parts that
add something ours lacks; keep our Minds-specific engine. Measurable half, per the gauntlet: our action cost against
the draft's bench (8.4 ms p50 at 5,000 events on its machine). Measure both on the same machine before comparing.

Ports, in order: save checksum, atomic write and `.bak` (H1); validators for reachability, route redundancy,
progress-safe responses and the diagnostic-vocabulary lint, run over `data/mirror` (H2); the `StringName` hash spike
(H3); bundle fuzz and property tests (H4); bench and soak (H5). Optional, behind a rent check: run diff and sandbox
(H6). Deferred: splitting `mirror_engine.gd` into modules (H7), until the goldens are stable.

## 9. Stale docs (REQ-23), from the audit

- `README.md:18`: "the characters are placeholders". They are real models.
- `docs/PROVENANCE.md:84` and `docs/ARCHITECTURE.md:85`: "every model is a primitive". Not true.
- `docs/MINDS.md:150`: "the room does not yet emit `walked`". It does (`painted_room.gd:398`).
- `docs/art/characters_witch.md:146` and `characters_tomas.md:101-110`: "not wired". Both are wired.
- `CLAUDE.md` "not built" line: `walked` is emitted now; only the PropEvents wiring is missing.
- `docs/art/characters_witch.md`: its triangle count (8,016) is stale against the 6,500 test budget; verify before editing.

Each correction is checked against code, and the evidence goes in the task's acceptance record.

## 10. Persistence of the tracker

Beads state is in `.beads/` (embedded Dolt). The container is ephemeral, and anything not committed or pushed is
lost when it is reclaimed. So the tracker is durable only once X11 is decided. Until then, the beads database is
local to this session. I ran `bd init` and it committed the beads files; I undid that local commit, so nothing has
been committed. The Dolt sync remote it configured (`github.com/shapefuture/witch`) is cleared, so nothing syncs
outward without your decision.

## 11. Guesses to check

- Upbeat is merged (X10). Vera is kept as she is (X2). Elian and Ilya follow the draft fixture (X3). The first
  happening is a poked prop (X7). Painted room is room 2 (X9). LimboAI is deferred (X1). Re-bake is the geometry
  route (X6).
- Shadow, shadow_lady and witch_antler are placed in room 2, and Vera with them. Their locations are not
  designed. This is a guess, not a decision.

## 12. Risks

- Parallel streams in separate worktrees need one import each. The gate is slow, so the integrator runs it once
  per candidate, not once per worker.
- Save format changes (H1, D) make older saves fail to load. Acceptable before release, and it is stated here so it
  is not discovered later.
- G is blocked on images, not effort. Without X4, no visual win can be claimed.
- Hashes and goldens move with H (checksum, possibly StringName) and D (fingerprint). The integrator regenerates
  once, not per stream.
- The unverified GitHub CI (A4) is shown as unverified until it has run on GitHub.
