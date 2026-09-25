class_name EscapeCompass
extends Control
## The navigation overlay: flight reticle, velocity vector, and -- once Goliath
## has hold of you -- the escape compass and the shrinking sky aperture.
##
## This exists because the shadow is a genuine gameplay problem. Inside it there
## are no stars, no disk and no parallax, so there is nothing to steer by and
## "which way is out" stops being answerable by looking. The compass answers it
## directly: radially outward is the only direction that increases your radius,
## and the aperture ring shows how much sky is left to fly back through.
##
## Everything is drawn rather than built from nodes, because all of it is
## projected from 3D each frame and none of it participates in layout.

const EDGE_MARGIN := 64.0
## Sentinel for "this point is behind the camera". A typed sentinel keeps
## _project() returning a plain Vector2 instead of a Variant, which GDScript's
## static typing cannot infer through.
const OFFSCREEN := Vector2(INF, INF)

var _ship: Ship = null
var _camera: Camera3D = null
var _well: GravityWell = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _resolve():
		return
	var centre := size * 0.5
	_draw_reticle(centre)
	_draw_prograde()

	var aperture := _well.sky_aperture_angle(_ship.global_position)
	var captured := _well.is_captured(_ship.global_position)
	# Only assert itself when it is actually needed: out in open space the
	# compass would be clutter.
	# The escape chevron carries the sky angle as a number. There used to be
	# dashed aperture and horizon circles as well; they were removed because a
	# ring drawn over a black hole is a ring drawn over the thing the player is
	# already looking at, and the arrow plus the angle says everything the
	# circles did without covering the view at the one moment it matters.
	if captured or aperture < 1.05:
		_draw_escape_vector(aperture)


func _draw_reticle(centre: Vector2) -> void:
	var c := Color(SciFi.CYAN.r, SciFi.CYAN.g, SciFi.CYAN.b, 0.55)
	for s in [-1.0, 1.0]:
		draw_line(centre + Vector2(9.0 * s, 0), centre + Vector2(22.0 * s, 0), c, 1.5, true)
		draw_line(centre + Vector2(0, 9.0 * s), centre + Vector2(0, 18.0 * s), c, 1.5, true)
	draw_arc(centre, 3.0, 0.0, TAU, 12, c, 1.5, true)


## Prograde marker: where the ship is actually going, which under a
## semi-Newtonian model is regularly not where it is pointing.
func _draw_prograde() -> void:
	var v := _ship.velocity
	if v.length() < 4.0:
		return
	var target := _ship.global_position + v.normalized() * 400.0
	var pos := _project(target)
	if not pos.is_finite():
		return
	var c := Color(SciFi.GOOD.r, SciFi.GOOD.g, SciFi.GOOD.b, 0.7)
	draw_arc(pos, 8.0, 0.0, TAU, 20, c, 1.4, true)
	for a in [0.0, PI * 0.5, PI]:
		var d := Vector2(cos(a - PI * 0.5), sin(a - PI * 0.5))
		draw_line(pos + d * 8.0, pos + d * 14.0, c, 1.4, true)


func _draw_escape_vector(aperture: float) -> void:
	var out_dir := _well.escape_vector(_ship.global_position)
	var target := _ship.global_position + out_dir * 6000.0
	var screen := _project(target)
	var accent := SciFi.AMBER

	if screen.is_finite() and _inside(screen):
		SciFi.glow_polyline(self, _chevron(screen, -PI * 0.5, 15.0), accent, 2.0)
		SciFi.label(self, screen + Vector2(20.0, 4.0),
			"ESCAPE · SKY %d°" % int(round(rad_to_deg(aperture))), accent, SciFi.FONT_SMALL)
		return

	# Off screen (or behind): pin an arrow to the rim, pointing the way to turn.
	var dir_2d := _offscreen_direction(target)
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - EDGE_MARGIN
	var pin := centre + dir_2d * radius
	SciFi.glow_polyline(self, _chevron(pin, dir_2d.angle(), 19.0), accent, 2.2)
	# The angle goes on the arrow too. When the way out is behind you the ring
	# below cannot be drawn at all -- which is precisely the moment the number
	# matters most.
	var txt := "ESCAPE VECTOR · SKY %d°" % int(round(rad_to_deg(aperture)))
	var w := SciFi.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
	SciFi.label(self, pin - dir_2d * 30.0 - Vector2(w * 0.5, -22.0), txt, accent, SciFi.FONT_SMALL)


# --- helpers ------------------------------------------------------------------

## Arrow-head polygon centred on [param at], pointing along [param angle].
## Public because the minimap pins Goliath to its rim with the same shape.
static func _chevron(at: Vector2, angle: float, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array([
		Vector2(s, 0.0), Vector2(-s * 0.55, s * 0.62),
		Vector2(-s * 0.2, 0.0), Vector2(-s * 0.55, -s * 0.62),
	])
	var out := PackedVector2Array()
	for p in pts:
		out.append(at + p.rotated(angle))
	return out


func _project(world: Vector3) -> Vector2:
	if _camera.is_position_behind(world):
		return OFFSCREEN
	return _camera.unproject_position(world)


func _inside(p: Vector2) -> bool:
	return p.x > EDGE_MARGIN and p.y > EDGE_MARGIN \
		and p.x < size.x - EDGE_MARGIN and p.y < size.y - EDGE_MARGIN


## Screen-space direction to a world point that is off screen or behind the
## camera. unproject_position() is meaningless in those cases, so the direction
## is taken in the camera's own frame instead.
func _offscreen_direction(world: Vector3) -> Vector2:
	var local := _camera.global_transform.affine_inverse() * world
	var v := Vector2(local.x, -local.y)
	if v.length() < 0.0001:
		v = Vector2(0.0, -1.0)
	v = v.normalized()
	# Behind the camera, the target is literally the other way round.
	if local.z > 0.0:
		v = -v
	return v


func _resolve() -> bool:
	if not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group(&"player") as Ship
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	if not is_instance_valid(_well):
		var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
		_well = wells[0] if not wells.is_empty() else null
	return is_instance_valid(_ship) and is_instance_valid(_camera) and is_instance_valid(_well)
