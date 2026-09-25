class_name ImpactFlash
extends Node3D
## A short expanding glow where a laser landed.
##
## Pooled and reused like the tracers. This is the only feedback a hit gets:
## without it, shooting a rock that takes six shots to break looks exactly like
## missing it six times.

const LIFETIME := 0.22

var _age: float = 0.0
var _size: float = 1.0
var _alive: bool = false

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	set_process(false)
	visible = false


## Pops a flash at [param at], scaled by [param size] in world units.
func pop(at: Vector3, size: float, tint: Color) -> void:
	global_position = at
	_size = size
	_age = 0.0
	_alive = true
	visible = true
	var mat := _mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = tint
		mat.emission = tint
	_light.light_color = tint
	set_process(true)


func _process(delta: float) -> void:
	if not _alive:
		return
	_age += delta
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	# Fast out, slow stop: the eye reads the leading edge, not the fade.
	scale = Vector3.ONE * _size * (0.35 + 1.5 * sqrt(t))
	var fade := 1.0 - t
	var mat := _mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = 9.0 * fade
	_light.light_energy = 7.0 * fade
	if t >= 1.0:
		_alive = false
		visible = false
		set_process(false)


func busy() -> bool:
	return _alive
