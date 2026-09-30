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

## Scene (the Clearing)

133 nodes, 91 meshes (91 surfaces, so ~91 draw calls before batching), ~2,700 vertices,
4 lights, no shadows (the PSX shaders disable them). Trivial for a desktop; the first thing to
check on a phone is draw-call count: merge static props per material if it matters.

## What to measure on real hardware

CPU frame time, GPU frame time, draw calls, visible meshes, particle cost, VRAM, scene load
time and **input latency** (touch to first reaction), per profile:

- **Mobile**: Forward+ is the configured renderer; on phones evaluate Mobile and Compatibility.
  Compare the OpenGL compatibility path used by `render_check.sh` with the real target.
- **Desktop**
- **Capture/High**: for marketing shots.

No scalability system is built until the visual identity is settled.

## Budgets worth holding

| Path | Budget |
|---|---|
| Commit + first reaction after a tap | < 50 ms on a phone |
| Open the action surface | < 10 ms of logic |
| Load a typical save | < 250 ms |
