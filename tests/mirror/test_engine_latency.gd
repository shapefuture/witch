extends TestCase

# Tap-to-commit latency budget (beads witch-29y.12.13). A tap submits one ordinary player action to the
# runtime behind the `Mirror` autoload (MirrorRuntime.submit: the action queue, the engine's resolve_action,
# the `committed` signal) and gets the committed result back. That path must stay fast at the log size of a
# long play session, because the engine's per-action cost grows with the event log (docs/engine/BENCH.md).
#
# Log size, from evidence (the reasoning is also in docs/engine/BENCH.md, "Latency budget"):
#   - the simulations (data/sim) commit about 2.6 events per authored action (patient_with_bell: 8 steps,
#     21 events); the soak (tools/soak.gd, 3 seeds of 400 steps) about 2.0 (90 to 120 commits, 211 to 229 events);
#   - a player commits about one consequential action every 15 s (tap an object, pick an option, read the
#     lines): 4 a minute, about 10 events a minute;
#   - the Mirror clock (PropEvents.seconds_per_tick = 1.0, game/mirror/prop_events.gd) commits one
#     TimeAdvanced event per second of play while the hall coordinator is attached: 60 events a minute. It is
#     not wired into game_root.gd yet, but it is the design, and it dominates the log.
#   So a minute of play writes about 70 events. Session length is still open (docs/design/PREPRODUCTION.md,
#   DQ5); a long mobile session is taken as 45 minutes, about 3,150 events. LOG_EVENTS rounds that to 3,000.
#   The log is built with that mix (CLOCK_TICKS_PER_ACTION clock ticks per authored action).
#
# Budget: 50 ms per ordinary interaction on a phone. This container (x86 Xeon, 2.1 GHz base) runs GDScript
# about three times faster on one core than a mid-range phone's big core, so the in-gate budget is
# 50 ms / PHONE_SLOWDOWN = 16 ms (rounded down). The assertion is on the 95th percentile of SAMPLES
# committed taps after WARMUP; refusals are not timed.
#
# Do not raise the budget to make this pass. If it fails, the engine is over budget: see BENCH.md.

const LOG_EVENTS := 3000
const CLOCK_TICKS_PER_ACTION := 15
const PHONE_BUDGET_MS := 50.0
const PHONE_SLOWDOWN := 3.0
const GATE_BUDGET_MS := 16.0
const WARMUP := 10
const SAMPLES := 100
const ACTIONS := [
	["look_bell", "bell"],
	["look_tomas", "tomas"],
	["wait_watch", "tomas"],
	["look_machine", "machine"],
]

var _serial := 0

# One tap: submit through the queue, as the game does, and return the result the queue finished with.
func _tap(r: MirrorRuntime, index: int) -> Dictionary:
	var entry: Array = ACTIONS[index % ACTIONS.size()]
	_serial += 1
	var finished: Array = []
	var on_finished := func(result: Dictionary) -> void: finished.append(result)
	r.queue.finished.connect(on_finished)
	r.submit(r.make_action(str(entry[0]), str(entry[1]), {}, "latency-%d" % _serial))
	r.queue.finished.disconnect(on_finished)
	return finished[0] if not finished.is_empty() else {}

func _build_log(r: MirrorRuntime, target: int) -> void:
	var step := 0
	while r.engine.event_store.size() < target and step < target * 2:
		if step % (CLOCK_TICKS_PER_ACTION + 1) == CLOCK_TICKS_PER_ACTION:
			r.resolve_now(r.make_action(str(ACTIONS[step % ACTIONS.size()][0]), str(ACTIONS[step % ACTIONS.size()][1]), {}, "build-%d" % step))
		else:
			r.minds.advance_time(1, "clock")
		step += 1

func test_tap_to_commit_p95_stays_within_budget_at_a_long_session_log() -> void:
	var r := GameFixtures.runtime()
	var build_start := Time.get_ticks_msec()
	_build_log(r, LOG_EVENTS)
	var build_seconds := (Time.get_ticks_msec() - build_start) / 1000.0
	ok(r.engine.event_store.size() >= LOG_EVENTS, "the log reached %d events (has %d)" % [LOG_EVENTS, r.engine.event_store.size()])
	ok(not r.is_busy(), "the queue is idle before timing")

	for i in WARMUP:
		_tap(r, i)
	var times: Array = []
	var refused := 0
	var attempt := 0
	while times.size() < SAMPLES and attempt < SAMPLES * 4:
		var start := Time.get_ticks_usec()
		var result := _tap(r, attempt)
		var elapsed := Time.get_ticks_usec() - start
		attempt += 1
		if result.get("ok", false):
			times.append(elapsed)
		else:
			refused += 1
	eq(times.size(), SAMPLES, "enough committed taps were timed (refused %d)" % refused)
	if times.is_empty():
		return
	times.sort()
	var n := times.size()
	var p50_ms: float = times[n / 2] / 1000.0
	var p95_ms: float = times[mini(n - 1, int(ceil(n * 0.95)) - 1)] / 1000.0
	print("  latency: %d events (built in %.1f s), %d taps: p50 %.2f ms, p95 %.2f ms, max %.2f ms; gate budget p95 <= %.1f ms (%.0f ms on a phone / %.1f)" % [
		r.engine.event_store.size(), build_seconds, n, p50_ms, p95_ms, times[n - 1] / 1000.0, GATE_BUDGET_MS, PHONE_BUDGET_MS, PHONE_SLOWDOWN])
	ok(GATE_BUDGET_MS <= PHONE_BUDGET_MS / PHONE_SLOWDOWN, "the gate budget keeps the stated headroom")
	ok(p95_ms <= GATE_BUDGET_MS,
		"LATENCY BUDGET EXCEEDED: tap-to-commit p95 %.2f ms > %.1f ms at %d events (p50 %.2f ms). The engine is over budget; do not raise the budget. See docs/engine/BENCH.md." % [
		p95_ms, GATE_BUDGET_MS, r.engine.event_store.size(), p50_ms])
