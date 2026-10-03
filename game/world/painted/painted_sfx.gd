class_name PaintedSfx
extends Node

# The painted room's tiny sound player. The sounds are the WAVs tools/painted/synth.py writes to assets/painted/sfx,
# named by props.json's "sound" slots. A few voices take turns so quick pokes overlap instead of cutting each
# other off. Nothing here depends on the audio device: with a dummy driver (headless) play() still counts.

signal played(sound: String)

const DIR := "res://assets/painted/sfx/"
const VOICES := 4

var play_count := 0
var last_sound := ""
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		add_child(player)
		_players.append(player)

static func path_of(sound: String) -> String:
	return DIR + sound + ".wav"

static func exists(sound: String) -> bool:
	return ResourceLoader.exists(path_of(sound))

# Plays `sound` and returns whether it exists. The pitch drifts a little from poke to poke (deterministically),
# so a rattle poked three times is not the same rattle.
func play(sound: String) -> bool:
	if sound.is_empty():
		return false
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		if not exists(sound):
			return false
		stream = load(path_of(sound)) as AudioStream
		_streams[sound] = stream
	play_count += 1
	last_sound = sound
	if not _players.is_empty():
		var player := _players[_next % _players.size()]
		_next += 1
		player.stream = stream
		player.pitch_scale = 1.0 + 0.05 * sin(float(play_count) * 2.399)
		player.play()
	played.emit(sound)
	return true
