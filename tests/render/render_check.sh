#!/usr/bin/env bash
# Render regression. Needs xvfb-run and a software OpenGL (Mesa llvmpipe) - both are optional:
# without them this script reports SKIPPED and exits 0 so the headless gate still works anywhere.
#
# It boots the real game under Xvfb with the OpenGL compatibility renderer (Godot cannot compile
# shaders headlessly), captures three scenarios, fails on any shader/script error in the log,
# then checks the pixels:  start (scene + Russian subtitle), mundane vs magic (palette expands).
#   GODOT=/path/to/godot ./tests/render/render_check.sh [output_dir]
set -u
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"

if ! command -v xvfb-run >/dev/null 2>&1; then
	echo "RENDER SKIPPED: xvfb-run not available"
	exit 0
fi

fail=0
capture() {
	local name="$1"; shift
	local log="$OUT/$name.log"
	timeout 240 xvfb-run -a -s "-screen 0 1280x960x24" "$GODOT" --path . \
		--rendering-method gl_compatibility --rendering-driver opengl3 \
		-- --capture "$OUT/$name.png" "$@" >"$log" 2>&1
	if ! grep -q "^CAPTURE .* (ok)" "$log"; then
		echo "RENDER FAIL: $name did not capture"; tail -5 "$log"; fail=1; return
	fi
	if grep -E "SHADER ERROR|SCRIPT ERROR|Parse Error|Shader compilation failed|ERROR: .*shader" "$log"; then
		echo "RENDER FAIL: $name logged shader/script errors"; fail=1
	fi
}

capture start --capture-frames 90
capture mundane --capture-frames 40 --sim-first impulsive_recovery --show-options path_out
capture magic --capture-frames 40 --sim-first impulsive_recovery --show-options path_out --magic 1.0
[ "$fail" -ne 0 ] && { echo "RENDER FAILED"; exit 1; }

"$GODOT" --headless --path . --script res://tests/render/analyze_shots.gd -- \
	"$OUT/start.png" "$OUT/mundane.png" "$OUT/magic.png" 2>&1 | grep -E "^STATS|^RENDER"
[ "${PIPESTATUS[0]}" -eq 0 ] && echo "screenshots in $OUT" || exit 1
