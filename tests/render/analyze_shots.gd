extends SceneTree

# Pixel checks over captured screenshots (see render_check.sh). Usage:
#   godot --headless --script res://tests/render/analyze_shots.gd -- start.png mundane.png magic.png
# Prints one STATS line per image and a final RENDER PASSED / RENDER FAILED line.

func _initialize() -> void:
	var paths := OS.get_cmdline_user_args()
	var stats := {}
	for path in paths:
		var image := Image.new()
		if image.load(path) != OK:
			print("RENDER FAILED: cannot read %s" % path)
			quit(1)
			return
		stats[path.get_file()] = _stats(image)
		print("STATS %s %s" % [path.get_file(), JSON.stringify(stats[path.get_file()])])
	var failures: Array[String] = []
	for name in stats.keys():
		var s: Dictionary = stats[name]
		# 360 internal rows whatever the window shape; the width expands from 480 (4:3) with the aspect.
		if s["height"] != 360 or s["width"] < 480:
			failures.append("%s: expected the 360-row internal resolution (>= 480 wide), got %dx%d" % [name, s["width"], s["height"]])
		if s["distinct_colors"] < 40:
			failures.append("%s: only %d distinct colours (blank or broken render?)" % [name, s["distinct_colors"]])
		if s["lit_fraction"] < 0.25:
			failures.append("%s: only %.0f%% of the frame is lit (scene missing?)" % [name, s["lit_fraction"] * 100.0])
		if s["luma_stddev"] < 0.05:
			failures.append("%s: no tonal variation (flat frame)" % name)
	if stats.has("start.png") and stats["start.png"]["text_pixels"] < 40:
		failures.append("start.png: the arrival subtitle strip has no text pixels")
	if stats.has("mundane.png") and stats.has("magic.png"):
		var mundane: int = stats["mundane.png"]["distinct_colors"]
		var magic: int = stats["magic.png"]["distinct_colors"]
		if float(magic) < float(mundane) * 1.15:
			failures.append("magic must visibly expand the palette: %d distinct colours vs %d mundane" % [magic, mundane])
	for failure in failures:
		print("RENDER FAIL ", failure)
	print("RENDER PASSED" if failures.is_empty() else "RENDER FAILED: %d problem(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _stats(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var colors := {}
	var lit := 0
	var sum := 0.0
	var sum_sq := 0.0
	var text_pixels := 0
	for y in range(height):
		for x in range(width):
			var c := image.get_pixel(x, y)
			colors[c.to_rgba32()] = true
			var luma := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			sum += luma
			sum_sq += luma * luma
			if luma > 0.12:
				lit += 1
			# Subtitle strip: light glyph pixels (narration is drawn blue-grey, luma about 0.8) inside the panel.
			if y >= 186 and y < 232 and x >= 10 and x < 310 and luma > 0.7:
				text_pixels += 1
	var count := float(width * height)
	var mean := sum / count
	return {
		"width": width, "height": height, "distinct_colors": colors.size(),
		"lit_fraction": snappedf(lit / count, 0.001), "mean_luma": snappedf(mean, 0.001),
		"luma_stddev": snappedf(sqrt(maxf(sum_sq / count - mean * mean, 0.0)), 0.001), "text_pixels": text_pixels,
	}
