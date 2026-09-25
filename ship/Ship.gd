class_name Ship
extends CharacterBody3D
## The player vessel, flown with a flight-assisted ("semi-Newtonian") model.
##
## Not a [RigidBody3D]: the whole point of this model is that thrust, drag and
## gravity are authored rather than emergent, and the assist has a deliberate
## authority ceiling that [i]loses[/i] to Goliath close in. A rigid body would
## hide all of that behind the physics solver. [method move_and_collide] still
## gives real collisions, which is all the asteroids need.
##
## [b]Linear feel.[/b] Braking thrusters run continuously, pulling velocity
## toward zero with a time constant of [member Globals.ship_brake_time] / 3 --
## so releasing the throttle sheds ~95% of your speed in that many seconds.
## Two consequences fall out for free: a natural terminal velocity
## (thrust x tau), and, because assist authority is capped at
## [member Globals.ship_assist_authority] x thrust, a radius inside which
## gravity simply beats your engines. That radius is the game.
##
## [b]Angular feel.[/b] Mouse motion is read as a rate [i]command[/i] (pixels
## per second -> rad/s), not as an impulse, so the handling does not change with
## frame rate. Angular velocity chases that command with its own drag constant,
## which is what lets the ship keep tumbling for a moment after a flick.

signal hull_changed(current: float, maximum: float)
signal impact_felt(speed: float, normal: Vector3)
## Raised the moment the horizon is crossed, ahead of [signal destroyed] by
## [member Globals.horizon_death_delay].
signal terminal_began
signal destroyed

var hull: float = 100.0
## Thruster heat, 0..1. Cosmetic telemetry: it drives the HUD gauge and nothing
## else yet, but it is the natural hook for a boost cooldown later.
var heat: float = 0.0
## Current throttle demand magnitude, 0..1. Drives the engine glow.
var throttle: float = 0.0

var _angular := Vector3.ZERO
var _mouse_delta := Vector2.ZERO
var _well: GravityWell = null
var _dead := false
## Soft target: a hostile the pilot asked to be helped onto. Steers the nose
## toward it for a few seconds, then lets go.
var _soft_target: Node3D = null
var _soft_timer: float = 0.0
## Past the horizon but not yet written off: the ship tumbles under control of
## nothing but gravity while the clock runs down.
var _dying := false
var _death_timer := 0.0
## Radius at the last terminal tick, used to keep the fall monotonic.
var _last_radius := 0.0
## What finished the ship off, for the death notice. Empty while alive.
var death_reason := ""

@onready var _hull_mesh: MeshInstance3D = $Hull
@onready var _body_shape: CollisionShape3D = $Body
@onready var _glow_left: MeshInstance3D = $EngineGlowL
@onready var _glow_right: MeshInstance3D = $EngineGlowR
@onready var _thruster_light: OmniLight3D = $ThrusterLight
@onready var _camera: ChaseCamera = $ChaseCamera
@onready var _cannon: LaserCannon = $LaserCannon

var _charge: ChargeBeam = null


func _ready() -> void:
	add_to_group(&"player")
	# The hull is generated, not authored, so the scene file carries only the
	# node skeleton and materials; geometry comes from the selected class here.
	# See [ShipClasses] and [ShipMesh].
	var hull_class: int = Globals.selected_ship
	_hull_mesh.mesh = ShipClasses.build_mesh(hull_class)
	_hull_mesh.material_override = ShipClasses.material(hull_class)
	_body_shape.shape = ShipClasses.build_shape(hull_class)
	var entry := ShipClasses.data(hull_class)
	var muzzle: Vector3 = entry["muzzle"]
	_cannon.muzzles = [muzzle, Vector3(-muzzle.x, muzzle.y, muzzle.z)]
	# Bigger hulls sit further back, or the Anvil fills half the screen.
	_camera.distance = entry["chase"]
	var bell := ShipMesh.build_engine_glow()
	_glow_left.mesh = bell
	_glow_right.mesh = bell
	# The charged beam hangs off the nose, which is a different station on every
	# hull, so it is placed from the same table the guns are.
	_charge = ChargeBeam.new()
	_charge.position = Vector3(0.0, muzzle.y, muzzle.z - 0.9)
	add_child(_charge)
	hull = Globals.ship_max_hull
	hull_changed.emit(hull, Globals.ship_max_hull)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += (event as InputEventMouseMotion).relative
	elif event.is_action_pressed(&"target_assist"):
		_acquire_soft_target()
	elif event.is_action_pressed(&"toggle_mouse_capture"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _dying:
		_charge.tick(delta, false)
		_terminal(delta)
		return
	_steer(delta)
	_fly(delta)
	var at_the_controls := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if Input.is_action_pressed(&"fire_laser") and at_the_controls:
		_cannon.try_fire()
	_charge.tick(delta, at_the_controls)
	_thermals(delta)
	_move(delta)


# --- soft targeting -----------------------------------------------------------

## Grabs whatever hostile sits nearest the crosshair and tracks it for
## [member Globals.soft_lock_duration].
##
## The cone is wide (tens of degrees, against the cannon's few) because this is
## a "help me come about" button, not an auto-aim: the assist it applies is a
## steering rate proportional to the angular error, capped well below what the
## pilot can command, and faded out over the last second so it releases rather
## than snaps off. You can always out-turn it.
func _acquire_soft_target() -> void:
	_soft_target = null
	_soft_timer = 0.0
	if Globals.soft_lock_duration <= 0.0:
		return
	var origin := global_position
	var forward := -global_transform.basis.z
	var best_dot := cos(deg_to_rad(Globals.soft_lock_cone))
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Node3D
		var offset := enemy.global_position - origin
		var distance := offset.length()
		if distance < 1.0 or distance > Globals.soft_lock_range:
			continue
		var alignment := forward.dot(offset / distance)
		if alignment > best_dot:
			best_dot = alignment
			_soft_target = enemy
	if _soft_target != null:
		_soft_timer = Globals.soft_lock_duration


## The hostile currently being tracked, or null. Drawn by the HUD, and preferred
## by [LaserCannon] over its own magnetic lock.
func soft_target() -> Node3D:
	return _soft_target if is_instance_valid(_soft_target) and _soft_timer > 0.0 else null


## Seconds of tracking left, 0..1 of the full duration.
func soft_lock_fraction() -> float:
	return clampf(_soft_timer / maxf(Globals.soft_lock_duration, 0.01), 0.0, 1.0)


func _soft_steer(cmd: Vector3, delta: float) -> Vector3:
	_soft_timer = maxf(_soft_timer - delta, 0.0)
	var target := soft_target()
	if target == null:
		return cmd
	var offset := target.global_position - global_position
	if offset.length() > Globals.soft_lock_range:
		_soft_timer = 0.0 # drifted out of range; let go
		return cmd
	var local := global_transform.basis.inverse() * offset.normalized()
	# Fade over the last second so the hand-back is felt as easing, not a cut.
	var fade := clampf(_soft_timer, 0.0, 1.0)
	var gain: float = Globals.soft_lock_strength * fade
	cmd.y += -local.x * gain
	cmd.x += local.y * gain
	return cmd


# --- rotation -----------------------------------------------------------------

func _steer(delta: float) -> void:
	var turn: float = Globals.ship_turn_rate
	var cmd := Vector3.ZERO
	if delta > 0.0:
		# Pixels-this-tick / seconds-this-tick = pixels per second, so the same
		# hand movement gives the same turn rate at any frame rate.
		var sensitivity: float = Globals.mouse_sensitivity
		var pitch_px := _mouse_delta.y * (1.0 if Globals.invert_pitch else -1.0)
		cmd.x = clampf(pitch_px * sensitivity / delta, -turn, turn)
		cmd.y = clampf(-_mouse_delta.x * sensitivity / delta, -turn, turn)
	_mouse_delta = Vector2.ZERO

	var roll := Input.get_action_strength(&"roll_left") - Input.get_action_strength(&"roll_right")
	cmd.z = roll * Globals.ship_roll_rate

	cmd = _soft_steer(cmd, delta)

	var tau: float = maxf(Globals.ship_angular_brake_time / 3.0, 0.01)
	_angular = _angular.lerp(cmd, 1.0 - exp(-delta / tau))

	# Integrate in the ship's own frame so pitch/yaw/roll stay body-relative and
	# the ship can tumble through any orientation without gimbal trouble.
	var b := global_transform.basis
	b = b.rotated(b.x, _angular.x * delta)
	b = b.rotated(b.y, _angular.y * delta)
	b = b.rotated(b.z, _angular.z * delta)
	global_transform.basis = b.orthonormalized()


# --- translation --------------------------------------------------------------

func _fly(delta: float) -> void:
	var input := Vector3(
		Input.get_action_strength(&"fly_right") - Input.get_action_strength(&"fly_left"),
		Input.get_action_strength(&"fly_up") - Input.get_action_strength(&"fly_down"),
		Input.get_action_strength(&"fly_back") - Input.get_action_strength(&"fly_forward")
	)
	if input.length() > 1.0:
		input = input.normalized()
	throttle = input.length()

	var power: float = Globals.ship_thrust
	if Input.is_action_pressed(&"fly_boost"):
		power *= Globals.ship_boost_multiplier
	velocity += (global_transform.basis * input) * power * delta

	var well := _find_well()

	# Braking thrusters. Capped authority is what makes the hole lethal: past
	# some radius Goliath simply out-pulls anything the engines can answer with.
	#
	# Crucially they brake toward the *local rest frame*, not toward zero. Out in
	# open space that frame is stationary and this behaves as before. Inside the
	# accretion disk it is the orbiting gas, so letting go of the throttle in
	# there leaves you co-moving with the disk rather than stopping dead: turn
	# into the flow, release W, and you keep going round.
	var rest := Vector3.ZERO
	var grip := 0.0
	if well != null:
		grip = well.disk_containment(global_position) * Globals.disk_drag
		if grip > 0.0:
			rest = well.disk_flow_velocity(global_position)

	var tau: float = maxf(Globals.ship_brake_time / 3.0, 0.01)
	var brake := (rest - velocity) / tau
	var ceiling: float = Globals.ship_thrust * Globals.ship_assist_authority
	if brake.length() > ceiling:
		brake = brake.normalized() * ceiling
	velocity += brake * delta

	if well != null:
		velocity += well.get_acceleration(global_position) * delta
		# Crossing the horizon is not a hazard to recover from. It is not an
		# instant loss either: see _terminal().
		if well.inside_horizon(global_position):
			_begin_terminal()
	_hazards(delta)


## Everything in the system that is not Goliath: the white dwarf's pull, the
## pulsar's beams.
##
## Summed over the whole group rather than resolved against a nearest one. Each
## hazard is exactly zero outside its own radius, so the sum is only ever over
## the handful you are actually inside, and summing means two overlapping
## hazards behave like two overlapping hazards instead of like whichever the
## sort order happened to pick.
func _hazards(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(Hazard.GROUP):
		var hazard := node as Hazard
		if hazard == null:
			continue
		velocity += hazard.get_acceleration(global_position) * delta
		var burn := hazard.damage_rate(global_position)
		if burn > 0.0:
			take_damage(burn * delta)
		var shake := hazard.trauma_rate(global_position)
		if shake > 0.0:
			_camera.add_trauma(shake * delta)
		if hazard.is_lethal_contact(global_position):
			_crash(hazard.death_notice())
			return


## Flown into something solid and hot. Unlike the horizon there is nothing to
## play out here -- the ship is simply gone -- so this is immediate.
func _crash(reason: String) -> void:
	if _dead or _dying:
		return
	death_reason = reason
	Effects.burst(self, global_position, 48.0, Color(1.0, 0.85, 0.55))
	Effects.burst(self, global_position, 26.0, Color(0.6, 0.9, 1.0))
	_camera.add_trauma(1.0)
	hull = 0.0
	hull_changed.emit(hull, Globals.ship_max_hull)
	_dead = true
	destroyed.emit()


## Shockwave from a nearby detonation. [param amount] is 0..1.
func feel_blast(amount: float) -> void:
	if amount > 0.0:
		_camera.add_trauma(clampf(amount, 0.0, 1.0))


## Charge state for the HUD gauge: how full the held charge is, how far through
## the recharge the weapon is, and whether it can be fired at all.
func charge_fraction() -> float:
	return _charge.charge() if _charge != null else 0.0


func charge_readiness() -> float:
	return _charge.readiness() if _charge != null else 1.0


func charge_ready() -> bool:
	return _charge == null or _charge.is_ready()


## How strongly the disk currently has hold of the ship, 0..1. HUD telemetry.
func disk_grip() -> float:
	var well := _find_well()
	return 0.0 if well == null else well.disk_containment(global_position)


func _thermals(delta: float) -> void:
	var boost: float = Globals.ship_boost_multiplier if Input.is_action_pressed(&"fly_boost") else 1.0
	var thermal_load := throttle * boost
	var heat_rate: float = Globals.ship_heat_rate
	var cool_rate: float = Globals.ship_cool_rate
	heat = clampf(heat + (thermal_load * heat_rate - cool_rate) * delta, 0.0, 1.0)

	var glow := clampf(throttle, 0.0, 1.0)
	if Input.is_action_pressed(&"fly_boost") and throttle > 0.0:
		glow = 1.0
	_set_engine_glow(glow)


func _set_engine_glow(amount: float) -> void:
	var energy := 0.18 + amount * 3.2
	for m in [_glow_left, _glow_right]:
		var mat := m.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = energy
		m.scale = Vector3(1.0, 1.0, 1.0) * (0.8 + amount * 0.45)
	_thruster_light.light_energy = amount * 6.0
	_thruster_light.omni_range = 3.0 + amount * 5.0


# --- collision ----------------------------------------------------------------

func _move(delta: float) -> void:
	var hit := move_and_collide(velocity * delta)
	if hit == null:
		return
	var n := hit.get_normal()
	var closing := maxf(-velocity.dot(n), 0.0)
	# Slide off rather than stop dead, and lose most of the normal component.
	velocity = velocity.slide(n) * 0.55
	# Push clear so the next tick does not start already overlapping.
	global_position += n * 0.08
	if closing > 1.0:
		impact_felt.emit(closing, n)
		# Trauma is squared by the camera, so a gentle scrape at 60 u/s reads as
		# a nudge while a 600 u/s hit genuinely rattles the frame.
		_camera.add_trauma(clampf(closing / 600.0, 0.10, 1.0))
		take_damage(closing * Globals.ship_impact_damage)


## Hands the ship to gravity for a few seconds before declaring it lost.
##
## Crossing the horizon is the most dramatic thing in this game, and cutting
## straight from it to a restart prompt throws that away. Control is gone
## immediately -- nothing you press matters past the horizon, and pretending
## otherwise would be a lie -- but the fall itself is played out: gravity keeps
## accelerating the wreck inward, the tumble builds, and the camera shakes
## harder the deeper it goes.
func _begin_terminal() -> void:
	if _dying or _dead:
		return
	_dying = true
	death_reason = "CRUSHED BEYOND THE HORIZON"
	_death_timer = Globals.horizon_death_delay
	var well := _find_well()
	_last_radius = global_position.distance_to(well.global_position) if well != null else 0.0
	hull = 0.0
	hull_changed.emit(hull, Globals.ship_max_hull)
	terminal_began.emit()


func _terminal(delta: float) -> void:
	_death_timer -= delta
	var well := _find_well()
	if well != null:
		velocity += well.get_acceleration(global_position) * delta

	# Tumble builds as the clock runs down.
	var severity := 1.0 - clampf(_death_timer / maxf(Globals.horizon_death_delay, 0.01), 0.0, 1.0)
	_angular = _angular.lerp(Vector3(1.9, -2.6, 3.4) * (0.35 + severity), 1.0 - exp(-delta / 0.8))
	var b := global_transform.basis
	b = b.rotated(b.x, _angular.x * delta)
	b = b.rotated(b.y, _angular.y * delta)
	b = b.rotated(b.z, _angular.z * delta)
	global_transform.basis = b.orthonormalized()
	global_position += velocity * delta

	# Nothing inside a horizon gets further away from the singularity. The
	# tangential term in the well is large enough down here to sling the wreck
	# back out past the horizon, which looks like the ship escaping something
	# nothing escapes, so radius is held monotonically decreasing.
	if well != null:
		var offset := global_position - well.global_position
		var r := offset.length()
		if r > 0.001 and r > _last_radius:
			global_position = well.global_position + offset * (_last_radius / r)
			r = _last_radius
		_last_radius = r

	_camera.add_trauma((0.5 + 2.5 * severity) * delta)
	_set_engine_glow(0.0)

	if _death_timer <= 0.0:
		_dying = false
		_dead = true
		destroyed.emit()


## True while past the horizon and still falling.
func is_falling_in() -> bool:
	return _dying


func take_damage(amount: float) -> void:
	if _dead or _dying or amount <= 0.0:
		return
	hull = maxf(hull - amount, 0.0)
	hull_changed.emit(hull, Globals.ship_max_hull)
	if hull <= 0.0:
		if death_reason == "":
			death_reason = "HULL BREACH"
		_dead = true
		destroyed.emit()


func repair_full() -> void:
	_dead = false
	_dying = false
	death_reason = ""
	_angular = Vector3.ZERO
	hull = Globals.ship_max_hull
	hull_changed.emit(hull, Globals.ship_max_hull)


# --- telemetry for the HUD ----------------------------------------------------

func hull_ratio() -> float:
	return clampf(hull / maxf(Globals.ship_max_hull, 0.001), 0.0, 1.0)


func speed() -> float:
	return velocity.length()


## Speed as a fraction of the assist's natural terminal velocity, for the gauge.
func speed_ratio() -> float:
	var terminal: float = Globals.ship_thrust * maxf(Globals.ship_brake_time / 3.0, 0.01)
	return clampf(speed() / maxf(terminal, 1.0), 0.0, 1.0)


func is_dead() -> bool:
	return _dead


func _find_well() -> GravityWell:
	if is_instance_valid(_well):
		return _well
	var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
	_well = wells[0] if not wells.is_empty() else null
	return _well
