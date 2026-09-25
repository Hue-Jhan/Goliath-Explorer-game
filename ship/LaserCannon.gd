class_name LaserCannon
extends Node3D
## Forward-firing lasers, with aim assist and impact feedback.
##
## The shot is resolved as a single ray down the ship's centre line -- what the
## crosshair covers is what gets hit -- and two tracers are spawned from the
## wing roots for the look of it. See [LaserBolt] for why the tracers do not
## carry the hit test themselves.

signal hit_registered(target: Node3D, at: Vector3)

const BOLT := preload("res://ship/LaserBolt.tscn")
const FLASH := preload("res://ship/ImpactFlash.tscn")

@export var range_limit: float = 9000.0
## Tracer origins in the firer's local frame.
@export var muzzles: Array[Vector3] = [Vector3(0.52, -0.02, -0.62), Vector3(-0.52, -0.02, -0.62)]
@export var pool_size: int = 48
@export var flash_pool_size: int = 10

var _cooldown: float = 0.0
var _pool: Array[LaserBolt] = []
var _flashes: Array[ImpactFlash] = []
var _next: int = 0
var _owner_body: Node3D = null
var _exclude: Array[RID] = []

var _lock: Node3D = null
var _lock_timer: float = 0.0


func _ready() -> void:
	_owner_body = get_parent() as Node3D
	var body := _owner_body as CollisionObject3D
	if body != null:
		_exclude.append(body.get_rid())
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	for i in pool_size:
		var bolt := BOLT.instantiate() as LaserBolt
		host.add_child.call_deferred(bolt)
		_pool.append(bolt)
	for i in flash_pool_size:
		var flash := FLASH.instantiate() as ImpactFlash
		host.add_child.call_deferred(flash)
		_flashes.append(flash)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_lock(delta)


## The hostile the assist is currently pulling toward, or null. The HUD draws a
## reticle on it.
## The target the shot will be pulled onto, or null.
##
## Anything returned here MUST be inside the aim cone. The soft target (E) gets
## priority among candidates, but only while it is actually ahead of the nose --
## an earlier version handed it priority unconditionally, and since the soft lock
## lasts seconds, shooting at an asteroid quietly sent every round at a hostile
## somewhere off screen. Aim assist may nudge a shot; it may not choose the
## target for you.
func locked_target() -> Node3D:
	var ship := _owner_body as Ship
	if ship != null:
		var chosen := ship.soft_target()
		if chosen != null and _within_cone(chosen):
			return chosen
	return _lock if is_instance_valid(_lock) else null


func _within_cone(target: Node3D) -> bool:
	if _owner_body == null:
		return false
	var offset := target.global_position - _owner_body.global_position
	var distance := offset.length()
	if distance < 1.0 or distance > range_limit:
		return false
	var forward := -_owner_body.global_transform.basis.z
	return forward.dot(offset / distance) > cos(deg_to_rad(Globals.aim_assist_cone))


## Keeps a magnetic lock on whatever is nearest the crosshair.
##
## The lock survives for [member Globals.aim_assist_grace] after the crosshair
## leaves the cone, which is the whole point: at these closing speeds a target
## crosses the cone in a couple of frames, and without the grace period the
## assist would only ever help players who were already on target.
func _update_lock(delta: float) -> void:
	_lock_timer = maxf(_lock_timer - delta, 0.0)
	if not is_instance_valid(_lock) or _lock_timer <= 0.0:
		_lock = null

	if _owner_body == null or Globals.aim_assist_cone <= 0.0:
		return
	var origin := _owner_body.global_position
	var forward := -_owner_body.global_transform.basis.z
	var limit := cos(deg_to_rad(Globals.aim_assist_cone))
	var best: Node3D = null
	var best_dot := limit
	for enemy in get_tree().get_nodes_in_group(Enemy.GROUP):
		var target := enemy as Node3D
		var offset := target.global_position - origin
		var distance := offset.length()
		if distance < 1.0 or distance > range_limit:
			continue
		var alignment := forward.dot(offset / distance)
		if alignment > best_dot:
			best_dot = alignment
			best = target
	if best != null:
		_lock = best
		_lock_timer = Globals.aim_assist_grace


## Fires if off cooldown. Safe to call every frame while the trigger is held.
func try_fire() -> bool:
	if _cooldown > 0.0 or _owner_body == null or not is_inside_tree():
		return false
	_cooldown = 1.0 / maxf(Globals.laser_fire_rate, 0.01)

	var base := _owner_body.global_transform
	var from := base.origin
	var forward := -base.basis.z
	# Aim assist: pull the shot onto the locked target. Only the ray bends --
	# the tracers still leave the muzzles pointing where the ship points, so the
	# help is felt rather than seen.
	var locked := locked_target()
	if locked != null:
		forward = (locked.global_position - from).normalized()
	var to := from + forward * range_limit

	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Layer 1 is asteroids, layer 3 is hostiles; the player's own layer 2 is
	# deliberately absent so you cannot shoot yourself.
	query.collision_mask = 1 | 4
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var travel := range_limit
	if not hit.is_empty():
		var at: Vector3 = hit["position"]
		travel = from.distance_to(at)
		var target: Object = hit["collider"]
		var killed := false
		if target != null and target.has_method(&"take_damage"):
			target.take_damage(Globals.laser_damage)
			killed = not is_instance_valid(target)
		_pop_flash(at, killed, target)
		hit_registered.emit(target as Node3D, at)

	for muzzle in muzzles:
		var bolt := _take()
		if bolt == null:
			continue
		var t := base
		t.origin = base * muzzle
		bolt.fire(t, maxf(travel, 1.0))
	return true


## A small flash for a hit, a much bigger one for a kill.
func _pop_flash(at: Vector3, killed: bool, target: Object) -> void:
	var flash := _take_flash()
	if flash == null:
		return
	var size := 9.0
	var tint := Color(1.0, 0.45, 0.22)
	if killed:
		var rock := target as Asteroid
		size = (rock.radius * 1.6) if rock != null else 34.0
		tint = Color(1.0, 0.72, 0.30)
	flash.pop(at, size, tint)


func _take() -> LaserBolt:
	for i in _pool.size():
		var bolt := _pool[(_next + i) % _pool.size()]
		if not bolt.visible:
			_next = (_next + i + 1) % _pool.size()
			return bolt
	return null


func _take_flash() -> ImpactFlash:
	for flash in _flashes:
		if not flash.busy():
			return flash
	return null
