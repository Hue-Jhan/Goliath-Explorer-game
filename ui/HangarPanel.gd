extends Control
## Ship locker: pick one of three hulls and see what you are getting.
##
## The preview renders the same geometry the expedition flies, from
## [ShipClasses], in its own [SubViewport] world -- so it can never drift out of
## sync with the real ship the way a screenshot would.
##
## Selecting writes [member Globals.selected_ship], whose setter copies the
## whole class entry into the tuning properties. Nothing else has to know a
## class system exists: the flight model, the HUD gauges and the cannon all keep
## reading the same fields they always did.

signal closed

@onready var _preview: MeshInstance3D = $Frame/Preview/SubViewport/ShipPreview
@onready var _speed: StatBar = $Frame/Stats/Speed
@onready var _laser: StatBar = $Frame/Stats/Laser
@onready var _hull: StatBar = $Frame/Stats/Hull
@onready var _charge: StatBar = $Frame/Stats/Charge
@onready var _cards: HBoxContainer = $Frame/Cards
@onready var _name: Label = $Frame/Name
@onready var _class_line: Label = $Frame/Class
@onready var _close: Button = $Frame/Close

var _card_nodes: Array[ShipCard] = []


func _ready() -> void:
	_build_cards()
	_close.pressed.connect(close)
	_apply(Globals.selected_ship)
	hide()


func open() -> void:
	_apply(Globals.selected_ship)
	show()
	_close.grab_focus()


func close() -> void:
	hide()
	Globals.save_settings()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"menu_back"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if visible:
		_preview.rotate_y(delta * 0.45)


func _build_cards() -> void:
	for child in _cards.get_children():
		child.queue_free()
	_card_nodes.clear()
	for i in ShipClasses.COUNT:
		var card := ShipCard.new()
		card.index = i
		card.chosen.connect(_on_chosen)
		_cards.add_child(card)
		_card_nodes.append(card)


func _on_chosen(index: int) -> void:
	Globals.selected_ship = index
	Globals.save_settings()
	_apply(index)


func _apply(index: int) -> void:
	var entry := ShipClasses.data(index)
	_preview.mesh = ShipClasses.build_mesh(index)
	_preview.material_override = ShipClasses.material(index)
	_name.text = entry["name"]
	_class_line.text = entry["blurb"]

	for card in _card_nodes:
		card.selected = card.index == index

	# Bars are normalised against the best hull in each category, so the three
	# are read against each other rather than against an invented maximum.
	var top := ShipClasses.top_speed(index)
	_speed.value = clampf(top / 2100.0, 0.0, 1.0)
	_speed.readout = "%d u/s" % int(round(top))

	var dps: float = float(entry["damage"]) * float(entry["fire_rate"])
	_laser.value = clampf(dps / 90.0, 0.0, 1.0)
	_laser.readout = "%.0f dps" % dps

	_hull.value = clampf(float(entry["hull"]) / 220.0, 0.0, 1.0)
	_hull.readout = "%d HP" % int(round(float(entry["hull"])))

	# Inverted, because the number is a wait: the hull that recharges fastest
	# gets the fullest bar, so every bar in this block still means "more is
	# better" and the rack can be read at a glance.
	var recharge: float = float(entry["charge"])
	_charge.value = clampf(1.0 - (recharge - 5.0) / 11.0, 0.0, 1.0)
	_charge.readout = "%.1f s recharge" % recharge
