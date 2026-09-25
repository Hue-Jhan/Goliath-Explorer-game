class_name ContactBar
extends Control
## Horizontal bearing tape across the top: where everything is, relative to
## where the nose is pointing.
##
## A tape rather than a list, because the question a pilot actually has is
## "which way do I turn", and a column of coordinates does not answer it. Each
## contact is placed by its bearing in the ship's own frame, so a mark left of
## centre means turn left and how far left says how much.
##
## [b]Bearing only, deliberately.[/b] The tape is one dimension; elevation is
## dropped rather than squeezed in, because a two-axis reticle at this size is
## unreadable and the range under each mark already carries the part that
## matters. Contacts behind the ship pin to whichever end is the shorter way
## round to them, with a chevron -- an off-scale mark that does not say which
## way to turn is worse than no mark at all.
##
## [b]Tags, not glyphs.[/b] The first version used ◉ ✶ ◆ ▲. Half of them did not
## exist in the fallback font and came out as boxes or blanks, and the half that
## did were indistinguishable at 14px. Three letters is legible at any size and
## needs no legend.

## Half-width of the tape, in degrees of bearing.
const SPAN_DEG := 110.0
## At most this many hostiles, nearest first, so a swarm cannot crowd out the
## landmarks that are the reason this exists.
const MAX_HOSTILES := 4
## Rows available for staggering overlapping marks.
const ROWS := 2

var _ship: Node3D = null
var _well: Node3D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _resolve():
		return
	var width := minf(size.x * 0.58, 980.0)
	var rect := Rect2(Vector2((size.x - width) * 0.5, 6.0), Vector2(width, 48.0))

	var fill := SciFi.PANEL_FILL
	fill.a *= 0.75
	SciFi.panel(self, rect, Color(SciFi.CYAN.r, SciFi.CYAN.g, SciFi.CYAN.b, 0.5), 10.0, 15, fill)

	var basis := _ship.global_transform.basis
	var forward := -basis.z
	var right := basis.x

	_draw_scale(rect)
	for mark in _lay_out(rect, forward, right):
		_draw_mark(rect, mark)

	# Dead ahead, so the centre of the tape is never in doubt.
	var mid := rect.position.x + rect.size.x * 0.5
	draw_line(Vector2(mid, rect.position.y + 2.0), Vector2(mid, rect.position.y + 8.0),
		Color(SciFi.CYAN.r, SciFi.CYAN.g, SciFi.CYAN.b, 0.9), 1.5)


## Ticks every 30 degrees, so the tape has a scale and not just marks.
func _draw_scale(rect: Rect2) -> void:
	var col := Color(SciFi.TEXT_DIM.r, SciFi.TEXT_DIM.g, SciFi.TEXT_DIM.b, 0.3)
	for step in range(-90, 91, 30):
		if step == 0:
			continue
		var x := rect.position.x + rect.size.x * (0.5 + float(step) / (SPAN_DEG * 2.0))
		draw_line(Vector2(x, rect.position.y + 2.0), Vector2(x, rect.position.y + 7.0), col, 1.0)


## Places every contact on the tape and staggers the ones that collide.
##
## Without this the marks overlap into illegible mush the moment two things
## share a bearing, which out here is constantly: the landmarks are fixed and
## the player turns past them. Sorting by position and pushing each colliding
## mark to the next row down costs nothing and is the difference between a
## readable instrument and a smear.
func _lay_out(rect: Rect2, forward: Vector3, right: Vector3) -> Array:
	var marks: Array = []
	for contact in _contacts():
		var offset: Vector3 = contact["at"] - _ship.global_position
		var distance := offset.length()
		if distance < 1.0:
			continue
		var dir := offset / distance
		# Signed bearing from the nose, positive to starboard. atan2 of the two
		# projections rather than acos of one, so it keeps its sign all the way
		# round to dead astern.
		var bearing := rad_to_deg(atan2(dir.dot(right), dir.dot(forward)))
		var clamped := clampf(bearing / SPAN_DEG, -1.0, 1.0)
		marks.append({
			"x": rect.position.x + 22.0 + (rect.size.x - 44.0) * (clamped * 0.5 + 0.5),
			"tag": contact["tag"],
			"tint": contact["tint"],
			"pinned": absf(bearing) > SPAN_DEG,
			"side": signf(bearing),
			# 1 world unit is ~10 m, so range in kilometres.
			"range": ("%.0f km" % (distance * 0.01)) if distance > 10000.0
				else ("%.1f km" % (distance * 0.01)),
		})

	marks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["x"] < b["x"])
	var row_end := PackedFloat32Array()
	for i in ROWS:
		row_end.append(-1e9)
	for mark in marks:
		var half := _mark_half_width(mark)
		var row := ROWS - 1
		for r in ROWS:
			if mark["x"] - half > row_end[r]:
				row = r
				break
		mark["row"] = row
		row_end[row] = mark["x"] + half
	return marks


func _mark_half_width(mark: Dictionary) -> float:
	var f := SciFi.font()
	var tag: float = f.get_string_size(String(mark["tag"]), HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
	var rng: float = f.get_string_size(String(mark["range"]), HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
	return maxf(tag, rng) * 0.5 + 5.0


func _draw_mark(rect: Rect2, mark: Dictionary) -> void:
	var x: float = mark["x"]
	var col: Color = mark["tint"]
	if mark["pinned"]:
		col.a = 0.55
	var y: float = rect.position.y + 20.0 + float(mark["row"]) * 15.0

	var f := SciFi.font()
	var tag := String(mark["tag"])
	var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
	draw_string(f, Vector2(x - tw * 0.5, y), tag,
		HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL, col)

	var rng := String(mark["range"])
	var rw := f.get_string_size(rng, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
	draw_string(f, Vector2(x - rw * 0.5, y + 11.0), rng,
		HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL,
		Color(SciFi.TEXT_DIM.r, SciFi.TEXT_DIM.g, SciFi.TEXT_DIM.b, col.a * 0.85))

	# A stalk up to the scale, so the mark and its bearing are one object even
	# when it has been pushed to the lower row.
	draw_line(Vector2(x, rect.position.y + 7.0), Vector2(x, y - 9.0),
		Color(col.r, col.g, col.b, col.a * 0.45), 1.0)

	if mark["pinned"]:
		var s: float = mark["side"]
		var tip := Vector2(x + s * (_mark_half_width(mark) + 5.0), y - 4.0)
		draw_polyline(PackedVector2Array([
			tip - Vector2(s * 4.0, 4.0), tip, tip - Vector2(s * 4.0, -4.0)]), col, 1.4, true)


## Everything worth a mark. Order does not matter; _lay_out sorts by bearing.
func _contacts() -> Array:
	var out: Array = []
	out.append({"at": _well.global_position, "tag": "GOLIATH", "tint": SciFi.AMBER})

	for node in get_tree().get_nodes_in_group(Hazard.GROUP):
		var hazard := node as Hazard
		if hazard != null:
			out.append({"at": hazard.global_position, "tag": hazard.short_tag(), "tint": hazard.tint})

	var boss := get_tree().get_nodes_in_group(Mothership.GROUP)
	if not boss.is_empty():
		var shard := boss[0] as Node3D
		if shard != null:
			out.append({"at": shard.global_position, "tag": "DREAD", "tint": Mothership.BIOLUME})

	var hostiles: Array = []
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Node3D
		hostiles.append({
			"d": enemy.global_position.distance_to(_ship.global_position),
			"at": enemy.global_position})
	hostiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	for i in mini(hostiles.size(), MAX_HOSTILES):
		out.append({"at": hostiles[i]["at"], "tag": "HOSTILE", "tint": SciFi.DANGER})
	return out


func _resolve() -> bool:
	if not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group(&"player") as Node3D
	if not is_instance_valid(_well):
		var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
		_well = wells[0] as Node3D if not wells.is_empty() else null
	return is_instance_valid(_ship) and is_instance_valid(_well)
