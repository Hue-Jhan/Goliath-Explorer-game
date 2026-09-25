class_name DebugCamera
extends Camera3D
## Free-fly camera for looking at Goliath before the real ship exists.
##
## Two flight modes, toggled with G:
##   * [b]Arcade[/b] (default) -- thrust plus heavy damping. Release the keys
##     and you stop. Gravity is ignored entirely. Good for framing shots.
##   * [b]Newtonian[/b] -- no damping, and [GravityWell] acceleration is
##     integrated every tick. This is the mode that lets you feel the deadzone:
##     nothing at all out in the disk, then a rising spiral once you cross the
##     capture radius. It is a preview of the flight model that will live in
##     [code]ship/[/code].
##
## Throwaway in the sense that the ship will not inherit from it -- but the
## gravity integration here is the shape the ship's will take.

@export_range(10.0, 20000.0, 10.0) var thrust: float = 1200.0
@export_range(1.0, 20.0, 0.5) var boost_multiplier: float = 6.0
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.0025
## Velocity damping per second in arcade mode. Newtonian mode uses none.
@export_range(0.0, 20.0, 0.1) var arcade_damping: float = 5.0
## Start in Newtonian mode with gravity live.
@export var gravity_enabled: bool = false

var velocity: Vector3 = Vector3.ZERO

var _pitch: float = 0.0
var _yaw: float = 0.0
var _well: GravityWell = null


func _ready() -> void:
	near = 0.5
	far = 60000.0
	_yaw = rotation.y
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not Globals.settings_changed.is_connected(_on_settings_changed):
		Globals.settings_changed.connect(_on_settings_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)
		return

	if event.is_action_pressed(&"toggle_mouse_capture"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
	elif event.is_action_pressed(&"toggle_gravity"):
		gravity_enabled = not gravity_enabled


func _physics_process(delta: float) -> void:
	var input := Vector3(
		Input.get_action_strength(&"fly_right") - Input.get_action_strength(&"fly_left"),
		Input.get_action_strength(&"fly_up") - Input.get_action_strength(&"fly_down"),
		Input.get_action_strength(&"fly_back") - Input.get_action_strength(&"fly_forward")
	)
	var power := thrust
	if Input.is_action_pressed(&"fly_boost"):
		power *= boost_multiplier
	velocity += (global_transform.basis * input.normalized()) * power * delta

	if gravity_enabled:
		# Newtonian: no damping, so the well is the only thing changing your
		# trajectory once you stop thrusting. Exactly zero out in the disk.
		var w := _find_well()
		if w != null:
			velocity += w.get_acceleration(global_position) * delta
	else:
		# Exponential damping -- frame-rate independent, unlike v *= 0.9.
		velocity *= exp(-arcade_damping * delta)

	global_position += velocity * delta
	_update_fov()


## Widens the FOV on approach. Driven by [method GravityWell.proximity], not by
## the gravity deadzone, so the view starts stretching while you are still
## coasting freely rather than snapping the instant the pull engages.
func _update_fov() -> void:
	var target: float = Globals.base_fov
	var w := _find_well()
	if w != null and Globals.fov_distortion_intensity > 0.0:
		target += 45.0 * Globals.fov_distortion_intensity * w.proximity(global_position)
	fov = clampf(target, 1.0, 179.0)


## Distance to the hole in Schwarzschild radii, for telemetry.
func distance_rs() -> float:
	var w := _find_well()
	if w == null or Globals.rs_world() <= 0.0:
		return INF
	return global_position.distance_to(w.global_position) / Globals.rs_world()


func captured() -> bool:
	var w := _find_well()
	return w != null and w.is_captured(global_position)


func _find_well() -> GravityWell:
	if is_instance_valid(_well):
		return _well
	var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
	_well = wells[0] if not wells.is_empty() else null
	return _well


func _on_settings_changed() -> void:
	_update_fov()
