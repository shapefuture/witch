extends Node

const SAVE_PATH := "user://settings.cfg"
const FONT_PATH := "res://game/ui/fonts/pixel.ttf"

var master_volume: float = 1.0

func _ready() -> void:
	_load()
	_apply_volume()

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save()

# pixel.ttf covers the full Russian alphabet (including the letter yo) and the punctuation
# the script uses (guillemets, em dash, ellipsis).
func get_font() -> Font:
	return load(FONT_PATH) as Font

func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, -80.0 if master_volume <= 0.0 else linear_to_db(master_volume))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		master_volume = cfg.get_value("settings", "master_volume", 1.0)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.save(SAVE_PATH)
