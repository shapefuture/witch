# SYS workcell progress

Worktree: /home/user/witch/.claude/worktrees/agent-a84888e1bd1c9cdac (branch worktree-agent-a84888e1bd1c9cdac).
Base: 4d2dd7d. The designated branch claude/loving-brown-whtlm0 is NOT merged here: after the container restart the
coordinator's procedure is that the coordinator integrates this branch (no merge, no git stash in this worktree).
Brief: the SYS row of docs/design/GAME_SPEC.md section 7 and the restart brief (38_agent.md).

Godot for this workcell: /root/godot/Godot_v4.6.3-stable_linux.x86_64. A fresh worktree needs one `--import` before
any test runs (class names are registered by it).

## Slices (state)

1. Notebook kinds (done): NotebookView lists only claims a sidecar names, with the authored kind (seven kinds);
   UNRESOLVED_BY_DESIGN is untestable whatever the sidecar says; load_claims validates data/notebook/*.json;
   pages() groups by kind for the slab. Old names (TOLD, GUESSED, OPEN) kept as aliases.
2. Notebook slab and the witch's systems actions (done): NotebookSlab (game/ui/notebook_slab.gd) shows one page a
   kind, turns by tap, closes by its plaque; NotebookPresenter plays the `notebook` step, holds until she closes it,
   and is tested through the director's seam (test_notebook_presenter.gd). data/mirror/areas/systems/actions.json has
   the witch's two options (notebook; sight, not in the postgame).
3. Expectation-Sight (done): ExpectationSight and SightPresenter (copies of the actor's meshes, ghost silhouette); writes
   nothing to Mirror (tested by event count and world/npc state).
4. flash (done): FlashPresenter hangs a card on the camera for two seconds, the place's plate through
   render/psx/flash_card.gdshader, with the painted rooms' chime and no caption. Tested: plate resolution, the card's
   size, no caption, the cue, the stand-in, reduced effects, a flash step through the registered seam, and one
   brightening over two seconds (test_flash.gd).
5. Magic modes (done): MagicPresentation.play(effect, at, mode) keeps violet as the default look; verdigris is a ring
   that frames and changes nothing; gold is a warm disc at face height; effect "fizzle" sputters three times and emits
   `sputtered(index)` at each one, so the count is checked without frame timing (test_magic_modes.gd).
6. docs/engine/SYSTEMS.md (done). Its Decisions section lists the guesses.
7. Content checks (done): tests/systems/test_systems_content.gd reads every step under data/mirror. Every systems step
   (notebook, sight, flash) has a handler once the seam is registered; every magic step names a look and an effect
   that MagicPresentation plays.

## Leak at process exit (found and fixed)

- Bisect by directory, run before the restart (scratchpad/bisect_summary.txt): mirror leaves one resource at exit;
  dialogue and interaction leave the Dialogue Manager's two (allowed). The bisect list did not include tests/systems,
  and a later run of tests/systems exits clean.
- The verbose mirror run names the leaked resource: res://addons/mirror_engine/mirror_event.gd, still in use, with five
  suspended GDScriptFunctionState coroutines and four RefCounted objects. The non-verbose gate prints only the single
  count at exit (2, the Dialogue Manager's), which is why the mirror leak is not visible there.
- Directory: tests/mirror. Test: tests/mirror/test_live_hall_game.gd, alone, reproduces it.
- Cause: the test boots GameRoot. Its opening storylet `story.arrival` plays a camera step and two lines, and a line
  waits for the player. The test ended while that line was still typing, so its coroutines kept the Mirror events and
  an audio playback alive until exit.
- Fix: `_settle` in that test advances the presentation until the subtitle and the Mirror queue are idle. Nothing is
  allow-listed. The change is outside the SYS write set (it is in tests/mirror, not tests/systems); flagged here.

## Gate

- Baseline gate on the tree as it stood (before the leak fix and the new tests): FAIL, 27 failures, all in
  test_engine_fuzz. They are collisions on the shared user:// folder with other Godot processes, including SYS's own
  diagnostic runs, which overlapped the gate. The fuzz test passes when run alone. Exit count: 2 (allowed).
- Final gate: GATE PASS (scratchpad/sys/gate_2.log: 92 suites, 663 tests, 8017 assertions). Its exit count is 2, the
  Dialogue Manager's. A verbose run of tests/mirror after the fix ends with no leaked resource and no leaked instance.

## Needs from the integrator

- game/main/game_root.gd must call `SystemsPresenters.register(presentation, self)` once, after `_register_presentation()`.
  Until then `notebook`, `sight` and `flash` are unhandled in the running game (the director warns about them). Only the
  framework root can make that call.
- game/main/game_root.gd `_play_magic` must pass the step's look: `magic.play(effect, at, str(entry.get("mode", "violet")))`.
  Until then verdigris and gold steps play as violet.
- tests/mirror/test_live_hall_game.gd carries the leak fix (see above), outside the SYS write set.
- The `ending` kind has no handler yet (framework cell).

## Guesses where the spec is open

See the Decisions section of docs/engine/SYSTEMS.md.
