class_name AsteroidField
extends Node3D
## Populates the annulus around Goliath with rocks.
##
## Placement is deliberately shaped rather than uniform: density peaks near the
## disk's midplane and thins with height, and the inner edge is kept outside the
## gravity deadzone so the field is somewhere you can actually fly, not a wall
## of debris in the one region where your engines have already lost.
##
## Count scales with [member Globals.asteroid_density]. The field rebuilds only
## when that value actually changes, so dragging any other slider costs nothing.

## Inner and outer edge of the field, in Schwarzschild radii.
@export_range(1.0, 40.0, 0.5) var inner_rs: float = 9.5
@export_range(1.0, 60.0, 0.5) var outer_rs: float = 27.0
## Standard deviation of the vertical scatter, in Schwarzschild radii.
@export_range(0.1, 20.0, 0.1) var vertical_spread_rs: float = 2.6
## Rock count at [member Globals.asteroid_density] == 1.
@export_range(0, 1200, 1) var base_count: int = 160
@export var min_radius: float = 5.0
@export var max_radius: float = 44.0
@export_range(0.0, 1.0, 0.01) var max_spin: float = 0.22
## Fixed seed, so a given density always produces the same field.
@export var field_seed: int = 20260922

var _rocks: Array[Asteroid] = []
var _built_density: float = -1.0

const _ASTEROID := preload("res://environment/Asteroid.tscn")


func _ready() -> void:
	add_to_group(&"asteroid_field")
	_rebuild()
	if not Globals.settings_changed.is_connected(_on_settings_changed):
		Globals.settings_changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	if not is_equal_approx(_built_density, Globals.asteroid_density):
		_rebuild()


func _process(delta: float) -> void:
	# One loop for the whole field: cheaper than a script per rock, and it keeps
	# the tumble rates in a single place where they can be culled later.
	for rock in _rocks:
		if is_instance_valid(rock) and rock.spin != Vector3.ZERO:
			rock.rotate_object_local(rock.spin.normalized(), rock.spin.length() * delta)


func _rebuild() -> void:
	for rock in _rocks:
		rock.queue_free()
	_rocks.clear()
	_built_density = Globals.asteroid_density

	var count := int(round(float(base_count) * Globals.asteroid_density))
	if count <= 0:
		return

	var rs: float = Globals.rs_world()
	var rng := RandomNumberGenerator.new()
	rng.seed = field_seed

	for i in count:
		var rock := _ASTEROID.instantiate() as Asteroid
		# sqrt-weighted radius gives uniform area density across the annulus,
		# instead of piling up against the inner edge.
		var u := rng.randf()
		var r_rs := sqrt(lerpf(inner_rs * inner_rs, outer_rs * outer_rs, u))
		var theta := rng.randf() * TAU
		# Sum of two uniforms approximates a normal closely enough, and unlike
		# randfn it cannot throw an outlier into the horizon.
		var y_rs := (rng.randf() + rng.randf() - 1.0) * vertical_spread_rs

		rock.position = Vector3(cos(theta) * r_rs, y_rs, sin(theta) * r_rs) * rs
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		# Bias small: a few landmarks, mostly gravel.
		rock.radius = lerpf(min_radius, max_radius, pow(rng.randf(), 2.2))
		rock.variant = rng.randi() % Asteroid.VARIANTS
		rock.spin = Vector3(rng.randfn(0.0, 0.4), rng.randfn(0.0, 0.4), rng.randfn(0.0, 0.4)).normalized() * rng.randf() * max_spin
		rock.destroyed.connect(_on_rock_destroyed)
		add_child(rock)
		_rocks.append(rock)


## Keeps the tumble list tight when rocks are shot apart.
func _on_rock_destroyed(rock: Asteroid) -> void:
	_rocks.erase(rock)


## Number of rocks currently live. Used by the HUD and by tests.
func rock_count() -> int:
	return _rocks.size()


## Live rocks, for the minimap and the map.
func rocks() -> Array[Asteroid]:
	return _rocks
