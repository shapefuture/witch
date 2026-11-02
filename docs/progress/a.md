# Workcell A: prologue and act I (progress)

Worktree: /home/user/witch/.claude/worktrees/agent-ab315b9e14371b2ac (branch worktree-agent-ab315b9e14371b2ac).
Base: 75de726. The worktree had been cut from an older main (243230b); it was fast-forwarded to 75de726.

## Slices (each one committed when its tests pass)

1. Prologue mechanics: kettle state machine, garden claims, drawing, board, chuyka, street, end of day.
2. Prologue text, notebook, expectations, hotspots, sims (prologue_main, prologue_cast), tests.
3. Act I mechanics: day state machine (act1_day 1 to 5), Miron's window beat, the Fog's edge, modes, exit.
4. Act I text, notebook, expectations, hotspots, sims (act1_main, act1_hound, act1_prove), tests.
5. Lore pass (only if the lore briefs exist; checked before the text pass).

## Interfaces published (exact ids)

Prologue: prologue_garden_two_tastes, prologue_bench_crooked, prologue_knot, prologue_sunflowers,
prologue_father_drawing, prologue_fog_mentioned, prologue_kettle_rule, op.prologue_unwatched.
Act I: act1_fog_is_quiet, act1_miron_left, act1_key_on_hook, act1_visits_unwatched, act1_replaced.
World: npc_state.miron.place = fog after act I; story.act = act1 at the end of the prologue, act2 (magic.state
failing) at the end of act I. Exit targets owned: window_seat (shop to window), act1_marsh_road (street to fog_edge),
act1_marsh_back (fog_edge to street).

## Needs from the integrator

- Hotspot files: the prologue file carries the shop and garden doors and the street door (no core hotspot file
  exists yet). The act I file carries window_back (the window place) and the Fog's edge targets.
- Spots: raccoon in shop (about [430, 600]), miron in garden (about [560, 470]), miron in street while watched
  from the window (about [650, 470]), vera in street (about [880, 600]).
- `anim` and `npc` presentation kinds only drive the witch and Tomas today. Mine never animate NPCs; a sit or laugh
  for Miron would need a handler.
- The notebook sidecars use the field `text` (per the spec), so tools/text_tool.py reports their note keys as unused.
  The QA owner may want it to read `text` in data/notebook.
- The witch's own wand and notebook options (tapping the witch) belong to FW/SYS and the act IV owner; I add only
  the chuyka action on the witch (`prologue_sight_self`).

## Decisions (see the report for the full list)

- Target ids are prefixed with their area (prologue_kettle, act1_bed) so that the display keys obj.<target> cannot collide
  across areas. Core ids (miron, raccoon, vera, witch, window_back, door_*) are used as they are.
- Kettle: states simmering, still, boiled, thunder. Refill is a GO, so a forced kettle never blocks the rule.
- Miron's days: act1_day n 1 to 5. Ending the day (bed) advances n. Day 3 window beat: looking at him
  from the window, then turning away (WAIT) makes him go. Day 4: the Fog's edge opens. Day 5: key on the hook.
  Ending day 5 is the exit to act2.
