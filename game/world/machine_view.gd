class_name MachineView
extends Node3D

# How the brass machine LOOKS for a given Mirror machine state. It reads state; it never
# decides it. Wrong-beat magic runs fast and uneven, working-together runs slow and even,
# singing glows.

const SPEEDS := {"jammed": 0.0, "running_by_magic": 4.2, "running_together": 1.3, "singing": 2.2}

# The parts this view drives, each with every name it ships under: the placeholder machine uses the
# first, the Blender prop (assets/archive/props/machine.glb) the second, and glTF import appends a
# numeric suffix ("GearBig_001"), which part_matches ignores.
const PART_NAMES := {
	"BigGear": ["BigGear", "GearBig"],
	"SmallGear": ["SmallGear", "GearSmall"],
	"Indicator": ["Indicator"],
}

var state := "jammed"
var _time := 0.0
var _big: Node3D
var _small: Node3D
var _indicator: Node3D
# Extra gears (any other node named Gear*), turning about local Y, alternating direction.
var _gears: Array[Node3D] = []
var _resolved := false

func _ready() -> void:
	_resolve()

# True when `node_name` is one of the shipped names of `part` (glTF's "_001"-style suffix ignored).
static func part_matches(node_name: String, part: String) -> bool:
	var names: Array = PART_NAMES.get(part, [part])
	return names.has(_base_name(node_name))

static func _base_name(node_name: String) -> String:
	var cut := node_name.rfind("_")
	if cut > 0 and node_name.substr(cut + 1).is_valid_int():
		return node_name.substr(0, cut)
	return node_name

# The node that plays `part` (BigGear, SmallGear, Indicator), or null when this machine has none.
func find_part(part: String) -> Node3D:
	for node in find_children("*", "Node3D", true, false):
		if part_matches(str(node.name), part):
			return node as Node3D
	return null

func _resolve() -> void:
	if _resolved:
		return
	_resolved = true
	_big = find_part("BigGear")
	_small = find_part("SmallGear")
	_indicator = find_part("Indicator")
	_gears.clear()
	for node in find_children("Gear*", "Node3D", true, false):
		if node != _big and node != _small:
			_gears.append(node as Node3D)

func apply_state(new_state: String) -> void:
	_resolve()
	state = new_state
	if _indicator != null:
		_indicator.visible = state != "jammed"

func _process(delta: float) -> void:
	_resolve()
	_time += delta
	var speed: float = SPEEDS.get(state, 0.0)
	if speed == 0.0:
		return
	# Uneven by design when it is running by magic: the beat is wrong.
	var wobble := 1.0 + (0.6 * sin(_time * 7.0) if state == "running_by_magic" else 0.0)
	if _big != null:
		_big.rotate_object_local(Vector3.UP, speed * wobble * delta)
	if _small != null:
		_small.rotate_object_local(Vector3.UP, -speed * 1.9 * wobble * delta)
	for i in range(_gears.size()):
		_gears[i].rotate_object_local(Vector3.UP, speed * (1.0 if i % 2 == 0 else -1.6) * wobble * delta)
