class_name Mothership
extends StaticBody3D
## The 'Oumuamua-class dreadnought: a derelict-looking shard that is very much
## not derelict.
##
## A [StaticBody3D] moved by hand rather than a [CharacterBody3D]. It drifts at
## walking pace and never needs to resolve a collision against anything -- the
## player bounces off it, not the other way round -- and a static body is what
## the player's hitscan rounds want to find on the far end of a raycast.
##
## [b]Layers.[/b] It sits on layer 3 (mask bit 4) with the interceptors, so
## [LaserCannon]'s existing 1|4 query picks it up with no special case. Its
## turrets are deliberately not separate bodies: rounds that land on a turret are
## absorbed by the hull capsule that encloses it, which is both what a player
## expects and one fewer collision shape per turret.

const GROUP := &"boss"
## The green the whole design hangs off: hull lights, turret muzzles, bolts.
const BIOLUME := Color(0.30, 1.0, 0.42)
## Awarded for killing it.
const POINTS := 2500
## Seconds the death sequence walks secondaries down the spine for.
const DEATH_LENGTH := 2.6

## Hull length and maximum half-girth, world units.
##
## 1750 units is a little over seventeen kilometres at this project's scale, and
## roughly a thousand times the length of the ship flying at it. It is meant to
## be the largest thing in the game that is not a star; at the old 640 it read
## as a big asteroid rather than as a vessel.
@export var length: float = 1750.0
@export var girth: float = 130.0
@export var max_health: float = 2000.0
## The player gets a boss bar inside this range. Scaled with the hull -- at this
## size it is recognisable from much further out than the old one was.
@export var engage_range: float = 17000.0
@export var escort_count: int = 3
@export var bolt_pool_size: int = 30

var health: float = 0.0

var _drift := Vector3.ZERO
var _dying := false
var _death_clock: float = 0.0
var _next_blast: float = 0.0
var _bolts: Array[LaserBolt] = []
var _next_bolt: int = 0
var _lights: Array[MeshInstance3D] = []
var _lamps: Array[OmniLight3D] = []
var _pulse: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health
	collision_layer = 4
	collision_mask = 0
	_build_hull()
	_build_biolume()
	_build_turrets()
	_build_bolt_pool()
	_spawn_escorts.call_deferred()
	# Barely moving: the shard should read as tumbling through the system on its
	# own trajectory rather than as patrolling.
	#
	# Tangential to Goliath rather than an arbitrary vector, so however long a
	# session runs the shard never wanders into the disk -- it circles the
	# system at the radius it was placed at.
	var radial := Vector3(global_position.x, 0.0, global_position.z)
	_drift = Vector3(-6.0, 0.8, 4.0)
	if radial.length() > 1.0:
		_drift = Vector3.UP.cross(radial.normalized()) * 6.5 + Vector3(0.0, 0.35, 0.0)


func _process(delta: float) -> void:
	_pulse += delta
	# The bioluminescence breathes rather than blinks: two beats at slightly
	# different rates, so no two lights are ever quite in phase.
	for i in _lights.size():
		var beat := 0.55 + 0.45 * sin(_pulse * 1.3 + float(i) * 0.9)
		var mat := _lights[i].material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 1.4 + beat * 4.2
	for i in _lamps.size():
		_lamps[i].light_energy = 1.2 + 2.6 * (0.5 + 0.5 * sin(_pulse * 1.1 + float(i) * 1.4))

	if _dying:
		_chain_explode(delta)
		return
	global_position += _drift * delta
	rotate_object_local(Vector3(0.12, 1.0, 0.06).normalized(), 0.045 * delta)


# --- combat -------------------------------------------------------------------

func take_damage(amount: float) -> void:
	if _dying or amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		health = 0.0
		_begin_death()


func health_ratio() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


## True once the player is close enough for the boss bar to be worth the screen
## space it takes.
func engaged_by(world_pos: Vector3) -> bool:
	return not _dying and global_position.distance_to(world_pos) < engage_range


## Lends a pooled tracer to a [Turret]. Silently drops the shot if every bolt is
## already in flight, which is the right failure: a sixth simultaneous round is
## not missed, and growing the pool mid-fight is worse than not firing.
func fire_hostile_bolt(from: Transform3D, distance: float, damage: float) -> void:
	for i in _bolts.size():
		var bolt := _bolts[(_next_bolt + i) % _bolts.size()]
		if not bolt.visible:
			_next_bolt = (_next_bolt + i + 1) % _bolts.size()
			bolt.fire_hostile(from, distance, BIOLUME, damage, 14.0)
			return


## Goes up in stages rather than in one flash.
##
## Something 640 units long detonating as a single sphere looks like a bug: the
## eye has the hull's length for scale and a point explosion contradicts it. So
## secondaries walk down the spine for a couple of seconds, each at a real point
## on the hull, and only then does the whole thing go.
func _begin_death() -> void:
	_dying = true
	_death_clock = 0.0
	_next_blast = 0.0
	Globals.add_score(POINTS, "MOTHERSHIP DESTROYED", true)
	for child in get_children():
		var turret := child as Turret
		if turret != null:
			turret.set_physics_process(false)



func _chain_explode(delta: float) -> void:
	_death_clock += delta
	_next_blast -= delta
	if _next_blast <= 0.0:
		_next_blast = randf_range(0.11, 0.24)
		var along := randf_range(-0.5, 0.5) * length
		var at := global_position + global_basis.z * along \
			+ global_basis.x * randf_range(-girth, girth) \
			+ global_basis.y * randf_range(-girth, girth)
		Effects.burst(self, at, randf_range(34.0, 70.0), BIOLUME.lerp(Color(1.0, 0.72, 0.25), randf()))
	# Sinking and tumbling harder as it comes apart.
	var severity := clampf(_death_clock / DEATH_LENGTH, 0.0, 1.0)
	rotate_object_local(Vector3(0.4, 0.7, 0.5).normalized(), (0.2 + severity * 1.6) * delta)
	global_position += _drift * delta

	if _death_clock >= DEATH_LENGTH:
		Effects.burst(self, global_position, length * 0.55, Color(0.75, 1.0, 0.70))
		Effects.burst(self, global_position + global_basis.z * length * 0.3, length * 0.35, Color(1.0, 0.85, 0.45))
		Effects.burst(self, global_position - global_basis.z * length * 0.3, length * 0.35, Color(1.0, 0.85, 0.45))
		for bolt in _bolts:
			if is_instance_valid(bolt):
				bolt.queue_free()
		queue_free()


# --- construction -------------------------------------------------------------

func _build_hull() -> void:
	var hull := MeshInstance3D.new()
	hull.mesh = CelestialMesh.shard(length, girth, 20240)
	hull.material_override = CelestialMesh.rock_material(Color(0.115, 0.105, 0.10), 0.95)
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hull)

	var shape := CollisionShape3D.new()
	shape.shape = CelestialMesh.shard_shape(length, girth)
	# CapsuleShape3D stands along +Y; the shard runs along +Z.
	shape.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	add_child(shape)


## Veins of light down the spine. These are what make it read as alive rather
## than as a very large rock, so there are a lot of them and they are bright.
func _build_biolume() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var vein := CelestialMesh.uv_sphere(1.0, 6, 9)
	for i in 40:
		var t := float(i) / 39.0
		var z := lerpf(-length * 0.46, length * 0.46, t)
		var profile := pow(sin(t * PI), 0.62)
		var angle := rng.randf() * TAU
		var node := MeshInstance3D.new()
		node.mesh = vein
		node.material_override = CelestialMesh.glow_material(BIOLUME, 3.0, 0.75)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(
			cos(angle) * girth * profile * 0.95,
			sin(angle) * girth * profile * 0.70,
			z)
		# Stretched along the hull rather than spherical. At the old size a round
		# glow read as a light; at this one it reads as a polka dot, and the
		# thing wants seams.
		var bead := rng.randf_range(2.2, 5.0) * (girth / 46.0)
		node.scale = Vector3(bead, bead, bead * rng.randf_range(2.5, 5.5))
		add_child(node)
		_lights.append(node)

	for z: float in [-length * 0.3, 0.0, length * 0.3]:
		var lamp := OmniLight3D.new()
		lamp.light_color = BIOLUME
		lamp.light_energy = 2.0
		lamp.omni_range = girth * 9.0
		lamp.shadow_enabled = false
		lamp.position = Vector3(0.0, 0.0, z)
		add_child(lamp)
		_lamps.append(lamp)


func _build_turrets() -> void:
	# Alternating dorsal and ventral so the ship has an answer whichever side it
	# is approached from, and so no single strafing run stays out of every arc.
	var stations := [-0.34, -0.12, 0.08, 0.28, 0.44]
	for i in stations.size():
		var t: float = stations[i]
		var normal := Vector3.UP if i % 2 == 0 else Vector3.DOWN
		var profile := pow(sin((t + 0.5) * PI), 0.62)
		var turret := Turret.new()
		turret.position = Vector3(0.0, normal.y * girth * profile * 0.72, t * length)
		add_child(turret)
		turret.setup(normal, girth * 0.22)


func _build_bolt_pool() -> void:
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	var scene: PackedScene = load("res://ship/LaserBolt.tscn")
	for i in bolt_pool_size:
		var bolt := scene.instantiate() as LaserBolt
		host.add_child.call_deferred(bolt)
		_bolts.append(bolt)


## Patrol interceptors, parented to the scene rather than to the hull: an escort
## that inherited the mothership's transform would be welded to it, and the
## point of an escort is that it leaves to come after you.
func _spawn_escorts() -> void:
	var host := get_parent()
	if host == null:
		return
	var scene: PackedScene = load("res://enemy/Enemy.tscn")
	for i in escort_count:
		var enemy := scene.instantiate() as Enemy
		var angle := TAU * float(i) / float(maxi(escort_count, 1))
		enemy.position = global_position + Vector3(cos(angle), 0.35, sin(angle)) * girth * 9.0
		enemy.patrol_centre = global_position
		enemy.patrol_anchor = self
		enemy.patrol_radius = girth * 16.0
		# Escorts sit closer to the hull and are a shade tougher than the drifters
		# the spawner puts around Goliath.
		enemy.max_health = 55.0
		enemy.hull_size = 5.2
		host.add_child(enemy)
