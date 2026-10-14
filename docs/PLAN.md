# Witch You Were Here: plan of record

Status: working plan. **Task status lives in beads only** (`bd ready`, `bd list`, `bd show <id>`). This file holds
the requirements, the decisions, the workcell boundaries and the integration rules. It holds no status, so it
cannot drift from the tracker.

**Phase: pre-production (since 2026-10-14).** The user is finalising the design and the narrative. The game is not
being built yet. The build streams are held behind two gates (section 13). The work that is allowed now is the
references, the style and navigation studies, the design and narrative questions, and the gate and engine
housekeeping.

Baseline: branch `claude/loving-brown-whtlm0`, at `e10c817` (the pre-production commit, on `9c9e9fe`, the plan commit, on `243230b`, main). The gate is red at
baseline: one vacuous test (REQ-20).

Tracker: beads root epic `witch-29y`. Run `bd ready` for the next unblocked work. The tracker is exported to
`.beads/issues.jsonl` for commits; re-export after any change.

## 1. Outcome

A playable, Russian-only diorama adventure in which the Minds layer runs during live play. The player goes
hall (room 1) → painted room (room 2) → path out, with a main menu, a full ending, and the cast placed in rooms.
The exact design and story are not final: the user finalises them (DESIGN-FREEZE, section 13).

Done means: the gate passes on a clean checkout, the playthrough above works through the UI, every REQ below is
accepted with recorded evidence, and the open decisions are closed.

## 2. Requirement register

Each REQ maps to one or more beads tasks through the `req:REQ-nn` label. A REQ closes only when every mapped task
closes with evidence and the integrated gate passes.

| REQ | Requirement | Source | Today |
|---|---|---|---|
| REQ-01 | Minds coordinator live in the hall (happenings reach `Mirror.minds.perceive`) | CLAUDE.md, MINDS.md | not built: `PropEvents.attach` used only by tests. Held (DESIGN-FREEZE) |
| REQ-02 | Gossip: interpretation rules read other witnesses' accounts | MINDS.md | not built. Held |
| REQ-03 | Conventions spread between communities | MINDS.md | not built. Held |
| REQ-04 | UI for the witch's knowledge of a custom | MINDS.md | not built. Held |
| REQ-05 | Raccoon tele-somatic perception channel | CLAUDE.md, MINDS.md | empty anchor `placeholders.gd:78`. Held; depends on NQ-c |
| REQ-06 | Town graph | CLAUDE.md | not built. Held |
| REQ-07 | World compiler from place resources | CLAUDE.md | not built. Held |
| REQ-08 | LimboAI | CLAUDE.md | decision X1 (default: defer) |
| REQ-09 | On-device mobile profiling | CLAUDE.md | headless probe only; needs a phone |
| REQ-10 | Main menu (diegetic, pointer only) | CLAUDE.md | not built; game boots into the hall. Held |
| REQ-11 | Full ending (`go_path_out` → ending → credits → menu) | CLAUDE.md, DESIGN_INVARIANTS | only the path-out action exists. Held; depends on D4 |
| REQ-12 | Shadow, shadow_lady and witch_antler placed in a room | CLAUDE.md | built as GLBs, not placed. Held |
| REQ-13 | Vera, Elian and Ilya | CLAUDE.md | Vera: generated design in `docs/art`; Elian and Ilya: none. Held; NQ-b |
| REQ-14 | Painted room runs as room 2 with PropEvents reactions | CLAUDE.md | `walked` is emitted; the room is not in the game. Held |
| REQ-15 | Round 9: grade pass on the hall plates | `docs/visual-gauntlet/rounds.json` | not started. Held (HALL, STYLE-LOCK) |
| REQ-16 | Round 9: wider nave, vault, nested arches, lit stair | same | not started. Held (HALL, STYLE-LOCK, decision X6) |
| REQ-17 | Reference hall image in the repo | CLAUDE.md, BAR.md | **supplied 2026-10-14**: `docs/visual-gauntlet/bar/reference_hall.png`; metrics reproduce BAR.md |
| REQ-18 | `pixel.ttf` licence recorded | CLAUDE.md | **deferred by the user** ("ignore for now"); blocks shipping only |
| REQ-19 | Delete the quarantined `Scenes/` | CLAUDE.md | pending (housekeeping, open) |
| REQ-20 | Gate green at HEAD | GAUNTLET.md | red: `test_a_character_added_later…` makes no assertions. Open (A1) |
| REQ-21 | Continuous gate (CI) | none in repo | no `.github/`. Open (A4) |
| REQ-22 | Engine hardening (saves, validators, test depth, bench) | draft mirror-engine upload | open (H) |
| REQ-23 | Stale docs corrected to match code | audit | pending (section 9; open, A3) |
| REQ-24 | Character "still off" items | `docs/art/characters_*.md` | pending. Held (STYLE-LOCK); the sheet is now supplied |
| REQ-25 | `claude/upbeat-fermi-trp4xm` merged or dropped | git | 2 commits unmerged, tools and docs only, flag off (decision X10) |
| REQ-26 | Concept sheet in the repo as the judging bar for characters | characters docs | **supplied 2026-10-14**: `docs/visual-gauntlet/bar/reference_characters.png` |
| REQ-27 | Style locked: SC1 confirmed, SC2 and SC3 settled, SC4 not canon; rules R1 to R6 accepted | `docs/art/STYLE_BIBLE.md` | SC1 and SC3 settled; R1 to R6 still need the user's acceptance |
| REQ-28 | Design and narrative frozen: questions answered or deferred | `docs/design/PREPRODUCTION.md` | question lists written; DESIGN-FREEZE decision |
| REQ-29 | Navigation rules decided: input mode, cut and walk, cut during a reaction | `docs/design/NAVIGATION.md` | mobile-first design written; N1 to N3 taken as guesses, to confirm |

Explicit exclusions (none chosen yet): a generative AI runtime (the spec forbids it in the shipped core); Popochiu
(the draft lists it as unexercised; we don't use it).

## 3. Decisions

Each decision is a beads item of type `decision` (epic `witch-29y.10`). The default is what proceeds if you say
nothing. A decision whose default proceeds **does not block work**. Gating decisions are listed in section 13.

| ID | Question | Default (proceeds) | Alternative | Status |
|---|---|---|---|---|
| X1 | LimboAI | **defer**; the Minds layer and Mirror decide NPC behaviour; document in ARCHITECTURE | vendor 1.8.1 (the draft has a runtime-tested blackboard guard, but its binaries are Linux x86_64 only and the game is mobile-first) | open |
| X2 | Vera's design | **keep** the generated design and its rig (8,998 triangles, two surfaces, jug on `hand.L`) | new design | open; the design freeze may change it |
| X3 | Elian and Ilya's canon | **start from** the draft's fixture behaviour (Elian accepts help; Ilya is friendly when asked, and is startled by an unasked CAST), marked as placeholder canon | write your own | open; the narrative freeze may change it |
| X4 | Reference hall image and the concept sheet | — | — | **answered 2026-10-14**: supplied and placed (section 2) |
| X5 | `pixel.ttf` licence | — | — | **deferred by the user**: "ignore for now"; blocks shipping only |
| X6 | Hall geometry route (G3) | **re-bake** in Blender (exact occlusion, about 40 s) | paint the new art over the existing proxy (faster, occlusion fitted by hand) | open; held by STYLE-LOCK |
| X7 | First happening in the live hall | **poke a prop**, with echo, regard and name as the three hall rules | another verb | open; held by DESIGN-FREEZE |
| X8 | Raccoon eyes | **keep open** (deliberate deviation from the sheet, per the characters doc) | closed arcs as drawn | open |
| X9 | Painted room | **room 2**, reached by a GO edge from the hall | cut it | open; held by DESIGN-FREEZE |
| X10 | Upbeat branch (REQ-25) | **merge** (tools and docs only, flag off) | drop | open |
| X11 | Persistence of beads state (section 10) | — | — | **answered**: JSONL export committed with the plan (commit `9c9e9fe`) |
| X12 | Full `full-plan-delivery` bundle | **not installed**: practices only, from the references | install the bundle (writes AGENTS.md, Claude hooks, a Python package) | open |

New decisions from the references and the navigation study (see section 13 for the gates). On 2026-10-14 the user asked for educated guesses; those are marked as guesses and can be changed:

| ID | Question | Default | Alternative |
|---|---|---|---|
| N1 | Input mode | **Guess (2026-10-14): touch and mouse are primary; no tank controls; no movement keys.** Keyboard adds accelerators only (advance, pause). To confirm: this rewords the CLAUDE.md "pointer only" rule | tank controls or movement keys on desktop |
| N2 | A room cut during a walk | **Guess: the walk is cancelled**; a tap in the new view starts a new walk | finish the walk in the new camera |
| N3 | A room cut during a Minds reaction | **Guess: the cut waits** until the subtitle box clears; a tap advances faster | cut at once |
| SC1 | Interface: counters in 02, or the references | **Confirmed by the user 2026-10-14**: no counters or sidebar; choices as paper strips (06); subtitle box with advance arrow (09); one satchel that opens as a letter cabinet for knowledge, inventory and objectives. Declined: bubble bar (08), sidebar (10), card tray (07) | keep counters, or a sidebar as in 10 |
| SC2 | Which witch | **Interim: orange (03)** for work now; preference is blonde (04), decided at DESIGN-FREEZE | blonde now |
| SC3 | Rendering family | **Decided 2026-10-14: 3D, not pixel art** | — |
| SC4 | Setting | **Not canon** (user, 2026-10-14). Decided by NQ-g, not by the references | — |
| HALL | Is the archive hall in the final game? | **Open** (user): the olive hall is one sample scene and may not be in the game. Holds the grade and geometry work (G1, G3, G4). CLAUDE.md's art rule (the hall is the first scene) conflicts | keep the hall as the first room |

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
| P Pre-production | `docs/art/references/**`, `docs/art/STYLE_BIBLE.md`, `docs/design/**`, `docs/visual-gauntlet/bar/**` | the references | no code; allowed now |
| A Gate and housekeeping | `tests/render/test_character_models.gd`, `Scenes/`, `.github/workflows/`, doc files named in section 9 | everything | owns the stale-doc edits; CLAUDE.md edits go to the integrator |
| H Engine hardening | `addons/mirror_engine/**`, `game/save/**`, `tests/save/**`, `tests/mirror/test_engine_*`, `tools/bench.gd`, `tools/soak.gd` | `data/mirror/**` | save format changes reset old saves (acceptable before release) |
| B Live coordinator | `game/world/archive/**` (not `game_root.gd`), `game/mirror/prop_events.gd`, `game/mirror/coordinator.gd` (new), `tests/mirror/test_live_hall*` (new) | `game/mirror/minds/**` | hall rules: echo, regard, name |
| C Minds gaps | `game/mirror/minds/**`, `data/mirror/minds/**`, `game/ui/knowledge_*` (new), the RaccoonLink anchor in `game/world/placeholders.gd`, `tests/mirror/test_minds_*` | B's coordinator | four-laws linter must pass |
| D World | `game/world/town/**` (new), `data/world/**` (new), `game/world/room_slot*` (new), `game/world/painted/**`, `data/mirror/actions/go.json`, `data/mirror/world.json` | H's validators | D is the only writer of catalog files; it changes the fingerprint |
| E Cast | `game/npc/**`, `tools/characters/**`, `assets/characters/**`, `data/text/ru.E.json` | D's room anchors | E4 (budgets test) waits for A1 |
| F Shell | `game/ui/main_menu*` (new), `game/main/ending*` (new), `data/text/ru.F.json` | D's GO edge, C3's diegetic base (read-only) | |
| G Art | `tools/blender/**`, `assets/archive/**`, `tools/visual_gauntlet/**`, `docs/visual-gauntlet/**`, `tools/grade_plates.py` (new) | `docs/visual-gauntlet/bar/**`, `docs/art/STYLE_BIBLE.md` | section 6 |
| I Integrator | `game/main/game_root.gd`, `data/text/ru.json`, `tests/golden/**`, `project.godot`, `export_presets.cfg`, `CLAUDE.md`, `docs/ARCHITECTURE.md`, `.github/` (merge) | all | only the coordinator writes here |

**Running now:** P (pre-production) and, once the user says go, A and H. **Held:** B, C, D, E, F and I behind
DESIGN-FREEZE; G1, G3, G4 and E4 behind STYLE-LOCK (section 13).

**Batch order once the gates open.** Batch 1: A, H, B, G1 and D3 (the slot contract, which touches no shared file).
C's units start with B. D1 waits for H2 (validators). Batch 2: C1–C4 once B1 lands; D2 and D4 once D1 and D3 land; E1–E3
after D4; F1 now, F2 after D4. Batch 3: G3 and G4 after the decision X6 default is confirmed.

**Integration order:** A → H → B → C → D → E → F → G3 and G4 → I1–I5.

**Room slot (AAA P13).** The room is a component slot. Its contract: `walked(pixel, world)`, walkable mask,
occluders, anchors, reaction requests, cut shots, and the Mirror room id. `ArchiveHall` and `PaintedRoom` both
implement it. A compatibility suite runs both. `game_root.gd` is the only composition root that names a concrete
room.

## 6. Revised stream G (art)

The Blender bake is needed only for the geometry, so the work splits. The whole stream waits for HALL and STYLE-LOCK: the grade is a style decision, and the geometry follows the style. If the archive hall is not in the final game, G is dropped rather than finished.
grade is a style decision, and the geometry follows the style.

- **G1: grade pass, no bake.** Darken and olive-grade the existing plates with a 2D colour script
  (`tools/grade_plates.py`), re-import, and capture the standard frames (`tools/visual_gauntlet/capture.sh`).
  Measure against `BAR.md`. The bar is now in the repo: re-measured on 2026-10-14 from
  `docs/visual-gauntlet/bar/reference_hall.png` with `tools/visual_gauntlet/metrics.py`, median luma 0.155 (BAR says
  0.16), 99th percentile 0.636 (0.63), mean saturation 0.585 (0.58). So the numbers match the image.
  The blind verdict is now possible. It is still a proxy measurement until the critic picks blind.
- **G3: geometry** (wider nave, vault visible, nested arches, lit stair) by the route in X6 (default: re-bake). Re-bake
  regenerates plates, proxy and anchors together, so the walk mask and occlusion cannot drift apart. Then the gate,
  and the walk and anchor tests.
- **G4: gauntlet exit.** A fresh-context harsh critic gets our frame and the reference, labels stripped and shuffled,
  and picks the better one, then names the single biggest gap. The builder fixes that gap. Repeat per piece (grade,
  nave, vault, arches, stair) until the critic picks ours. No round count. Log each round in
  `docs/visual-gauntlet/rounds.json`.
- **Characters** use the same loop, against `docs/visual-gauntlet/bar/reference_characters.png` (REQ-26), through E4.

## 7. What the references and studies changed

- **robonuggets/gauntlet-loop.** Adopted: a named, fetchable bar; a separate harsh critic with fresh context; blind
  A/B with labels stripped; a binary pick; the exit is winning the comparison, not a round count; a live progress
  record. Applied to G and to E4. The bar is now present (REQ-17, REQ-26), so the loop is no longer blocked on
  images; it is held by STYLE-LOCK.
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
- **The user's style references** (`docs/art/references/`, five images). They set the look, not the design. 01 is one sample
  scene, so the hall is a bar only if the hall stays (HALL). The sheet (03) sets the characters. 02, 04 and 05 raise the conflicts
  SC1 to SC4 (`docs/art/STYLE_BIBLE.md`).
- **The interface references** (`docs/design/ui_references/`, 06 to 10) drive SC1 and the navigation rules
  (`docs/design/NAVIGATION.md`). Several are commercial screenshots: keep them in a private repo, and remove them before any public release.
- **Alone in the Dark** (1992, not 1982; Infogrames; Frédérick Raynal). Fixed cameras over pre-rendered backdrops,
  camera changes at room and corridor boundaries, and tank controls. We match the camera and the cuts, and we
  differ on input (pointer only). The decisions N1 to N3 come from that difference (`docs/design/NAVIGATION.md`).

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
- `CLAUDE.md` "The reference image the user supplied is NOT in the repo": now stale. The images are committed on
  the user's request (`docs/art/references/`, `docs/visual-gauntlet/bar/`).
- `docs/art/characters_witch.md`: its triangle count (8,016) is stale against the 6,500 test budget; verify before editing.

Each correction is checked against code, and the evidence goes in the task's acceptance record.

## 10. Persistence of the tracker

Beads state is in `.beads/` (embedded Dolt). The container is ephemeral, so the tracker is durable only when committed.
X11 is answered: the tracker's issues are exported to `.beads/issues.jsonl` and committed with the work. The Dolt
database and runtime files stay git-ignored. The Dolt sync remote is unset, so nothing syncs outward. Re-export and
commit after each change to the tracker.

## 11. Guesses to check

- Upbeat is merged (X10). Vera is kept as she is (X2). Elian and Ilya follow the draft fixture (X3). The first
  happening is a poked prop (X7). Painted room is room 2 (X9). LimboAI is deferred (X1). Re-bake is the geometry
  route (X6).
- Shadow, shadow_lady and witch_antler are placed in room 2, and Vera with them. Their locations are not designed.
  This is a guess, not a decision.
- The witch is the sheet's orange witch for now (SC2 interim). Blonde (04) is the user's preference, decided at DESIGN-FREEZE. The gown in reference 05 is a style reference, not the design.
- Navigation is touch and mouse first, with no tank controls (N1). A walk is cancelled at a cut (N2). A cut waits for the subtitle (N3). The satchel is the one diegetic menu (SC1). All are guesses, to confirm.
- The river (02) and the hotel (04) are not assumed to be places in the game (SC4 and NQ-g).
- The 2D counters in 02 are not adopted (SC1 recommendation: no counters). The interface references (06 to 10) are read as interaction references, not as a design.

## 12. Risks

- Parallel streams in separate worktrees need one import each. The gate is slow, so the integrator runs it once
  per candidate, not once per worker.
- Save format changes (H1, D) make older saves fail to load. Acceptable before release, and it is stated here so it
  is not discovered later.
- SC3 is decided (3D), so the pixel references do not change the plate pipeline. The archive hall may leave the game (HALL): B and G work on it would then be rework, so decide before spending on it.
- The five references add about 7 MB of PNG to the repo. Acceptable for a personal project; re-encode if it grows.
- Hashes and goldens move with H (checksum, possibly StringName) and D (fingerprint). The integrator regenerates
  once, not per stream.
- The unverified GitHub CI (A4) is shown as unverified until it has run on GitHub.
- Generated art (Higgsfield) costs money per run. None is planned until STYLE-LOCK, and each run needs approval.

## 13. Pre-production gates

- **DESIGN-FREEZE** (decision, the user). Met when DQ1 to DQ7 and NQ-a to NQ-g in `docs/design/PREPRODUCTION.md` are answered
  or explicitly deferred, the room list is written, and the cast list is fixed. It holds B, C, D, E, F and I.
  It depends on N1 to N3 being decided.
- **STYLE-LOCK** (decision, the user). Met when SC1 is confirmed, SC2 and SC3 are settled, and R1 to R6 in `docs/art/STYLE_BIBLE.md` are accepted. It holds G1, G3, G4 and E4.
- **HALL** (decision, the user). Met when the user says whether the archive hall is in the final game. It holds G1, G3 and G4 as well.
- Work that is allowed now: P (references, style, navigation, questions), A (gate and housekeeping, including A1,
  which turns the gate green) and H (engine hardening). The user said not to build the game; these are not game
  content. A1 is ready when you say go.
