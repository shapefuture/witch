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

# 1. Import + parse the whole project (registers class_names, compiles addons).
"$GODOT" --headless --path . --import >"$LOG" 2>&1
if grep -E "SCRIPT ERROR|Parse Error|ERROR: Failed to load script|ERROR: Failed to compile" "$LOG"; then
	echo "GATE FAIL: project import produced script errors"; fail=1
fi

# 2. Run the suite.
"$GODOT" --headless --path . --script res://tests/run_tests.gd ${1:+-- "$1"} >"$LOG" 2>&1
code=$?
cat "$LOG"
if [ "$code" -ne 0 ]; then echo "GATE FAIL: runner exit code $code"; fail=1; fi
if ! grep -q "^TESTS PASSED:" "$LOG"; then echo "GATE FAIL: no positive proof the suite ran"; fail=1; fi
# Dialogue Manager 3.10.4 (vendored, unmodified) keeps its parsed dialogue resource alive
# through process exit, which Godot reports as two shutdown messages. They happen even with no
# game state involved, so they are allow-listed here, and ONLY these two. Leaked Nodes of our
# own are checked inside the runner (orphan count) and still fail the run.
ALLOWED='resources still in use at exit|ObjectDB instances leaked at exit'
if grep -vE "$ALLOWED" "$LOG" | grep -E "SCRIPT ERROR|Parse Error|^ERROR:|^FAIL " >/dev/null; then echo "GATE FAIL: error markers in output"; fail=1; fi

if [ "$fail" -eq 0 ]; then echo "GATE PASS"; else exit 1; fi
