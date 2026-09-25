class_name ChargeBeam
extends Node3D
## The Q ability: hold to charge, release to fire a heavy area-of-effect shot.
##
## Three states, and the gauge shows all three: recharging (unusable),
## ready (idle), charging (a sphere growing at the nose). Releasing below
## [constant MIN_CHARGE] is treated as a cancel and costs nothing -- a weapon
## with a fifteen second cooldown must not be spendable by brushing a key.
##
## Driven by [Ship] rather than by its own [code]_physics_process[/code], so
## that a dead or falling ship stops charging without this class needing to know
## anything about how the ship dies.

## Below this fraction of a full charge, releasing cancels instead of firing.
const MIN_CHARGE := 0.18
## Radius of the orb at full charge, world units.
const ORB_RADIUS := 1.05

var _charge: float = 0.0
var _cooldown: float = 0.0
var _held: bool = false

var _orb: MeshInstance3D = null
var _material: ShaderMaterial = null
var _lamp: OmniLight3D = null


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://ship/charge_orb.gdshader")

	_orb = MeshInstance3D.new()
	_orb.mesh = CelestialMesh.uv_sphere(ORB_RADIUS, 10, 14)
	_orb.material_override = _material
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orb.visible = false
	add_child(_orb)

	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(0.35, 0.9, 1.0)
	_lamp.light_energy = 0.0
	_lamp.omni_range = 14.0
	_lamp.shadow_enabled = false
	add_child(_lamp)


## One tick of the ability. [param allowed] is false whenever the ship must not
## be able to charge -- dead, past the horizon, cursor released.
func tick(delta: float, allowed: bool) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var wants := allowed and Input.is_action_pressed(&"super_beam")

	if wants and _cooldown <= 0.0:
		_held = true
		_charge = minf(_charge + delta / maxf(Globals.charge_time, 0.05), 1.0)
	elif _held:
		_held = false
		if _charge >= MIN_CHARGE:
			_launch()
		_charge = 0.0

	_show()


## 0..1 of a full charge, for the HUD.
func charge() -> float:
	return _charge


## 0..1 of the recharge, 1 meaning ready to fire.
func readiness() -> float:
	var full: float = maxf(Globals.charge_cooldown, 0.01)
	return clampf(1.0 - _cooldown / full, 0.0, 1.0)


func is_ready() -> bool:
	return _cooldown <= 0.0


func _show() -> void:
	_orb.visible = _charge > 0.001
	if not _orb.visible:
		_lamp.light_energy = 0.0
		return
	# Grows fast at first and then creeps, so the last quarter of the charge
	# feels like it is straining rather than simply taking longer.
	_orb.scale = Vector3.ONE * (0.30 + 1.45 * sqrt(_charge))
	_material.set_shader_parameter("charge", _charge)
	_lamp.light_energy = 5.5 * _charge
	_lamp.omni_range = 10.0 + 22.0 * _charge


func _launch() -> void:
	var shot := ChargeShot.new()
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(shot)
	var muzzle := global_transform
	muzzle.basis = owner_basis()
	var exclude: Array[RID] = []
	var body := get_parent() as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
	shot.launch(muzzle, _charge, exclude)
	_cooldown = Globals.charge_cooldown


## The firing direction is the ship's, not the orb node's: the orb hangs off the
## nose and is free to be nudged around for looks without steering the weapon.
func owner_basis() -> Basis:
	var parent := get_parent() as Node3D
	return parent.global_transform.basis if parent != null else global_transform.basis
