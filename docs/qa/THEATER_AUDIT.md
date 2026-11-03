# Theater audit of the gate (witch-29y.12.11)

Audited at commit `3ee3ba7`. "Theater" here means a check that passes without testing the behaviour it
claims. Findings are ordered by severity:

- **high**: a real bug could ship, or has shipped;
- **medium**: the check is hollow, but a neighbouring check or a second guard still limits the damage;
- **low**: the claim is overstated or the assertion is weaker than its message.

Summary: **3 high, 5 medium, 16 low.** One of the high findings is a real bug that is live now: the
machine's indicator lamp is never driven (H3).

## Method

1. Read `tests/run_tests.sh`, `tests/run_tests.gd`, `tests/base_case.gd`, `tests/render/render_check.sh`,
   `tests/render/painted_walk_check.sh` and every suite under `tests/` (51 suites, 418 tests), plus the
   render-only scripts `analyze_shots.gd`, `painted_life_check.gd` and `painted_walk_render.gd`.
2. For each assertion I asked three questions. Can it pass on an empty collection? Does other content also
   satisfy its predicate? Does its fixture ever reach the limit the code enforces?
3. I confirmed the suspicions that mattered by running the gate with Godot 4.6.3 (xvfb present, so the render
   step ran):
   - Baseline: `GATE PASS`, 51 suites, 418 tests, 5130 assertions.
   - Temporary mutations of the game code, each reverted afterwards (`git status` was clean before this
     commit).
   - Temporary probe suites under `tests/zz_probe/`, deleted afterwards.
   - Pixel measurements of the frames `render_check.sh` captured.

   Each finding says what was run.

## High

### H1. The last render step has no positive proof, so a broken `analyze_shots.gd` still gives GATE PASS

- **Where:** `tests/render/render_check.sh:51-53`, `tests/run_tests.sh:36`
- **Claim:** "Render regression (real shaders, real pixels)". The step checks resolution, lit fraction,
  tonal spread, the subtitle and the palette expansion under magic.
- **Why it passes without the behaviour:**
  - `run_tests.sh` fails the render step only when the output contains a line starting with
    `RENDER FAILED`. It ignores the exit code of `render_check.sh`.
  - The final step of `render_check.sh` pipes `analyze_shots.gd` through `grep -E "^STATS|^RENDER"`.
    Godot's `SCRIPT ERROR` / `Parse Error` lines are filtered out, and on failure the script runs a bare
    `exit 1` without printing anything.
  - So if `analyze_shots.gd` fails to compile, or raises a runtime error before its last line, the gate
    never sees `RENDER FAILED`.
  - The other two render checks require a positive line (`PAINTED_LIFE PASSED`, `WALK RENDER PASSED`). This
    one does not.
- **Evidence:** I added a syntax error to `analyze_shots.gd` and ran the step exactly as
  `render_check.sh` runs it, on the frames the baseline had captured. The output had no `RENDER` line, and
  the `run_tests.sh` grep let it through ("render step passes (GATE PASS)"). Reverted.
- **Fix:**
  - In `render_check.sh`, keep the analyzer's full log and print `RENDER FAILED` (not a bare `exit 1`)
    unless the log has a line `^RENDER PASSED`, or if it has `SCRIPT ERROR|Parse Error`.
  - In `run_tests.sh`, also fail when `render_out` contains neither `^RENDER PASSED` nor
    `^RENDER SKIPPED`.
  - In `run_tests.sh`, also fail when `render_check.sh` exits non-zero.

### H2. The "arrival subtitle" pixel check measures the lit archway, not the subtitle

- **Where:** `tests/render/analyze_shots.gd:30-31` (predicate at `:62`)
- **Claim:** "start.png: the arrival subtitle strip has no text pixels" fails when the subtitle is missing.
- **Why it passes without the behaviour:**
  - The predicate counts pixels with luma above 0.7 inside a fixed box: rows 186-232 and columns 10-310 of
    the 360-row picture, which is x 15-465 and y 279-348 at 540 rows.
  - In the current frames the arrival line is drawn as a speech bubble at about x 590-920, outside that box.
  - Everything the box counts is the brightly lit arch behind the machine.
- **Evidence:** I recounted with the same predicate on the baseline captures:

  | Frame | Pixels counted | Columns they fall in | Subtitle on screen |
  |---|---|---|---|
  | `start.png` | 159 | 268-456 | yes |
  | `mundane.png` | 760 | 289-464 | no (only option plaques) |
  | `magic.png` | 607 | 289-464 | no (only option plaques) |

  The frame with no subtitle scores almost five times higher than the one with it. A build that dropped the
  arrival subtitle would pass. This is the same defect class as the hair-colour test fixed this week.
- **Fix:**
  - Measure the bubble where it actually is: get its rectangle from the capture (have `--capture` print the
    `SpeechBubble.screen_rect()` of the active bubble), or search the frame for the bubble's light panel.
  - Then require, inside that rectangle, dark glyph pixels on the light panel.
  - Add a negative control: the same measurement on `mundane.png` (no subtitle) must come out below the
    threshold.

### H3. The machine-parts check is satisfied by any `Gear*` node; the real machine has none of the named parts (live bug)

- **Where:** `tests/render/test_archive_hall.gd:13-14`
- **Claim:** "the machine has Base, BigGear, SmallGear, Pipe, Lever, Cam, Indicator (MachineView and the
  outline depend on the names)".
- **Why it passes without the behaviour:**
  - Each part's assertion is `get_node_or_null(part) != null or find_children("Gear*").size() > 0`.
  - The second clause does not depend on the part, so once any `Gear*` node exists, all seven assertions
    pass.
- **Evidence:**
  - A probe listed the nodes of the shipped `assets/archive/props/machine.glb`: `Base_001`, `GearBig_001`,
    `GearSmall_001`, `GearTiny_001`, `Pipe_001`, `Lever_001`, `Cam_001`, `Indicator_001`. None of the seven
    names exists.
  - `game/world/machine_view.gd:27` looks up `get_node_or_null("Indicator")`, so the indicator lamp is never
    shown or hidden by Mirror's machine state. It stays as imported whether the machine is jammed or
    running.
  - `BigGear` and `SmallGear` at `:36-37` are also never found. The gears still turn only through the
    `Gear*` fallback.
- **Fix:**
  - Assert the names the code actually drives: `Indicator` must resolve via the same lookup `MachineView`
    uses, and `BigGear`/`SmallGear` or at least one `Gear*`.
  - Fix the lookup (strip glTF's `_001` suffix, or match by prefix as the gears do) or the export names.
  - Add a behaviour test: `apply_state("jammed")` then `apply_state("running_together")` must change the
    indicator's visibility.

## Medium

### M1. "Input is ignored while an action is presenting" passes with both guards removed

- **Where:** `tests/interaction/test_game_flow.gd:146-161`
- **Claim:** A click while dialogue is on screen opens nothing and commits nothing.
- **Why it passes without the behaviour:**
  - The check runs one physics frame after the click.
  - Clicking an object first walks the witch there, which takes many frames, so the surface could not be
    open after one frame anyway.
  - A click never commits on its own, so "nothing else committed" is true by construction.
- **Evidence:**
  - With `IntentInput.handle_event`'s `enabled` guard and `InteractionFlow.handle`'s `runtime.is_busy()`
    guard both disabled, `test_game_flow` passed (13 tests).
  - With only the `InteractionFlow` busy guard disabled, the whole suite passed (418 tests, `GATE PASS`).
  - The `enabled` flag alone is covered by `tests/input/test_intent_input.gd:126`. The integration claim and
    the busy guard are not covered anywhere. Reverted.
- **Fix:**
  - After the click, assert `not game.input.enabled`.
  - Assert `not game.witch.is_walking()` over about 30 frames.
  - Assert `not await _until(func(): return game.surface.is_open(), 120)`.
  - Add a unit test that `InteractionFlow.handle(PlayerIntent.inspect(...))` while `runtime.is_busy()`
    leaves `focused_target` empty and does not start a walk.

### M2. The rollback test checks indexes under a guessed transaction id that never existed

- **Where:** `tests/mirror/test_golden_and_rollback.gd:47-48`
- **Claim:** "rolled back events are not indexed" and "rolled back transaction is not indexed".
- **Why it passes without the behaviour:**
  - The ids are hard-coded as `tx_two_4`.
  - A probe showed `next_sequence()` is 3 at that point, so the rolled-back transaction was `tx_two_3`.
  - `get_by_id("tx_two_4:action") == null` and `get_transaction("tx_two_4").size() == 0` hold whatever
    the indexes contain.
- **Fix:**
  - Read `var tx := "tx_two_%d" % e.event_store.next_sequence()` before the failing `resolve_action`, and
    assert on that.
  - Better, also assert that the id index size equals `size` after the rollback.

### M3. The save-size cap is never tested against the event cap; a long game becomes unsaveable

- **Where:** `tests/save/test_save_hardening.gd:90-116`, `addons/mirror_engine/mirror_persistence.gd:11`,
  `addons/mirror_engine/mirror_event_store.gd:6`
- **Claim:** "an oversized save is refused before it is parsed".
- **Why a bug past the limit stays hidden:**
  - The test lowers the cap to 2000 bytes with a 3-action fixture.
  - No test asks whether a game that reaches the event store's own limit (`max_events` 100000) still fits
    under `max_save_bytes` (64 MiB).
  - A probe measured 105 events of `data/sim/hall_rules.json` at 365,875 bytes, about 3.5 KB per event
    (envelope and projection included).
  - At that rate the save cap is reached near 19,000 events. The store keeps accepting events up to 100,000,
    but `SaveGame.save` refuses (`ERR_INVALID_DATA`) and the game can no longer be saved.
- **Fix:**
  - Add a test that fills a runtime to a realistic long session (for example, the hall sim repeated, or
    `max_events` worth of minimal events) and asserts that `SaveGame.save` returns `OK` and the file reloads.
  - Or assert the invariant directly: `max_events * <measured bytes per event> < max_save_bytes`.
  - Either way, decide which limit is wrong.

### M4. `max_fired_per_pump` is never reached

- **Where:** `tests/mirror/minds_fixtures.gd:19`, `tests/mirror/test_minds_queue.gd`;
  code at `game/mirror/minds/mirror_minds.gd:175`
- **Claim:** The queue is bounded (`test_the_queue_is_bounded_and_so_is_a_chain_of_consequences`).
- **Why a bug past the limit stays hidden:**
  - `max_pending` (8) and `max_chain_depth` (3) are reached, but no test has more than 16 consequences fall
    due in one pump.
  - What happens to the 17th is unpinned. It stays pending with a past `due`, and fires only on the next
    `TimeAdvanced`.
  - A regression that dropped it, fired it twice, or made the next pump fire it out of order would pass.
- **Fix:**
  - Set `max_fired_per_pump` to 2 in a rig and schedule 3 consequences due at the same tick.
  - Assert that `advance_time` fires exactly 2 and leaves 1 pending.
  - Assert that `advance_time(1)` fires the third, and that the order is due-then-id.

### M5. `UPDATE_GOLDEN=1` in the environment turns the golden test into `ok(true)` for the whole gate

- **Where:** `tests/sim/test_golden_transcripts.gd:80-90`
- **Claim:** "Every sim matches its golden transcript".
- **Why it passes without the behaviour:**
  - With `UPDATE_GOLDEN=1` set (by a shell profile, a CI variable, or a previous command), any run of the
    gate overwrites every golden from the current behaviour, asserts `ok(true, "updated ...")`, and prints
    `GATE PASS`.
  - The sims' `expect` blocks still run in `test_simulation.gd`. But `options_after` and the camera beats are
    checked only by the goldens (see L16).
- **Fix:**
  - Have the runner print a `GOLDEN UPDATED` line.
  - Have `run_tests.sh` refuse to print `GATE PASS` when `UPDATE_GOLDEN` is set, or when no filter
    containing `golden` was given.

## Low

### L1. "Engine remains usable after a rollback" accepts a failure

- **Where:** `tests/mirror/test_golden_and_rollback.gd:50-51`
- **Problem:** The assertion is `ok(again["ok"] or again["error"] == "evidence_conflict", ...)`. A probe
  showed that `again` does fail, with `evidence_conflict`, so the "usable" claim is never exercised.
- **Fix:** Resolve an action that does not touch `shared.evidence` (register a third plain action in the
  fixture), then `ok(result["ok"])` and check that the chain verifies.

### L2. "Preview equals commit" compares only `observed`

- **Where:** `tests/mirror/test_golden_and_rollback.gd:63-74`
- **Fix:** Also assert that the post-commit projection equals the pre-commit projection with `p1`'s
  `projection_diff` applied, or compare `p1["event_types"]` and the response id with the committed result.

### L3. Tautology

- **Where:** `tests/mirror/test_engine_stringname.gd:28`
- **Problem:** `eq(catalog.hash(), catalog.hash(), ...)` compares a value with itself. The test name
  promises the stamp survives a round trip, but the stamp is never compared with the reloaded catalog.
- **Fix:** `eq(catalog.hash(), (reloaded as Dictionary).hash(), ...)`, or compare two separately built
  engines' stamps.

### L4. `ok(true, "done")`

- **Where:** `tests/render/test_actor_presentation.gd:64`
- **Problem:** It pads the assertion count, which defeats the runner's "made no assertions" guard.
- **Fix:** Delete it.

### L5. The test name claims the disabled Continue shows "no save"; the body only checks the key exists

- **Where:** `tests/ui/test_main_menu.gd:91-92`
- **Fix:** Open the menu with `has_save == false` and
  `eq(menu.option_labels()[1], tr("menu.continue_empty"))`.

### L6. "A second poke answers differently" has an OR escape

- **Where:** `tests/render/test_painted_generated_toys.gd:111`
- **Problem:** `prop.last_reaction != first or names[0] == names[1]` passes for a prop whose first two
  answers are the same. It also never checks that the second poke plays the *second* answer.
- **Fix:** `eq(prop.last_reaction, str(names[1]))`, as `test_painted_toybox.gd:135` does for the hall.

### L7. "Clicking empty ground closes the surface" never asserts that the surface was open

- **Where:** `tests/interaction/test_game_flow.gd:114` (and `:132`)
- **Problem:** The surface may never have been open, so "closed" proves nothing.
- **Fix:** `ok(await _open_surface(game, "tomas"), "the surface opened")` before the click.

### L8. "Dialogue reads but never writes game state" checks one title

- **Where:** `tests/dialogue/test_dialogue_bridge.gd:54-60`
- **Problem:** It checks only `tomas_thanks_together`, a title with no conditions.
- **Fix:** Move the head-hash and projection equality into the all-titles loop of
  `test_every_authored_title_plays_to_the_end_in_russian`.

### L9. "A walk nobody reacts to writes nothing" does not say why nothing was written

- **Where:** `tests/mirror/test_prop_events.gd:127-135`
- **Problem:** An error result would also write nothing.
- **Fix:** Capture the return of `bridge.walked(...)` and assert `result["ok"] and not result["recorded"]`.

### L10. The witch palette check cannot tell hair from skin; two other loops skip silently

- **Where:** `tests/render/test_character_models.gd:163-169`, `:35`, `:53`
- **Problem:**
  - The "ash-blond" band admits skin, as its own message says, so the hair colour is not really checked.
  - The budget and shading loops `continue` silently when a model fails to load. Loading is asserted in the
    first test, so this is a duplicate-coverage gap only.
- **Fix:**
  - Count the band only inside the hair's UV island (from the rig's atlas layout), or require a
    hair-specific hue that skin does not reach.
  - Replace the silent `continue` with `ok(false, "%s loads" % id)`.

### L11. The raccoon's triangle budget counts indexed meshes only

- **Where:** `tests/render/test_raccoon_model.gd:254`
- **Problem:** `indices.size() / 3` counts an unindexed surface as 0 triangles, so the budget passes
  vacuously.
- **Fix:** Use the same vertex-count fallback as `test_character_models.gd:45`.

### L12. The Cyrillic scan covers five roots and five extensions

- **Where:** `tests/mirror/test_text_single_source.gd:7-8`
- **Problem:**
  - CLAUDE.md states "No Cyrillic in any other file". The test does not scan `project.godot`, `*.tres`,
    `*.cfg`, `addons/`, `tools/` or `assets/`.
  - Player-visible text in a theme `.tres`, an asset, or the window title would not be caught.
  - Today Cyrillic exists outside the table in `docs/PLAN.md`, `docs/art/STYLE_BIBLE.md`,
    `docs/design/PREPRODUCTION.md`, `tools/text_tool.py` and the vendored `uk.po`.
- **Fix:** Scan every git-tracked text file with an explicit allow-list (the table, the vendored l10n,
  named docs), so a new location must be added on purpose.

### L13. A variable named for clarity records only presence

- **Where:** `tests/mirror/test_minds_interpretation.gd:71-75`
- **Problem:** `ana_clarity` is set to 1 whenever Ana appears. The "clarity 46" claim rests only on the
  following `reads == "rude"`.
- **Fix:** Read `reading["clarity"]` and `eq(..., 46)`.

### L14. Determinism tests do not check that the steps succeeded

- **Where:** `tests/mirror/test_engine_core.gd:119-128`, `tests/mirror/test_minds_queue.gd:181-189`
- **Problem:** If every step failed, both runs would have equal (empty) heads and the test would pass.
- **Fix:** Assert each `resolve_action`/`perceive` returns `ok` and that `event_store.size() > 0`.

### L15. Gate details

All in `tests/run_tests.sh` unless noted.

- **Line 28.** The allow-list matches any count of leaked resources and ObjectDB instances, so a new
  resource leak of our own at exit is masked. Orphan Nodes are counted by the runner; resources and
  RefCounted objects are not. **Fix:** pin the exact message (`2 resources still in use`), or count the
  leaks with `--verbose` and compare with a baseline.
- **Line 14.** The import step greps a narrower set of markers than step 2 (no generic `^ERROR:`).
  **Fix:** use the same grep as step 2.
- **Lines 33 and 39.** With `SKIP_RENDER=1`, or without `xvfb-run`, the gate prints the same `GATE PASS`
  as a full run. **Fix:** print `GATE PASS (render skipped)` so a log shows which gate passed.
- **No timeout.** A coroutine test that awaits a signal that never comes hangs the gate. It does not pass,
  but CI would sit until it is killed. **Fix:** wrap step 2 in `timeout`.

### L16. Some golden fields have no independent assertion

- **Where:** `tests/sim/test_golden_transcripts.gd:36-39`
- **Problem:** Every sim has an `expect` block (state, knowledge, models, operators), checked independently
  in `test_simulation.gd`. But `options_after` per step and the authored camera beats are pinned only by
  the goldens, so a regenerated golden accepts a vanished option.
- **Fix:** Add `expect.options` (target → ids that must be offered at the end) to the sim scripts, and check
  it in `SimulationRunner.check_expectations`.

### Also noted, low

- `tests/save/test_save_game.gd:36` ignores `fresh.load_game(SLOT)`'s result before comparing options.
  Add `ok(...["ok"])`.
- `tests/save/test_save_game.gd:76` is named "saving is atomic" but checks only that no `.tmp` is left.
  The interrupted-write case is not exercised.

## Checked and found clean

- **`tests/run_tests.gd`.** A test with zero assertions fails, coroutine tests are awaited, a suite that
  does not compile or does not extend `TestCase` fails, leaked Nodes fail, and a filter that matches nothing
  fails (`total_tests > 0`).
- **`run_tests.sh` steps 1-2.** They require `TESTS PASSED:` and grep `SCRIPT ERROR`, `Parse Error`,
  `^ERROR:` and `^FAIL`.
- **`painted_life_check.gd` and `painted_walk_check.sh`.** Both require a positive `PASSED` line and grep
  shader and script errors.
- **`painted_life_check.gd`.** It uses negative controls: intensity 0 equals plain, the quiet corner does not
  change, and the pulse decays to an exact rest.
- **`test_engine_fuzz.gd`.** A probe showed the accepted catalogs commit actions (173 commits over 58
  accepted runs, one with zero). Random play commits 22 of 48 steps. The refusal paths assert that the
  engine is unchanged.
- **`test_save_hardening.gd`, `test_mirror_load_integrity.gd`, `test_mirror_persistence.gd`.** Re-sealed
  forgeries, truncation, corrupt sections and legacy formats each assert both the error and an unchanged
  engine.
- **The Minds suites** (`test_minds_*`, `test_world_events.gd`, `test_hall_rules.gd`, `test_live_hall*.gd`,
  `test_prop_events.gd`, except L9 and L13). `max_pending`, `max_chain_depth`, `max_origin_events`, the
  tally cap and `max_active_conventions` are each reached by a fixture.
- **`test_four_laws.gd`.** Each law has a broken fixture that must fail with a named code. The baseline
  fixture is asserted clean.
- **`test_engine_validators.gd`.** Each fixture must load cleanly first. Truncation is an error. The state
  count must be above 1000.
- **`test_limits_signals_and_bridges.gd`.** The event capacity and the transaction event limit are reached.
- **`test_simulation.gd`.** Every sim has an `expect` block, and save at every cut then resume must end on
  the same head.
- **`test_intent_input.gd`, `test_main_menu.gd` (except L5), `test_diegetic_ui.gd`, `test_room_slot.gd`.**
- **`test_plates.gd`, `test_painted_room.gd`, `test_painted_overscan.gd`, `test_painted_walk.gd`,
  `test_painted_toybox.gd`, `test_painted_life.gd`.** Their loops are guarded by size or existence
  assertions.
- **The rest:** `test_camera_director.gd`, `test_psx_materials.gd`, `test_tomas_clearing.gd`,
  `test_interaction_resolver.gd` (a probe showed three distinct option groups for Tomas, so the ordering
  check has content), and `test_mirror_stores.gd`.

## Could not check

- Device-level behaviour: on-device touch and mobile memory. The gate does not claim it.
- Whether the indicator lamp's fixed visibility in H3 is visible in the shipped frames. I confirmed the
  lookup fails, not how the lamp looks.
- The render step's checks other than H1 and H2 on other GPUs or drivers. I ran Mesa under Xvfb only.

## Resolution of the low findings (stream L, Q-low, 2026-10-16)

Each low finding is fixed in its test, or answered here with the reason it stays open. Counted in
`witch-29y.12.30`.

| Finding | Status | What changed, or why it is open |
|---|---|---|
| L1 | fixed | the engine is used after the rollback by a plain action that must resolve |
| L2 | fixed | the commit's events, response and projection change are compared with the preview's |
| L3 | fixed | the stamp is compared across two builds, not with itself |
| L4 | fixed | the padding assertion is deleted |
| L5 | partly | renamed to what it checks (the cue is in the text table). Open: the menu with no save shows the cue; needs the main menu wired into the boot path, which is not built |
| L6 | fixed | the second poke must play the second answer |
| L7 | fixed | the surface is asserted open before the click, and the open is asserted |
| L8 | fixed | speaking writes no event and changes no state, for every authored title |
| L9 | fixed | the walk's result is asserted: taken, not recorded |
| L10 | open | the hair band needs the hair's own UV island from the rig's atlas, or a hue skin cannot reach. Needs the atlas layout from `tools/characters/witch_ref.py`; a follow-up |
| L11 | fixed | an unindexed surface is counted from its vertices, not as zero triangles |
| L12 | fixed | the scan covers every project text folder and extension, with an allow-list of five named files (the vendored plugin's translation, three design notes that quote Russian titles, and the text tool) |
| L13 | fixed | Ana's clarity is read from the reading and is 46 at nine tiles |
| L14 | fixed | each determinism step must succeed, and the run must write events |
| L15 | fixed | the import step greps like the suite step; the suite has a 900 s timeout; the leak allow-list is pinned to two resources; a skipped render prints `GATE PASS (render skipped)` |
| L16 | open | `expect.options` per sim (the options each target must offer at the end) needs a field in the sim scripts and a check in `SimulationRunner`; a follow-up |
| save_game:36 | fixed | the load's result is asserted before the options are compared |
| save_game:76 | open | the name says atomic, the body checks only that no temp file is left. Needs a test that a failed rename leaves the slot as it was; a follow-up |
