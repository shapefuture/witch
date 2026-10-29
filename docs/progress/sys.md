# SYS workcell progress

Worktree: /home/user/witch/.claude/worktrees/agent-a84888e1bd1c9cdac (branch worktree-agent-a84888e1bd1c9cdac).
Base: 75de726 (the worktree was fast-forwarded to it from 243230b at the start, as the brief asks).
Brief: the SYS row of docs/design/GAME_SPEC.md section 7 and the restart brief (38_agent.md).

Godot for this workcell: /root/godot/Godot_v4.6.3-stable_linux.x86_64. A fresh worktree needs one `--import` before
any test runs (class names are registered by it).

## Slices (most important first)

1. Notebook kinds (done): NotebookView lists only claims a sidecar names, with the authored kind (seven kinds);
   UNRESOLVED_BY_DESIGN is untestable whatever the sidecar says; load_claims validates data/notebook/*.json;
   pages() groups by kind for the slab. Old names (TOLD, GUESSED, OPEN) kept as aliases.
2. Notebook slab and the witch's systems actions: pending.
3. Expectation-Sight (sight step, ghosts, render/psx/ghost_*): pending.
4. flash (the telesomatic vignette, render/psx/flash_*): pending.
5. Magic modes (violet, verdigris, gold) and effect fizzle: pending.
6. docs/engine/SYSTEMS.md, final gate: pending.

## Needs from the integrator

- game/main/game_root.gd `_play_magic` must pass the step's mode: `magic.play(effect, at, str(entry.get("mode", "violet")))`.
  Until then verdigris and gold steps render as violet.
- game/main/game_root.gd must call `SystemsPresenters.register(presentation, self)` once, after `_register_presentation()`.
- The notebook and sight steps are gated by the root's input: the slab takes its own taps (IntentInput child, as the
  main menu does), so no change to the root's tap routing is needed.
- data/notebook/<area>.json sidecars come from the content areas (A to D). None exist yet, so the notebook lists nothing.
- data/expectations/<area>.json comes from the content areas. None exist yet, so sight shows no ghosts.
- data/world/places/<place>.json comes from FW. Until then flash falls back to assets/painted/<image>/plate.png.
