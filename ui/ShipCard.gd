@tool
class_name ShipCard
extends Control
## One selectable hull in the ship locker.
##
## Draws itself rather than using a themed Button so the card can carry the
## class's own accent colour, a role line and a selection state in one shape --
## and so the three cards read as a rack of hulls rather than a row of buttons.

signal chosen(index: int)

@export var index: int = 0:
	set(value):
		index = value
		queue_redraw()

@export var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

var _hovered := false


func _init() -> void:
	custom_minimum_size = Vector2(250, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		chosen.emit(index)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		queue_redraw()


func _draw() -> void:
	var entry := ShipClasses.data(index)
	var accent: Color = entry["accent"]
	var rect := Rect2(Vector2.ZERO, size)
	var fill := SciFi.PANEL_FILL_DEEP
	if selected:
		fill = Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.92)
	elif _hovered:
		fill = Color(accent.r * 0.10, accent.g * 0.10, accent.b * 0.10, 0.9)
	SciFi.panel(self, rect, accent if (selected or _hovered) else Color(0.3, 0.35, 0.4), 11.0, 5, fill)

	SciFi.label(self, Vector2(16, 30), entry["name"], SciFi.TEXT, SciFi.FONT_BODY)
	SciFi.label(self, Vector2(16, 50), entry["role"], accent, SciFi.FONT_SMALL)

	# A three-bar summary, so the trade-offs are visible without selecting.
	var stats := [
		["SPD", ShipClasses.top_speed(index) / 2100.0],
		["HP", float(entry["hull"]) / 220.0],
		["DPS", float(entry["damage"]) * float(entry["fire_rate"]) / 90.0],
	]
	var x := 16.0
	for stat in stats:
		SciFi.label(self, Vector2(x, 72), stat[0], SciFi.TEXT_DIM, SciFi.FONT_SMALL)
		SciFi.bar(self, Rect2(Vector2(x + 30.0, 64.0), Vector2(38.0, 6.0)), stat[1], accent)
		x += 76.0

	if selected:
		SciFi.label_right(self, size.x - 16.0, 30.0, "ACTIVE", accent, SciFi.FONT_SMALL)
