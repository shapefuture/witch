class_name StagedReveal
extends RefCounted

# A plaque's inspection reveal in layers (ROOM_OF_US item 3): one layer per tap, in a fixed order whatever order the
# data was written in: the evocative line, then a surprise, a memory, and a connection to something else. An object
# shows only the layers it has. The last layer stays until the player moves on.

const ORDER := ["evocative", "surprise", "memory", "connection"]

var _keys: Array[String] = []
var _at := 0

# `layers` maps a layer name (see ORDER) to its text key. Unknown layer names are ignored, not guessed at.
func _init(layers: Dictionary = {}) -> void:
	for layer in ORDER:
		if layers.has(layer):
			_keys.append(str(layers[layer]))

func layer_count() -> int:
	return _keys.size()

# The key shown now, or "" when the object has no layers.
func current() -> String:
	return _keys[_at] if _at < _keys.size() else ""

# One more layer. Returns false (and changes nothing) once the last layer is showing.
func advance() -> bool:
	if _at + 1 >= _keys.size():
		return false
	_at += 1
	return true

func at_last() -> bool:
	return _at >= _keys.size() - 1
