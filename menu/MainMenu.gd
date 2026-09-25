extends Control
## Title screen.
##
## Sits over a live 3D backdrop (see [code]Backdrop[/code] / MenuBackdrop.gd)
## rather than a flat fill, so the menu shows the actual renderer rather than a
## picture of it. Button signals are connected here instead of in the scene file
## so the whole control flow reads in one place.

const EXPEDITION := "res://environment/Expedition.tscn"

## Placeholder locale ring for the top-right toggle. Real translation data does
## not exist yet; this proves the switch is wired and shows which locale is live.
const LOCALES := [
	["en", "EN"], ["fr", "FR"], ["de", "DE"], ["es", "ES"], ["ja", "JA"],
]

@onready var _buttons: VBoxContainer = $Center/Column/Buttons
@onready var _language: Button = $LanguageButton
@onready var _options: Control = $Options
@onready var _hangar: Control = $Hangar
@onready var _info: Control = $Info

var _locale_index := 0


func _ready() -> void:
	# The expedition captures the cursor; coming back here must release it.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Globals.apply_av_settings(get_viewport())

	_button(&"StartButton").pressed.connect(_on_start_pressed)
	_button(&"OptionsButton").pressed.connect(_on_options_pressed)
	_button(&"ShipsButton").pressed.connect(_on_ships_pressed)
	_button(&"InfoButton").pressed.connect(_on_info_pressed)
	_language.pressed.connect(_on_language_pressed)

	_options.closed.connect(_refocus)
	_hangar.closed.connect(_refocus)
	_info.closed.connect(_refocus)

	_style_title()
	_sync_language()
	_button(&"StartButton").grab_focus()


## Godot's default face is fine at body sizes but flat as a title. A
## [FontVariation] over it adds real tracking and weight without shipping a font
## file -- the letter-spacing in particular is what makes a short, all-caps
## title read as designed rather than as a large Label.
func _style_title() -> void:
	var title := $Center/Column/Title as Label
	var heavy := FontVariation.new()
	heavy.base_font = ThemeDB.fallback_font
	heavy.variation_embolden = 0.42
	heavy.spacing_glyph = 14
	title.add_theme_font_override(&"font", heavy)

	var tagline := $Center/Column/Tagline as Label
	var wide := FontVariation.new()
	wide.base_font = ThemeDB.fallback_font
	wide.spacing_glyph = 7
	tagline.add_theme_font_override(&"font", wide)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"menu_back"):
		return
	get_viewport().set_input_as_handled()
	if _options.visible:
		_options.close()
	elif _hangar.visible:
		_hangar.close()
	elif _info.visible:
		_info.close()
	else:
		Globals.save_settings()
		get_tree().quit()


func _button(node_name: StringName) -> Button:
	return _buttons.get_node(NodePath(node_name)) as Button


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(EXPEDITION)


func _on_options_pressed() -> void:
	_options.open()


func _on_ships_pressed() -> void:
	_hangar.open()


func _on_info_pressed() -> void:
	_info.open()


func _on_language_pressed() -> void:
	_locale_index = (_locale_index + 1) % LOCALES.size()
	TranslationServer.set_locale(LOCALES[_locale_index][0])
	_sync_language()
	print("[MainMenu] Locale -> %s (no translation data loaded yet)" % LOCALES[_locale_index][0])


func _sync_language() -> void:
	_language.text = "🌐  %s" % LOCALES[_locale_index][1]


func _refocus() -> void:
	_button(&"StartButton").grab_focus()
