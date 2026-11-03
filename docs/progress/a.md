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

## Resumed (2026-11-02): integration fixes

- Merged claude/loving-brown-whtlm0 (4d2dd7d); the worktree branch was a fast-forward, my two commits were already in it.
- The five sims (prologue_main, prologue_cast, act1_main, act1_hound, act1_prove) are back in data/sim with goldens
  under tests/golden. The golden harness (tests/sim/test_golden_transcripts.gd) now replays a game-scope sim in the
  game scope; before, it replayed every sim in the hall, so a game sim would have recorded only refusals.
- Exit hotspots: the five core exits my areas use (door_shop_street, door_street_shop, door_shop_garden,
  door_garden_shop, window_back) now sit at the positions of my plates, in data/world/hotspots/core.json (integrator
  owned: please check). One definition each, no duplicate (place, target) pairs. Board moved to (130, 430) so it does
  not overlap the garden door.
- Dead taps (the ratchet counts a tap as dead when no claim, world or mind changes): every tap in the five sims now
  changes something. Added: the raccoon's noise verdict, the bench cast (world prologue_bench), Miron on the bench,
  Vera's evening answer, a second look at the thunder kettle.
- Lore pass (four analyst briefs and HUMOUR_MECHANISMS): the morning opens on "I didn't say that was me" and the
  "how did you sleep / not enough" exchange (line.prologue.morning_how_slept); the kettle's correction and its
  chant (line.prologue.name_witch, line.prologue.name_raccoon, line.prologue.kettle_cast_chant); Miron's seeds (the
  window call, "not empty-handed" with the moss, line.act1.ask_where_miron, note.act1.dream, line.act1.prove_miron,
  line.prologue.light_miron); the witch's "later" at the window (line.act1.turn_away_witch).

## Decisions (see the report for the full list)

- Target ids are prefixed with their area (prologue_kettle, act1_bed) so that the display keys obj.<target> cannot collide
  across areas. Core ids (miron, raccoon, vera, witch, window_back, door_*) are used as they are.
- Kettle: states simmering, still, boiled, thunder. Refill is a GO, so a forced kettle never blocks the rule.
- Miron's days: act1_day n 1 to 5. Ending the day (bed) advances n. Day 3 window beat: looking at him
  from the window, then turning away (WAIT) makes him go. Day 4: the Fog's edge opens. Day 5: key on the hook.
  Ending day 5 is the exit to act2.

## Resumed (2026-11-03): geometry, reachability and goldens

- Reachability (the blocker): a thing on the wall, or on floor beyond the walk grid, projected 19 to 40 m away, and
  the navigator snaps only 2.75 m. So the street door, the garden door, the kettle, the bed, the garden claims and the
  window seat could not be walked to, and their options never opened. Painted rooms now approach such a thing from the
  standable floor cell nearest its pixel on screen (`PaintedRoom.standable_near_pixel`). Arrivals use the same rule.
- The window has no walk grid, so its taps are taken where she stands (`InteractionFlow._inspect`).
- Core exits: `data/world/hotspots/core.json` is unchanged in this run; the exits follow it.
- Arrivals now name the door she came through: shop from street (640, 643), shop from garden (223, 613), garden from
  shop (814, 548). Spots: Miron in the window (650, 470), Vera in the street (880, 600).
- Plates: the street door (330, 480), the archway (705, 475), the observatory door (1100, 500), the window sill, the
  attic door and Fog's edge agree with the picture. The shop draws no street or back door; the garden house door sits
  on the wall beside the ivy; the marsh road is a rock outcrop. Those are plate gaps for the art owner.
- Tests: `tests/world/test_places.gd` checks that every act I room hotspot has a standable approach she can walk to from
  her default arrival, and that every arrival stands on the floor.
- Exit-time leak: a test file that builds painted rooms without naming `PaintedRoom`, `ArchiveHall` and `StageRoom` is
  reported at exit (43 to 45 resources in use); the same rooms in `test_places.gd` are clean. Not allow-listed. The
  PSX material caches (`render/psx/psx_materials.gd`) are never cleared, which is a separate issue.

Guesses (the design is unclear here):
1. The shop's street door is the floor that leaves the bottom of the frame (`exit_point`), so none is drawn.
2. Vera's street spot is in front of the flower stall, from the notes' estimate.
3. The garden house door is reached from the lily bed's edge, the nearest floor the picture shows.

Not fixed here: the painted hotspot pick is a fixed 0.6 m sphere and the JSON `radius` is ignored, so far objects are
small targets. Miron's and Vera's spots and the garden's arrivals are estimates until the plates are repainted.
