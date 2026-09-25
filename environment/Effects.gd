class_name Effects
extends Node3D
## Pool of detonations, found by anything that needs to blow up.
##
## A group lookup rather than an autoload: explosions are a property of the
## expedition scene, not of the game, and the menu has no business carrying a
## particle pool around.

const GROUP := &"effects"
const EXPLOSION := preload("res://environment/Explosion.tscn")

@export var pool_size: int = 8

var _pool: Array[Explosion] = []


func _ready() -> void:
	add_to_group(GROUP)
	for i in pool_size:
		var boom := EXPLOSION.instantiate() as Explosion
		add_child(boom)
		_pool.append(boom)


## Detonates at [param at]. Silently does nothing if the pool is saturated --
## which is the right failure: the eleventh simultaneous explosion is not
## missed, and dropping it is cheaper than growing the pool mid-fight.
func detonate(at: Vector3, size: float, tint: Color) -> void:
	for boom in _pool:
		if not boom.busy():
			boom.pop(at, size, tint)
			return


## Convenience for callers that only have a node. Safe when no Effects node
## exists, so the debug scenes do not need one.
static func burst(from: Node, at: Vector3, size: float, tint: Color) -> void:
	var found := from.get_tree().get_nodes_in_group(GROUP)
	if not found.is_empty():
		(found[0] as Effects).detonate(at, size, tint)
