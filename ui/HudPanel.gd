@tool
class_name HudPanel
extends Control
## A chamfered, glowing frame drawn behind whatever children it contains.
##
## A plain [Container] with a StyleBox cannot do the cut corners or the
## multi-pass glow, so the frame is drawn here and layout is left to a child
## container. Give it a [VBoxContainer] child with margins and forget about it.

@export var accent: Color = SciFi.CYAN:
	set(v):
		accent = v
		queue_redraw()

@export var title: String = "":
	set(v):
		title = v
		queue_redraw()

## Bit flags for which corners are cut: 1 TL, 2 TR, 4 BR, 8 BL.
@export_range(0, 15, 1) var cut_corners: int = 5:
	set(v):
		cut_corners = v
		queue_redraw()

@export_range(0.0, 40.0, 1.0) var cut: float = 14.0:
	set(v):
		cut = v
		queue_redraw()

@export var deep_fill: bool = false:
	set(v):
		deep_fill = v
		queue_redraw()


func _draw() -> void:
	var fill := SciFi.PANEL_FILL_DEEP if deep_fill else SciFi.PANEL_FILL
	SciFi.panel(self, Rect2(Vector2.ZERO, size), accent, cut, cut_corners, fill)
	if title == "":
		return
	# Title sits in a notch on the top edge, with the rule broken around it.
	var f := SciFi.font()
	var w := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
	draw_rect(Rect2(Vector2(cut + 6.0, -1.0), Vector2(w + 12.0, 3.0)), Color(0, 0, 0, 0))
	draw_line(Vector2(cut + 4.0, 0.0), Vector2(cut + w + 16.0, 0.0), Color(0, 0, 0, 0.85), 3.0)
	SciFi.label(self, Vector2(cut + 10.0, 4.0), title, accent, SciFi.FONT_SMALL)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
