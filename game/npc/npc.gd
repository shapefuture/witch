class_name NPC
extends Node3D

# An actor in the room. Its BEHAVIOUR (what it expects, how it responds) lives in Mirror; this
# node only knows how to LOOK like a pose. Poses are named by Mirror response presentation
# ("npc" entries) and mapped to anchors (where to stand, which way to face).

signal pose_changed(pose: String)

@export var actor_id := ""

# pose name -> {"position": Vector3, "yaw_deg": float}
var anchors: Dictionary = {}
var pose := ""
var visual: Node3D
var _time := 0.0
var _body_rest := Vector3.ZERO

func _ready() -> void:
	add_to_group("camera_target")
	if visual == null:
		var model := CharacterModels.instantiate(actor_id) if actor_id != "" else null
		set_visual(model if model != null else Placeholders.tomas())
	BlobShadow.attach(self, 0.38, 0.95)

func set_visual(new_visual: Node3D) -> void:
	if visual != null:
		visual.queue_free()
	visual = new_visual
	add_child(visual)

# Snaps to a pose immediately (used at load and in headless tests).
func snap_pose(pose_name: String) -> void:
	_apply_anchor(pose_name)
	pose = pose_name
	_reset_limbs()

# Walks/turns into a pose over `duration` and resolves when settled.
func set_pose(pose_name: String, duration: float = 0.9) -> void:
	if pose_name == pose:
		return
	pose = pose_name
	var anchor: Dictionary = anchors.get(pose_name, {})
	if not anchor.is_empty():
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "position", anchor["position"], duration).set_trans(Tween.TRANS_SINE)
		tween.tween_property(self, "rotation_degrees:y", float(anchor["yaw_deg"]), duration).set_trans(Tween.TRANS_SINE)
		await tween.finished
	_reset_limbs()
	pose_changed.emit(pose_name)

func face_point(point: Vector3) -> void:
	var direction := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if direction.length() > 0.01:
		rotation.y = atan2(direction.x, direction.z)

# One-shot gestures: pause (freeze), look_up (head tips back).
func play_anim(animation_name: String) -> void:
	if CharacterModels.player_of(visual) != null:
		if animation_name == "look_up":
			CharacterModels.play(visual, "talk", 0.8)
		await get_tree().create_timer(1.0 if animation_name == "pause" else 1.2).timeout
		_play_pose_clip()
		return
	var head := visual.get_node_or_null("Head") as Node3D if visual != null else null
	var tween := create_tween()
	match animation_name:
		"pause":
			tween.tween_interval(1.0)
		"look_up":
			if head != null:
				tween.tween_property(head, "rotation_degrees:x", -35.0, 0.35)
				tween.tween_interval(0.5)
				tween.tween_property(head, "rotation_degrees:x", 0.0, 0.35)
		_:
			tween.tween_interval(0.05)
	await tween.finished

func _apply_anchor(pose_name: String) -> void:
	var anchor: Dictionary = anchors.get(pose_name, {})
	if not anchor.is_empty():
		position = anchor["position"]
		rotation_degrees.y = float(anchor["yaw_deg"])

func _reset_limbs() -> void:
	if visual == null:
		return
	if _play_pose_clip():
		return
	for limb in ["ArmL", "ArmR"]:
		var node := visual.get_node_or_null(limb) as Node3D
		if node != null:
			node.rotation_degrees = Vector3.ZERO
	var body := visual.get_node_or_null("Body") as Node3D
	if body != null:
		body.scale = Vector3.ONE
		body.position = Vector3(0, 0.45, 0)

# A real model shows a pose with one of its clips. Returns false for a placeholder.
func _play_pose_clip() -> bool:
	match pose:
		"working":
			return CharacterModels.play(visual, "work")
		"partnered":
			return CharacterModels.play(visual, "work", 0.6)
		"inviting":
			return CharacterModels.play(visual, "talk")
		"withdrawn":
			return CharacterModels.play(visual, "idle", 0.5)
	return CharacterModels.play(visual, "idle")

func _process(delta: float) -> void:
	if visual == null or CharacterModels.player_of(visual) != null:
		return
	_time += delta
	var left := visual.get_node_or_null("ArmL") as Node3D
	var right := visual.get_node_or_null("ArmR") as Node3D
	var body := visual.get_node_or_null("Body") as Node3D
	match pose:
		"working", "partnered":
			if right != null:
				right.rotation_degrees.x = -35.0 + sin(_time * (5.0 if pose == "working" else 2.5)) * 14.0
			if left != null:
				left.rotation_degrees.x = -25.0 + sin(_time * 3.0 + 1.0) * 6.0
		"braced":
			if left != null:
				left.rotation_degrees.z = -38.0
			if right != null:
				right.rotation_degrees.z = 38.0
		"inviting":
			if right != null:
				right.rotation_degrees.x = -80.0
		"withdrawn":
			if body != null:
				body.scale = Vector3(1.0, 0.72, 1.0)
				body.position = Vector3(0, 0.33, 0)
		"quiet":
			if left != null:
				left.rotation_degrees.x = 0.0
