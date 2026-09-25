@tool
class_name StatBar
extends Control
## One labelled bar: caption on the left, value on the right, bar underneath.
## Used by both the in-flight HUD and the hangar's stat block.

@export var caption: String = "HULL":
	set(value):
		caption = value
		queue_redraw()

## 0..1.
@export_range(0.0, 1.0, 0.001) var value: float = 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

## Text shown at the right of the caption row. Empty hides it.
@export var readout: String = "":
	set(v):
		readout = v
		queue_redraw()

@export var accent: Color = SciFi.CYAN:
	set(v):
		accent = v
		queue_redraw()

## Recolour the bar by value (green / amber / red) instead of using [member accent].
@export var color_by_value: bool = false:
	set(v):
		color_by_value = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(0, 36)


func _draw() -> void:
	var c := SciFi.status_color(value) if color_by_value else accent
	SciFi.label(self, Vector2(0, 14), caption, SciFi.TEXT_DIM, SciFi.FONT_LABEL)
	if readout != "":
		SciFi.label_right(self, size.x, 14, readout, c, SciFi.FONT_LABEL)
	SciFi.bar(self, Rect2(Vector2(0, 21), Vector2(size.x, 7)), value, c)
