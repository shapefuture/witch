#!/usr/bin/env bash
# Captures the standard set of frames for a visual gauntlet round: the same scenes the critic
# compares against the bar, at the shapes that matter (4:3, 16:9, a 20:9 phone in landscape).
#
#   GODOT=/path/to/godot tools/visual_gauntlet/capture.sh out_dir
#
# Needs xvfb-run and software GL (Mesa llvmpipe). Frames are deterministic: the diorama clock
# is the frame count, so the same code renders the same pictures.
set -eu
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
OUT="${1:?usage: capture.sh out_dir}"
mkdir -p "$OUT"
shot() {
	local name="$1" res="$2"; shift 2
	xvfb-run -a -s "-screen 0 2800x1400x24" "$GODOT" --path . \
		--rendering-method gl_compatibility --rendering-driver opengl3 --resolution "$res" \
		-- --capture "$OUT/$name.png" --capture-frames 200 "$@" 2>&1 | grep -E "^CAPTURE|SCRIPT ERROR|Shader|Parse" || true
}
shot wide_169        1280x720
shot wide_43         1200x900
shot wide_phone_219  2400x1080
shot conversation    1280x720 --shot conversation
shot magic           1280x720 --shot magic_reveal --lens 1.0 --magic 0.8
shot options_machine 1280x720 --show-options machine
shot closeup_bell    1280x720 --cam 1.8,2.6,0.5,4.6,2.6,-3.0,55
shot top_down        1280x960 --no-fx --cam 1,26,-1,1,0,-2,45
echo "frames in $OUT"
