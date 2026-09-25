extends SubViewportContainer
## The title screen's living backdrop: the real Goliath, rendered small.
##
## Profiling put the raymarch at 49 ms and the procedural sky at 11 ms of a
## 65 ms frame, and the menu was paying both at full resolution to sit behind a
## scrim and a column of buttons. Rather than fake a black hole in 2D, the same
## scene now renders into a [SubViewport] at a fraction of the linear resolution
## and is upscaled to fill the screen -- cost falls with the square of the
## shrink factor (a shrink of 4 is 1/16 the pixels), and the softness that
## buys is, behind a menu, atmosphere rather than a defect.
##
## The shrink follows the quality slider, so a machine that cannot afford the
## expedition cannot be ambushed by the title screen either.

## Orbit radius in Schwarzschild radii.
@export_range(20.0, 120.0, 0.5) var radius_rs: float = 46.0
## Radians per second. Slow enough to read as drift, not as a turntable.
@export var orbit_speed: float = 0.021
## Polar angle. Near pi/2 is edge-on, which is the silhouette worth showing.
@export var polar: float = 1.42
@export var azimuth: float = 0.6
## Pushes Goliath off-centre so the menu column has clear space to sit in.
## A fraction of the orbit radius, applied as a sideways shift of the look-at
## target, so it is independent of field of view.
@export_range(-1.0, 1.0, 0.01) var aim_offset: float = 0.40

@onready var _camera: Camera3D = $SubViewport/Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Globals.settings_changed.is_connected(_apply_quality):
		Globals.settings_changed.connect(_apply_quality)
	_apply_quality()


## Linear downscale factor. Cost falls with its square, so even 2 is a 4x
## saving; past about 4 the starfield starts to alias into chunky specks and the
## shadow edge goes ragged, which reads as low-resolution rather than as
## atmosphere. 3 is the point where it still looks deliberate.
func _apply_quality() -> void:
	stretch_shrink = 5 if Globals.quality_level <= 3 else (3 if Globals.quality_level <= 7 else 2)


func _process(delta: float) -> void:
	azimuth += orbit_speed * delta
	var r: float = radius_rs * Globals.rs_world()
	_camera.global_position = Vector3(
		sin(polar) * sin(azimuth),
		cos(polar),
		sin(polar) * cos(azimuth)) * r
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	# Aiming to one side of the hole slides the hole to the other side of frame.
	var right := _camera.global_transform.basis.x
	_camera.look_at(-right * (r * aim_offset), Vector3.UP)
