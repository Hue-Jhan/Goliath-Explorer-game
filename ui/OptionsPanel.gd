extends Control
## Settings panel, generated from a table rather than hand-built.
##
## Every row names a property on the [Globals] autoload and reads its current
## value straight off it, so there is no second copy of the settings to keep in
## sync -- moving a control writes the singleton, and the singleton's own setter
## fans the change out to the shader, the audio buses and the viewport. Adding a
## knob means adding one line to [constant ROWS].
##
## Row kinds are distinguished by the first field: [code]#[/code] is a section
## heading, [code]@[/code] a checkbox, [code]$[/code] the key-binding block, and
## anything else a slider.

signal closed

const ROWS := [
	["#", "QUALITY"],
	["Graphics quality", "quality_level", 1.0, 10.0, 1.0, "", true],
	["#", "SIMULATION"],
	["Lensing strength", "bh_strength", 0.0, 4.0, 0.01, "%.2f", false],
	["Disk radius", "disk_outer_rs", 4.0, 40.0, 0.5, "%.1f rs", false],
	["Gravity reach", "bh_capture_radius", 1.5, 30.0, 0.1, "%.1f rs", false],
	["Gravity strength", "bh_gravity", 0.0, 20000.0, 100.0, "%d u/s²", true],
	["Disk thickness", "disk_thickness_rs", 0.0, 3.0, 0.01, "%.2f rs", false],
	["Nebula brightness", "nebula_gain", 0.0, 3.0, 0.05, "%.2f", false],
	["Asteroid density", "asteroid_density", 0.0, 6.0, 0.05, "%.2f", false],
	["Enemy spawn rate", "enemy_spawn_rate", 0.0, 10.0, 0.05, "%.2f /s", false],
	["Max enemies", "max_enemies", 0.0, 200.0, 1.0, "%d", true],
	["#", "LANDMARKS"],
	["Remnant gravity", "remnant_gravity", 0.0, 9000.0, 50.0, "%d u/s²", true],
	["Remnant size", "remnant_scale", 0.25, 4.0, 0.05, "%.2fx", false],
	["Pulsar gravity", "pulsar_gravity", 0.0, 9000.0, 50.0, "%d u/s²", true],
	["Pulsar size", "pulsar_scale", 0.25, 4.0, 0.05, "%.2fx", false],
	["#", "CAMERA & INPUT"],
	["Mouse sensitivity", "mouse_sensitivity", 0.0005, 0.02, 0.0001, "%.4f", false],
	["Field of view", "base_fov", 40.0, 110.0, 1.0, "%d°", true],
	["FOV distortion", "fov_distortion_intensity", 0.0, 2.0, 0.01, "%.2f", false],
	["Camera shake", "shake_intensity", 0.0, 2.0, 0.05, "%.2f", false],
	["@", "invert_pitch", "Invert pitch"],
	["#", "WEAPONS"],
	["Aim assist cone", "aim_assist_cone", 0.0, 12.0, 0.1, "%.1f°", false],
	["Target assist hold", "soft_lock_duration", 0.0, 10.0, 0.1, "%.1f s", false],
	["Laser beam length", "laser_beam_length", 80.0, 1200.0, 10.0, "%d u", true],
	["Charged beam radius", "charge_blast_radius", 100.0, 1600.0, 10.0, "%d u", true],
	["#", "AUDIO"],
	["Master", "master_volume", 0.0, 1.0, 0.01, "%d%%", false],
	["Music", "music_volume", 0.0, 1.0, 0.01, "%d%%", false],
	["SFX", "sfx_volume", 0.0, 1.0, 0.01, "%d%%", false],
	["#", "CONTROLS"],
	["$"],
]

@onready var _rows: VBoxContainer = $Frame/Scroll/Rows
@onready var _close: Button = $Frame/Close

## Action currently waiting for a key press, or "" when not rebinding.
var _listening: String = ""
var _listening_button: Button = null
var _bind_buttons: Dictionary = {}


func _ready() -> void:
	_build()
	_close.pressed.connect(close)
	hide()


func open() -> void:
	_sync()
	show()
	_close.grab_focus()


func close() -> void:
	_cancel_listen()
	hide()
	# Settings are only worth having if they survive the session.
	Globals.save_settings()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"menu_back"):
		close()
		get_viewport().set_input_as_handled()


# --- key rebinding ------------------------------------------------------------

## Runs ahead of everything else so a key being bound cannot also fire whatever
## it is currently bound to.
func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	var key := event as InputEventKey
	var button := event as InputEventMouseButton
	if key == null and button == null:
		return
	if (key != null and not key.pressed) or (button != null and not button.pressed):
		return
	get_viewport().set_input_as_handled()
	if key != null and key.echo:
		return
	if key != null and key.physical_keycode == KEY_ESCAPE:
		_cancel_listen() # Escape backs out rather than binding itself
		return
	_assign(_listening, key if key != null else button)
	_cancel_listen()
	_refresh_bindings()


func _begin_listen(action: String, button: Button) -> void:
	_cancel_listen()
	_listening = action
	_listening_button = button
	button.text = "press a key…"


func _cancel_listen() -> void:
	if _listening_button != null:
		_listening_button.text = Globals.binding_label(_listening)
	_listening = ""
	_listening_button = null


func _assign(action: String, event: InputEvent) -> void:
	var clean := _strip(event)
	# A key can only mean one thing, so take it away from whatever held it.
	for entry in Globals.BINDABLE:
		var other: String = entry[0]
		for existing in InputMap.action_get_events(other):
			if existing.is_match(clean, true):
				InputMap.action_erase_event(other, existing)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	Globals.save_settings()


## Rebuilds the event with only the fields we bind on, so a stray modifier state
## or mouse position captured at press time cannot make the binding unmatchable.
static func _strip(event: InputEvent) -> InputEvent:
	var key := event as InputEventKey
	if key != null:
		var out := InputEventKey.new()
		out.physical_keycode = key.physical_keycode
		return out
	var mb := event as InputEventMouseButton
	var out_mb := InputEventMouseButton.new()
	out_mb.button_index = mb.button_index
	return out_mb


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		(_bind_buttons[action] as Button).text = Globals.binding_label(action)


# --- construction -------------------------------------------------------------

func _build() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_bind_buttons.clear()
	for row in ROWS:
		match row[0]:
			"#": _add_header(row[1])
			"@": _add_toggle(row[1], row[2])
			"$": _add_bindings()
			_: _add_slider(row)


func _add_header(text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	_rows.add_child(gap)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", SciFi.FONT_SMALL)
	label.add_theme_color_override(&"font_color", SciFi.AMBER)
	_rows.add_child(label)
	var rule := ColorRect.new()
	rule.color = Color(SciFi.AMBER.r, SciFi.AMBER.g, SciFi.AMBER.b, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	_rows.add_child(rule)


func _row_line(caption: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(196, 32)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", SciFi.FONT_LABEL)
	label.add_theme_color_override(&"font_color", SciFi.TEXT)
	line.add_child(label)
	return line


func _add_slider(row: Array) -> void:
	var prop: String = row[1]
	var is_int: bool = row[6]
	var fmt: String = row[5]
	var line := _row_line(row[0])

	var slider := HSlider.new()
	slider.min_value = row[2]
	slider.max_value = row[3]
	slider.step = row[4]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(230, 32)
	slider.value = float(Globals.get(prop))
	line.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(230 if prop == "quality_level" else 96, 32)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override(&"font_size", SciFi.FONT_LABEL)
	value_label.add_theme_color_override(&"font_color", SciFi.CYAN)
	line.add_child(value_label)

	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(18, 0)
	line.add_child(gutter)

	slider.value_changed.connect(func(v: float) -> void:
		Globals.set(prop, int(round(v)) if is_int else v)
		value_label.text = _format(prop, v, fmt)
		Globals.apply_av_settings(get_viewport()))

	value_label.text = _format(prop, slider.value, fmt)
	slider.set_meta(&"prop", prop)
	slider.set_meta(&"value_label", value_label)
	slider.set_meta(&"fmt", fmt)
	_rows.add_child(line)


func _add_toggle(prop: String, caption: String) -> void:
	var line := _row_line(caption)
	var box := CheckBox.new()
	box.button_pressed = bool(Globals.get(prop))
	box.toggled.connect(func(on: bool) -> void: Globals.set(prop, on))
	line.add_child(box)
	_rows.add_child(line)


func _add_bindings() -> void:
	for entry in Globals.BINDABLE:
		var action: String = entry[0]
		var line := _row_line(entry[1])
		var button := Button.new()
		button.custom_minimum_size = Vector2(180, 32)
		button.text = Globals.binding_label(action)
		button.pressed.connect(_begin_listen.bind(action, button))
		line.add_child(button)
		var gutter := Control.new()
		gutter.custom_minimum_size = Vector2(18, 0)
		line.add_child(gutter)
		_bind_buttons[action] = button
		_rows.add_child(line)

	var reset := Button.new()
	reset.text = "Reset all bindings"
	reset.custom_minimum_size = Vector2(0, 34)
	reset.pressed.connect(func() -> void:
		Globals.reset_bindings()
		Globals.save_settings()
		_refresh_bindings())
	_rows.add_child(reset)


## Quality gets a summary rather than a bare number, because "6" means nothing
## while "6/10 · 73% res · 143 steps" tells you what you just bought.
func _format(prop: String, v: float, fmt: String) -> String:
	if prop == "quality_level":
		return "%d/10 · %d%% res · %d steps" % [
			int(round(v)), int(round(Globals.render_scale * 100.0)), Globals.raymarch_steps]
	if fmt.ends_with("%%"):
		return fmt % int(round(v * 100.0))
	if fmt.contains("%d"):
		return fmt % int(round(v))
	return fmt % v


## Re-reads every control from [Globals], in case something else changed them
## while the panel was closed.
func _sync() -> void:
	_refresh_bindings()
	for line in _rows.get_children():
		for child in line.get_children():
			var slider := child as HSlider
			if slider == null or not slider.has_meta(&"prop"):
				continue
			var prop := String(slider.get_meta(&"prop"))
			slider.set_value_no_signal(float(Globals.get(prop)))
			var label := slider.get_meta(&"value_label") as Label
			label.text = _format(prop, slider.value, String(slider.get_meta(&"fmt")))
