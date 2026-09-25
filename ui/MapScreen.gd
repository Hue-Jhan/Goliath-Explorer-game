extends Control
## Fullscreen tactical map: a top-down plan view of the Goliath system.
##
## Everything is projected onto the disk plane (world XZ), because that is the
## plane the interesting radii live in and a perspective view of a black hole
## tells you nothing about how close you are to dying in it. Altitude above the
## plane is reported as a number rather than drawn, which is the honest way to
## show it on a 2D plan.
##
## The rings are the danger thresholds, and they are read live from [Globals]
## and [GravityWell] rather than hardcoded, so moving a slider moves the map.

signal closed

var _ship: Node3D = null
var _well: GravityWell = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func toggle() -> void:
	if visible:
		close()
	else:
		show()


func close() -> void:
	hide()
	closed.emit()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.004, 0.008, 0.014, 0.985))
	if not _resolve():
		return

	var rs: float = Globals.rs_world()
	var centre := size * 0.5
	var enemies := _enemies()
	var hazards := _hazards()

	# Fit the disk, the player, every hostile and every landmark into the view
	# with a margin. This is a system map now rather than a map of the hole: the
	# hazards are the reason to open it, so they have to be on it.
	var reach: float = Globals.disk_outer_rs * 1.25
	reach = maxf(reach, _plane_radius(_ship.global_position) / rs * 1.18)
	for e in enemies:
		reach = maxf(reach, _plane_radius(e.global_position) / rs * 1.18)
	for h in hazards:
		reach = maxf(reach, (_plane_radius(h.global_position) + h.danger_radius) / rs * 1.10)
	var px_per_rs := (minf(size.x, size.y) * 0.5 - 70.0) / maxf(reach, 1.0)

	_draw_disk(centre, px_per_rs)
	_draw_rings(centre, px_per_rs)
	for h in hazards:
		_draw_hazard(centre, px_per_rs, h)
	_draw_boss(centre, px_per_rs)

	for e in enemies:
		var at := centre + _to_map(e.global_position, px_per_rs)
		draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), SciFi.DANGER)
		draw_rect(Rect2(at - Vector2(7, 7), Vector2(14, 14)), Color(SciFi.DANGER.r, SciFi.DANGER.g, SciFi.DANGER.b, 0.3), false, 1.0)

	_draw_player(centre, px_per_rs)
	_draw_legend(enemies.size(), hazards.size())


func _draw_disk(centre: Vector2, px_per_rs: float) -> void:
	var inner: float = Globals.disk_inner_rs * px_per_rs
	var outer: float = Globals.disk_outer_rs * px_per_rs
	# Filled as a band of concentric strokes: draw_colored_polygon cannot do an
	# annulus, and a ring of thick arcs costs nothing at this size.
	var steps := 26
	for i in steps:
		var t := float(i) / float(steps - 1)
		var r := lerpf(inner, outer, t)
		var warmth := Color(0.95, 0.38, 0.10).lerp(Color(0.35, 0.07, 0.02), t)
		warmth.a = 0.16
		draw_arc(centre, r, 0.0, TAU, 72, warmth, (outer - inner) / float(steps) + 1.5, false)


func _draw_rings(centre: Vector2, px_per_rs: float) -> void:
	var authority: float = Globals.ship_thrust * Globals.ship_assist_authority
	var rings := [
		[1.0, SciFi.DANGER, "EVENT HORIZON"],
		[_well.point_of_no_return_rs(authority), Color(1.0, 0.45, 0.25), "POINT OF NO RETURN"],
		[Globals.disk_inner_rs, Color(1.0, 0.75, 0.35), "ISCO / DISK INNER"],
		[Globals.bh_capture_radius, SciFi.AMBER, "GRAVITY DEADZONE"],
		[Globals.disk_outer_rs, Color(0.85, 0.35, 0.12), "DISK OUTER"],
	]
	# Labels are spread around the rings rather than stacked at the top: the
	# inner three radii are close together, and a column of overlapping text at
	# twelve o'clock was illegible exactly where the numbers matter most.
	var label_angle := -PI * 0.5
	for ring in rings:
		var r_rs: float = ring[0]
		var col: Color = ring[1]
		var r := r_rs * px_per_rs
		label_angle += 0.62
		if r < 3.0 or r > maxf(size.x, size.y):
			continue
		draw_arc(centre, r, 0.0, TAU, 96, Color(col.r, col.g, col.b, 0.75), 1.4, true)
		var dir := Vector2(cos(label_angle), sin(label_angle))
		# Angular spread alone cannot separate the innermost rings -- the
		# horizon and the point of no return sit a couple of rs apart, which is
		# a few pixels. Labels for tight radii are pushed out to a common
		# distance and joined back with a leader.
		var anchor := centre + dir * r
		var text_at := centre + dir * maxf(r, 78.0)
		var text := "%s · %.2f rs" % [ring[2], r_rs]
		var text_w := SciFi.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
		var offset := Vector2(9.0, -5.0) if dir.x >= 0.0 else Vector2(-text_w - 9.0, -5.0)
		draw_line(anchor, text_at + dir * 6.0, Color(col.r, col.g, col.b, 0.45), 1.0, true)
		SciFi.label(self, text_at + dir * 8.0 + offset, text, col, SciFi.FONT_SMALL)

	# The horizon itself, filled, so the centre reads as a hole and not a target.
	draw_circle(centre, maxf(1.0 * px_per_rs, 3.0), Color(0.0, 0.0, 0.0, 1.0))


## A hazard: its gravitational boundary as a dashed ring, the body itself as a
## filled dot, and the name alongside.
##
## Dashed rather than solid so it never reads as one of Goliath's rings -- those
## are concentric on the map's centre and these are not, and the eye should not
## have to work that out.
func _draw_hazard(centre: Vector2, px_per_rs: float, hazard: Hazard) -> void:
	var rs: float = Globals.rs_world()
	var at := centre + _to_map(hazard.global_position, px_per_rs)
	var radius := hazard.danger_radius / rs * px_per_rs
	var col := hazard.tint

	if radius > 3.0:
		var dashes := 44
		for i in dashes:
			if i % 2 == 1:
				continue
			var a0 := TAU * float(i) / float(dashes)
			var a1 := TAU * float(i + 1) / float(dashes)
			draw_arc(at, radius, a0, a1, 4, Color(col.r, col.g, col.b, 0.72), 1.4, true)

	draw_circle(at, 5.0, col)
	draw_arc(at, 9.0, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.45), 1.2, true)
	SciFi.label(self, at + Vector2(13.0, 4.0), hazard.hazard_name, col, SciFi.FONT_LABEL)
	SciFi.label(self, at + Vector2(13.0, 19.0),
		"danger %.1f rs" % (hazard.danger_radius / rs), SciFi.TEXT_DIM, SciFi.FONT_SMALL)


## The mothership, as a shard-shaped mark rather than a dot: it is the one thing
## out there whose facing matters before you arrive.
func _draw_boss(centre: Vector2, px_per_rs: float) -> void:
	var found := get_tree().get_nodes_in_group(Mothership.GROUP)
	if found.is_empty():
		return
	var boss := found[0] as Mothership
	if boss == null:
		return
	var at := centre + _to_map(boss.global_position, px_per_rs)
	var heading := boss.global_transform.basis.z
	var ang := atan2(heading.z, heading.x)
	var shard := PackedVector2Array([
		at + Vector2(15, 0).rotated(ang),
		at + Vector2(0, 5).rotated(ang),
		at + Vector2(-15, 0).rotated(ang),
		at + Vector2(0, -5).rotated(ang)])
	draw_colored_polygon(shard, Mothership.BIOLUME)
	SciFi.glow_polyline(self, shard, Mothership.BIOLUME, 1.4)
	SciFi.label(self, at + Vector2(18.0, -6.0), "DREADNOUGHT", Mothership.BIOLUME, SciFi.FONT_LABEL)


func _draw_player(centre: Vector2, px_per_rs: float) -> void:
	var at := centre + _to_map(_ship.global_position, px_per_rs)
	var heading := -_ship.global_transform.basis.z
	var ang := atan2(heading.z, heading.x)
	var tri := PackedVector2Array([
		at + Vector2(12, 0).rotated(ang),
		at + Vector2(-8, 7).rotated(ang),
		at + Vector2(-8, -7).rotated(ang)])
	draw_colored_polygon(tri, SciFi.CYAN)
	SciFi.glow_polyline(self, tri, SciFi.CYAN, 1.2)

	var altitude := _ship.global_position.y - _well.global_position.y
	SciFi.label(self, at + Vector2(16, 4),
		"YOU · %.2f rs · %+.2f rs above plane" % [
			_ship.global_position.distance_to(_well.global_position) / Globals.rs_world(),
			altitude / Globals.rs_world()],
		SciFi.CYAN, SciFi.FONT_LABEL)


func _draw_legend(enemy_count: int, hazard_count: int) -> void:
	var panel := Rect2(Vector2(28, 24), Vector2(330, 118))
	SciFi.panel(self, panel, SciFi.CYAN, 14.0, 5, SciFi.PANEL_FILL_DEEP)
	SciFi.label(self, panel.position + Vector2(18, 28), "GOLIATH SYSTEM · PLAN VIEW", SciFi.TEXT, SciFi.FONT_BODY)
	SciFi.label(self, panel.position + Vector2(18, 52), "hostiles tracked: %d" % enemy_count, SciFi.DANGER, SciFi.FONT_LABEL)
	SciFi.label(self, panel.position + Vector2(18, 74), "gravitational hazards: %d" % hazard_count, SciFi.AMBER, SciFi.FONT_LABEL)
	SciFi.label(self, panel.position + Vector2(18, 96), "M or ESC to close", SciFi.TEXT_DIM, SciFi.FONT_LABEL)


## World position -> map offset in pixels, projected onto the disk plane.
func _to_map(world: Vector3, px_per_rs: float) -> Vector2:
	var d := world - _well.global_position
	return Vector2(d.x, d.z) / Globals.rs_world() * px_per_rs


func _plane_radius(world: Vector3) -> float:
	var d := world - _well.global_position
	return Vector2(d.x, d.z).length()


func _enemies() -> Array:
	return get_tree().get_nodes_in_group(Enemy.GROUP)


func _hazards() -> Array[Hazard]:
	var out: Array[Hazard] = []
	for node in get_tree().get_nodes_in_group(Hazard.GROUP):
		var hazard := node as Hazard
		if hazard != null:
			out.append(hazard)
	return out


func _resolve() -> bool:
	if not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group(&"player") as Node3D
	if not is_instance_valid(_well):
		var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
		_well = wells[0] if not wells.is_empty() else null
	return is_instance_valid(_ship) and is_instance_valid(_well)
