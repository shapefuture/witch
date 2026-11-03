# CHARS progress

Worktree: `/home/user/witch/.claude/worktrees/agent-abc20107e61eff01c`, branch `worktree-agent-abc20107e61eff01c` (not pushed).
Base: 75de726. The designated branch `claude/loving-brown-whtlm0` (baa70f5) is merged in as ce56ddf, a merge commit, not a
fast-forward. No further merges: the coordinator integrates this branch.

## Done

- [x] Witch, X23 (copper-ginger hair, blue-grey eyes, pointed violet hat; `assets/characters/witch.glb`; frames in
  `docs/art/characters/witch_*`). The copper test replaces the ash-blond one (see `docs/art/characters.md`). Commit 2ccb979.
- [x] Miron, regenerated from `tools/characters/npc_crude.py`: 728 triangles, one surface, one 128 px atlas, four clips,
  1.72 m. The regeneration is deterministic (two runs, the same bytes). Commit b010282 had a ring collar and boots that
  stopped 4 cm above the floor. This change puts the collar at the back of the neck (the ring read as a beard), stands the
  boots on the floor, and keeps the three fixes from b010282: the collar shows, the head is larger, the sigil is clear of
  the scarf.
- [ ] Held out of the repository, not committed: elian, vera, ilya, janitor and concierge (a bird). Their GLBs, figure
  atlases and `.import` files, the town test `tests/world/test_npc_models.gd` and the lineup image are in the workcell's
  scratch folder `chars_extra`, so they cannot be committed by accident. The script still builds all six.

## Gate

- Gate for this commit: GATE PASS, TESTS PASSED 92 suites, 669 tests, 8212 assertions. The run came after the moves. Its
  only `ERROR:` lines are the two exit-time leak messages that the gate allow-lists.
- Text check (`python3 tools/text_tool.py check`): 0 errors, 263 warnings (unused keys; the data is not changed here).
- Privacy guard: 671 strings checked; the only flag is the known line.

## Next

- [ ] When the integrator takes the town in: move the five held files back and re-run `tests/world/test_npc_models.gd`
  (every `npc_state` id with a model: loads, is skinned, has idle, walk and talk, stays in budget, heights and floor).
- [ ] The game's own frames of Miron (and the five) at 480x360; the lineup was numpy, not the game renderer.
- [ ] Motion beyond the clips: the figures are rigid toys, so a walk swings the legs and little else.
- [ ] Shadow (`shadow.glb`) is unchanged, as the brief asks.

## Needs from the integrator

- `tools/characters/npc_crude.py` is committed whole, because `miron.glb` is generated from it. The same file carries the
  floor fixes for the five held characters (their boots, elian's cap, vera's first ring, the concierge's foot). No GLBs
  for them are committed.
- Miron's look changed from b010282 (back collar, box boots). Anything that was checked against the ring needs a look.
- Gate runs queue on the shared lock behind other workcells; one gate run covers the final state of a batch.
- Blender (bpy) is not installed: Python here is 3.13 and no bpy wheel is on hand for it. No builder this workcell needs
  it (`lowpoly_bake.py` is the only one that imports bpy, and it is not used).

## Notes for a resume

- Build Miron: `python3 tools/characters/npc_crude.py --out assets/characters --only miron --preview DIR`.
- Build the town, all six (the five held ones included): `python3 tools/characters/npc_crude.py --out assets/characters --preview DIR`.
- Build the witch: `python3 tools/characters/witch_ref.py --out assets/characters --preview DIR`.
- Import after a GLB changes: `/root/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --import`.
- Filtered tests: `/root/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --script res://tests/run_tests.gd -- <filter>`
  (check for `TESTS PASSED` and absence of `SCRIPT ERROR` / `Parse Error` / `ERROR:`).
- The full gate: `flock /tmp/witch-gate.lock env GODOT=/root/godot/Godot_v4.6.3-stable_linux.x86_64 ./tests/run_tests.sh > LOG 2>&1`,
  graded only by the `GATE PASS` and `TESTS PASSED` lines.
- Real-render captures: `xvfb-run -a /root/godot/Godot_v4.6.3-stable_linux.x86_64 --path . --rendering-method gl_compatibility
  --rendering-driver opengl3 --resolution 1280x720 --script res://tools/characters/capture_witch.gd -- OUT_DIR`.
