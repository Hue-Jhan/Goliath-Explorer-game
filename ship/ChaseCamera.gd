class_name ChaseCamera
extends Camera3D
## Third-person chase camera, zoomable through to a cockpit view.
##
## Runs as [member Node3D.top_level] even though it is parented to the ship, so
## it inherits nothing and computes its own frame instead. It tracks in the
## physics step; see [method _physics_process].
##
## [b]Why the position does not simply lag.[/b] The obvious implementation --
## exponentially interpolate toward the ship each frame -- is wrong for a craft
## that accelerates this hard. An interpolation with time constant [code]tau[/code]
## settles at a steady-state error of [code]speed * tau[/code]: at 1200 u/s and
## tau = 0.09 that is a hundred-odd units, so the ship appears to tear away from
## the camera under thrust and snap back when you release it. Here the camera
## tracks the ship's frame [i]exactly[/i], and the only displacement allowed is
## a small lean driven by acceleration and hard-limited to
## [member max_lean] units. The result keeps the physical cue -- the ship
## presses back into frame when you burn -- without the rubber band.

@export var target_path: NodePath = ^".."

## Distance behind the ship at the widest zoom.
@export var max_distance: float = 15.0
## Distance change per wheel click.
@export var zoom_step: float = 0.8
## Below this distance the hull is hidden and the view becomes first person.
@export var cockpit_threshold: float = 0.9
## Eye position inside the canopy, used at zero distance.
@export var cockpit_offset: Vector3 = Vector3(0.0, 0.17, -0.48)
## Camera rises with distance at this ratio, so it looks down over the hull.
@export var height_ratio: float = 0.145
## How far ahead of the ship the camera aims.
@export var look_ahead: float = 11.0

## Seconds to close ~63% of an orientation gap. Position is not smoothed.
@export_range(0.01, 1.0, 0.01) var orient_tau: float = 0.07
## Peak displacement from the acceleration lean, in world units.
@export_range(0.0, 3.0, 0.05) var max_lean: float = 0.32
@export_range(0.01, 1.0, 0.01) var lean_tau: float = 0.12

@export_range(0.0, 8.0, 0.1) var trauma_decay: float = 1.6
@export var max_shake_offset: float = 0.32
@export var max_shake_roll: float = 0.09

var trauma: float = 0.0
var distance: float = 4.3

var _target: Node3D = null
var _ship: Ship = null
var _hull: MeshInstance3D = null
var _well: GravityWell = null
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _lean := Vector3.ZERO
var _prev_velocity := Vector3.ZERO


func _ready() -> void:
	top_level = true
	# near and far are deliberately NOT set here. They used to be, and the far
	# assignment silently overrode whatever Ship.tscn said -- which is the kind
	# of duplicate that costs nothing until something is placed past it. The
	# landmarks moved out to ~110 km and simply stopped being drawn: no error,
	# no warning, the volumes were beyond a clip plane the scene file believed
	# it had already moved. One owner per value; the scene is it.
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.9
	_resolve()
	if _target != null:
		global_transform = _desired_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cam_zoom_in"):
		distance = maxf(distance - zoom_step, 0.0)
	elif event.is_action_pressed(&"cam_zoom_out"):
		distance = minf(distance + zoom_step, max_distance)


## Adds shake. [param amount] is in trauma units (0..1); it accumulates and
## clamps, so repeated small hits still build up.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * Globals.shake_intensity, 0.0, 1.0)


## Tracking runs in _physics_process, not _process, and this is not incidental.
## The ship moves in the physics step; a camera that recomputed during idle
## processing sat exactly one frame behind it, so the gap between them grew as
## speed x frame_time -- over 150 units at 1100 u/s and 7 fps. Because Godot
## calls _physics_process on a parent before its children, and this camera is a
## child of the ship, running here means it always reads a position the ship has
## already finished moving to.
func _physics_process(delta: float) -> void:
	if _target == null:
		_resolve()
		if _target == null:
			return

	var want := _desired_transform()
	# Position is tracked exactly; see the class note on why.
	global_position = want.origin + _target.global_transform.basis * _lean_offset(delta)
	var q := Quaternion(global_transform.basis.orthonormalized()).slerp(
		Quaternion(want.basis.orthonormalized()), 1.0 - exp(-delta / orient_tau))
	global_transform.basis = Basis(q)

	if _hull != null:
		_hull.visible = distance >= cockpit_threshold

	_apply_shake(delta)
	_update_fov(delta)


## Small acceleration-driven displacement in the ship's own frame: burn forward
## and the camera falls back a little, strafe and it swings the other way. Hard
## limited, so it can never become the rubber band it replaced.
func _lean_offset(delta: float) -> Vector3:
	if _ship == null or delta <= 0.0:
		return Vector3.ZERO
	var accel := (_ship.velocity - _prev_velocity) / delta
	_prev_velocity = _ship.velocity
	var local_accel := _target.global_transform.basis.inverse() * accel
	var target_lean := local_accel * (max_lean / maxf(Globals.ship_thrust, 1.0))
	_lean = _lean.lerp(target_lean, 1.0 - exp(-delta / lean_tau))
	_lean = _lean.limit_length(max_lean)
	return _lean


func _desired_transform() -> Transform3D:
	var b := _target.global_transform.basis
	# Blend from the cockpit to a trailing chase position as you zoom out, so
	# scrolling all the way in lands the eye inside the canopy rather than
	# clipping through the hull.
	var chase := Vector3(0.0, distance * height_ratio, distance)
	var t := clampf(distance / 1.2, 0.0, 1.0)
	var eye := _target.global_position + b * cockpit_offset.lerp(chase, t)
	var aim := _target.global_position - b.z * look_ahead
	return Transform3D(Basis.looking_at(aim - eye, b.y), eye)


func _apply_shake(delta: float) -> void:
	trauma = maxf(trauma - trauma_decay * delta, 0.0)
	if trauma <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return
	_t += delta
	var s := trauma * trauma
	h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * max_shake_offset * s
	v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * max_shake_offset * s
	rotate_object_local(Vector3.FORWARD, _noise.get_noise_2d(_t * 33.0, 17.0) * max_shake_roll * s)


func _update_fov(delta: float) -> void:
	var target: float = Globals.base_fov
	var well := _find_well()
	if well != null and Globals.fov_distortion_intensity > 0.0:
		target += 45.0 * Globals.fov_distortion_intensity * well.proximity(global_position)
	if _ship != null:
		target += 9.0 * _ship.speed_ratio()
	fov = lerpf(fov, clampf(target, 1.0, 179.0), 1.0 - exp(-delta / 0.25))


func _resolve() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_ship = _target as Ship
	if _target != null:
		_hull = _target.get_node_or_null(^"Hull") as MeshInstance3D


func _find_well() -> GravityWell:
	if is_instance_valid(_well):
		return _well
	var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
	_well = wells[0] if not wells.is_empty() else null
	return _well
