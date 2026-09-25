@tool
class_name Goliath
extends Node3D
## Goliath: the black hole, its accretion disk, and its gravity.
##
## Three parts, each replaceable on its own:
##   * [b]Volume[/b] -- an inverted bounding sphere carrying Goliath.gdshader.
##     Everything you see comes out of that one fragment shader's raymarch.
##   * [b]GravityWell[/b] -- the force source ships query. No visuals.
##   * this script -- the only thing that knows about both, whose entire job is
##     to push [Globals] into the shader and keep the two in sync.
##
## [code]@tool[/code] so the hole renders and re-tunes live in the editor while
## you drag sliders in [code]core/Globals.tscn[/code].

@onready var volume: MeshInstance3D = $Volume
@onready var well: GravityWell = $GravityWell


func _ready() -> void:
	# Reached through the Object signal API rather than the property, and
	# guarded: while the editor is first scanning the project, @tool scenes can
	# be instantiated before the Globals autoload scene has been imported, and
	# the placeholder Node standing in for it has none of these members yet.
	if not Globals.has_signal(&"settings_changed"):
		return
	if not Globals.is_connected(&"settings_changed", _apply_settings):
		Globals.connect(&"settings_changed", _apply_settings)
	_apply_settings()


func _process(_delta: float) -> void:
	# The shader marches in hole-local natural units, so it needs the world ->
	# local transform every frame: the node can be moved, and axis_tilt is
	# animatable. One mat4 upload is far cheaper than an inverse() per fragment.
	if volume != null:
		var mat := volume.material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter(&"bh_inv_xform", global_transform.affine_inverse())


func _apply_settings() -> void:
	if volume == null or well == null or not Globals.has_method(&"rs_world"):
		return

	var rs: float = Globals.rs_world()
	var influence: float = Globals.influence_radius_world()

	# The mesh is just the region the shader is allowed to run in. Sizing it
	# from Globals means bh_scale genuinely rescales the whole system.
	var sphere := volume.mesh as SphereMesh
	if sphere != null:
		sphere.radius = influence
		sphere.height = influence * 2.0

	var mat := volume.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(&"bh_inv_xform", global_transform.affine_inverse())
		mat.set_shader_parameter(&"rs_world", rs)
		mat.set_shader_parameter(&"influence_radius", influence)
		mat.set_shader_parameter(&"disk_inner", Globals.disk_inner_rs)
		mat.set_shader_parameter(&"disk_outer", Globals.disk_outer_rs)
		mat.set_shader_parameter(&"disk_thickness", Globals.disk_thickness_rs)
		mat.set_shader_parameter(&"max_steps", Globals.raymarch_steps)
		mat.set_shader_parameter(&"disk_detail", Globals.sky_detail)
		mat.set_shader_parameter(&"sky_detail", Globals.sky_detail)
		mat.set_shader_parameter(&"nebula_gain", Globals.nebula_gain)
		mat.set_shader_parameter(&"disk_rot_speed", Globals.bh_disk_rot_speed)
		mat.set_shader_parameter(&"disk_spin", float(Globals.bh_disk_spin))
		mat.set_shader_parameter(&"lens_strength", Globals.bh_strength)
		mat.set_shader_parameter(&"disk_tint", Globals.bh_color_tint)
		mat.set_shader_parameter(&"axis_tilt", deg_to_rad(Globals.bh_axis_tilt))
		mat.set_shader_parameter(&"exposure", Globals.bh_exposure)

	# The shader tilts the disk by rotating incoming rays by -axis_tilt, which
	# is equivalent to rotating the hole by +axis_tilt. Match the gravity well's
	# spin axis to it so frame-dragging stays in the plane you can see.
	well.rotation.x = deg_to_rad(Globals.bh_axis_tilt)

	_sync_sky_exposure()


## Keeps the surrounding sky's exposure locked to the hole's, so the lensed
## backdrop inside the volume and the plain one outside it match in brightness.
func _sync_sky_exposure() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null or vp.world_3d == null:
		return # the editor's scan-time viewport has no 3D world attached
	var env := vp.world_3d.environment
	if env == null or env.sky == null:
		return
	var sky_mat := env.sky.sky_material as ShaderMaterial
	if sky_mat != null:
		sky_mat.set_shader_parameter(&"exposure", Globals.bh_exposure)
		sky_mat.set_shader_parameter(&"sky_detail", Globals.sky_detail)
		sky_mat.set_shader_parameter(&"nebula_gain", Globals.nebula_gain)
	Globals.apply_quality_to_environment(env)
