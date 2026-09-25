class_name Hazard
extends Node3D
## Base class for the deep-space hazards: a point of gravity, somewhere you can
## die, and an entry on the map.
##
## Modelled on [GravityWell] rather than on [Area3D], and for the same reason:
## everything that wants to be pulled asks for an acceleration at a point once
## per physics tick, so nothing has to overlap anything and non-physics movers
## work too. What this adds over the well is that there can be several of them,
## found through the [constant GROUP] group, each with its own danger radius --
## which is why [Ship] sums the group rather than consulting one node.
##
## Gravity here is deliberately weaker than the assist ceiling of every hull, so
## a hazard's pull is a current you have to fly against rather than a capture.
## Goliath is the only thing in the game that wins outright.

const GROUP := &"hazards"

## Outside this, the pull is exactly zero -- same deadzone idea as the hole's,
## so drifting through the system is never a slow accumulation of nudges from
## objects you cannot see.
@export var danger_radius: float = 7000.0
## Peak inward acceleration, reached at the core, in world units/s^2.
@export var pull: float = 2800.0
## Touching anything inside this radius destroys the ship.
@export var kill_radius: float = 0.0
## Shown on the map and the minimap.
@export var hazard_name: String = "HAZARD"
@export var tint: Color = Color(1.0, 0.8, 0.4)


func _ready() -> void:
	add_to_group(GROUP)


## Acceleration at [param world_pos]. Ramps as (1 - d/R)^2 from the boundary,
## so entering the zone is felt as a gathering current rather than a step.
func get_acceleration(world_pos: Vector3) -> Vector3:
	if pull <= 0.0 or danger_radius <= 0.0:
		return Vector3.ZERO
	var offset := global_position - world_pos
	var distance := offset.length()
	if distance <= 0.001 or distance >= danger_radius:
		return Vector3.ZERO
	var t := 1.0 - distance / danger_radius
	return (offset / distance) * pull * t * t


## 0 outside the danger radius, 1 at the core. Drives the HUD warning.
func threat(world_pos: Vector3) -> float:
	if danger_radius <= 0.0:
		return 0.0
	var distance := global_position.distance_to(world_pos)
	return clampf(1.0 - distance / danger_radius, 0.0, 1.0)


## True once the ship has flown into the thing at the middle.
func is_lethal_contact(world_pos: Vector3) -> bool:
	return kill_radius > 0.0 and global_position.distance_to(world_pos) < kill_radius


## Hull damage per second at [param world_pos]. Zero for hazards that only pull.
func damage_rate(_world_pos: Vector3) -> float:
	return 0.0


## Camera trauma per second at [param world_pos].
func trauma_rate(_world_pos: Vector3) -> float:
	return 0.0


## What the ship's log calls this when it kills you.
func death_notice() -> String:
	return "LOST TO " + hazard_name


## Short form for the bearing tape, where there is room for a word and not a
## name. Overridden per hazard; the default is the first word of the full one.
func short_tag() -> String:
	return hazard_name.split(" ")[0]
