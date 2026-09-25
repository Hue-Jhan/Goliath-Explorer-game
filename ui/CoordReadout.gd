class_name CoordReadout
extends Control
## The ship's position in world coordinates, bottom left.
##
## Separate from [ContactBar] because it answers a different question. The bar
## says which way to turn; this says where you are, which is what you need to
## read back, compare against a previous run, or sanity-check a map reading
## against. Small and static, in the one corner nothing else uses.

const MARGIN := Vector2(28.0, 26.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var ship := get_tree().get_first_node_in_group(&"player") as Node3D
	if ship == null:
		return
	var at := ship.global_position
	var panel := Rect2(Vector2(MARGIN.x, size.y - MARGIN.y - 62.0), Vector2(238.0, 62.0))
	var fill := SciFi.PANEL_FILL
	fill.a *= 0.75
	SciFi.panel(self, panel, Color(SciFi.CYAN.r, SciFi.CYAN.g, SciFi.CYAN.b, 0.45), 10.0, 5, fill)

	SciFi.label(self, panel.position + Vector2(14.0, 18.0), "POSITION", SciFi.TEXT_DIM, SciFi.FONT_SMALL)

	# Signed and fixed-width, so the numbers do not jitter sideways as they
	# cross zero or gain a digit -- which at these speeds they do constantly.
	var axes := [["X", at.x, SciFi.CYAN], ["Y", at.y, SciFi.GOOD], ["Z", at.z, SciFi.AMBER]]
	var x := panel.position.x + 14.0
	for axis: Array in axes:
		SciFi.label(self, Vector2(x, panel.position.y + 40.0), String(axis[0]),
			Color(axis[2].r, axis[2].g, axis[2].b, 0.8), SciFi.FONT_SMALL)
		SciFi.label(self, Vector2(x + 12.0, panel.position.y + 40.0), "%+06d" % int(axis[1]),
			SciFi.TEXT, SciFi.FONT_LABEL)
		x += 72.0

	var rs: float = maxf(Globals.rs_world(), 0.001)
	SciFi.label_right(self, panel.position.x + panel.size.x - 14.0, panel.position.y + 18.0,
		"%.1f rs" % (at.length() / rs), SciFi.AMBER, SciFi.FONT_SMALL)
