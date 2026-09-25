class_name Explosion
extends Node3D
## One pooled detonation: fireball, shockwave, sparks and a light flash.
##
## Four layers because a single expanding sphere reads as a bubble, not a kill.
## The fireball carries the colour, the shockwave is a thinner shell that runs
## ahead of it, the sparks give the eye something with direction, and the light
## puts the event onto nearby geometry so it registers even at the edge of
## vision.

const LIFETIME := 1.05

var _age: float = 0.0
var _size: float = 1.0
var _alive: bool = false

@onready var _fireball: MeshInstance3D = $Fireball
@onready var _shock: MeshInstance3D = $Shock
@onready var _sparks: GPUParticles3D = $Sparks
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	set_process(false)
	visible = false
	_sparks.process_material = _spark_material()


func pop(at: Vector3, size: float, tint: Color) -> void:
	global_position = at
	_size = size
	_age = 0.0
	_alive = true
	visible = true
	_tint(_fireball, tint, 14.0)
	_tint(_shock, Color(1.0, 0.92, 0.75), 10.0)
	_light.light_color = tint
	_sparks.amount = 26
	_sparks.lifetime = LIFETIME * 0.8
	var mat := _sparks.process_material as ParticleProcessMaterial
	if mat != null:
		mat.initial_velocity_min = size * 5.0
		mat.initial_velocity_max = size * 13.0
	_sparks.restart()
	_sparks.emitting = true
	set_process(true)


func _process(delta: float) -> void:
	if not _alive:
		return
	_age += delta
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	var fade := 1.0 - t

	# Fireball: fast expansion that eases off, holding colour as it dims.
	_fireball.scale = Vector3.ONE * _size * (0.3 + 1.9 * sqrt(t))
	_set_energy(_fireball, 14.0 * fade * fade)

	# Shockwave: thinner, faster, gone sooner.
	var shock_t := clampf(t / 0.55, 0.0, 1.0)
	_shock.visible = shock_t < 1.0
	_shock.scale = Vector3.ONE * _size * (0.4 + 3.4 * sqrt(shock_t))
	_set_energy(_shock, 9.0 * (1.0 - shock_t) * (1.0 - shock_t))

	_light.light_energy = 18.0 * fade * fade
	_light.omni_range = _size * 9.0

	if t >= 1.0:
		_alive = false
		visible = false
		_sparks.emitting = false
		set_process(false)


func busy() -> bool:
	return _alive


static func _tint(mesh: MeshInstance3D, colour: Color, energy: float) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.7)
		mat.emission = colour
		mat.emission_energy_multiplier = energy


static func _set_energy(mesh: MeshInstance3D, energy: float) -> void:
	var mat := mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = maxf(energy, 0.0)


static func _spark_material() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.4
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 1.0
	mat.damping_max = 4.0
	mat.scale_min = 0.5
	mat.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.92, 0.55, 1.0))
	ramp.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	mat.color_ramp = tex
	return mat
