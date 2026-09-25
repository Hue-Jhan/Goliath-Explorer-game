class_name Enemy
extends CharacterBody3D
## A hostile interceptor.
##
## Kept deliberately simple: it closes on the player, and it will not fly itself
## into Goliath. The second part matters more than it sounds -- without it a
## spawner quietly feeds its whole population into the hole within a minute and
## the map empties out.
##
## Lives on collision layer 3 so laser bolts and the player can hit it while it
## still collides with asteroids on layer 1.
##
## The body is never scaled. Its size is baked into the generated mesh instead,
## because scaling a [CharacterBody3D] scales its basis vectors, and
## [code]-basis.z * thrust[/code] then quietly multiplies the engines by the
## scale factor.

signal died(enemy: Enemy)

const GROUP := &"enemies"
## Awarded for a kill.
const POINTS := 150

@export var max_health: float = 40.0
## Top speed works out as thrust x (brake_time / 3). Kept well under the
## player's so a dogfight is a pursuit rather than a chase you always lose.
@export var thrust: float = 420.0
@export var turn_rate: float = 0.75
@export var brake_time: float = 1.9
## Hull size in world units. Baked into the geometry, never applied as node
## scale -- see the class note.
@export var hull_size: float = 4.5

## Engagement range, in world units.
@export var aggro_range: float = 14000.0
## Where this hostile loiters when it has nobody to chase. Left at zero radius
## it patrols the ring around Goliath, which is what the spawner wants; an
## escort is handed its mothership's position and a tight radius instead, so it
## stays with the ship it is escorting rather than wandering home to the hole.
@export var patrol_centre: Vector3 = Vector3.ZERO
@export var patrol_radius: float = 0.0
## Optional: a node to patrol around instead of a fixed point. An escort's
## mothership drifts, and a patrol pinned to where it was at spawn leaves the
## escorts loitering over empty space a few minutes in.
var patrol_anchor: Node3D = null
## Never approach the hole closer than this, in Schwarzschild radii.
##
## Derived rather than authored: it has to sit outside
## [member Globals.bh_capture_radius], and that is now a setting the player can
## move. A fixed number here would quietly start spawning hostiles inside the
## deadzone the moment anyone raised it.
@export var keep_out_margin_rs: float = 2.0

var health: float = 40.0

var _player: Node3D = null
var _well: GravityWell = null
var _wander := Vector3.ZERO
var _wander_timer := 0.0

@onready var _hull: MeshInstance3D = $Hull
@onready var _shape: CollisionShape3D = $Body


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health
	_hull.mesh = ShipMesh.build_interceptor(hull_size)
	_hull.material_override = hull_material()
	_shape.shape = ShipMesh.build_interceptor_shape(hull_size)
	_pick_wander()


static func hull_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.13, 0.14)
	mat.metallic = 0.7
	mat.roughness = 0.42
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.18, 0.12)
	mat.emission_energy_multiplier = 0.55
	mat.rim_enabled = true
	mat.rim = 0.6
	return mat


func _physics_process(delta: float) -> void:
	var goal := _goal()
	var to_goal := goal - global_position
	if to_goal.length() > 1.0:
		_face(to_goal.normalized(), delta)
		velocity += -global_transform.basis.z * thrust * delta

	# Same flight-assist shape as the player, so they handle alike.
	var tau := maxf(brake_time / 3.0, 0.01)
	velocity += (-velocity / tau) * delta

	var well := _find_well()
	if well != null:
		velocity += well.get_acceleration(global_position) * delta
		if _crushed_by(well):
			return

	var hit := move_and_collide(velocity * delta)
	if hit != null:
		velocity = velocity.slide(hit.get_normal()) * 0.5


## Kills anything that has crossed the horizon, and leans on anything that is
## merely captured.
##
## Both halves are needed. An interceptor's engines are a twelfth of the pull at
## the horizon, so once it is inside the deadzone it is going in whatever its
## flight plan says -- [method _goal] keeps its *destination* outside, but an
## overshoot at speed still ends up captured. Without the crush they pile up in
## the shadow, where they cannot be shot, cannot leave, and keep showing on the
## map as contacts that never resolve.
##
## No score for it. Goliath killed it, not the player.
func _crushed_by(well: GravityWell) -> bool:
	if well.inside_horizon(global_position):
		Effects.burst(self, global_position, hull_size * 2.0, Color(1.0, 0.45, 0.16))
		died.emit(self)
		queue_free()
		return true
	# Captured but not yet lost: burn straight out, on top of whatever the
	# flight plan wanted. Enough to save a shallow overshoot, nowhere near
	# enough to climb out from deep in.
	var escape := well.capture_progress(global_position)
	if escape > 0.0:
		velocity += well.escape_vector(global_position) * thrust * escape * 1.6 			* get_physics_process_delta_time()
	return false


## Closest the hostile will willingly come to Goliath, in Schwarzschild radii.
func keep_out_rs() -> float:
	return Globals.bh_capture_radius + keep_out_margin_rs


## Where it wants to be: the player if in range and safely out of the well,
## otherwise a drifting patrol point. Either way the result is pushed back out
## to [method keep_out_rs] so it never chases anyone into the horizon.
func _goal() -> Vector3:
	var target := _wander
	var player := _find_player()
	if player != null and player.global_position.distance_to(global_position) < aggro_range:
		target = player.global_position

	_wander_timer -= get_physics_process_delta_time()
	if _wander_timer <= 0.0:
		_pick_wander()

	var well := _find_well()
	if well == null:
		return target
	var from_hole := target - well.global_position
	var floor_radius: float = keep_out_rs() * Globals.rs_world()
	if from_hole.length() < floor_radius:
		target = well.global_position + from_hole.normalized() * floor_radius
	return target


func _pick_wander() -> void:
	_wander_timer = randf_range(5.0, 11.0)
	var angle := randf() * TAU
	if patrol_radius > 0.0:
		var home := patrol_centre
		if is_instance_valid(patrol_anchor):
			home = patrol_anchor.global_position
		_wander = home + Vector3(
			cos(angle) * patrol_radius,
			randf_range(-0.35, 0.35) * patrol_radius,
			sin(angle) * patrol_radius) * randf_range(0.45, 1.0)
		return
	var rs: float = Globals.rs_world()
	var radius := randf_range(keep_out_rs() + 2.0, keep_out_rs() + 18.0) * rs
	_wander = Vector3(cos(angle) * radius, randf_range(-4.0, 4.0) * rs, sin(angle) * radius)


func _face(dir: Vector3, delta: float) -> void:
	var want := Basis.looking_at(dir, Vector3.UP)
	var q := Quaternion(global_transform.basis.orthonormalized()).slerp(
		Quaternion(want), clampf(turn_rate * delta, 0.0, 1.0))
	global_transform.basis = Basis(q)


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		Effects.burst(self, global_position, hull_size * 2.6, Color(1.0, 0.55, 0.18))
		Globals.add_score(POINTS, "%s DESTROYED" % _short_name(), true)
		died.emit(self)
		queue_free()


func _short_name() -> String:
	return "INTERCEPTOR"


func _find_player() -> Node3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	return _player


func _find_well() -> GravityWell:
	if not is_instance_valid(_well):
		var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
		_well = wells[0] if not wells.is_empty() else null
	return _well
