# Mirror Engine benchmark (branch wc/H)

Both engines were measured on the same machine in the same session: a 4-core Linux container,
Godot 4.6.3 headless, load average about 0.8 during the runs. Two runs per engine. Wall-clock
numbers vary by machine; the comparison is between the rows of this table, not with other machines.

## Method

- **This engine** (`addons/mirror_engine` 1.3.1 with the hardening on this branch): `tools/bench.gd`,
  run as `godot --headless --path . --script res://tools/bench.gd -- 5000 200`. It builds the
  authored catalog (`data/mirror`), commits about 5,000 events with four authored actions, then
  times 200 committed `resolve_action` calls (refusals are not in the percentiles), the save and
  load, and a full chain verification.
- **Draft** (`/tmp/.../draft/mirror-engine`): its own `tools/bench.gd`, unmodified, run from a copy in
  the scratch directory outside the repository (`godot --headless --path . -s res://tools/bench.gd`).
  Its budgets are printed in the JSON. Its action timings use a new kernel per round.
- **Draft, same content, warm kernel** (scratch script on the same copy, outside the repository): the
  draft's golden actions, timed on one kernel for 10 rounds, on a fresh log and after 5,000 events.
  This was added to separate its cold-start cost from its per-action cost.

Content is not the same: the draft measures its golden path, this engine measures the authored hall.
Action counts are not the same either: the draft's bench counts every call, this engine counts
committed calls only.

## Results

### Actions

| Measurement | Run 1 | Run 2 |
| --- | --- | --- |
| This engine, fresh log: p50 / p95 | 3.93 / 7.87 ms | 3.53 / 7.11 ms |
| This engine, at 5,466 events: p50 / p95 / max | 29.6 / 42.0 / 55.6 ms | 29.9 / 40.1 / 86.1 ms |
| Draft (its bench), fresh kernels: p50 / p95 / max | 9.9 / 27.6 / 35.8 ms | 10.3 / 19.5 / 57.2 ms |
| Draft, same golden actions, warm kernel, fresh log: p50 / p95 | 1.36 / 9.9 ms | (one run) |
| Draft, same golden actions, warm kernel, 5,000 events: p50 / p95 | 1.47 / 9.96 ms | (one run) |

The draft's own budget (p95 at most 25 ms) failed in run 1 and passed in run 2 on the same machine.

### Save, load and queries

| Measurement | This engine, run 1 | This engine, run 2 | Draft, run 1 | Draft, run 2 |
| --- | --- | --- | --- | --- |
| Events | 5,466 | 5,466 | 5,000 | 5,000 |
| Save (engine JSON / envelope) | 1.23 s / 1.97 s | 1.27 s / 2.03 s | not timed alone | not timed alone |
| Save bytes (engine / envelope) | 14.9 MB / 10.2 MB | same | 1.77 MB plain, 254 KB compressed | same |
| Load (verify, replay, check) | 5.63 s | 6.08 s | 2.16 s save+load | 2.36 s save+load |
| Load with full fold / with snapshot | not separate | not separate | 1.58 s / 1.28 s | 1.46 s / 1.52 s |
| Chain verification | 1.32 s | 1.32 s | not timed | not timed |
| Indexed lookup by event id (p50) | 1 µs | 1 µs | query 0.66 ms | query 0.69 ms |

The draft's query is a filtered log query, this engine's lookup is by id: they are not the same operation.
The byte counts are not the same format either: this engine pretty-prints with four-space indentation
and a checksum, the draft writes plain JSON.

Building 5,000 events took 30 to 35 s on this engine.

## What the numbers say

1. **This engine's action cost grows with the log.** At a fresh log a committed action takes about
   3.5 to 4 ms (p50). At about 5,500 events it takes about 30 ms (p50). The draft's golden actions
   stay near 1.4 ms in the warm measure at both sizes. The profile of this engine at 5,000 events
   (`_snapshot()` alone about 15 ms of roughly 33 ms per action):
   - models: 2,143 observations are copied on every snapshot (`models.to_dict`, about 5.6 ms),
   - action memory: 6,430 keys (`duplicate(true)`, about 3.4 ms),
   - relationships (about 3.6 ms), evidence (about 2.9 ms),
   - the event indexes: `append_bundle` copies `_by_id` and `_by_transaction` on every append (about 2.5 ms and 2.2 ms).
   The rest is validation and the commit itself. None of this is changed here: the fix is incremental
   snapshots or copy-on-write for the models, the memory and the indexes, and it needs its own change
   with the golden transcripts checked.
2. **Load is dominated by replay and parsing.** At 5,500 events: parsing the 15 MB text about 1.5 s,
   the checksum about 0.74 s, the replay and restore the rest (about 3 s). Save is about 1.3 s.
3. **Save size.** About 2.7 KB per event on this engine, against about 0.35 KB per event in the draft.
   Four-space indentation accounts for about 31% of the engine save: the envelope, which re-indents with a tab, is 10.2 MB against 14.9 MB for the same content. A compact encoding is a format change and
   was not made here.
4. **Soak (`tools/soak.gd`, not in the gate).** Six seeds of 400 random steps, 80 audits (each audit
   verifies the chain and reloads a save into a twin engine with the identical projection and head).
   No failures; 16.6 s in total. About three quarters of requests are refused (15% of them are deliberately
   unknown requests): the authored catalog has many actions unavailable at any given time, and a refusal that
   leaves the chain head unchanged is counted as correct behaviour.

## Not done, and why

- The draft's soak was not run; only its bench was asked for.
- The soak does not shrink a failing run to a minimal reproduction (the draft's ddmin). The seed and step
  are printed, which is enough to reproduce.
- The engine's bench has no pass or fail budgets; the gate's budget is the latency test below.
- No optimisation of the snapshot or the save format was made; see findings 1 and 3.

## Latency budget (witch-29y.12.13)

`tests/mirror/test_engine_latency.gd` fails the gate when a tap is too slow at the log size of a long
play session. It times the path a tap takes: `MirrorRuntime.submit` (the class behind the `Mirror`
autoload), the action queue, `resolve_action`, the `committed` signal, until the queue finishes with the
committed result. No presenter is attached, so presentation is not timed.

**Log size: 3,000 events.** Evidence:
- The simulations commit about 2.6 events per authored action (`patient_with_bell`: 8 steps, 21 events);
  the soak (3 seeds of 400 steps) about 2.0 (90 to 120 commits, 211 to 229 events).
- A player commits about one consequential action every 15 s (tap an object, pick an option, read the
  lines): 4 a minute, about 10 events.
- The Mirror clock (`PropEvents.seconds_per_tick = 1.0`) commits one `TimeAdvanced` event per second
  while the hall coordinator is attached: 60 a minute. The coordinator is not wired into `game_root.gd`
  yet, but this is the design, and it is most of the log.
- About 70 events a minute. Session length is open (DQ5 in `docs/design/PREPRODUCTION.md`); a long mobile
  session is taken as 45 minutes, about 3,150 events, rounded to 3,000. The test builds its log with the
  same mix: 15 clock ticks per authored action. A save carries its log, so a game resumed across sessions
  keeps growing; the curve below shows where the budget runs out.

**Budget: p95 at most 16 ms in the gate.** The target is 50 ms per ordinary interaction on a phone. This
container (Intel Xeon, 2.1 GHz base, 4 cores) runs single-threaded GDScript about three times faster than a
mid-range phone's big core, so the gate budget is 50 ms / 3, rounded down to 16 ms. The assertion is on
the 95th percentile of 100 committed taps after 10 warm-up taps; the median is printed too.

Measured in the gate's test (three runs, same container, load average about 3 from other jobs): 3,252
events at the end, built in 5.2 to 5.8 s; **p50 5.8 to 6.0 ms, p95 9.8 to 10.5 ms**, max 13.6 to 17.2 ms.
The test passes with about 35% headroom.

`tools/bench.gd` now prints the same measurement at several log sizes (`tap_curve_*`, default
1,000 to 5,000 events). One run (the timed taps of each row stay in the log, so each row is about 230
events past its target):

| Events | Session mix p50 / p95 | Actions only p50 / p95 |
| --- | --- | --- |
| about 1,230 | 4.9 / 9.4 ms | 9.7 / 14.4 ms |
| about 2,230 | 6.4 / 10.4 ms | 13.5 / 18.8 ms |
| about 3,230 | 8.4 / 14.8 ms | 17.3 / 22.3 ms |
| about 4,230 | 9.8 / 16.0 ms | 25.7 / 35.2 ms |
| about 5,230 | 11.4 / 18.0 ms | 28.1 / 38.0 ms |

What this says:
- Cost grows roughly linearly with the log on both mixes; the session mix grows more slowly because clock
  events add little to the projection that `_snapshot()` copies (models, action memory, relationships).
- With the clock as designed, the gate budget is reached at about 4,200 events, an hour of play. A log of
  authored actions alone crosses it at about 2,000 events. Both point at the same fix as finding 1 above
  (incremental snapshots or copy-on-write), and a clock that commits only when something falls due would
  shrink the log by six sevenths.
- The bench's curve row at about 3,230 events (14.8 ms) is slower than the test (about 10 ms) because the
  bench's log also holds the earlier rows' timed taps (more authored actions).

## Reproduce

```sh
godot --headless --path . --script res://tools/bench.gd -- 5000 200 1000,2000,3000,4000,5000
./tests/run_tests.sh test_engine_latency
godot --headless --path . --script res://tools/soak.gd -- 6 400 25
```
