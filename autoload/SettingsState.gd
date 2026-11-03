extends Node

const SAVE_PATH := "user://settings.cfg"
const FONT_PATH := "res://game/ui/fonts/pixel.ttf"

var master_volume: float = 1.0
# Accessibility: the diegetic text size (one of UIKit.TEXT_SCALES) and the reduced-effects switch
# (PSXGlobals). Defaults are the full look (STYLE_BIBLE SC6) at the designed text size.
var text_scale: float = 1.0
var reduced_effects: bool = false
# Where the settings live. Tests point it at their own file.
var save_path := SAVE_PATH

func _ready() -> void:
	reload()

# Reads the settings file (missing values keep their defaults) and applies everything.
func reload() -> void:
	master_volume = 1.0
	text_scale = 1.0
	reduced_effects = false
	_load()
	_apply_volume()
	_apply_text_scale()
	_apply_effects()

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save()

func set_text_scale(scale: float) -> void:
	text_scale = _nearest_text_scale(scale)
	_apply_text_scale()
	_save()

# The next text size step, wrapping from the largest back to the designed size.
func cycle_text_scale() -> void:
	var steps := UIKit.TEXT_SCALES
	set_text_scale(steps[(steps.find(text_scale) + 1) % steps.size()])

func set_reduced_effects(on: bool) -> void:
	reduced_effects = on
	_apply_effects()
	_save()

# pixel.ttf covers the full Russian alphabet (including the letter yo) and the punctuation
# the script uses (guillemets, em dash, ellipsis).
func get_font() -> Font:
	return load(FONT_PATH) as Font

func _nearest_text_scale(scale: float) -> float:
	var best := UIKit.TEXT_SCALES[0]
	for step in UIKit.TEXT_SCALES:
		if absf(step - scale) < absf(best - scale):
			best = step
	return best

func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, -80.0 if master_volume <= 0.0 else linear_to_db(master_volume))

func _apply_text_scale() -> void:
	UIKit.text_scale = text_scale

func _apply_effects() -> void:
	PSXGlobals.set_reduced_effects(reduced_effects)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		master_volume = float(cfg.get_value("settings", "master_volume", 1.0))
		text_scale = _nearest_text_scale(float(cfg.get_value("settings", "text_scale", 1.0)))
		reduced_effects = bool(cfg.get_value("settings", "reduced_effects", false))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.set_value("settings", "text_scale", text_scale)
	cfg.set_value("settings", "reduced_effects", reduced_effects)
	cfg.save(save_path)
