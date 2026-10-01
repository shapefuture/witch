class_name BellView
extends Node3D

# The brass bell: it hangs tilted into the draught and, when it has a real prop to do it with, sways a
# little on its yoke. Decoration on the diorama clock; it reads no game state.

var tilt_deg := 24.0
var swing_deg := 0.0

func _ready() -> void:
	rotation_degrees.z = tilt_deg

func _process(_delta: float) -> void:
	if swing_deg != 0.0:
		var t := PSXGlobals.time()
		rotation_degrees.z = tilt_deg + swing_deg * (sin(t * 1.4) * 0.8 + sin(t * 2.3 + 0.6) * 0.2)
