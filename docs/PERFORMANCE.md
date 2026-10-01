# Performance

Measure first, optimise when something is actually slow, and keep the visual identity a design
constraint: **320x240 is the look, not a hack**. Complexity budget goes to behaviour, state,
knowledge, interaction and consequence, not geometry.

## Measured (this repository, Linux, software rendering irrelevant: CPU-side logic only)

`godot --headless --path . --script res://tools/perf_probe.gd`; the catalog is the authored one
(15 actions, 24 KB canonical JSON). Wall-clock on a development machine; use ratios, and expect a
phone to be roughly 3-5x slower.

| Operation | Before audit | Now |
|---|---|---|
| `resolve_action`, 900 events | ~245 ms (linear in log length) | ~8 ms (flat) |
| `resolve_action`, 1,800 events | not measurable | ~10 ms |
| `options_for` (all four targets) | ~37 ms | ~5 ms |
| `explain_for` (debug panel) | ~17 ms | ~1.4 ms |
| `preview_action` | ~240 ms (rollback re-hashed the log) | ~30 ms |
| Load a save, 1,800 events | not measured | ~1.1 s (one SHA-256 per event + replay) |
| Load a save, ~150 events (a real session) | | ~90 ms |
| Save encode, 1,800 events | | ~290 ms, 2.7 MB |
| Catalog SHA-256 fingerprint | 5 ms, recomputed 3-4x per action | 5 ms, once at lock |

What the audit found: the PR attributed cost to `_snapshot()` (measured: 16 ms at 900 events).
The real cost was `_validate_post_commit()` re-hashing the **entire** chain on every commit
(215 ms), then recomputing the catalog fingerprint repeatedly. Fixed by validating only the
appended delta, rolling back by truncation, and a cheap tamper stamp. Hashes are byte-identical
(`tests/mirror/test_golden_and_rollback.gd`).

Remaining O(n) work, all off the tap-to-result path: loading a save, `audit_integrity()`, and
the encode cost. Saves are pretty-printed for readability; if a real session ever makes them
large, compact them and/or snapshot projections.

## Scene (the archive hall)

Static set: ~35,000 triangles in one batch of 23 surfaces (one draw call per painted tile) plus
~2,000 for the animated machine and bell and ~1,500 for the camera frame. No Godot lights and no
shadows: the set is unshaded (light is baked into vertex colours), characters sample a 96x96 light
map. Per frame the extras are a handful of additive meshes (two shaft prisms, a floor glow, 150
dust quads in one MultiMesh) and the diegetic UI (three to ten tiny slabs and Label3Ds). Fill is
the 480x360 base (about 170k pixels at 4:3, 290k at 20:9) with one full-screen grade pass that
samples the screen texture's mip chain for glow.

These budgets are **tests** (`tests/render/test_archive_hall.gd`): <= 60,000 static triangles,
<= 28 surfaces, painted tiles <= 256 px. The set GLB is about 4.5 MB; textures 0.8 MB.

## What to measure on real hardware

CPU frame time, GPU frame time, draw calls, visible meshes, particle cost, VRAM, scene load
time and **input latency** (touch to first reaction), per profile:

- **Mobile**: Compatibility (OpenGL ES 3) is the configured renderer. Check the vertex shader cost
  (snap + sway on ~110k split vertices) and the one screen-texture read; if either hurts, split the
  static batch into four regions so culling helps, and drop the bloom taps.
- **Desktop**
- **Capture/High**: for marketing shots.

No scalability system is built until the visual identity is settled.

## Budgets worth holding

| Path | Budget |
|---|---|
| Commit + first reaction after a tap | < 50 ms on a phone |
| Open the action surface | < 10 ms of logic |
| Load a typical save | < 250 ms |
