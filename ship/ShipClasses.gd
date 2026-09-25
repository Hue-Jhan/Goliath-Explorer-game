class_name ShipClasses
extends RefCounted
## The three playable hulls, and the single place their stats live.
##
## Selecting a hull writes this table into the corresponding [Globals]
## properties rather than being read through an indirection at every call site.
## That keeps every consumer -- the flight model, the HUD gauges, the chase
## camera's speed kick, the hangar's own stat bars -- working off exactly the
## numbers they already worked off, and leaves the inspector sliders usable for
## fine-tuning on top of a chosen hull.

const EXPLORER := 0
const SCOUT := 1
const HEAVY := 2
const COUNT := 3

## thrust / brake / assist / angular brake / turn / roll / hull / impact
## damage / laser damage / fire rate / boost / charged-beam recharge, plus
## presentation.
##
## "charge" is seconds to recharge the Q beam, and it runs deliberately against
## the rest of the table: the hull with the worst guns and the worst handling
## gets the fastest recharge, so the Anvil has one thing it is unambiguously
## best at and the Wasp pays for its agility somewhere.
const TABLE := [
	{
		"name": "MK-I SKIFF",
		"role": "Balanced Explorer",
		"blurb": "standard issue · deep survey hull",
		"thrust": 2600.0, "brake": 1.40, "authority": 1.60, "angular_brake": 0.45,
		"turn": 1.90, "roll": 2.20, "hull": 100.0, "impact": 0.035,
		"damage": 12.0, "fire_rate": 7.0, "boost": 4.0, "charge": 9.0,
		"muzzle": Vector3(0.52, -0.02, -0.62), "chase": 4.3,
		"tint": Color(0.36, 0.39, 0.44), "accent": Color(0.36, 0.86, 1.0),
	},
	{
		"name": "WASP INTERCEPTOR",
		"role": "Interceptor / Scout",
		"blurb": "needle hull · minimal armour",
		"thrust": 3900.0, "brake": 1.55, "authority": 1.90, "angular_brake": 0.30,
		"turn": 2.70, "roll": 3.10, "hull": 60.0, "impact": 0.060,
		"damage": 9.0, "fire_rate": 10.0, "boost": 5.2, "charge": 14.5,
		"muzzle": Vector3(0.34, 0.0, -0.95), "chase": 4.6,
		"tint": Color(0.30, 0.42, 0.46), "accent": Color(0.45, 1.0, 0.85),
	},
	{
		"name": "ANVIL MINING RIG",
		"role": "Heavy / Mining Rig",
		"blurb": "armoured prow · bore lasers",
		"thrust": 1250.0, "brake": 1.85, "authority": 1.30, "angular_brake": 0.70,
		"turn": 1.15, "roll": 1.30, "hull": 210.0, "impact": 0.018,
		"damage": 34.0, "fire_rate": 2.2, "boost": 2.6, "charge": 5.5,
		"muzzle": Vector3(0.74, -0.04, -0.80), "chase": 6.4,
		"tint": Color(0.42, 0.36, 0.30), "accent": Color(1.0, 0.68, 0.22),
	},
]


static func data(index: int) -> Dictionary:
	return TABLE[clampi(index, 0, COUNT - 1)]


static func build_mesh(index: int) -> ArrayMesh:
	match clampi(index, 0, COUNT - 1):
		SCOUT: return ShipMesh.build_scout()
		HEAVY: return ShipMesh.build_heavy()
		_: return ShipMesh.build()


static func build_shape(index: int) -> Shape3D:
	match clampi(index, 0, COUNT - 1):
		SCOUT: return ShipMesh.build_scout_shape()
		HEAVY: return ShipMesh.build_heavy_shape()
		_: return ShipMesh.build_collision_shape()


## Hull material for a class, so the three read apart at a glance in the
## hangar as well as in flight.
static func material(index: int) -> StandardMaterial3D:
	var entry := data(index)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = entry["tint"]
	mat.metallic = 0.85
	mat.metallic_specular = 0.6
	mat.roughness = 0.33
	mat.rim_enabled = true
	mat.rim = 0.55
	mat.rim_tint = 0.7
	return mat


## Fastest speed the hull will hold: thrust x the brake time constant.
##
## Worth stating because it is not obvious and it bit this table once already:
## flight assist means top speed is the product of engine power *and* how long
## the brakes take. Giving the fast hull punchier brakes to make it feel agile
## cancelled its extra thrust exactly, and all three classes came out within
## 90 u/s of each other. Agility now lives in the turn and angular-brake rates,
## which is where it belongs; the brake time is left to set top speed.
static func top_speed(index: int) -> float:
	var entry := data(index)
	return entry["thrust"] * maxf(entry["brake"] / 3.0, 0.01)
