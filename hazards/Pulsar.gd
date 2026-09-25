class_name Pulsar
extends Hazard
## A rotating neutron star with two opposed emission beams and a visible
## magnetosphere.
##
## The geometry is the mechanic. The magnetic axis is tilted away from the spin
## axis, so as the star turns the beams sweep out two cones -- this is the
## oblique-rotator picture, and it is the reason real pulsars pulse. Sitting
## anywhere on those cones means being swept twice per rotation, which is what
## the hull damage is modelling.
##
## [b]Two renderers, on purpose.[/b] The beams and the star are a raymarched
## volume ([code]hazards/pulsar.gdshader[/code]): a cone mesh has a hard
## straight silhouette that no amount of vertex fading removes, and light does
## not have edges. The magnetosphere stays a line mesh, because a field line is
## a line -- marching a volume to recover a curve would be slower and worse, and
## here it would not work at all, since a line a few hundred units thick inside
## an eleven-kilometre volume is finer than any step size that volume can
## afford.
##
## [b]One source of truth for the cone.[/b] [member beam_half_angle] is fed to
## the shader and used by [method beam_exposure] unchanged. A radiation beam you
## can see and a radiation beam that hurts you have to be the same object or the
## hazard is unreadable.

## How far the beams reach, world units.
## How far the beams reach at scale 1.0, world units.
## [member Globals.pulsar_scale] multiplies this and everything derived from it.
@export var base_beam_reach: float = 26000.0
@export var base_star_radius: float = 120.0
## Danger and lethal radii at scale 1.0. Scaled together with the beams, so
## resizing the pulsar in the options cannot leave its hazard behind.
@export var base_danger_radius: float = 17000.0
@export var base_kill_radius: float = 500.0
## Half-angle of a beam, degrees. At exactly this angle the drawn beam is at
## 1/e of its axial brightness, so the damaging cone is its bright core.
@export_range(1.0, 30.0, 0.5) var beam_half_angle_deg: float = 8.0
## Rotation rate about the spin axis, radians/second. Slow enough to see the
## sweep coming; fast enough that lingering on the cone is punished.
@export var spin_rate: float = 1.05
## Tilt of the magnetic axis away from the spin axis, degrees.
@export_range(0.0, 90.0, 1.0) var magnetic_tilt: float = 32.0
## Hull damage per second at the axis of a beam.
##
## Tuned against the hulls rather than picked: at 38 the standard 100-point hull
## survives about two and a half seconds of direct exposure, which is long
## enough to notice the alarm and turn out of the cone and short enough that
## parking in it is never an option. At the 62 it started at, a full sweep
## killed before the camera had finished shaking.
@export var beam_damage: float = 38.0
@export_range(0.0, 4.0, 0.05) var brightness: float = 1.0

var _spin: Node3D = null
var _magnetic: Node3D = null
var _volume: MeshInstance3D = null
var _lines: MeshInstance3D = null
var _lamp: OmniLight3D = null
var _material: ShaderMaterial = null


func _ready() -> void:
	super._ready()
	hazard_name = "PSR GOLIATH-1"
	tint = Color(0.62, 0.72, 1.0)

	_spin = Node3D.new()
	add_child(_spin)
	_magnetic = Node3D.new()
	_magnetic.rotation = Vector3(0.0, 0.0, deg_to_rad(magnetic_tilt))
	_spin.add_child(_magnetic)

	_build_volume()
	_build_field()
	_build_light()
	if Globals.has_signal(&"settings_changed") and not Globals.is_connected(&"settings_changed", _apply_settings):
		Globals.connect(&"settings_changed", _apply_settings)
	_apply_settings.call_deferred()


func _process(delta: float) -> void:
	_spin.rotate_object_local(Vector3.UP, spin_rate * delta)
	if _material != null:
		# The shader marches in the magnetic frame, so sweeping the beams is one
		# mat4 upload a frame and no per-fragment work at all.
		_material.set_shader_parameter(&"mag_inv_xform", _magnetic.global_transform.affine_inverse())


## Beam reach after [member Globals.pulsar_scale], world units.
func beam_reach() -> float:
	return base_beam_reach * maxf(Globals.pulsar_scale, 0.05)


## Half-angle of a beam, radians. The shader is handed this same value.
func beam_half_angle() -> float:
	return deg_to_rad(beam_half_angle_deg)


## Where the beams currently point, in world space. The +Y of the magnetic
## frame; the other cone is its negation.
func magnetic_axis() -> Vector3:
	return Vector3.UP if _magnetic == null else _magnetic.global_transform.basis.y.normalized()


## How deep in a beam [param world_pos] currently sits: 0 outside, 1 on the
## axis. Both cones count -- they are the same beam seen from two ends.
func beam_exposure(world_pos: Vector3) -> float:
	if _magnetic == null:
		return 0.0
	var offset := world_pos - global_position
	var distance := offset.length()
	if distance < 0.001 or distance > beam_reach():
		return 0.0
	var alignment := absf(offset.dot(magnetic_axis()) / distance)
	var edge := cos(beam_half_angle())
	if alignment < edge:
		return 0.0
	return clampf(inverse_lerp(edge, 1.0, alignment), 0.0, 1.0)


func damage_rate(world_pos: Vector3) -> float:
	var exposure := beam_exposure(world_pos)
	if exposure <= 0.0:
		return 0.0
	# Not a knife edge: clipping the rim of the cone still hurts, which is what
	# makes the sweep felt as a wash rather than as a trigger.
	return beam_damage * (0.45 + 0.55 * exposure)


func trauma_rate(world_pos: Vector3) -> float:
	var exposure := beam_exposure(world_pos)
	return 0.0 if exposure <= 0.0 else 2.6 * (0.4 + 0.6 * exposure)


func short_tag() -> String:
	return "PULSAR"


func _build_volume() -> void:
	# Built once at scale 1 and rescaled by the node rather than rebuilt: the
	# shader works in world units off its own uniforms, so the mesh is only ever
	# the region it is allowed to run in.
	var radius := base_beam_reach * 1.06
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12

	_material = ShaderMaterial.new()
	_material.shader = load("res://hazards/pulsar.gdshader")

	_volume = MeshInstance3D.new()
	_volume.mesh = sphere
	_volume.material_override = _material
	_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_volume.extra_cull_margin = radius
	# Parented to the hazard, not to the spinning node: the shader does its own
	# rotation through mag_inv_xform, and spinning a sphere achieves nothing but
	# a changed AABB.
	add_child(_volume)


## The magnetosphere, as geometry. See the class note for why this one is not
## in the shader.
func _build_field() -> void:
	# Shell radii as fractions of the beam reach, so the magnetosphere stays in
	# proportion at any size rather than shrinking into the star.
	var shells: Array = []
	for fraction: float in [0.110, 0.170, 0.245, 0.327, 0.418]:
		shells.append(base_beam_reach * fraction)
	var lines := MeshInstance3D.new()
	lines.mesh = CelestialMesh.dipole_lines(shells, 14, 34, base_beam_reach * 0.454)
	var mat := CelestialMesh.glow_material(Color(0.42, 0.60, 1.0), 2.0, 0.55)
	# The mesh carries a per-vertex fade with distance from the star, so the
	# outer shells thin out instead of ending abruptly.
	mat.vertex_color_use_as_albedo = true
	lines.material_override = mat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_magnetic.add_child(lines)
	_lines = lines


func _build_light() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.62, 0.74, 1.0)
	lamp.light_energy = 7.0
	lamp.omni_range = 7000.0
	lamp.shadow_enabled = false
	add_child(lamp)
	_lamp = lamp


func _apply_settings() -> void:
	if _material == null or not Globals.has_method(&"rs_world"):
		return
	var scale_factor: float = maxf(Globals.pulsar_scale, 0.05)
	var reach := base_beam_reach * scale_factor
	var radius := reach * 1.06
	pull = Globals.pulsar_gravity
	danger_radius = base_danger_radius * scale_factor
	kill_radius = base_kill_radius * scale_factor
	# Only the meshes are scaled, never _magnetic: the shader is handed that
	# node's inverse transform and marches in its frame, so a scale on it would
	# be applied to every sample twice.
	if _volume != null:
		_volume.scale = Vector3.ONE * scale_factor
	if _lines != null:
		_lines.scale = Vector3.ONE * scale_factor
	if _lamp != null:
		_lamp.omni_range = reach * 0.6

	_material.set_shader_parameter(&"mag_inv_xform", _magnetic.global_transform.affine_inverse())
	_material.set_shader_parameter(&"centre_world", global_position)
	_material.set_shader_parameter(&"volume_radius", radius)
	_material.set_shader_parameter(&"beam_reach", reach)
	_material.set_shader_parameter(&"core_radius", base_star_radius * scale_factor)
	_material.set_shader_parameter(&"beam_half_angle", beam_half_angle())
	_material.set_shader_parameter(&"brightness", brightness)
	_material.set_shader_parameter(&"exposure", Globals.bh_exposure)
	# Every step here is arithmetic -- there is no noise lookup anywhere in the
	# march -- so this affords a denser budget than the remnant despite a volume
	# three times the radius. It needs one: the per-pixel entry dither shows as
	# stippling along the beams if the steps are too few to smooth it out.
	_material.set_shader_parameter(&"steps", clampi(int(Globals.raymarch_steps / 3), 24, 68))
	_apply_occluder(_material)


## Hands the shader Goliath's frame and disk geometry, so it can stand aside
## wherever the hole has already claimed the pixel. See goliath_cover() in
## volume.gdshaderinc for why a transparent volume has to do this by hand.
func _apply_occluder(mat: ShaderMaterial) -> void:
	var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
	if wells.is_empty():
		mat.set_shader_parameter(&"bh_rs", 0.0)
		return
	var well := wells[0] as Node3D
	mat.set_shader_parameter(&"bh_inv_xform", well.global_transform.affine_inverse())
	mat.set_shader_parameter(&"bh_rs", Globals.rs_world())
	mat.set_shader_parameter(&"bh_disk_inner", Globals.disk_inner_rs)
	mat.set_shader_parameter(&"bh_disk_outer", Globals.disk_outer_rs)
