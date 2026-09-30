class_name MachineView
extends Node3D

# How the brass machine LOOKS for a given Mirror machine state. It reads state; it never
# decides it. Wrong-beat magic runs fast and uneven, working-together runs slow and even,
# singing glows.

const SPEEDS := {"jammed": 0.0, "running_by_magic": 4.2, "running_together": 1.3, "singing": 2.2}

var state := "jammed"
var _time := 0.0

func apply_state(new_state: String) -> void:
	state = new_state
	var indicator := get_node_or_null("Indicator") as Node3D
	if indicator != null:
		indicator.visible = state != "jammed"

func _process(delta: float) -> void:
	_time += delta
	var speed: float = SPEEDS.get(state, 0.0)
	if speed == 0.0:
		return
	var big := get_node_or_null("BigGear") as Node3D
	var small := get_node_or_null("SmallGear") as Node3D
	# Uneven by design when it is running by magic: the beat is wrong.
	var wobble := 1.0 + (0.6 * sin(_time * 7.0) if state == "running_by_magic" else 0.0)
	if big != null:
		big.rotate_object_local(Vector3.UP, speed * wobble * delta)
	if small != null:
		small.rotate_object_local(Vector3.UP, -speed * 1.9 * wobble * delta)
