class_name BossBar
extends Control
## The mothership's health bar, across the top of the screen.
##
## Appears only inside the boss's engagement range and fades out again when you
## disengage or it dies, for the same reason the scoreboard does: a permanently
## pinned bar for something that is not on screen is just furniture.
##
## Drawn rather than composed from [ProgressBar] nodes so it can carry the same
## chamfered, glowing vocabulary as the rest of the interface -- see [SciFi].

## Seconds to fade in and out.
const FADE := 0.4
## Width of the bar as a fraction of the viewport, capped so it does not run the
## whole width of an ultrawide.
const WIDTH_RATIO := 0.46
const MAX_WIDTH := 880.0

var _alpha: float = 0.0
var _boss: Mothership = null
var _ship: Node3D = null
## Held after the boss dies so the bar can finish emptying rather than vanishing
## mid-kill.
var _last_ratio: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var showing := _resolve()
	_alpha = clampf(_alpha + (delta / FADE) * (1.0 if showing else -1.0), 0.0, 1.0)
	if _alpha > 0.0:
		queue_redraw()


func _resolve() -> bool:
	if not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group(&"player") as Node3D
	if not is_instance_valid(_boss):
		var found := get_tree().get_nodes_in_group(Mothership.GROUP)
		_boss = found[0] as Mothership if not found.is_empty() else null
	if _boss == null or _ship == null:
		return false
	_last_ratio = _boss.health_ratio()
	return _boss.engaged_by(_ship.global_position)


func _draw() -> void:
	if _alpha <= 0.001:
		return
	var width := minf(size.x * WIDTH_RATIO, MAX_WIDTH)
	# Third in the centre column: bearing tape, scoreboard, then this.
	var rect := Rect2(Vector2((size.x - width) * 0.5, 126.0), Vector2(width, 54.0))
	var accent := Mothership.BIOLUME
	accent.a = _alpha
	var fill := SciFi.PANEL_FILL_DEEP
	fill.a *= _alpha
	SciFi.panel(self, rect, accent, 16.0, 15, fill)

	var title := "'OUMUAMUA-CLASS DREADNOUGHT"
	var tw := SciFi.font().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_LABEL).x
	draw_string(SciFi.font(), rect.position + Vector2((width - tw) * 0.5, 20.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_LABEL,
		Color(SciFi.TEXT.r, SciFi.TEXT.g, SciFi.TEXT.b, _alpha))

	# Red under a third: the colour is the warning, and it is the boss's own
	# green everywhere above that so the bar never reads as the player's.
	var bar_colour := (SciFi.DANGER if _last_ratio < 0.33 else Mothership.BIOLUME)
	bar_colour.a = _alpha
	SciFi.bar(self, Rect2(rect.position + Vector2(16.0, 30.0), Vector2(width - 32.0, 12.0)),
		_last_ratio, bar_colour)

	SciFi.label_right(self, rect.position.x + width - 16.0, rect.position.y + 52.0,
		"%d%% INTEGRITY" % int(round(_last_ratio * 100.0)),
		Color(SciFi.TEXT_DIM.r, SciFi.TEXT_DIM.g, SciFi.TEXT_DIM.b, _alpha), SciFi.FONT_SMALL)
