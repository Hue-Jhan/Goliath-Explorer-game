class_name Minimap
extends Control
## Circular radar, player-centred and heading-up.
##
## Heading-up rather than north-up because there is no north in a space sim: the
## only frame a pilot can act on immediately is their own. Goliath is drawn to
## true scale within the sweep so its bulk reads correctly, and pinned to the rim
## with an arrow once it falls outside the range.

## Radar range at the rim, in Schwarzschild radii.
@export var range_rs: float = 26.0

var _ship: Node3D = null
var _well: GravityWell = null
var _field: AsteroidField = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(196, 196)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	var amber := SciFi.AMBER

	# Only the bezel is decoration. The generic range rings and the bow line that
	# used to sit under it were static furniture: they moved for nothing and
	# competed with the marks that actually mean something. Every remaining
	# stroke is a real object in the world.
	draw_circle(centre, radius, Color(0.01, 0.03, 0.045, 0.72))
	SciFi.glow_polyline(self, _circle_points(centre, radius, 56), amber, 1.4)

	if not _resolve():
		return

	var scale_px := radius / maxf(range_rs * Globals.rs_world(), 1.0)
	var heading := -_ship.global_transform.basis.z
	var yaw := atan2(heading.x, heading.z)

	# Goliath, to scale, clipped to the sweep.
	var hole := _to_radar(_well.global_position, yaw, scale_px)
	var hole_r: float = Globals.rs_world() * scale_px
	if hole.length() < radius + hole_r:
		var at := centre + hole
		if hole.length() < radius:
			draw_circle(at, minf(maxf(hole_r, 2.5), radius - hole.length()), Color(0.02, 0.02, 0.03, 1.0))
		# The horizon, the disk and the deadzone, all clipped to the bezel.
		# These are drawn at true scale and the deadzone is now 13 rs, so at any
		# useful radar range at least one of them is wider than the instrument.
		# They used to be plain draw_arc calls and simply ran off it, painting
		# rings across the telemetry panel behind.
		_draw_clipped_circle(centre, radius, at, maxf(hole_r, 2.5), Color(1.0, 0.55, 0.2, 0.9), 1.5)
		_draw_clipped_circle(centre, radius, at,
			Globals.disk_outer_rs * Globals.rs_world() * scale_px,
			Color(0.95, 0.4, 0.12, 0.35), 1.2)
		_draw_clipped_circle(centre, radius, at,
			Globals.bh_capture_radius * Globals.rs_world() * scale_px,
			Color(1.0, 0.25, 0.18, 0.45), 1.0)
	else:
		var dir := hole.normalized()
		SciFi.glow_polyline(self, EscapeCompass._chevron(centre + dir * (radius - 9.0), dir.angle(), 8.0),
			Color(1.0, 0.55, 0.2, 0.9), 1.6)

	# Asteroids: dim, small, and clipped to the sweep rather than pinned to the
	# rim -- unlike hostiles, one off the edge of the radar is not worth knowing
	# about.
	var rock_col := Color(0.62, 0.60, 0.58, 0.55)
	for rock in _rocks():
		var rp := _to_radar(rock.global_position, yaw, scale_px)
		if rp.length() > radius - 3.0:
			continue
		draw_rect(Rect2(centre + rp - Vector2(1.5, 1.5), Vector2(3, 3)), rock_col)

	_draw_landmarks(centre, radius, yaw, scale_px)

	for enemy in _enemies():
		var p := _to_radar(enemy.global_position, yaw, scale_px)
		var clipped := p.limit_length(radius - 5.0)
		var at := centre + clipped
		var col := SciFi.DANGER if clipped == p else Color(SciFi.DANGER.r, SciFi.DANGER.g, SciFi.DANGER.b, 0.5)
		draw_rect(Rect2(at - Vector2(2.5, 2.5), Vector2(5, 5)), col)

	# The ship itself, always dead centre, always pointing up.
	var ship_marker := PackedVector2Array([
		centre + Vector2(0, -7), centre + Vector2(5, 6), centre, centre + Vector2(-5, 6)])
	draw_colored_polygon(ship_marker, SciFi.CYAN)

	SciFi.label(self, Vector2(6, size.y - 6), "%.0f rs" % range_rs, SciFi.TEXT_DIM, SciFi.FONT_SMALL)


## A circle drawn only where it falls inside the radar bezel.
##
## Canvas drawing has no circular clip and [method CanvasItem.draw_arc] cannot
## be masked, so the circle is walked as points and emitted as runs of polyline
## that stay inside. Splitting into runs rather than clamping matters: clamping
## an outside point to the rim would draw a false arc along the bezel, which
## reads as another ring rather than as the absence of one.
func _draw_clipped_circle(centre: Vector2, clip_radius: float, at: Vector2,
		r: float, col: Color, width: float) -> void:
	if r < 1.0:
		return
	# Enough segments that the polyline is smooth at any radius, capped so a
	# ring far wider than the instrument does not cost hundreds of points.
	var segments := clampi(int(r * 0.7), 24, 160)
	var run := PackedVector2Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var p := at + Vector2(cos(a), sin(a)) * r
		if p.distance_to(centre) <= clip_radius - 1.0:
			run.append(p)
		elif run.size() > 1:
			draw_polyline(run, col, width, true)
			run = PackedVector2Array()
		else:
			run = PackedVector2Array()
	if run.size() > 1:
		draw_polyline(run, col, width, true)


## Hazards and the dreadnought. Unlike asteroids these are pinned to the rim
## when they fall outside the sweep, the same way Goliath is: knowing that the
## pulsar is off to port is useful even at four times the radar range, and
## knowing where a rock you cannot see is, is not.
func _draw_landmarks(centre: Vector2, radius: float, yaw: float, scale_px: float) -> void:
	for node in get_tree().get_nodes_in_group(Hazard.GROUP):
		var hazard := node as Hazard
		if hazard == null:
			continue
		_pin(centre, radius, _to_radar(hazard.global_position, yaw, scale_px), hazard.tint,
			hazard.danger_radius * scale_px)

	var found := get_tree().get_nodes_in_group(Mothership.GROUP)
	if not found.is_empty():
		var boss := found[0] as Node3D
		if boss != null:
			_pin(centre, radius, _to_radar(boss.global_position, yaw, scale_px),
				Mothership.BIOLUME, 0.0)


## Draws a mark inside the sweep, or a chevron on the rim pointing at it.
func _pin(centre: Vector2, radius: float, offset: Vector2, col: Color, danger_px: float) -> void:
	if offset.length() < radius - 4.0:
		var at := centre + offset
		if danger_px > 4.0:
			draw_arc(at, minf(danger_px, radius * 2.0), 0.0, TAU, 40,
				Color(col.r, col.g, col.b, 0.28), 1.0, true)
		draw_circle(at, 3.5, col)
		return
	var dir := offset.normalized()
	SciFi.glow_polyline(self, EscapeCompass._chevron(centre + dir * (radius - 9.0), dir.angle(), 7.0),
		Color(col.r, col.g, col.b, 0.85), 1.4)


## World position -> radar offset in pixels, rotated so the ship's heading is up.
func _to_radar(world: Vector3, yaw: float, scale_px: float) -> Vector2:
	var d := world - _ship.global_position
	var flat := Vector2(d.x, d.z) * scale_px
	return flat.rotated(yaw) * Vector2(-1.0, -1.0)


static func _circle_points(centre: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(centre + Vector2(cos(a), sin(a)) * radius)
	return pts


func _rocks() -> Array:
	if is_instance_valid(_field):
		return _field.rocks()
	return []


func _enemies() -> Array:
	return get_tree().get_nodes_in_group(Enemy.GROUP)


func _resolve() -> bool:
	if not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group(&"player") as Node3D
	if not is_instance_valid(_well):
		var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
		_well = wells[0] if not wells.is_empty() else null
	if not is_instance_valid(_field):
		var fields := get_tree().get_nodes_in_group(&"asteroid_field")
		_field = fields[0] as AsteroidField if not fields.is_empty() else null
	return is_instance_valid(_ship) and is_instance_valid(_well)
