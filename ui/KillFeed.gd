class_name KillFeed
extends Control
## Kill banner, recent-events list, and a scoreboard that comes and goes.
##
## The scoreboard is deliberately temporary. A permanently pinned score panel is
## one more thing occupying the screen during the 95% of a flight where nothing
## is being shot; this one fades in on the first kill and back out a few seconds
## after the last, so it is present exactly while it is relevant.

## Seconds a banner stays up.
const BANNER_LIFE := 1.9
## Seconds an entry stays in the feed list.
const ENTRY_LIFE := 5.0
## Seconds the scoreboard lingers after the last event.
const BOARD_LINGER := 8.0
const MAX_ENTRIES := 4

var _entries: Array = []
var _last_event: float = -999.0
var _clock: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Globals.scored.is_connected(_on_scored):
		Globals.scored.connect(_on_scored)


func _process(delta: float) -> void:
	_clock += delta
	if not _entries.is_empty() or _clock - _last_event < BOARD_LINGER:
		queue_redraw()


func _on_scored(points: int, label: String) -> void:
	_entries.push_front({"label": label, "points": points, "at": _clock})
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)
	_last_event = _clock


func _draw() -> void:
	_entries = _entries.filter(func(e: Dictionary) -> bool:
		return _clock - float(e["at"]) < ENTRY_LIFE)

	var centre_x := size.x * 0.5
	_draw_banner(centre_x)
	_draw_list(centre_x)
	_draw_board(centre_x)


## The most recent event, big, rising and fading.
func _draw_banner(centre_x: float) -> void:
	if _entries.is_empty():
		return
	var top: Dictionary = _entries[0]
	var age := _clock - float(top["at"])
	if age > BANNER_LIFE:
		return
	var t := age / BANNER_LIFE
	var alpha := 1.0 - t * t
	var rise := 18.0 * t
	var y := size.y * 0.24 - rise

	var label := String(top["label"])
	var col := Color(SciFi.AMBER.r, SciFi.AMBER.g, SciFi.AMBER.b, alpha)
	var w := SciFi.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_BIG).x
	draw_string(SciFi.font(), Vector2(centre_x - w * 0.5, y), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_BIG, col)

	var points := "+%d" % int(top["points"])
	var pw := SciFi.font().get_string_size(points, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_BODY).x
	draw_string(SciFi.font(), Vector2(centre_x - pw * 0.5, y + 26.0), points,
		HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_BODY,
		Color(SciFi.GOOD.r, SciFi.GOOD.g, SciFi.GOOD.b, alpha))


## Everything still recent, stacked small under the banner.
func _draw_list(centre_x: float) -> void:
	var y := size.y * 0.24 + 52.0
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		var age := _clock - float(entry["at"])
		var alpha := clampf(1.0 - age / ENTRY_LIFE, 0.0, 1.0)
		if i == 0 and age < BANNER_LIFE:
			continue # still showing as the banner
		var text := "%s   +%d" % [entry["label"], int(entry["points"])]
		var w := SciFi.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
		draw_string(SciFi.font(), Vector2(centre_x - w * 0.5, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL,
			Color(SciFi.TEXT_DIM.r, SciFi.TEXT_DIM.g, SciFi.TEXT_DIM.b, alpha * 0.9))
		y += 17.0


func _draw_board(centre_x: float) -> void:
	var since := _clock - _last_event
	if since > BOARD_LINGER:
		return
	# Quick fade in, slow fade out.
	var alpha := clampf(minf(since / 0.25, (BOARD_LINGER - since) / 1.2), 0.0, 1.0)
	if alpha <= 0.0:
		return

	# Below the bearing tape, which occupies y 8..44 and is always up.
	var panel := Rect2(Vector2(centre_x - 132.0, 54.0), Vector2(264.0, 62.0))
	var accent := Color(SciFi.AMBER.r, SciFi.AMBER.g, SciFi.AMBER.b, alpha)
	var fill := SciFi.PANEL_FILL_DEEP
	fill.a *= alpha
	SciFi.panel(self, panel, accent, 12.0, 5, fill)

	var score_text := "%d" % Globals.score
	var sw := SciFi.font().get_string_size(score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_BIG).x
	draw_string(SciFi.font(), panel.position + Vector2(132.0 - sw * 0.5, 40.0), score_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_BIG,
		Color(SciFi.TEXT.r, SciFi.TEXT.g, SciFi.TEXT.b, alpha))
	SciFi.label(self, panel.position + Vector2(18.0, 54.0), "SCORE",
		Color(SciFi.TEXT_DIM.r, SciFi.TEXT_DIM.g, SciFi.TEXT_DIM.b, alpha), SciFi.FONT_SMALL)
	# Panel-relative, like every other coordinate here. This one was absolute and
	# only happened to line up while the panel sat at y = 22.
	SciFi.label_right(self, panel.position.x + 246.0, panel.position.y + 54.0,
		("%d KILL" % Globals.kills) if Globals.kills == 1 else ("%d KILLS" % Globals.kills),
		accent, SciFi.FONT_SMALL)
