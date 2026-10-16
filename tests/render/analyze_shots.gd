extends SceneTree

# Luma thresholds for the subtitle check: the bubble's lettering is dark ink on pale paper.
const INK_LUMA := 0.40
const PAPER_LUMA := 0.75

# Pixel checks over captured screenshots (see render_check.sh). Usage:
#   godot --headless --script res://tests/render/analyze_shots.gd -- start.png mundane.png magic.png
# Prints one STATS line per image and a final RENDER PASSED / RENDER FAILED line.
# The arrival subtitle is measured inside the box the capture recorded for it (start.subtitle.json, written
# beside the picture by game_root.gd): a frame that recorded no subtitle box has no subtitle to measure.

func _initialize() -> void:
	var paths := OS.get_cmdline_user_args()
	var stats := {}
	var failures: Array[String] = []
	for path in paths:
		var image := Image.new()
		if image.load(path) != OK:
			print("RENDER FAILED: cannot read %s" % path)
			quit(1)
			return
		stats[path.get_file()] = _stats(image)
		print("STATS %s %s" % [path.get_file(), JSON.stringify(stats[path.get_file()])])
		if path.get_file() == "start.png":
			failures.append_array(_subtitle_failures(path, image))
	for name in stats.keys():
		var s: Dictionary = stats[name]
		# 540 internal rows whatever the window shape; the width expands from 720 (4:3) with the aspect.
		if s["height"] != 540 or s["width"] < 720:
			failures.append("%s: expected the 540-row internal resolution (>= 720 wide), got %dx%d" % [name, s["width"], s["height"]])
		if s["distinct_colors"] < 40:
			failures.append("%s: only %d distinct colours (blank or broken render?)" % [name, s["distinct_colors"]])
		if s["lit_fraction"] < 0.25:
			failures.append("%s: only %.0f%% of the frame is lit (scene missing?)" % [name, s["lit_fraction"] * 100.0])
		if s["luma_stddev"] < 0.05:
			failures.append("%s: no tonal variation (flat frame)" % name)
	if stats.has("mundane.png") and stats.has("magic.png"):
		var mundane: int = stats["mundane.png"]["distinct_colors"]
		var magic: int = stats["magic.png"]["distinct_colors"]
		if float(magic) < float(mundane) * 1.15:
			failures.append("magic must visibly expand the palette: %d distinct colours vs %d mundane" % [magic, mundane])
	for failure in failures:
		print("RENDER FAIL ", failure)
	print("RENDER PASSED" if failures.is_empty() else "RENDER FAILED: %d problem(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _subtitle_failures(path: String, image: Image) -> Array[String]:
	var box := _subtitle_box(path)
	if not box.has_area():
		return ["start.png: no arrival subtitle on screen (the capture recorded no subtitle box to measure)"]
	var ink := 0
	var paper := 0
	var area := 0
	for y in range(maxi(int(box.position.y), 0), mini(int(box.end.y), image.get_height())):
		for x in range(maxi(int(box.position.x), 0), mini(int(box.end.x), image.get_width())):
			var luma := _luma(image.get_pixel(x, y))
			area += 1
			if luma < INK_LUMA:
				ink += 1
			elif luma > PAPER_LUMA:
				paper += 1
	# The bubble is pale paper with dark lettering: the box must be mostly paper (the bubble is there) and must hold
	# ink (its words are there). A box over the scene has no paper; an empty bubble has no ink.
	if area == 0 or float(paper) / area < 0.4:
		return ["start.png: the arrival subtitle box is not paper (no speech bubble over the scene)"]
	if ink < 200:
		return ["start.png: the arrival subtitle has only %d ink pixels in its box (expected 200 or more)" % ink]
	return []

func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

# The subtitle's rectangle in picture pixels, from the sidecar the capture wrote beside the picture.
func _subtitle_box(path: String) -> Rect2:
	var sidecar := path.get_basename() + ".subtitle.json"
	if not FileAccess.file_exists(sidecar):
		return Rect2()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
	if not (data is Dictionary) or not (data.get("subtitle") is Array):
		return Rect2()
	var v: Array = data["subtitle"]
	if v.size() != 4:
		return Rect2()
	return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))

func _stats(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var colors := {}
	var lit := 0
	var sum := 0.0
	var sum_sq := 0.0
	for y in range(height):
		for x in range(width):
			var c := image.get_pixel(x, y)
			colors[c.to_rgba32()] = true
			var luma := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			sum += luma
			sum_sq += luma * luma
			if luma > 0.12:
				lit += 1
	var count := float(width * height)
	var mean := sum / count
	return {
		"width": width, "height": height, "distinct_colors": colors.size(),
		"lit_fraction": snappedf(lit / count, 0.001), "mean_luma": snappedf(mean, 0.001),
		"luma_stddev": snappedf(sqrt(maxf(sum_sq / count - mean * mean, 0.0)), 0.001),
	}
