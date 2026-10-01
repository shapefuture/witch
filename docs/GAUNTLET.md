# The Witch gauntlet

The regression laboratory. Note: a `PRODUCTION_GAUNTLET.md` was referred to when this work was
requested, but no such file exists in this repository, in PR #1, or in the vendored addon; the
engine's own gate lived in a separate repository. This is the equivalent for *this* project,
and it measures what matters for Witch rather than fidelity to another game.

Run it: `GODOT=/path/to/godot ./tests/run_tests.sh` (prints `GATE PASS` or `GATE FAIL: <why>`).

| Layer | Question it answers | Where |
|---|---|---|
| Engine contracts | Is the event log sound, atomic, deterministic, replayable, and does a bad save fail cleanly? | `tests/mirror`, `tests/save` (incl. golden-master hashes of a scripted session) |
| Catalog and text | Does the content load with zero errors/warnings? Is there no prose outside `ru.json`? Do all keys and dialogue titles exist? | `test_game_catalog.gd`, `test_text_single_source.gd` |
| Does knowledge alter what is possible? | Same target, different knowledge, different options? Are unlocks driven by revised models? | `tests/interaction/test_interaction_resolver.gd`, `tests/npc/test_tomas_clearing.gd` |
| Does the NPC answer as designed? | Expectation violated vs confirmed; outcome certain, motive unresolved; the contradiction recorded as a model revision; recovery possible | `tests/npc/test_tomas_clearing.gd` |
| Input equivalence | Does tap == click (same intent, same action, same chain)? Is a pinch or a drag not a tap? Are emulated-mouse duplicates ignored? | `tests/input/test_intent_input.gd`, `test_game_flow.gd` |
| Sequencing | Can a second action interleave with a presentation? | `tests/interaction/test_action_queue.gd`, `test_game_flow.gd` |
| End to end | Does clicking through the real scene produce the identical event chain as the headless sim? | `test_a_full_playthrough_driven_through_the_ui_equals_the_scripted_simulation` |
| Save determinism | `state -> save -> reload -> identical canonical state`, at **every** cut point of every sim, and the resumed run ends on the identical chain head | `tests/sim/test_simulation.gd`, `tests/save/test_save_game.gd` |
| Deterministic replay | Same script, same head hash; different play, different history | `tests/sim/test_simulation.gd` |
| Behaviour snapshots | Per step: response chosen, observed, which predictions missed, camera beats, options offered afterwards; final world/knowledge/models/operators/chain head | `tests/golden/*.json` via `test_golden_transcripts.gd` |
| Camera | Distinct poses per dramatic beat; the `stay` (no-follow) contract; placement math | `tests/render/test_camera_director.gd` |
| Render | Does the real scene draw with real shaders (no errors), with Russian subtitles, and **does magic visibly expand the palette?** | `tests/render/render_check.sh` |

The render stage needs `xvfb-run` and Mesa software GL; without them it reports `RENDER SKIPPED`
and the headless gate still passes. Latest figures: start frame 216 distinct colours and 585
subtitle glyph pixels; mundane frame 172 colours vs **540 with magic** (3.1x).

## Mutation checks done while building it

The suites were not trusted on first green: rules were deliberately broken and the failures
confirmed (Tomas no longer withdrawing; the bell no longer speeding the invitation; forged
saves; tampered events; a locked catalog edited in place). Do the same after large changes.

## Golden updates

`UPDATE_GOLDEN=1 ./tests/run_tests.sh golden` rewrites the transcripts. Review the diff; a change
there is a statement about game behaviour, not noise.
