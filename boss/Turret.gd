class_name Turret
extends Node3D
## One defence turret on the [Mothership]'s spine.
##
## Owns its aiming and its cadence but not its ammunition: bolts come from the
## mothership's shared pool, because five turrets with a pool each would be five
## times the nodes for a rate of fire one pool can serve comfortably.
##
## [b]Firing arc.[/b] A turret only engages when the player is on its own side
## of the hull, tested against the mount normal. That is cheaper than a line of
## sight raycast and has the same effect at this geometry -- the hull is a
## convex shard, so "in front of the mount" and "not through the ship" are the
## same question.

## Seconds between shots.
@export var cadence: float = 1.6
@export var range_limit: float = 9000.0
## Hull damage a bolt that connects does.
##
## Down from 11. Five turrets at this cadence put roughly 3 hull points a second
## into a stationary target at three kilometres, which is pressure to fly out
## of rather than a countdown -- the standard hull has about half a minute in
## the open, and the Wasp still has to keep moving.
@export var damage: float = 7.0
## Angular error, radians, one standard deviation. The miss distance this
## produces grows with range -- 24 units at three kilometres, against an 18-unit
## hit radius -- so closing in is what makes the turrets dangerous, and standing
## off is a real but slow answer to them.
@export var spread: float = 0.008

var _cooldown: float = 0.0
var _head: Node3D = null
var _mothership: Mothership = null
var _mount_normal := Vector3.UP


func setup(mount_normal: Vector3, size: float) -> void:
	_mount_normal = mount_normal.normalized()
	_build(size)
	# Staggered, or all five fire on the same tick forever and the boss reads as
	# one gun with a five-round burst.
	_cooldown = randf() * cadence


func _ready() -> void:
	_mothership = _find_mothership()


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or _head == null:
		return
	var offset := player.global_position - global_position
	var distance := offset.length()
	if distance > range_limit or distance < 1.0:
		return

	var aim := _lead(player, distance)
	_head.global_basis = Basis.looking_at(aim, _safe_up(aim))

	# Mount normal in world space: the turret's parent is the hull, so this
	# follows the ship as it drifts and rolls.
	var outward := global_basis * _mount_normal
	if outward.dot(offset / distance) <= 0.05:
		return # player is on the far side of the hull
	if _cooldown <= 0.0:
		_cooldown = cadence
		_shoot(aim, distance)


## Where to point so a bolt at [constant LaserBolt.SPEED] and the player arrive
## in the same place. Straight-line prediction: a turn or a burn breaks it,
## which is exactly the out the player is meant to have.
func _lead(player: Node3D, distance: float) -> Vector3:
	var aim_point := player.global_position
	var ship := player as CharacterBody3D
	if ship != null:
		aim_point += ship.velocity * (distance / LaserBolt.SPEED)
	return (aim_point - global_position).normalized()


func _shoot(aim: Vector3, distance: float) -> void:
	if _mothership == null:
		_mothership = _find_mothership()
		if _mothership == null:
			return
	# Scatter within the cone by tilting the aim about two perpendicular axes.
	var side := _safe_up(aim).cross(aim).normalized()
	var up := aim.cross(side).normalized()
	var scattered := (aim + side * randfn(0.0, spread) + up * randfn(0.0, spread)).normalized()
	var muzzle := Transform3D(Basis.looking_at(scattered, _safe_up(scattered)), _head.global_position)
	_mothership.fire_hostile_bolt(muzzle, distance * 1.6, damage)


static func _safe_up(dir: Vector3) -> Vector3:
	return Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.97 else Vector3.RIGHT


## A right-handed basis whose +Y is [param axis]. Built by construction rather
## than by composing rotations, which cannot come out mirrored.
static func _basis_with_y(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var seed_axis := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := seed_axis.cross(y).normalized()
	return Basis(x, y, x.cross(y))


func _find_mothership() -> Mothership:
	var node := get_parent()
	while node != null:
		var boss := node as Mothership
		if boss != null:
			return boss
		node = node.get_parent()
	return null


## Barrel plus a glowing breech, built along -Z so [method Basis.looking_at]
## points it the way everything else in the project points.
func _build(size: float) -> void:
	var base := MeshInstance3D.new()
	var drum := CylinderMesh.new()
	drum.top_radius = size * 0.9
	drum.bottom_radius = size * 1.15
	drum.height = size * 0.8
	drum.radial_segments = 8
	base.mesh = drum
	base.material_override = CelestialMesh.rock_material(Color(0.13, 0.15, 0.14), 0.85)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The drum stands along the mount normal, so it sits flush on the hull. Set
	# as a local basis: the turret has not entered the tree yet, and its parent
	# frame is the hull anyway.
	base.basis = _basis_with_y(_mount_normal)
	add_child(base)

	_head = Node3D.new()
	add_child(_head)

	var barrel := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = size * 0.28
	tube.bottom_radius = size * 0.42
	tube.height = size * 3.0
	tube.radial_segments = 6
	barrel.mesh = tube
	barrel.material_override = CelestialMesh.rock_material(Color(0.10, 0.13, 0.12), 0.7)
	barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cylinder height runs along +Y; map it onto the head's -Z.
	barrel.transform = Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
		Vector3(0.0, 0.0, -size * 1.5))
	_head.add_child(barrel)

	var muzzle_glow := MeshInstance3D.new()
	muzzle_glow.mesh = CelestialMesh.uv_sphere(size * 0.5, 6, 8)
	muzzle_glow.material_override = CelestialMesh.glow_material(Mothership.BIOLUME, 4.0, 0.8)
	muzzle_glow.position = Vector3(0.0, 0.0, -size * 3.0)
	muzzle_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(muzzle_glow)
