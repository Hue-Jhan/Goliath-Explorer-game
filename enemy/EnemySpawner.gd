class_name EnemySpawner
extends Node3D
## Keeps a population of hostiles alive *around the player*, not around the map.
##
## The first version seeded a fixed ring around Goliath and left everything in
## it awake forever. Two things were wrong with that. Interceptors thirty
## kilometres away were still running full flight assist and pathfinding every
## physics tick for nobody's benefit, and because they were placed by radius
## rather than by proximity, flying out to the pulsar meant flying away from the
## entire population -- the map had hostiles on it and the game did not.
##
## So spawning is proximity-driven: hostiles appear in a shell around the
## player, out of immediate view, and are retired once they fall far enough
## behind that they could not rejoin the fight. The population is a budget for
## what is near you, not a census of the system.

const ENEMY := preload("res://enemy/Enemy.tscn")

## Hostiles appear no closer than this and no further than this, in world units.
## The inner bound is what stops an interceptor blinking into existence a
## hundred metres off the nose, which reads as a bug rather than as an ambush.
@export var spawn_near: float = 4200.0
@export var spawn_far: float = 9000.0
## Retired once this far from the player. Comfortably outside [member spawn_far]
## so a hostile that spawns at the rim and turns away is not deleted on the next
## tick -- that hysteresis is the whole reason the two numbers differ.
@export var cull_radius: float = 17000.0
## Never spawn inside the deadzone plus this margin, in Schwarzschild radii, so
## a fresh hostile is never born already captured. Measured against
## [member Globals.bh_capture_radius] rather than fixed, because that is a
## setting the player can move.
@export var keep_out_margin_rs: float = 3.0

var _accumulator: float = 0.0
var _live: Array[Enemy] = []
var _player: Node3D = null


func _ready() -> void:
	add_to_group(&"enemy_spawner")


func _process(delta: float) -> void:
	_prune()
	_cull()
	var player := _find_player()
	if player == null or Globals.enemy_spawn_rate <= 0.0:
		return
	if _live.size() >= Globals.max_enemies:
		return
	_accumulator += delta * Globals.enemy_spawn_rate
	while _accumulator >= 1.0 and _live.size() < Globals.max_enemies:
		_accumulator -= 1.0
		_spawn(player)


## Retires hostiles that have fallen too far behind to matter.
##
## Freed rather than hidden: a pool would keep their physics bodies in the
## world, and the cost this exists to avoid is exactly that. They are cheap to
## rebuild -- the mesh is cached per size by [ShipMesh] anyway.
func _cull() -> void:
	var player := _find_player()
	if player == null:
		return
	var kept: Array[Enemy] = []
	for e in _live:
		if e.global_position.distance_to(player.global_position) > cull_radius:
			e.queue_free()
		else:
			kept.append(e)
	_live = kept


## Closest a fresh hostile may be placed to Goliath, in Schwarzschild radii.
func keep_out_rs() -> float:
	return Globals.bh_capture_radius + keep_out_margin_rs


func _spawn(player: Node3D) -> void:
	var floor_radius: float = keep_out_rs() * Globals.rs_world()
	var where := player.global_position
	# A handful of tries to find somewhere in the shell that is not inside
	# Goliath's reach; if they all fail the spawn is skipped rather than placed
	# somewhere it would immediately be killed.
	var placed := false
	for _attempt in 8:
		var dir := Vector3(randf() - 0.5, (randf() - 0.5) * 0.45, randf() - 0.5)
		if dir.length() < 0.01:
			continue
		var candidate := player.global_position + dir.normalized() * randf_range(spawn_near, spawn_far)
		if candidate.length() > floor_radius:
			where = candidate
			placed = true
			break
	if not placed:
		return

	var enemy := ENEMY.instantiate() as Enemy
	enemy.position = where
	add_child(enemy)
	enemy.look_at_from_position(where, player.global_position, Vector3.UP)
	_live.append(enemy)


## Live hostiles, for the map, the minimap and the target markers.
func enemies() -> Array[Enemy]:
	_prune()
	return _live


## Drops freed hostiles. Written out rather than using Array.filter() because
## that returns an untyped Array, and round-tripping it back through a typed
## variable is a conversion this has no reason to rely on.
func _prune() -> void:
	var alive: Array[Enemy] = []
	for e in _live:
		if is_instance_valid(e):
			alive.append(e)
	_live = alive


func _find_player() -> Node3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	return _player
