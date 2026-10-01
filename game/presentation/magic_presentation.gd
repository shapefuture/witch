class_name MagicPresentation
extends Node

# Magic must be SEEN to break the rules. The mundane world is coarse: chunky vertex snap, a
# small banded palette, mechanical motion. While a spell plays, the screen grade expands the
# palette and relaxes the dither, geometry stops snapping, and light that comes from nowhere
# rises through the target. The player can tell reality became less constrained.

signal peaked(effect: String)
signal finished(effect: String)

const EFFECTS := {
	"repair": {"rise": 0.7, "hold": 1.5, "fall": 1.2, "tint": Palette.MAGIC_GOLD, "peak": 1.0},
	"flourish": {"rise": 0.9, "hold": 2.6, "fall": 1.6, "tint": Palette.MAGIC_ROSE, "peak": 1.0},
}

# Multiplies every duration (tests and capture mode use a small value).
var time_scale := 1.0
var _spark_parent: Node3D

func play(effect: String, at: Vector3) -> void:
	var spec: Dictionary = EFFECTS.get(effect, {})
	if spec.is_empty():
		push_warning("MagicPresentation: unknown effect '%s'" % effect)
		return
	var scale := maxf(time_scale, 0.001)
	var column := _column(spec["tint"], at)
	var tween := create_tween()
	tween.tween_method(_set_magic, 0.0, float(spec["peak"]), float(spec["rise"]) * scale)
	# the lens swings out to a fisheye as the spell rises (the camera tilts with it: see the
	# director's magic_reveal shot) and everything snaps back at once when it ends
	tween.parallel().tween_method(PSXGlobals.set_lens, 0.0, 1.0, float(spec["rise"]) * scale)
	tween.parallel().tween_property(column, "scale", Vector3(1.0, 1.0, 1.0), float(spec["rise"]) * scale).from(Vector3(0.2, 0.01, 0.2))
	tween.tween_callback(func() -> void: peaked.emit(effect))
	tween.tween_interval(float(spec["hold"]) * scale)
	tween.tween_method(_set_magic, float(spec["peak"]), 0.0, float(spec["fall"]) * scale)
	await tween.finished
	column.queue_free()
	PSXGlobals.reset()
	finished.emit(effect)

func _set_magic(amount: float) -> void:
	PSXGlobals.set_magic(amount)

# A column of light: smooth, unlit, no vertex snapping, colour outside the world's palette.
func _column(tint: Color, at: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.15
	mesh.bottom_radius = 0.9
	mesh.height = 5.0
	mesh.radial_segments = 24
	mesh.rings = 1
	var column := MeshInstance3D.new()
	column.name = "MagicColumn"
	column.mesh = mesh
	column.material_override = PSXMaterials.magic(tint, 1.3)
	column.position = at + Vector3(0, 2.5, 0)
	get_tree().current_scene.add_child(column) if get_tree().current_scene != null else get_parent().add_child(column)
	return column
