class_name SupernovaRemnant
extends Hazard
## A planetary nebula around a white dwarf: one raymarched volume, plus the
## light it throws on everything nearby.
##
## The visuals live entirely in [code]hazards/remnant.gdshader[/code]; this
## script owns the bounding volume the shader is allowed to run in, and keeps it
## fed. Same division of labour as [Goliath], and for the same reason -- the
## shader should not have to know what a scene tree is, and the node should not
## have to know what a density field is.
##
## The first version built this out of geometry: braided tori for the rings, a
## MultiMesh of instanced darts for the cometary knots, nested additive spheres
## for the gas. Every one of those has a silhouette, and gas does not. It could
## be tuned to read correctly from one distance and one angle at a time and
## never from all of them.
##
## There is deliberately nothing marking the gravitational boundary. A
## 6900-unit shell was tried, and a sphere that large at uniform opacity has a
## hard circular edge, so instead of a soft limit it drew an enormous ball
## across the sky. The boundary belongs on the map, where it already is.
##
## [b]The hazard.[/b] The dwarf pulls, but never hard enough to beat any hull's
## braking authority: you can always climb back out if you notice in time. What
## kills is contact. The star is 110 units across in a zone seven kilometres
## wide, so flying in is a decision, not an accident.

## Outer radius of the gas, world units. The bounding volume is slightly larger.
## Outer radius of the gas at scale 1.0, world units. The bounding volume is
## slightly larger, and [member Globals.remnant_scale] multiplies both.
@export var base_gas_radius: float = 9000.0
## Radius of the white dwarf itself, at scale 1.0.
@export var base_star_radius: float = 290.0
## Danger and lethal radii at scale 1.0. Everything scales together, so the
## remnant stays in proportion with itself however it is resized.
@export var base_danger_radius: float = 19000.0
@export var base_kill_radius: float = 690.0
@export_range(0.0, 4.0, 0.05) var brightness: float = 1.0

var _volume: MeshInstance3D = null
var _lamp: OmniLight3D = null
var _material: ShaderMaterial = null


func _ready() -> void:
	super._ready()
	hazard_name = "THE ASHES"
	tint = Color(0.55, 0.95, 1.0)
	_build_volume()
	_build_light()
	if Globals.has_signal(&"settings_changed") and not Globals.is_connected(&"settings_changed", _apply_settings):
		Globals.connect(&"settings_changed", _apply_settings)
	# Deferred: Goliath has to be in the tree before its influence radius can be
	# asked for, and sibling _ready order is not something to rely on.
	_apply_settings.call_deferred()


## Gas radius after [member Globals.remnant_scale].
func gas_radius() -> float:
	return base_gas_radius * maxf(Globals.remnant_scale, 0.05)


func short_tag() -> String:
	return "REMNANT"


func _build_volume() -> void:
	var sphere := SphereMesh.new()
	# Sized once, at scale 1, and rescaled by the node instead of rebuilt -- the
	# shader works in world units off its own uniforms, so the mesh is only ever
	# the region it is allowed to run in.
	sphere.radius = base_gas_radius * 1.15
	sphere.height = base_gas_radius * 2.3
	sphere.radial_segments = 24
	sphere.rings = 12

	_material = ShaderMaterial.new()
	_material.shader = load("res://hazards/remnant.gdshader")

	_volume = MeshInstance3D.new()
	_volume.mesh = sphere
	_volume.material_override = _material
	_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The bounding sphere is culled by its own AABB, and the shader marches well
	# inside it; without this the volume pops out of view when its centre leaves
	# the frustum but its far side has not.
	_volume.extra_cull_margin = base_gas_radius
	add_child(_volume)


## A real light, so the nebula actually lights the ship and any rock near it.
## The volume itself is unshaded and emits nothing into the scene.
func _build_light() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.74, 0.88, 1.0)
	lamp.light_energy = 9.0
	lamp.omni_range = 9000.0
	lamp.shadow_enabled = false
	add_child(lamp)
	_lamp = lamp


func _apply_settings() -> void:
	if _material == null or not Globals.has_method(&"rs_world"):
		return
	var scale_factor: float = maxf(Globals.remnant_scale, 0.05)
	var radius := base_gas_radius * scale_factor
	# Everything the hazard means is derived from the one scale, so resizing it
	# in the options cannot leave the lethal radius or the danger ring behind.
	pull = Globals.remnant_gravity
	danger_radius = base_danger_radius * scale_factor
	kill_radius = base_kill_radius * scale_factor
	if _volume != null:
		_volume.scale = Vector3.ONE * scale_factor
	if _lamp != null:
		_lamp.omni_range = radius * 2.6

	_material.set_shader_parameter(&"inv_xform", global_transform.affine_inverse())
	_material.set_shader_parameter(&"centre_world", global_position)
	_material.set_shader_parameter(&"volume_radius", radius * 1.15)
	_material.set_shader_parameter(&"gas_radius", radius)
	_material.set_shader_parameter(&"core_radius", base_star_radius * scale_factor)
	_material.set_shader_parameter(&"brightness", brightness)
	_material.set_shader_parameter(&"exposure", Globals.bh_exposure)
	_material.set_shader_parameter(&"sky_detail", Globals.sky_detail)
	# A seventh of the hole's budget. This is a secondary landmark and the gas is
	# smooth, but the real reason it is this low is measured: sitting inside the
	# volume, every step costs two fBm evaluations, and at a fifth it was adding
	# 25 ms to a 31 ms frame.
	_material.set_shader_parameter(&"steps", clampi(int(Globals.raymarch_steps / 7), 12, 34))
	_material.set_shader_parameter(&"gas_octaves", clampi(Globals.sky_detail + 1, 2, 4))
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
