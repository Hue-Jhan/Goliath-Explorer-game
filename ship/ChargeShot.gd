class_name ChargeShot
extends Node3D
## The projectile the Q ability launches, and its area detonation.
##
## Built entirely in code and freed when it lands -- there is at most one in
## flight per ship, on a cooldown measured in seconds, so a pool would be
## ceremony around a single object.
##
## [b]Why it is not hitscan.[/b] The lasers are, because a duelling weapon has to
## land where the crosshair is at the instant you pull. This is a siege weapon:
## its whole identity is that you commit to a heading, watch it cross the gap,
## and see what it takes with it. Travel time is the weapon.

const SPEED := 2400.0
const RANGE := 16000.0

var power: float = 1.0

var _travelled: float = 0.0
var _exclude: Array[RID] = []
var _mesh: MeshInstance3D = null
var _lamp: OmniLight3D = null
var _spin: float = 0.0


## Sends the shot out from [param from]. [param charge_power] is 0..1 and
## scales damage, blast radius and the size of the thing on screen together, so
## a half-charged shot looks like a half-charged shot.
func launch(from: Transform3D, charge_power: float, exclude: Array[RID]) -> void:
	power = clampf(charge_power, 0.05, 1.0)
	global_transform = from
	_exclude = exclude
	_build()


func _build() -> void:
	var size := lerpf(7.0, 20.0, power)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = CelestialMesh.uv_sphere(size, 10, 16)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ship/charge_orb.gdshader")
	mat.set_shader_parameter("charge", power)
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	# A stretched shell behind the core: the shot needs a direction at a glance,
	# and a sphere has none.
	var wake := MeshInstance3D.new()
	wake.mesh = CelestialMesh.uv_sphere(size * 0.8, 8, 12)
	wake.material_override = CelestialMesh.glow_material(Color(0.35, 0.95, 1.0), 2.4, 0.30)
	wake.scale = Vector3(1.0, 1.0, 4.5)
	wake.position = Vector3(0.0, 0.0, size * 2.2)
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wake)

	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(0.4, 0.95, 0.9)
	_lamp.light_energy = 6.0 * power
	_lamp.omni_range = size * 22.0
	_lamp.shadow_enabled = false
	add_child(_lamp)


func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	var from := global_position
	var to := from + -global_transform.basis.z * step
	_travelled += step
	_spin += delta * 6.0
	_mesh.rotation = Vector3(_spin * 0.6, _spin, 0.0)

	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Asteroids on layer 1, hostiles and the mothership on layer 3.
	query.collision_mask = 1 | 4
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_detonate(hit["position"])
		return

	global_position = to
	if _travelled >= RANGE:
		# Burns out rather than vanishing, so a miss still reads as a shot that
		# went somewhere.
		_detonate(global_position)


func _detonate(at: Vector3) -> void:
	var radius: float = Globals.charge_blast_radius * lerpf(0.55, 1.0, power)
	var centre_damage: float = Globals.charge_damage * power

	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), at)
	params.collision_mask = 1 | 4
	params.collide_with_areas = false
	params.exclude = _exclude
	# 64 is well above what the densest asteroid cluster in the field holds; the
	# cap exists so a detonation inside the disk cannot stall a frame.
	var found := get_world_3d().direct_space_state.intersect_shape(params, 64)

	for entry: Dictionary in found:
		var body := entry.get("collider") as Node3D
		if body == null or not body.has_method(&"take_damage"):
			continue
		# Linear falloff from the centre. Nothing at the rim takes full damage,
		# which is what stops the blast radius from being a hard line the player
		# has to guess at.
		var reach := clampf(1.0 - at.distance_to(body.global_position) / radius, 0.0, 1.0)
		if reach > 0.0:
			body.take_damage(centre_damage * reach)

	Effects.burst(self, at, radius * 0.55, Color(0.45, 1.0, 0.80))
	Effects.burst(self, at, radius * 0.30, Color(0.85, 1.0, 1.0))

	var player := get_tree().get_first_node_in_group(&"player") as Ship
	if player != null:
		var distance := at.distance_to(player.global_position)
		player.feel_blast(clampf(1.0 - distance / (radius * 6.0), 0.0, 1.0) * power)
	queue_free()
