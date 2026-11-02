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

- [ ] data for act3 (world, actions, storylets, operators, text, hotspots, notebook, expectations)
- [ ] data for act4
- [ ] data for act5
- [ ] tests (act3, act4, act5, cross-act contract)
- [ ] sims in data/sim_pending (act3_main, act4_main, act5_main, act5_wait)
- [ ] text_tool check, filtered tests, full gate

## Needs from the integrator

- tools/text_tool.py counts only `label_key` and `key` as references, so keys in data/notebook and
  data/expectations (`text`, `note`) show as "unused key" warnings until the tool reads those sidecars.
- The `notebook` presentation's field: this workcell uses `{"kind": "notebook", "claim": "<claim id>"}`; SYS must match.
- `sight`, `flash` and `notebook` are SYS's kinds. `magic` takes `mode` (violet, verdigris, gold) as the spec says.
- Act II's exit must keep the shop trapdoor usable (basement and shop) for the hidden wand's callback in act VII.
- Act III does not give Miron the reserved greeting: VOICES reserves it for Shadow. Act V uses the other reserved greeting for him.
