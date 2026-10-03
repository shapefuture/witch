class_name WitchAnimation
extends Node

# Idle, walk, interact and cast. A real model (CharacterModels) plays its own clips; a placeholder
# has its named parts driven procedurally.

var visual: Node3D
var walking := false
var _time := 0.0
var _busy := false

func _process(delta: float) -> void:
	if visual == null:
		return
	_time += delta
	if CharacterModels.player_of(visual) != null:
		if not _busy:
			CharacterModels.play(visual, "walk" if walking else "idle")
		return
	var body := visual.get_node_or_null("Body") as Node3D
	var hat := visual.get_node_or_null("Hat") as Node3D
	var bob := sin(_time * 10.0) * 0.045 if walking else sin(_time * 1.6) * 0.012
	visual.position.y = absf(bob)
	if hat != null:
		hat.rotation_degrees.z = -6.0 + (sin(_time * 5.0) * 4.0 if walking else sin(_time * 1.1) * 1.5)
	if body != null and walking:
		body.rotation_degrees.z = sin(_time * 10.0) * 2.0
	elif body != null:
		body.rotation_degrees.z = 0.0

func is_busy() -> bool:
	return _busy

# interact: a short reaching gesture. cast: wand raised, a flourish, lowered.
func play(animation_name: String) -> void:
	if visual == null or _busy:
		return
	if CharacterModels.player_of(visual) != null:
		await _play_clip(animation_name)
		return
	var arm := visual.get_node_or_null("ArmR") as Node3D
	if arm == null:
		return
	_busy = true
	var tween := create_tween()
	match animation_name:
		"interact":
			tween.tween_property(arm, "rotation_degrees:x", -70.0, 0.25)
			tween.tween_interval(0.35)
			tween.tween_property(arm, "rotation_degrees:x", 0.0, 0.25)
		"cast":
			tween.tween_property(arm, "rotation_degrees:x", -140.0, 0.3)
			tween.tween_property(arm, "rotation_degrees:z", 25.0, 0.2)
			tween.tween_property(arm, "rotation_degrees:z", -25.0, 0.3)
			tween.tween_property(arm, "rotation_degrees:z", 0.0, 0.2)
			tween.tween_property(arm, "rotation_degrees:x", 0.0, 0.3)
		_:
			tween.tween_interval(0.05)
	await tween.finished
	_busy = false

func _play_clip(animation_name: String) -> void:
	_busy = true
	var player := CharacterModels.player_of(visual)
	match animation_name:
		"cast":
			if CharacterModels.play(visual, "cast"):
				await player.animation_finished
		"interact":
			if CharacterModels.play(visual, "talk", 1.4):
				await get_tree().create_timer(0.7).timeout
		_:
			await get_tree().process_frame
	_busy = false
	CharacterModels.play(visual, "walk" if walking else "idle")
