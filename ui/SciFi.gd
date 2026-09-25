class_name SciFi
extends RefCounted
## Shared drawing vocabulary for the ship interface.
##
## Everything in [code]ui/[/code] draws itself through these helpers rather than
## through StyleBoxes, for two reasons: chamfered (cut-corner) panels are not a
## StyleBoxFlat shape, and the glow is a multi-pass stroke that a StyleBox
## cannot express. One file owns the whole look, so retheming the ship is a
## single edit.

const CYAN := Color(0.36, 0.86, 1.0)
const AMBER := Color(1.0, 0.68, 0.22)
const DANGER := Color(1.0, 0.33, 0.24)
const GOOD := Color(0.4, 1.0, 0.62)

const PANEL_FILL := Color(0.012, 0.042, 0.062, 0.58)
const PANEL_FILL_DEEP := Color(0.008, 0.024, 0.038, 0.86)
const TEXT := Color(0.84, 0.94, 1.0)
const TEXT_DIM := Color(0.46, 0.64, 0.74)

const FONT_SMALL := 12
const FONT_LABEL := 14
const FONT_BODY := 15
const FONT_BIG := 24


static func font() -> Font:
	return ThemeDB.fallback_font


## A rectangle with its corners cut off. [param cuts] selects which corners get
## the chamfer, as bit flags: 1 = top-left, 2 = top-right, 4 = bottom-right,
## 8 = bottom-left.
static func chamfer(rect: Rect2, cut: float, cuts: int = 5) -> PackedVector2Array:
	var l := rect.position.x
	var t := rect.position.y
	var r := rect.position.x + rect.size.x
	var b := rect.position.y + rect.size.y
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.5)
	var p := PackedVector2Array()
	if cuts & 1:
		p.append(Vector2(l, t + c))
		p.append(Vector2(l + c, t))
	else:
		p.append(Vector2(l, t))
	if cuts & 2:
		p.append(Vector2(r - c, t))
		p.append(Vector2(r, t + c))
	else:
		p.append(Vector2(r, t))
	if cuts & 4:
		p.append(Vector2(r, b - c))
		p.append(Vector2(r - c, b))
	else:
		p.append(Vector2(r, b))
	if cuts & 8:
		p.append(Vector2(l + c, b))
		p.append(Vector2(l, b - c))
	else:
		p.append(Vector2(l, b))
	return p


## Stroke drawn several times at growing width and falling alpha. Cheap fake
## bloom that works without touching the 3D glow pass, so HUD glow stays
## independent of scene exposure.
static func glow_polyline(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float, glow: float = 1.0) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	if glow > 0.0:
		for i in 3:
			var spread := float(i + 1)
			var c := color
			c.a = color.a * glow * 0.16 / spread
			ci.draw_polyline(closed, c, width + spread * 2.4, true)
	ci.draw_polyline(closed, color, width, true)


## The standard interface panel: translucent dark fill, chamfered outline, glow.
static func panel(ci: CanvasItem, rect: Rect2, accent: Color, cut: float = 12.0, cuts: int = 5, fill: Color = PANEL_FILL) -> void:
	var poly := chamfer(rect, cut, cuts)
	ci.draw_colored_polygon(poly, fill)
	glow_polyline(ci, poly, accent, 1.5)


## A plain filled bar on a dim track.
##
## This replaced a segmented meter. Segments look instrument-like in isolation
## but a HUD carrying three of them reads as a wall of blinking cells, and a
## partial segment is harder to judge at a glance than a continuous edge. The
## bright cap at the fill edge is the one piece of the old look worth keeping:
## it gives the eye something to land on.
static func bar(ci: CanvasItem, rect: Rect2, t: float, accent: Color) -> void:
	t = clampf(t, 0.0, 1.0)
	ci.draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.13))
	if t <= 0.0:
		return
	var fill := Rect2(rect.position, Vector2(rect.size.x * t, rect.size.y))
	ci.draw_rect(fill, Color(accent.r, accent.g, accent.b, 0.88))
	var cap_x := rect.position.x + fill.size.x
	ci.draw_line(Vector2(cap_x, rect.position.y - 1.0),
		Vector2(cap_x, rect.position.y + rect.size.y + 1.0), accent, 2.0)


static func label(ci: CanvasItem, pos: Vector2, text: String, color: Color, size: int = FONT_SMALL) -> void:
	ci.draw_string(font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func label_right(ci: CanvasItem, right_x: float, y: float, text: String, color: Color, size: int = FONT_SMALL) -> void:
	var w := font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font(), Vector2(right_x - w, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Colour for a 0..1 health-like value: green when full, amber mid, red low.
static func status_color(t: float) -> Color:
	if t > 0.6:
		return GOOD
	if t > 0.3:
		return AMBER
	return DANGER
