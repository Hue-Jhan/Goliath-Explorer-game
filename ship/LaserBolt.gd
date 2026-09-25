class_name LaserBolt
extends Node3D
## A visible laser tracer.
##
## Carries no hit test of its own. [LaserCannon] resolves the shot along the
## ship's centre line the moment the trigger is pulled and tells each bolt how
## far to travel; the bolt just flies that far and retires.
##
## That split is deliberate. Bolts leave the wing roots half a unit either side
## of the centre line, and at four kilometres against a hull a metre or so wide
## that offset is the difference between a hit and a clean miss — the guns were
## firing parallel and sailing past on both sides. Converging them would fix it
## at exactly one range. Resolving the shot where the player is actually aiming
## fixes it at every range, and costs one raycast per volley instead of two per
## physics tick.

signal expired(bolt: LaserBolt)

## World units per second.
const SPEED := 5200.0

## Height of the cylinder in [code]LaserBolt.tscn[/code]. Everything here is
## expressed as a ratio against it, so the mesh and the code cannot drift apart.
const BASE_LENGTH := 360.0
## Diameter of that cylinder, before the distance correction below.
const BEAM_WIDTH := 4.0

## Apparent width the tracer is pulled toward, as a fraction of range.
##
## Fired from a chase camera the bolt recedes almost exactly along the view
## axis, so it is seen end-on: however long the beam, what reaches the eye is
## its cross-section, and that shrinks with distance until the shot simply
## vanishes. Lengthening it does nothing — a 380-unit beam pointed away from the
## camera still projects to about 13 pixels. Muzzle spacing cannot rescue it
## either: half a unit of separation at two kilometres is 0.014 degrees.
##
## So the tracer is widened with range. [b]Partially[/b], though: at
## [constant WIDTH_EXPONENT] = 1 the correction is exact, the bolt holds a fixed
## size on screen, and with nothing changing frame to frame it reads as parked in
## mid-air rather than as travelling away. At 0.7 it still shrinks — the eye gets
## its motion cue — just far more slowly than perspective alone would shrink it,
## so the shot stays legible to the end of its run instead of vanishing in the
## first half second.
const APPARENT_WIDTH := 0.030
const WIDTH_EXPONENT := 0.70
## Bounds on that correction, so a bolt at the muzzle is not a billboard and one
## at maximum range is not a speck.
const MIN_GIRTH := 0.50
const MAX_GIRTH := 22.0

## Fraction of the flight spent fading out. Tracers used to wink out at full
## brightness the instant they reached their limit, which at range — where the
## width correction has them changing size only slowly — looked like the bolt
## stopping dead and being deleted.
const FADE_FRACTION := 0.34

var _travelled: float = 0.0
var _limit: float = 0.0
var _alive: bool = false
var _energy: float = 3.2
## Non-zero only for bolts fired at the player; see [method fire_hostile].
var _damage: float = 0.0
var _hit_radius: float = 0.0
var _player: Node3D = null

var _material: StandardMaterial3D = null

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	# Pooled bolts share one .tscn, so the material has to be unpicked from the
	# resource or tinting one green for a turret would tint every bolt in flight.
	_material = (_mesh.material_override as StandardMaterial3D).duplicate()
	_mesh.material_override = _material
	set_physics_process(false)
	visible = false


## Sends the tracer out from [param from], retiring after [param distance].
func fire(from: Transform3D, distance: float, tint: Color = Color(1.0, 0.16, 0.08), energy: float = 3.2) -> void:
	global_transform = from
	_travelled = 0.0
	_limit = maxf(distance, 1.0)
	_alive = true
	_energy = energy
	_damage = 0.0
	_hit_radius = 0.0
	visible = true
	_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.95)
	_material.emission = tint
	_apply_length(Globals.laser_beam_length)
	_hold_apparent_size()
	set_physics_process(true)


## Sends a bolt out that will hurt the player if it reaches them.
##
## The player's rounds are hitscan -- [LaserCannon] resolves them the instant
## the trigger is pulled -- but return fire is not, and deliberately so. A
## hitscan turret either always hits or randomly does not, and neither is
## something a pilot can answer; a bolt with real travel time can be seen coming
## and flown out of. It also means the turret has to lead its shot, so jinking
## works for exactly the reason it looks like it should.
func fire_hostile(from: Transform3D, distance: float, tint: Color, damage: float, hit_radius: float) -> void:
	fire(from, distance, tint, 4.0)
	_damage = damage
	_hit_radius = hit_radius


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	var step := minf(SPEED * delta, _limit - _travelled)
	var was := global_position
	global_position += -global_transform.basis.z * step
	_travelled += step
	if _damage > 0.0 and _check_player_hit(was, global_position):
		return
	_hold_apparent_size()
	_fade()
	if _travelled >= _limit - 0.01:
		_retire()


## Swept proximity test: closest approach of this tick's segment to the player,
## against a radius generous enough to be fair.
##
## Both halves of that matter. The radius is generous because the ship is about
## one unit across and a hairline test would be a hit the player could neither
## see coming nor avoid on purpose. The test is swept because the alternative --
## comparing the bolt's position at each tick against the radius -- silently
## never fires: at 5200 u/s a bolt covers 87 units per physics step, so it
## simply steps over an 18-unit sphere. Measured, that cost the turrets every
## shot they took at anything past about a kilometre.
func _check_player_hit(from: Vector3, to: Vector3) -> bool:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
		if _player == null:
			return false
	var target := _player.global_position
	var closest := Geometry3D.get_closest_point_to_segment(target, from, to)
	if closest.distance_to(target) > _hit_radius:
		return false
	var ship := _player as Ship
	if ship != null:
		ship.take_damage(_damage)
	_damage = 0.0
	# Retire where it actually connected, not where the step ended.
	global_position = closest
	_retire()
	return true


## Stretches the cylinder along the bolt's own -Z without touching its girth.
##
## The basis is rebuilt rather than scaled: node scale would take the width with
## it, and the width is the one thing [method _hold_apparent_size] owns.
func _apply_length(length: float) -> void:
	var k := maxf(length, 10.0) / BASE_LENGTH
	# Columns, not rows: the cylinder's own +Y (its height axis) is mapped onto
	# the bolt's -Z, which is where it travels.
	_mesh.transform = Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -k), Vector3(0.0, 1.0, 0.0)),
		Vector3(0.0, 0.0, -maxf(length, 10.0) * 0.5))


## Widens the tracer with distance so it stays legible without going static.
func _hold_apparent_size() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var distance := cam.global_position.distance_to(global_position)
	var want := distance * APPARENT_WIDTH / BEAM_WIDTH
	var girth := clampf(pow(maxf(want, 0.0001), WIDTH_EXPONENT), MIN_GIRTH, MAX_GIRTH)
	# Z is left alone: the length is the mesh's business, not the node's.
	scale = Vector3(girth, girth, 1.0)


func _fade() -> void:
	var remaining := 1.0 - _travelled / _limit
	var t := clampf(remaining / FADE_FRACTION, 0.0, 1.0)
	_material.albedo_color.a = 0.95 * t
	_material.emission_energy_multiplier = _energy * t


func _retire() -> void:
	_alive = false
	visible = false
	set_physics_process(false)
	expired.emit(self)
