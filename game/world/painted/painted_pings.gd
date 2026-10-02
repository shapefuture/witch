class_name PaintedPings
extends Node3D

# The answer to a tap that hit no prop and no hotspot: a ring of light opens at the tapped pixel (painted_ping.gdshader).
# A few quads take turns, so tapping fast never piles up nodes.

const SHADER := preload("res://game/world/painted/painted_ping.gdshader")
const POOL := 4
const SECONDS := 0.55

var ping_count := 0
var _quads: Array[MeshInstance3D] = []
var _tweens: Array[Tween] = []
var _next := 0

func _ready() -> void:
	for i in POOL:
		var quad := MeshInstance3D.new()
		quad.name = "Ping%d" % i
		quad.mesh = QuadMesh.new()
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("progress", 1.0)
		quad.material_override = material
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.visible = false
		add_child(quad)
		_quads.append(quad)
		_tweens.append(null)

# `at` is the point in the room, `size` the quad's side in metres, `axis`/`up` the painting camera's view axis and up.
func ping(at: Vector3, size: float, axis: Vector3, up: Vector3) -> void:
	var slot := _next % POOL
	_next += 1
	ping_count += 1
	var quad := _quads[slot]
	(quad.mesh as QuadMesh).size = Vector2(size, size)
	quad.transform = Transform3D(Basis(up.cross(-axis).normalized(), up, -axis), at)
	quad.visible = true
	var material := quad.material_override as ShaderMaterial
	if _tweens[slot] != null and _tweens[slot].is_valid():
		_tweens[slot].kill()
	var tween := create_tween()
	_tweens[slot] = tween
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter("progress", v), 0.0, 1.0, SECONDS)
	tween.tween_callback(func() -> void: quad.visible = false)

func active() -> int:
	var count := 0
	for quad in _quads:
		if quad.visible:
			count += 1
	return count
