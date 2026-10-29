# CHARS progress

Worktree: `/home/user/witch/.claude/worktrees/agent-abc20107e61eff01c`, branch as checked out there (not pushed).
Base: 75de726 (fast-forwarded from 243230b at the start).

## Done

- [x] Witch, X23 (copper-ginger hair, blue-grey eyes, pointed violet hat; rebuilt `assets/characters/witch.glb`; frames in
  `docs/art/characters/witch_*`). The copper test replaces the ash-blond one (see `docs/art/characters.md`).

## Next

- [ ] NPC crude models, one at a time, in `tools/characters/npc_crude.py`: miron, elian, vera, ilya, janitor, concierge (a bird).
- [ ] `tests/world/test_npc_models.gd`: every NPC id in `data/mirror/areas/core/world.json` npc_state that has a model loads,
  is skinned, has idle, walk and talk, and stays within 3,000 triangles and 2 surfaces.
- [ ] `game/world/character_models.gd`: only if a new id needs it (none expected: the loader is generic).
- [ ] Capture the NPCs at 480x360 (silhouettes), the gate (`GATE PASS`), the goldens if the witch moved one.

## Needs from the integrator

- Nothing blocking. The witch's hat and hair are visible in the goldens if any render test frames her; if a golden
  changes only for the witch, it is regenerated alone (`UPDATE_GOLDEN=1 ./tests/run_tests.sh golden`) and the diff is
  reviewed.
- Blender (bpy) is not installed: Python here is 3.13 and no bpy wheel is on hand for it. No builder this workcell needs
  it (`lowpoly_bake.py` is the only one that imports bpy, and it is not used).

## Notes for a resume

- Build the witch: `python3 tools/characters/witch_ref.py --out assets/characters --preview DIR`.
- Build the NPCs: `python3 tools/characters/npc_crude.py --out assets/characters --preview DIR [--only ID]`.
- Import after a GLB changes: `/root/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --import`.
- Filtered tests: `/root/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --script res://tests/run_tests.gd -- <filter>`
  (check for `TESTS PASSED` and absence of `SCRIPT ERROR` / `Parse Error` / `ERROR:`).
- Real-render captures: `xvfb-run -a /root/godot/Godot_v4.6.3-stable_linux.x86_64 --path . --rendering-method gl_compatibility
  --rendering-driver opengl3 --resolution 1280x720 --script res://tools/characters/capture_witch.gd -- OUT_DIR`.
