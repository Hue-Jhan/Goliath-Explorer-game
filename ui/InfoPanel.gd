extends Control
## The briefing: what this is, what is out there, and what will kill you.
##
## Built from a table, the same way [OptionsPanel] is, and for the same reason:
## adding a line means adding a line. Where a figure exists in [Globals] or
## [ShipClasses] it is read live rather than typed in, so the briefing cannot
## quietly start lying the moment somebody moves a slider -- which is exactly
## what a hand-written wall of text would do here, since half these numbers are
## settings the player can change from the next menu along.

signal closed

## Row kinds, by first field:
##   "#"  section heading
##   "P"  paragraph
##   ">"  fact line: label on the left, value on the right
##   "K"  key binding, read live from the InputMap
##   "-"  spacer
const SECTIONS := [
	["#", "BRIEFING"],
	["P", "Goliath is a Schwarzschild black hole. It is not a picture of one: "
		+ "every frame marches a ray per pixel through its gravity, so the "
		+ "shadow, the photon ring and the disk bent up over the top of itself "
		+ "are all consequences rather than artwork."],
	["P", "You have a ship, a pair of lasers and a very bad idea. Fly in, see "
		+ "how close you can hold an orbit, and fly back out."],

	["#", "WHAT IS OUT THERE"],
	["P", "Distances are shown on the bearing tape across the top of the flight "
		+ "screen, and on the map (M). One world unit is about ten metres."],
	[">", "Goliath", "the hole itself — disk, deadzone, horizon"],
	[">", "The Ashes", "a planetary nebula around a white dwarf, ~920 km out"],
	[">", "PSR Goliath-1", "a pulsar sweeping two radiation beams, ~1100 km out"],
	[">", "The Dreadnought", "an 'Oumuamua-class hulk, behind your start heading"],
	[">", "Asteroid field", "shoot rocks apart — bigger ones take more hits"],
	[">", "Hostiles", "interceptors, spawned near you and retired behind you"],

	["#", "WHAT WILL KILL YOU"],
	[">", "The event horizon", "no return; you get a few seconds of the fall first"],
	[">", "Gravity", "past the deadzone the hole out-pulls your engines"],
	[">", "Pulsar beams", "continuous burn while you are in the cone"],
	[">", "The white dwarf", "contact is instant"],
	[">", "Turrets and rocks", "the dreadnought shoots back; asteroids do not move"],

	["#", "YOUR SHIP"],
	["P", "Three hulls, chosen in the Hangar. Top speed is thrust multiplied by "
		+ "the braking time constant, which is why the fast hull is not simply "
		+ "the one with the biggest engine."],
	["H", ""],
	["P", "Hold the charged beam to spin up an area-of-effect shot. The hull "
		+ "with the worst guns recharges it fastest."],

	["#", "CONTROLS"],
	["P", "All of these are rebindable in Options."],
	["K", "fly_forward", "Thrust"],
	["K", "fly_back", "Reverse"],
	["K", "fly_boost", "Afterburner"],
	["K", "roll_left", "Roll"],
	["K", "fire_laser", "Fire lasers"],
	["K", "super_beam", "Charged beam (hold)"],
	["K", "target_assist", "Swing the nose onto a target"],
	["K", "toggle_map", "Map"],
	["K", "respawn", "Restart after a hull breach"],
	["K", "menu_back", "Back to this menu"],

	["#", "LIVE SETTINGS"],
	["P", "Everything below is a slider in Options and takes effect immediately."],
	["S", "bh_capture_radius", "Gravity reach", "%.1f rs"],
	["S", "bh_gravity", "Peak pull at the horizon", "%.0f u/s²"],
	["S", "disk_outer_rs", "Disk radius", "%.1f rs"],
	["S", "remnant_scale", "Remnant size", "%.2fx"],
	["S", "pulsar_scale", "Pulsar size", "%.2fx"],
	["S", "quality_level", "Graphics quality", "%d / 10"],
]

@onready var _rows: VBoxContainer = $Frame/Scroll/Rows
@onready var _close: Button = $Frame/Close


func _ready() -> void:
	_close.pressed.connect(close)
	hide()


func open() -> void:
	_build()
	show()
	_close.grab_focus()


func close() -> void:
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"menu_back"):
		close()
		get_viewport().set_input_as_handled()


## Rebuilt on every open rather than once, because the live rows are only
## correct at the moment they are made.
func _build() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for row in SECTIONS:
		match row[0]:
			"#": _add_header(row[1])
			"P": _add_paragraph(row[1])
			">": _add_fact(row[1], row[2], SciFi.TEXT_DIM)
			"K": _add_fact(Globals.binding_label(row[1]), row[2], SciFi.CYAN)
			"S": _add_setting(row[1], row[2], row[3])
			"H": _add_hulls()
			"-": _add_gap(10)


func _add_header(text: String) -> void:
	_add_gap(16)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", SciFi.FONT_SMALL)
	label.add_theme_color_override(&"font_color", SciFi.AMBER)
	_rows.add_child(label)
	var rule := ColorRect.new()
	rule.color = Color(SciFi.AMBER.r, SciFi.AMBER.g, SciFi.AMBER.b, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	_rows.add_child(rule)
	_add_gap(6)


func _add_gap(height: int) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	_rows.add_child(gap)


func _add_paragraph(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", SciFi.FONT_LABEL)
	label.add_theme_color_override(&"font_color", SciFi.TEXT)
	label.add_theme_constant_override(&"line_spacing", 4)
	_rows.add_child(label)
	_add_gap(8)


## A left-hand term and a right-hand explanation. The term column is fixed so
## the explanations line up into something scannable rather than ragged.
func _add_fact(term: String, text: String, tint: Color) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)

	var key := Label.new()
	key.text = term
	key.custom_minimum_size = Vector2(184, 24)
	key.add_theme_font_size_override(&"font_size", SciFi.FONT_LABEL)
	key.add_theme_color_override(&"font_color", tint)
	line.add_child(key)

	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override(&"font_size", SciFi.FONT_LABEL)
	body.add_theme_color_override(&"font_color", SciFi.TEXT)
	line.add_child(body)
	_rows.add_child(line)


func _add_setting(prop: String, caption: String, fmt: String) -> void:
	var value: float = float(Globals.get(prop))
	var shown := (fmt % int(round(value))) if fmt.contains("%d") else (fmt % value)
	_add_fact(shown, caption, SciFi.GOOD)


## The hull table, straight out of [ShipClasses] so it cannot drift from what
## the hangar shows or what the ship actually flies like.
func _add_hulls() -> void:
	for i in ShipClasses.COUNT:
		var entry := ShipClasses.data(i)
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 14)

		var name_label := Label.new()
		name_label.text = String(entry["name"])
		name_label.custom_minimum_size = Vector2(184, 24)
		name_label.add_theme_font_size_override(&"font_size", SciFi.FONT_LABEL)
		name_label.add_theme_color_override(&"font_color", entry["accent"])
		line.add_child(name_label)

		var stats := Label.new()
		stats.text = "%d u/s · %d HP · %.0f dps · %.1f s beam recharge" % [
			int(round(ShipClasses.top_speed(i))), int(entry["hull"]),
			float(entry["damage"]) * float(entry["fire_rate"]), float(entry["charge"])]
		stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_theme_font_size_override(&"font_size", SciFi.FONT_LABEL)
		stats.add_theme_color_override(&"font_color", SciFi.TEXT)
		line.add_child(stats)
		_rows.add_child(line)
	_add_gap(8)
