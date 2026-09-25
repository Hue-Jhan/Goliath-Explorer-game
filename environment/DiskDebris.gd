class_name DiskDebris
extends Node3D
## Rocks caught in the accretion disk, orbiting with the flow.
##
## Rendered through [MultiMeshInstance3D] and moved kinematically on fixed
## circular tracks. Two consequences, both deliberate:
##
## * They cannot fall in. Orbital radius is a constant of each instance rather
##   than the result of integrating gravity, so no amount of drift or numerical
##   error can walk one across the horizon. The disk stays populated forever.
## * They cost almost nothing. Three multimeshes of a few hundred instances draw
##   in three calls, against several hundred for individual bodies -- and the
##   profile already says the raymarch owns this frame, so scenery has to be
##   close to free or it does not go in.
##
## They carry no collision. The disk is a hazard you fly through, not a debris
## field you thread, and hundreds of moving colliders inside the one region the
## player is most likely to be would be both expensive and infuriating.

## Instances at [member Globals.asteroid_density] == 1, split across variants.
@export_range(0, 2000, 10) var base_count: int = 270
## Orbital band, as a fraction of the gap between the disk's inner and outer
## edges. Kept clear of both so nothing clips through the ISCO gap or trails
## outside the visible disk.
@export_range(0.0, 1.0, 0.01) var band_inner: float = 0.08
@export_range(0.0, 1.0, 0.01) var band_outer: float = 0.88
@export var min_size: float = 2.5
@export var max_size: float = 13.0
@export var debris_seed: int = 517

var _meshes: Array[MultiMeshInstance3D] = []
## Per instance: radius (rs), phase, angular speed, height (rs), size, tumble axis.
var _tracks: Array = []
var _time: float = 0.0
var _built_density: float = -1.0
var _built_outer: float = -1.0


func _ready() -> void:
	_rebuild()
	if not Globals.settings_changed.is_connected(_on_settings_changed):
		Globals.settings_changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	# Radius matters as much as density: the tracks are laid out between the
	# disk's edges, so moving an edge has to re-lay them or debris ends up
	# orbiting outside the disk it belongs to.
	if not is_equal_approx(_built_density, Globals.asteroid_density) \
			or not is_equal_approx(_built_outer, Globals.disk_outer_rs):
		_rebuild()


func _process(delta: float) -> void:
	_time += delta
	var rs: float = Globals.rs_world()
	var spin := signf(float(Globals.bh_disk_spin))
	var rate: float = Globals.bh_disk_rot_speed
	for m in _meshes:
		var mm := m.multimesh
		for i in mm.instance_count:
			var track: Array = _tracks[int(m.get_meta(&"offset")) + i]
			var angle: float = track[1] + track[2] * _time * rate * spin
			var radius: float = track[0] * rs
			var basis := Basis(track[5], _time * track[6]).scaled(Vector3.ONE * track[4])
			mm.set_instance_transform(i, Transform3D(basis, Vector3(
				cos(angle) * radius, track[3] * rs, sin(angle) * radius)))


func _rebuild() -> void:
	for m in _meshes:
		m.queue_free()
	_meshes.clear()
	_tracks.clear()
	_built_density = Globals.asteroid_density
	_built_outer = Globals.disk_outer_rs

	var total := int(round(float(base_count) * Globals.asteroid_density))
	if total <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = debris_seed
	var inner: float = Globals.disk_inner_rs
	var outer: float = Globals.disk_outer_rs
	var per_variant := maxi(total / 3, 1)

	for variant in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Asteroid.mesh_for(variant)
		mm.instance_count = per_variant

		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = _debris_material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The disk is huge and the instances are placed by hand each frame, so
		# the automatic AABB is meaningless; give it one that covers the disk or
		# the whole batch vanishes the moment the centre leaves the frustum.
		var extent: float = outer * 1.2 * Globals.rs_world()
		node.custom_aabb = AABB(Vector3(-extent, -extent * 0.25, -extent),
			Vector3(extent * 2.0, extent * 0.5, extent * 2.0))
		node.set_meta(&"offset", _tracks.size())
		add_child(node)
		_meshes.append(node)

		for i in per_variant:
			var t := rng.randf()
			var r_rs := lerpf(lerpf(inner, outer, band_inner), lerpf(inner, outer, band_outer), sqrt(t))
			# Keplerian shear, matching the swirl the shader draws.
			var omega := 0.9 / pow(r_rs / inner, 1.5)
			var span := clampf((r_rs - inner) / maxf(outer - inner, 0.001), 0.0, 1.0)
			var half_h: float = maxf(Globals.disk_thickness_rs * (0.30 + 0.70 * span), 0.012)
			_tracks.append([
				r_rs,
				rng.randf() * TAU,
				omega,
				rng.randfn(0.0, half_h * 0.45),
				rng.randf_range(min_size, max_size),
				Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)).normalized(),
				rng.randf_range(-0.5, 0.5),
			])


## Dark and slightly heated: these are silhouettes against a very bright disk,
## and a little emission keeps them from reading as holes punched in it.
static func _debris_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.15, 0.14)
	mat.roughness = 0.95
	mat.metallic = 0.02
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.17, 0.05)
	mat.emission_energy_multiplier = 0.35
	return mat


## Live instance count, for tests and telemetry.
func debris_count() -> int:
	return _tracks.size()
