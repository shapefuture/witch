#!/usr/bin/env bash
# Walking in the painted room, in real pixels (tests/render/painted_walk_render.gd). Like render_check.sh it needs
# xvfb-run and a software OpenGL, and reports SKIPPED without them. Prints "RENDER FAILED" on failure.
#   GODOT=/path/to/godot ./tests/render/painted_walk_check.sh [output_dir]
set -u
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"

if ! command -v xvfb-run >/dev/null 2>&1; then
	echo "RENDER SKIPPED: xvfb-run not available (painted walk)"
	exit 0
fi

LOG="$OUT/painted_walk.log"
timeout 300 xvfb-run -a -s "-screen 0 1600x1000x24" "$GODOT" --path . \
	--rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1280x720 \
	--script res://tests/render/painted_walk_render.gd -- "$OUT" >"$LOG" 2>&1
if ! grep -q "^WALK RENDER PASSED" "$LOG"; then
	grep -E "^FAIL|SCRIPT ERROR|Parse Error|SHADER ERROR|^WALK RENDER" "$LOG" | head -20
	echo "RENDER FAILED: painted walk (log $LOG)"
	exit 1
fi
if grep -E "SHADER ERROR|SCRIPT ERROR|Parse Error|Shader compilation failed" "$LOG"; then
	echo "RENDER FAILED: painted walk logged shader/script errors"
	exit 1
fi
grep -E "^WALK RENDER|^viewport|silhouette" "$LOG"
echo "painted walk frames in $OUT"
