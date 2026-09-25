extends Control
## In-flight interface. Reads the ship and the gravity well; owns no state.
##
## Split three ways by what the pilot needs to know:
##   * top left  -- the ship: can it still fly, how fast, how hot
##   * top right -- Goliath: how close, how hard it is pulling, is it already
##                  too late
##   * centre    -- [EscapeCompass], which is navigation rather than telemetry

@onready var _hull_bar: StatBar = $VesselPanel/Hull
@onready var _thrust_bar: StatBar = $VesselPanel/Thrust
@onready var _heat_bar: StatBar = $VesselPanel/Heat
@onready var _charge_bar: StatBar = $VesselPanel/Charge
@onready var _proximity_bar: StatBar = $GoliathPanel/Proximity
@onready var _readout: Label = $GoliathPanel/Readout
@onready var _status: Label = $GoliathPanel/Status
@onready var _flash: ColorRect = $DamageFlash
@onready var _vessel_panel: HudPanel = $VesselPanel
@onready var _goliath_panel: HudPanel = $GoliathPanel

var _ship: Ship = null
var _well: GravityWell = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0


func _process(_delta: float) -> void:
	if not _resolve():
		return
	_update_vessel()
	_update_goliath()


func _update_vessel() -> void:
	# Hit points, not a percentage: "84 / 100" tells a pilot how many more hits
	# they have left, which "84%" does not.
	_hull_bar.value = _ship.hull_ratio()
	_hull_bar.readout = "%d / %d HP" % [ceili(_ship.hull), int(round(Globals.ship_max_hull))]

	_thrust_bar.value = _ship.speed_ratio()
	_thrust_bar.readout = "%d u/s" % int(round(_ship.speed()))

	_heat_bar.value = _ship.heat
	_heat_bar.readout = "%d%%" % int(round(_ship.heat * 100.0))
	_heat_bar.accent = SciFi.DANGER if _ship.heat > 0.85 else SciFi.AMBER

	# One gauge, two meanings, because they are never both interesting: while the
	# weapon is recharging the bar is the recharge, and once it is ready the bar
	# becomes the charge you are holding. Showing both would mean two bars that
	# are each blank most of the time.
	if _ship.charge_ready():
		var held := _ship.charge_fraction()
		# Full bar when idle-and-available, not an empty one: on every other
		# gauge here a full bar means "you have this", and the weapon being
		# ready is exactly that.
		_charge_bar.value = held if held > 0.0 else 1.0
		_charge_bar.readout = ("HOLDING %d%%" % int(round(held * 100.0))) if held > 0.0 else "READY"
		_charge_bar.accent = Color(0.35, 0.95, 0.75) if held < 0.99 else Color(1.0, 1.0, 0.9)
	else:
		var ready := _ship.charge_readiness()
		_charge_bar.value = ready
		_charge_bar.readout = "%.1f s" % (Globals.charge_cooldown * (1.0 - ready))
		_charge_bar.accent = Color(0.35, 0.55, 0.80)

	_vessel_panel.accent = SciFi.DANGER if _ship.hull_ratio() < 0.3 else SciFi.CYAN


func _update_goliath() -> void:
	var rs: float = Globals.rs_world()
	var r_world := _ship.global_position.distance_to(_well.global_position)
	var r_rs := r_world / maxf(rs, 0.001)
	var pull := _well.get_acceleration(_ship.global_position).length()
	var aperture := _well.sky_aperture_angle(_ship.global_position)

	# 1 world unit is ~10 m, so altitude above the horizon in kilometres.
	var altitude_km := maxf(r_world - rs, 0.0) * 0.01

	_readout.text = "\n".join([
		"RADIUS      %7.2f rs" % r_rs,
		"ALTITUDE    %7.0f km" % altitude_km,
		"PULL        %7.0f u/s²" % pull,
		"SKY OPEN    %7.0f°" % rad_to_deg(aperture),
	])

	_proximity_bar.value = _well.proximity(_ship.global_position)
	_proximity_bar.readout = "DEADZONE %.1f rs" % Globals.bh_capture_radius

	var authority: float = Globals.ship_thrust * Globals.ship_assist_authority
	if pull > authority:
		_status.text = "◆ PAST POINT OF NO RETURN"
		_status.modulate = SciFi.DANGER
		_goliath_panel.accent = SciFi.DANGER
	elif pull > 0.0:
		var limit := _well.point_of_no_return_rs(authority)
		_status.text = "◆ CAPTURED · no-return %.2f rs" % limit
		_status.modulate = SciFi.AMBER
		_goliath_panel.accent = SciFi.AMBER
	else:
		_status.text = "○ FREE FLIGHT"
		_status.modulate = SciFi.GOOD
		_goliath_panel.accent = SciFi.AMBER


func _on_impact(speed: float, _normal: Vector3) -> void:
	_flash.modulate.a = clampf(speed / 500.0, 0.12, 0.6)
	var tween := create_tween()
	tween.tween_property(_flash, "modulate:a", 0.0, 0.45)


func _resolve() -> bool:
	if not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group(&"player") as Ship
		if _ship != null and not _ship.impact_felt.is_connected(_on_impact):
			_ship.impact_felt.connect(_on_impact)
	if not is_instance_valid(_well):
		var wells := get_tree().get_nodes_in_group(GravityWell.GROUP)
		_well = wells[0] if not wells.is_empty() else null
	return is_instance_valid(_ship) and is_instance_valid(_well)
