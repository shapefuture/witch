#!/usr/bin/env bash
# Release gate. Grades on error markers AND positive proof the suite ran,
# because Godot exits 0 when GDScript fails to compile.
#   GODOT=/path/to/godot ./tests/run_tests.sh [filter]
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
fail=0
render_skipped=0

# 1. Import + parse the whole project (registers class_names, compiles addons).
"$GODOT" --headless --path . --import >"$LOG" 2>&1
if grep -E "SCRIPT ERROR|Parse Error|^ERROR:|ERROR: Failed to load script|ERROR: Failed to compile" "$LOG"; then
	echo "GATE FAIL: project import produced script errors"; fail=1
fi

# 2. Run the suite.
timeout 900 "$GODOT" --headless --path . --script res://tests/run_tests.gd ${1:+-- "$1"} >"$LOG" 2>&1
code=$?
cat "$LOG"
if [ "$code" -ne 0 ]; then echo "GATE FAIL: runner exit code $code"; fail=1; fi
if ! grep -q "^TESTS PASSED:" "$LOG"; then echo "GATE FAIL: no positive proof the suite ran"; fail=1; fi
# Dialogue Manager 3.10.4 (vendored, unmodified) keeps its parsed dialogue resource alive
# through process exit, which Godot reports as two shutdown messages. They happen even with no
# game state involved, so they are allow-listed here, and ONLY these two. Leaked Nodes of our
# own are checked inside the runner (orphan count) and still fail the run.
# Pinned: exactly two resources (Dialogue Manager). A third leak of ours at exit fails the gate.
ALLOWED='2 resources still in use at exit|ObjectDB instances leaked at exit'
if grep -vE "$ALLOWED" "$LOG" | grep -E "SCRIPT ERROR|Parse Error|^ERROR:|^FAIL " >/dev/null; then echo "GATE FAIL: error markers in output"; fail=1; fi

# 3. Render regression (real shaders, real pixels). Skipped automatically when Xvfb / software GL
#    are unavailable, or with SKIP_RENDER=1.
if [ "${SKIP_RENDER:-0}" != "1" ]; then
	render_out="$(GODOT="$GODOT" ./tests/render/render_check.sh 2>&1)"
	echo "$render_out"
	if echo "$render_out" | grep -q "^RENDER FAILED"; then echo "GATE FAIL: render regression"; fail=1; fi
	if echo "$render_out" | grep -q "^RENDER SKIPPED"; then render_skipped=1; fi
	# Positive proof, as for the suite: a render step that printed neither a pass nor a skip did not run.
	if ! echo "$render_out" | grep -qE "^RENDER (PASSED|SKIPPED)"; then echo "GATE FAIL: no positive proof the render check ran"; fail=1; fi
fi

# Only a full run is the gate. A golden rewrite compares nothing, and a filtered run skips areas, so
# neither prints GATE PASS.
if [ -n "${UPDATE_GOLDEN:-}" ]; then
	[ "$fail" -eq 0 ] && { echo "GOLDENS UPDATED: review the diff, then run the gate again without UPDATE_GOLDEN (not a gate pass)"; exit 0; }
	exit 1
fi
if [ -n "${1:-}" ]; then
	[ "$fail" -eq 0 ] && { echo "FILTER PASS: '$1' only (not the gate: run without a filter)"; exit 0; }
	exit 1
fi
# A skipped render says so: the log then shows which gate passed.
if [ "$fail" -eq 0 ]; then
	if [ "$render_skipped" -eq 1 ] || [ "${SKIP_RENDER:-0}" = "1" ]; then echo "GATE PASS (render skipped)"; else echo "GATE PASS"; fi
else
	exit 1
fi
