# Workcell C: acts III, IV and V (progress and resume notes)

Worktree: /home/user/witch/.claude/worktrees/agent-ae71aba68a7824aa4, branch worktree-agent-ae71aba68a7824aa4, base 75de726.
Brief: scratchpad briefs/41_agent.md (writer C). Contracts: docs/design/GAME_SPEC.md sections 3 to 6.

## Design decisions (mechanics)

- Story and place only move through actions (GO effects set witch.place; the exit action of each act sets story.act).
- Loop (clocktower): `act3_loop` {n} and `act3_clock` {face}. `act3_climb` steps n 0 to 3 (awake, bored, asleep,
  backwards). The loop ends (face `counted`, operator granted) by reading the clock (`act3_read_clock_known` with
  act2_ilya_backwards, or `act3_read_clock_backwards` once it runs backwards) or by going down and up again
  (`act3_go_hotel_clocktower` after one climb). Both routes stay open, so the operator is always reachable.
- Garden (garden_below): `act3_garden` {stillness} 0 to 4, raised by perfecting casts (the bees stop at 2).
  Differences register only with the prologue claims (holder player). `act3_only_mine` is inferred from two
  differences, or at stillness 3 (fallback, so the exit is never a softlock). Exit: `act3_sit_bench` (WAIT),
  which also needs the operator.
- Wand (act IV): four CUSTOM actions on target `witch`, exclusive through `wand.fate == held`. `hidden` takes the
  witch down to the basement, because the wand must stay reachable for act VII and garden_below is gone by then.
- Glass (act V): the hold is `act5_hold` {held}. Pull (CAST) brings Miron into the threshold. Every other action at
  the threshold releases the hold (a response with `when: act5_hold.held`), except asks and looks at him.
  The phase ends (magic `gone`, garden_below `fading`) at the first of: release, wait at the glass, show.
- Garden decay: fading at the phase end; dust when she leaves or waits in it, or waters it. No action returns it to
  lush (tests/content/test_act5.gd).
- Stairs home (`act5_stairs_home`) start in the basement and need `magic.state == gone`.

## Status

- [x] data for acts III to V (world, actions, storylets, operators, text, hotspots, notebook, expectations)
- [x] tests: test_act3 (14), test_act4 (7), test_act5 (15), test_act345_contract (9), test_act_chain (3)
- [x] goldens for the four chains: tests/golden/act3_main.json, act4_main.json, act5_main.json, act5_wait.json.
      Each is the transcript of the whole chain from a new game, at game scope, written by test_act_chain
      (UPDATE_GOLDEN=1 for that file only). Every step is accepted and every segment's expectations hold.
      Regenerated after the merge of baa70f5: head_hash (the catalog fingerprint) and two postgame world flags
      (postgame_clue_coin, postgame_clue_hook, seen false) changed. No step's response, observation or options changed
      (diffed against the previous goldens).
- [x] no dead taps in acts III to V at game scope (test_act_chain): the shadow's refusal and each of Miron's
      answers now set a claim of their own, so the aliveness ratchet's rule holds for these taps.
- [ ] sims moved into data/sim: NOT MOVED. The four chains stay in data/sim_pending. Re-measured on baa70f5 with the
      chains copied into data/sim (then removed): tests/sim drifts for all four (hall-scope golden), test_simulation
      fails their expectations and act3's save/resume cuts, and test_aliveness measures attention return 0.29 (ratchet
      0.90) and 89 dead taps (ratchet 0). The gate fails with them in data/sim, so they do not move.
- [x] text_tool check: 0 errors (the remaining warnings are dynamic obj.* keys and sidecar note keys).

## Guesses (the design was unclear)

- Clock tower: a second way out of the loop, going down and up again after one climb, so the operator stays reachable
  without Ilya's clock. The spec named only reading the clock.
- Garden: `act3_only_mine` also falls back at stillness 3, so the bench exit cannot softlock.
- Wand: `hidden` puts the wand in the basement, the one place act II's trapdoor already links, so it stays reachable
  for act VII.
- Glass: Miron's hold releases on every action at the threshold except asks and looks at him. The spec gave the pull,
  the release and the three options; the exceptions for asks and looks are a guess.

## Needs from the integrator

- Why the four chains are not in data/sim yet (measured, not guessed; measured again on baa70f5 with the chains copied
  in, then removed):
  1. tests/sim/test_golden_transcripts.gd builds a hall-scope runtime (`GameFixtures.runtime()`) for every data/sim
     script, so every game-scope chain drifts at its first difference. Fix: `GameFixtures.runtime(SimulationRunner.wants_areas(script))`.
  2. game/mirror/aliveness_lint.gd `measure_sim` also builds a hall runtime. With the chains moved in it measured
     attention return 0.288 and 89 dead taps (the ratchet asks 0.90 and 0). Fix: set `runtime.include_areas` from
     `wants_areas(script)` before `new_game()`. Measured at game scope, these chains have no dead taps (test_act_chain).
  3. The chains' "after" resolves only inside data/sim, so prologue_main, act1_* and act2_main move with them, together.
  Both gate scripts are outside this workcell's write set, so they are not edited here.

- tools/text_tool.py counts only `label_key` and `key` as references, so keys in data/notebook and
  data/expectations (`text`, `note`) show as "unused key" warnings until the tool reads those sidecars.
- The `notebook` presentation's field: this workcell uses `{"kind": "notebook", "claim": "<claim id>"}`; SYS must match.
- `sight`, `flash` and `notebook` are SYS's kinds. `magic` takes `mode` (violet, verdigris, gold) as the spec says.
- Act II's exit must keep the shop trapdoor usable (basement and shop) for the hidden wand's callback in act VII.
- Act III does not give Miron the reserved greeting: VOICES reserves it for Shadow. Act V uses the other reserved greeting for him.
