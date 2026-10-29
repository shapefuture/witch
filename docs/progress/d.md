# Workcell D progress: acts VII, VIII, IX and the postgame

Branch: worktree-agent-a71548b7c2b61e9ec (base 75de726). Brief: the orchestrator's brief 42, with its updates.

## Status

- Act VII: data, text, dialogue, notebook, expectations, hotspots, tests (tests/content/test_act7_*.gd). Green.
- Act VIII: pending.
- Act IX: pending.
- Postgame: pending.
- Sims (data/sim_pending/*_main.json): pending.
- Full gate: pending (run once at the end).

## Files written

- data/mirror/areas/<area>/actions.json, storylets.json, world.json (postgame only), operators none.
- data/text/ru/<area>.json (Russian; the only place Cyrillic may live).
- data/conversations/<area>.dialogue (linear, keys only; titles start with the area id).
- data/notebook/<area>.json, data/expectations/<area>.json, data/world/hotspots/<area>.json.
- data/sim_pending/<area>_main.json (scope game, chained with "after").
- tests/content/test_<area>*.gd.

## Test commands

- Filtered: /root/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --script res://tests/run_tests.gd -- act7
- Text: python3 tools/text_tool.py check (notes are warnings: note.* keys are not scanned by the tool yet)

## Decisions so far

- The return to magic is the first act VII action (CAST at the jars, magic.state gone to returned).
- Verdigris casts (hold the frame; open the lanterns) never set machine or town state; they only set claims.
- The hidden wand: the trapdoor look is the only option in act VII (the basement is outside act VII's places).
- Target ids of my own objects carry the area prefix (act7_jars, act8_flower, pg_...) so display keys cannot collide.

## Needs from the integrator

- project.godot: Godot's import appends each .dialogue to locale/translations_pot_files. Not committed by this cell.
- Core exits used in the postgame (door_shop_garden, door_garden_shop, ladder_shop_attic, ladder_attic_shop) need
  hotspots from the owner of core, or from the framework.
- Hotspots for the archive hall's machine come from its anchors, so act VII adds none for it.
