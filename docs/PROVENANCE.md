# Provenance

What this project started from, what was kept, and what is third-party.

## YAKO baseline

The project began as a fork of **YAKO** (`MournfulOx/YAKO_Demo_Godot3D`), a PSX-style
first-person walking/dialogue game. It is now the *engine substrate* for Witch You Were Here,
not a template to preserve.

- Baseline commit: **`a08cfbc`** ("Add YAKO development article to README"), tagged
  `yako-baseline` in the working clone. Everything removed below is recoverable from it
  (`git show yako-baseline:<path>`).
- To track upstream again: `git remote add upstream https://github.com/MournfulOx/YAKO_Demo_Godot3D.git`

**Kept (as infrastructure):** the PSX shader family (`render/psx/psx_base.gdshaderinc` and the
lit/unlit/actor/transparent/alpha-scissor/metal variants, `pp_band-dither`, `sky_stars`,
`focus_outline`, formerly `npc_outline`), the pixel font, `tools/fbx_to_glb_with_texture.py`, the
320x240 viewport configuration, and the *ideas* in `SceneManager`, `SettingsState` and
`Localization` (rewritten; see below).

**Removed:** all maps, NPC scenes, the Television/Ending/Collectibles/Duck scenes, the cigarette
system, `YellowDuckState` / `BackroomState` / `TravelState` / `BGMPlayer`, every 3D asset and
audio file (the working tree went from ~1.4 GB to ~2.5 MB; **git history still contains them**,
so `.git` is unchanged in size. Shrinking history needs `git filter-repo` and would invalidate
open PRs, so it was deliberately not done).

**Rewritten rather than mutated:** `player.gd` -> `game/player/witch.gd`; `npc_base.gd` ->
`game/npc/npc.gd` + `game/presentation/psx_actor_presenter.gd` + `focus_outline.gd`;
`dialogue_ui.gd` -> `game/ui/subtitle_ui.gd` + `game/dialogue/dialogue_bridge.gd`.
YAKO's NPC class mixed interaction, dialogue progression, shader installation, lighting and
facing in one object; those concerns are now separate.

**Stale, pending removal:** `Scenes/` still holds four small old scripts (`player.gd`,
`dialogue_ui.gd`, `pause_menu_ui.gd`, `settings_menu_ui.gd`) and the old player scene. A final
`git rm -r Scenes` was declined by the sandbox's permission classifier, so the directory is
quarantined with a `Scenes/.gdignore` (Godot ignores it). Delete it with `git rm -r Scenes`.

## Mirror Engine 1.3.1

Vendored at `addons/mirror_engine/` from PR #1 (commit `69b0a4c`). The PR shipped the addon
without its tests, so its claims could not be checked from this repository; the audit results
are in `docs/ARCHITECTURE.md` and the tests in `tests/mirror`, `tests/save`, `tests/knowledge`.

Local modifications (all covered by tests; each fixes a defect found by the new suite or adds a
small capability the game needs):

| Change | Why |
|---|---|
| Replay skips the relationship record for target-less actions | A save containing e.g. a bare `WAIT` failed to load (`projection_mismatch`). |
| `load_json` is atomic | A rejected save was re-adopted into the engine (forged projection, foreign events). |
| Saves validated by shape (`SAVE_SHAPES`), `MirrorEvent.validate_dict`, missing sections rejected | Malformed saves raised hard `SCRIPT ERROR`s instead of a clean rejection. |
| Response `requires_models` honours `observer_id` | A contract gated on the *player's* model could never match. |
| `MirrorConditions.get_path` -> `read_path`; `has_path` fixed | The static `get_path` shadows `Resource.get_path()` and was uncallable from outside; `has_path` raised on numeric values and leaked an Object per call. |
| Precondition failures tagged `kind: "state"` | The `blocked_by_state` affordance bucket was unreachable. |
| Incremental post-commit validation, truncation rollback, single-pass load, catalog stamp | An action cost ~245 ms at 900 events and grew linearly: a full-chain re-hash on *every* commit (not the snapshot the PR blamed). Now ~7-10 ms, flat. Hashes are byte-identical (golden-master test). |
| Additive: `npc.<id>` in condition context; response `relationship_target`; `audit_integrity()`; `rebuild_projections_from_event_log(verify_chain)`; `MirrorEventStore.tail/verify_tail/truncate_to` | Responses to an action on an object must be able to depend on a person; casting at a machine is a social act toward its owner; full audits are now explicit. |
| Additive: `record_world_event(actor, subject, payload, observations)` (a `WorldEventHappened` plus one `ObservationRecorded` per witness, one atomic transaction); `relationship_effects` in an observation (recorded live and on replay); replay of `WorldEventHappened` effects; `check_requirements(definition, holder, ctx)`; `next_world_event_id()` | The Minds layer (`docs/MINDS.md`): a prop being poked or a deferred consequence falling due is a happening in a place, not a menu action, and each witness's beliefs about it must replay from the log. Tests: `tests/mirror/test_world_events.gd`. Existing event payloads and hashes are unchanged. |

Known limitations carried from the PR (unchanged): `MirrorCausalHypothesisStore` is unused (the
engine keeps a plain dictionary); `MirrorEvidenceResource` / `MirrorKnowledgeResource` /
`MirrorModelResource` have no `register_*` (initial beliefs enter as events: see
`data/mirror/prologue.json`); `MirrorPopochiuBridge` is tested but unexercised;
`MirrorDialogueBridge.record_choice` cannot lazily register its action after the catalog locks,
so the game catalog registers `DIALOGUE_CHOICE` up front.

## Dialogue Manager 3.10.4

`addons/dialogue_manager/`, MIT, by Nathan Hoad, from tag `v3.10.4`
(`github.com/nathanhoad/godot_dialogue_manager`), copied **unmodified**. Its `.uid` files are
not tracked (the repository's `.gitignore` excludes `*.uid`). Known: it leaks its parsed resource
at process exit even with no game state involved; `tests/run_tests.sh` allow-lists exactly those
two shutdown messages.

## Engine and fonts

Godot **4.6.3-stable** (Forward+, Jolt). `game/ui/fonts/pixel.ttf` was carried over from YAKO; it
covers the full Russian alphabet. Its original source and licence are **not recorded in this
repository**: confirm before shipping. The two Ark Pixel CJK fonts (OFL) were removed with the
multi-language support.

## Placeholders

Every model in the diorama is a primitive built in `game/world/placeholders.gd`. Key character
models are to be supplied; see `docs/ARCHITECTURE.md` (Replacing placeholders).
