@tool
class_name GravityWell
extends Node3D
## The black hole's pull, as a plain queryable force source.
##
## Deliberately not an [Area3D]: ships, asteroids and debris all need the same
## acceleration at a point, and several of them will not be physics bodies at
## all. Anything that wants to be pulled asks for [method get_acceleration]
## once per physics tick; nothing has to overlap anything.
##
## The defining feature is the deadzone. Outside [member Globals.bh_capture_radius]
## the returned acceleration is exactly zero -- no drift, no nagging tug, the
## whole outer disk is free flight. Inside it, inward pull and tangential spin
## ramp in together, so crossing the line puts you into a decaying spiral
## rather than yanking you along a straight line into the horizon.
##
## Lives in the [code]gravity_wells[/code] group so consumers can find it
## without a hardcoded path.

const GROUP := &"gravity_wells"


func _ready() -> void:
	add_to_group(GROUP)


## Acceleration in world units/s^2 at [param world_pos]. Exactly
## [constant Vector3.ZERO] outside the capture radius.
func get_acceleration(world_pos: Vector3) -> Vector3:
	var offset := world_pos - global_position
	var dist := offset.length()
	var rs: float = Globals.rs_world()
	if dist <= 0.001 or rs <= 0.0:
		return Vector3.ZERO

	var t := capture_progress(world_pos)
	if t <= 0.0:
		return Vector3.ZERO

	var ramp: float = pow(t, Globals.bh_falloff_exponent)
	var inward := -offset / dist

	# Spin axis is the hole's own local +Y, so tilting the node tilts the
	# frame-dragging with it, matching the shader's axis_tilt.
	var axis := global_transform.basis.y.normalized()
	var tangential := axis.cross(offset).normalized()
	if not tangential.is_finite():
		tangential = Vector3.ZERO

	var pull: float = Globals.bh_gravity
	var spin: float = Globals.bh_spin_strength
	return inward * pull * ramp + tangential * spin * ramp


## 0.0 at (and outside) the capture radius, rising to 1.0 at the event horizon.
## This is the raw ramp, before [member Globals.bh_falloff_exponent] shapes it.
func capture_progress(world_pos: Vector3) -> float:
	var rs: float = Globals.rs_world()
	if rs <= 0.0:
		return 0.0
	var r_natural: float = (world_pos - global_position).length() / rs
	var capture: float = Globals.bh_capture_radius
	if capture <= 1.0 or r_natural >= capture:
		return 0.0
	# 1.0 at the horizon (r = 1 rs), 0.0 at the capture radius.
	return clampf(inverse_lerp(capture, 1.0, r_natural), 0.0, 1.0)


## True once [method get_acceleration] would return something non-zero.
func is_captured(world_pos: Vector3) -> bool:
	return capture_progress(world_pos) > 0.0


## Unit vector pointing straight away from the singularity. The only direction
## that unambiguously increases your radius, and therefore the one the HUD's
## escape compass points along.
func escape_vector(world_pos: Vector3) -> Vector3:
	var offset := world_pos - global_position
	if offset.length_squared() < 0.000001:
		return Vector3.UP
	return offset.normalized()


## Velocity of the disk's gas at [param world_pos], in world units/s.
##
## Zero outside the disk, ramping in across both the radial edges and the
## slab's vertical falloff so there is no step to fly across. Speed follows the
## Keplerian profile v ∝ r^-1/2 anchored at the ISCO, matching the differential
## shear the shader draws, and the direction is the same tangential sense the
## disk visibly rotates in.
##
## [Ship] brakes toward this rather than toward zero while inside the disk, so
## releasing the throttle in there leaves you co-moving with the gas -- which is
## to say, orbiting -- instead of stopping dead in a torrent of infalling
## plasma.
func disk_flow_velocity(world_pos: Vector3) -> Vector3:
	var containment := disk_containment(world_pos)
	if containment <= 0.0:
		return Vector3.ZERO
	var local := global_transform.affine_inverse() * world_pos
	var radial := Vector3(local.x, 0.0, local.z)
	var r_rs := radial.length() / maxf(Globals.rs_world(), 0.001)
	if r_rs < 0.001:
		return Vector3.ZERO
	var speed: float = Globals.disk_flow_speed * sqrt(Globals.disk_inner_rs / maxf(r_rs, 0.001))
	var tangent := Vector3.UP.cross(radial.normalized()) * signf(float(Globals.bh_disk_spin))
	return global_transform.basis * (tangent * speed * containment)


## 0..1 measure of how deep inside the accretion disk [param world_pos] sits:
## the product of a radial window and the slab's vertical Gaussian. Used to fade
## the disk's grip on the ship in and out smoothly.
func disk_containment(world_pos: Vector3) -> float:
	var rs: float = Globals.rs_world()
	if rs <= 0.0:
		return 0.0
	var local := global_transform.affine_inverse() * world_pos
	var r_rs := Vector2(local.x, local.z).length() / rs
	var inner: float = Globals.disk_inner_rs
	var outer: float = Globals.disk_outer_rs
	var radial := smoothstep(inner * 0.92, inner * 1.15, r_rs) * (1.0 - smoothstep(outer * 0.85, outer * 1.1, r_rs))
	if radial <= 0.0:
		return 0.0
	# Matches disk_half_thickness() in Goliath.gdshader: the slab flares outward.
	var t := clampf((r_rs - inner) / maxf(outer - inner, 0.001), 0.0, 1.0)
	var half_h: float = maxf(Globals.disk_thickness_rs * (0.30 + 0.70 * t), 0.012) * rs
	var vertical := exp(-(local.y * local.y) / maxf(half_h * half_h, 0.001))
	return radial * vertical


## True once the craft is inside the event horizon. There is no coming back from
## here by construction -- no thrust can raise your radius -- so callers should
## treat it as lethal rather than as a hazard to fly out of.
func inside_horizon(world_pos: Vector3) -> bool:
	var rs: float = Globals.rs_world()
	return rs > 0.0 and (world_pos - global_position).length() < rs


## Magnitude of the pull at a radius given in Schwarzschild radii. Split out from
## [method get_acceleration] so the HUD can ask "how bad does it get at r?"
## without synthesising a position.
func acceleration_at_rs(r_natural: float) -> float:
	var capture: float = Globals.bh_capture_radius
	if capture <= 1.0 or r_natural >= capture:
		return 0.0
	var t := clampf(inverse_lerp(capture, 1.0, r_natural), 0.0, 1.0)
	var ramp: float = pow(t, Globals.bh_falloff_exponent)
	var pull: float = Globals.bh_gravity
	var spin: float = Globals.bh_spin_strength
	# Inward and tangential are perpendicular, so the magnitude is the hypotenuse.
	return sqrt(pull * pull + spin * spin) * ramp


## Radius, in Schwarzschild radii, inside which a craft able to produce
## [param max_accel] can no longer climb back out. Bisection rather than an
## inversion because [member Globals.bh_falloff_exponent] makes the closed form
## ugly and this runs once per HUD refresh, not per pixel.
func point_of_no_return_rs(max_accel: float) -> float:
	if max_accel <= 0.0:
		return Globals.bh_capture_radius
	if acceleration_at_rs(1.0) <= max_accel:
		return 1.0 # engines win everywhere; there is no such radius
	var lo := 1.0
	var hi: float = Globals.bh_capture_radius
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if acceleration_at_rs(mid) > max_accel:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## Angular radius, in radians, of the patch of sky still visible from
## [param world_pos] -- the "hole in the dark" you have to fly back out through.
##
## The shadow of a Schwarzschild hole subtends sin(theta) = b_c/r * sqrt(1-1/r)
## with the critical impact parameter b_c = 3*sqrt(3)/2 rs, taking the obtuse
## branch inside the photon sphere. The sky is whatever is left over, so it
## shrinks to a point as you approach the horizon. This is the number that tells
## the player how much trouble they are actually in.
func sky_aperture_angle(world_pos: Vector3) -> float:
	var rs: float = Globals.rs_world()
	if rs <= 0.0:
		return PI
	var r := (world_pos - global_position).length() / rs
	if r <= 1.0:
		return 0.0
	var s := clampf(2.598076 / r * sqrt(maxf(1.0 - 1.0 / r, 0.0)), 0.0, 1.0)
	var shadow := asin(s)
	if r < 1.5: # inside the photon sphere the shadow covers more than a hemisphere
		shadow = PI - shadow
	return clampf(PI - shadow, 0.0, PI)


## 0.0 out past the disk's outer edge, rising to 1.0 at the horizon. Unlike
## [method capture_progress] this ignores the gravity deadzone -- it is a pure
## "how close am I" signal, used to drive the FOV distortion so the view starts
## stretching on approach rather than snapping the instant gravity engages.
func proximity(world_pos: Vector3) -> float:
	var rs: float = Globals.rs_world()
	if rs <= 0.0:
		return 0.0
	var r_natural: float = (world_pos - global_position).length() / rs
	var outer: float = maxf(Globals.disk_outer_rs, 2.0)
	return clampf(inverse_lerp(outer, 1.0, r_natural), 0.0, 1.0)
