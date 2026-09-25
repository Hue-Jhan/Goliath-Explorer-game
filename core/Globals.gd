@tool
extends Node
## Central tuning hub for GoliathExplorer.
##
## Registered as the [code]Globals[/code] autoload (see Project Settings ->
## Autoload). The autoload points at [code]core/Globals.tscn[/code] rather than
## at this script directly: Godot only surfaces [annotation @GDScript.@export]
## variables for nodes you can select in the inspector, so a bare script
## autoload would give you a "customization hub" you could only edit by hand.
## Open [code]core/Globals.tscn[/code] and every knob below is a live slider.
##
## Anything that consumes these values should connect to [signal settings_changed]
## so editing a knob updates the running game (and the editor preview, since
## Goliath.gd is a [code]@tool[/code] script).
##
## [code]@tool[/code] itself is load-bearing rather than decorative: the editor
## instantiates non-tool autoloads as inert placeholders, so a [code]@tool[/code]
## consumer like Goliath.gd would get a stub with no methods on it. A tool
## provider is required for a tool consumer.

## Emitted whenever any exported value below changes.
signal settings_changed

# --- Black hole: visual -------------------------------------------------------

@export_group("Black Hole / Visual")

## Multiplier on the geodesic deflection applied to each photon step. 1.0 is
## the physically-motivated Schwarzschild approximation; higher values bend
## light harder for a more dramatic (less accurate) silhouette.
@export_range(0.0, 4.0, 0.01) var bh_strength: float = 1.20:
	set(value):
		bh_strength = value
		_changed()

## Multiplies the accretion disk's colour ramp. White leaves the calibrated
## Interstellar-reference palette untouched.
@export var bh_color_tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		bh_color_tint = value
		_changed()

## Uniform scale on the whole hole + disk system. Scales [member bh_rs_world]
## and therefore every derived radius; gameplay distances scale with it.
@export_range(0.1, 5.0, 0.01) var bh_scale: float = 1.15:
	set(value):
		bh_scale = value
		_changed()

## Tilt of the hole's spin axis away from world +Y, in degrees. Applied inside
## the raymarch, so it tilts the hole rather than the camera.
@export_range(-75.0, 75.0, 0.5, "degrees") var bh_axis_tilt: float = 0.0:
	set(value):
		bh_axis_tilt = value
		_changed()

## How fast the disk's turbulence is dragged around its Keplerian orbit.
@export_range(0.0, 4.0, 0.01) var bh_disk_rot_speed: float = 1.0:
	set(value):
		bh_disk_rot_speed = value
		_changed()

## +1 or -1. Flips which side of the disk is Doppler-brightened.
@export_enum("Counter-clockwise:-1", "Clockwise:1") var bh_disk_spin: int = 1:
	set(value):
		bh_disk_spin = value
		_changed()

## Linear exposure applied to the raymarch output before the scene's global
## ACES tonemapper sees it.
@export_range(0.1, 4.0, 0.01) var bh_exposure: float = 1.3:
	set(value):
		bh_exposure = value
		_changed()

# --- Black hole: physics ------------------------------------------------------

@export_group("Black Hole / Physics")

## Peak inward acceleration at the event horizon, in world units/s^2. Ramps up
## from zero at [member bh_capture_radius]; see [GravityWell].
@export_range(0.0, 20000.0, 10.0) var bh_gravity: float = 5800.0:
	set(value):
		bh_gravity = value
		_changed()

## Deadzone boundary, in Schwarzschild radii. Outside this, gravity is exactly
## zero -- everything beyond it is free flight. Inside it, pull and spin ramp in.
##
## At 8.0 this sat halfway between the ISCO and the disk's rim, and you had to
## be most of the way into the disk before the hole did anything at all. At 13
## it sits just inside the visible rim (17 rs), so approaching the disk is
## approaching the danger and the long spiralling orbit starts where it looks
## like it should.
@export_range(1.5, 30.0, 0.1) var bh_capture_radius: float = 15.0:
	set(value):
		bh_capture_radius = value
		_changed()

## Peak tangential (frame-dragging-flavoured) acceleration at the horizon.
## This is what turns a straight plunge into a decaying spiral.
@export_range(0.0, 20000.0, 10.0) var bh_spin_strength: float = 3600.0:
	set(value):
		bh_spin_strength = value
		_changed()

## Orbital speed of the disk's gas at the ISCO, in world units/s, falling off
## as r^-0.5 (Keplerian) further out. This is what the ship is dragged toward
## while inside the disk, so it is also the speed you end up orbiting at when
## you let go of the throttle in there.
@export_range(0.0, 4000.0, 10.0) var disk_flow_speed: float = 950.0:
	set(value):
		disk_flow_speed = value
		_changed()

## How hard the disk's gas couples the ship to that flow, as a fraction of the
## braking authority. 1.0 means the assist works just as hard to match the flow
## as it normally does to stop you.
@export_range(0.0, 2.0, 0.05) var disk_drag: float = 0.85:
	set(value):
		disk_drag = value
		_changed()

## Shape of the ramp between the deadzone edge and the horizon. 1 is linear,
## 2 is a gentle lead-in with a vicious finish.
@export_range(0.5, 6.0, 0.1) var bh_falloff_exponent: float = 2.0:
	set(value):
		bh_falloff_exponent = value
		_changed()

# --- World scale --------------------------------------------------------------

@export_group("World Scale")

## Schwarzschild radius in Godot units, before [member bh_scale]. The shader
## works in natural units (rs = 1) internally, exactly like the WebGL original;
## this is the only place the two scales meet. 1 unit is roughly 10 m, so a
## ship is about 1 unit across.
@export_range(50.0, 5000.0, 1.0) var bh_rs_world: float = 500.0:
	set(value):
		bh_rs_world = value
		_changed()

## Accretion disk inner edge, in Schwarzschild radii. 3.0 is the real ISCO for
## a non-spinning hole and leaves a clean black gap above the horizon.
@export_range(1.5, 10.0, 0.05) var disk_inner_rs: float = 3.0:
	set(value):
		disk_inner_rs = value
		_changed()

## Accretion disk outer edge, in Schwarzschild radii.
@export_range(4.0, 40.0, 0.1) var disk_outer_rs: float = 22.0:
	set(value):
		disk_outer_rs = value
		_changed()

## Half-thickness of the disk at its outer edge, in Schwarzschild radii. The
## disk flares: it is thinner near the ISCO and thickest at the rim. Drives the
## volumetric integration in Goliath.gdshader -- at 0 the disk collapses back to
## the infinitely thin plane it used to be.
@export_range(0.0, 3.0, 0.01) var disk_thickness_rs: float = 1.0:
	set(value):
		disk_thickness_rs = value
		_changed()

# --- Ship ---------------------------------------------------------------------

@export_group("Ship")

## Which hull is flown. Setting this writes the whole of that class's entry in
## [ShipClasses] into the properties below, so every consumer keeps reading the
## same fields it always did and the sliders stay usable for fine-tuning on top.
@export_range(0, 2, 1) var selected_ship: int = 0:
	set(value):
		selected_ship = clampi(value, 0, ShipClasses.COUNT - 1)
		_apply_ship_class()
		_changed()

## Main engine acceleration, world units/s^2.
@export_range(50.0, 20000.0, 10.0) var ship_thrust: float = 2600.0:
	set(value):
		ship_thrust = value
		_changed()

## Afterburner multiplier on [member ship_thrust].
@export_range(1.0, 12.0, 0.1) var ship_boost_multiplier: float = 4.0:
	set(value):
		ship_boost_multiplier = value
		_changed()

## Seconds for the braking thrusters to kill ~95% of your speed after you let
## go of the throttle. This is the whole "in-between" flight feel: not the
## instant stop of an arcade game, not the forever-drift of true Newtonian.
@export_range(0.2, 8.0, 0.05) var ship_brake_time: float = 1.4:
	set(value):
		ship_brake_time = value
		_changed()

## Seconds for angular drag to kill ~95% of a tumble.
## Braking-thruster authority as a multiple of [member ship_thrust]. Above ~1
## the assist can stop you faster than you can accelerate; it is capped so that
## close to Goliath, gravity out-pulls the engines and you are genuinely caught.
@export_range(0.2, 6.0, 0.05) var ship_assist_authority: float = 1.6:
	set(value):
		ship_assist_authority = value
		_changed()

@export_range(0.1, 4.0, 0.05) var ship_angular_brake_time: float = 0.45:
	set(value):
		ship_angular_brake_time = value
		_changed()

## Peak pitch/yaw rate from a full mouse deflection, radians/s.
@export_range(0.1, 6.0, 0.05) var ship_turn_rate: float = 1.9:
	set(value):
		ship_turn_rate = value
		_changed()

## Peak roll rate from Q/E, radians/s.
@export_range(0.1, 6.0, 0.05) var ship_roll_rate: float = 2.2:
	set(value):
		ship_roll_rate = value
		_changed()

@export_range(1.0, 1000.0, 1.0) var ship_max_hull: float = 100.0:
	set(value):
		ship_max_hull = value
		_changed()

## Hull damage per (world unit/second) of impact speed into an asteroid.
@export_range(0.0, 2.0, 0.005) var ship_impact_damage: float = 0.035:
	set(value):
		ship_impact_damage = value
		_changed()

## How hard the thrusters heat up under sustained burn, and how fast they shed
## it. Heat is cosmetic telemetry for now -- it drives the HUD gauge only.
@export_range(0.0, 3.0, 0.01) var ship_heat_rate: float = 0.42:
	set(value):
		ship_heat_rate = value
		_changed()

@export_range(0.01, 3.0, 0.01) var ship_cool_rate: float = 0.33:
	set(value):
		ship_cool_rate = value
		_changed()

## Damage per laser volley.
@export_range(1.0, 200.0, 0.5) var laser_damage: float = 12.0:
	set(value):
		laser_damage = value
		_changed()

## Volleys per second.
@export_range(0.5, 20.0, 0.1) var laser_fire_rate: float = 7.0:
	set(value):
		laser_fire_rate = value
		_changed()

## Length of a laser tracer in world units. Purely cosmetic -- the shot itself
## is a raycast down the centre line -- but it is the strongest cue the player
## has for where rounds are going, so it is exposed.
@export_range(80.0, 1200.0, 10.0) var laser_beam_length: float = 360.0:
	set(value):
		laser_beam_length = value
		_changed()

## Seconds to recharge the Q charged beam after a shot. Overwritten by the
## selected hull -- see [ShipClasses] -- and differentiating the three hulls is
## most of the point of the weapon.
@export_range(1.0, 40.0, 0.5) var charge_cooldown: float = 9.0:
	set(value):
		charge_cooldown = value
		_changed()

## Seconds of holding Q for a full-power shot.
@export_range(0.2, 6.0, 0.05) var charge_time: float = 1.4:
	set(value):
		charge_time = value
		_changed()

## Damage at the centre of a full-power detonation, falling to zero at the edge
## of the blast.
@export_range(50.0, 4000.0, 10.0) var charge_damage: float = 900.0:
	set(value):
		charge_damage = value
		_changed()

## Radius of that detonation, in world units. Wide enough to take a cluster of
## asteroids with one shot, which is what the weapon is for.
@export_range(100.0, 1600.0, 10.0) var charge_blast_radius: float = 460.0:
	set(value):
		charge_blast_radius = value
		_changed()

## Half-angle of the aim-assist cone, in degrees. Inside it the shot is pulled
## onto the target; 0 disables assist entirely.
@export_range(0.0, 12.0, 0.1) var aim_assist_cone: float = 4.4:
	set(value):
		aim_assist_cone = value
		_changed()

## How long a target stays magnetically locked after the crosshair leaves the
## cone. This is what makes a fast sweep across a target still land shots.
@export_range(0.0, 2.0, 0.05) var aim_assist_grace: float = 0.85:
	set(value):
		aim_assist_grace = value
		_changed()

## How long the E soft-lock keeps steering the nose toward a target.
@export_range(0.0, 10.0, 0.1) var soft_lock_duration: float = 3.5:
	set(value):
		soft_lock_duration = value
		_changed()

## Half-angle of the cone E searches for a target in, in degrees. Wide, because
## this is a "help me come about" button rather than an auto-aim.
@export_range(1.0, 80.0, 1.0) var soft_lock_cone: float = 34.0:
	set(value):
		soft_lock_cone = value
		_changed()

@export_range(1000.0, 40000.0, 100.0) var soft_lock_range: float = 16000.0:
	set(value):
		soft_lock_range = value
		_changed()

## Steering rate the soft lock may command, rad/s. Kept well under
## [member ship_turn_rate] so the pilot can always out-turn it.
@export_range(0.0, 3.0, 0.05) var soft_lock_strength: float = 0.85:
	set(value):
		soft_lock_strength = value
		_changed()

## Seconds of tumbling inside the horizon before the game-over panel appears.
## Crossing the horizon is the most dramatic thing in the game and cutting
## straight to a restart prompt throws it away.
@export_range(0.0, 12.0, 0.1) var horizon_death_delay: float = 4.2:
	set(value):
		horizon_death_delay = value
		_changed()

# --- Landmarks ----------------------------------------------------------------

@export_group("Landmarks")

## Peak pull of the white dwarf at the middle of the supernova remnant, in world
## units/s^2. Deliberately below every hull's braking authority: a landmark is a
## current you fly against, not a capture. Goliath is the only thing in the game
## that wins outright.
@export_range(0.0, 9000.0, 50.0) var remnant_gravity: float = 2900.0:
	set(value):
		remnant_gravity = value
		_changed()

## Overall size of the remnant. Scales the gas, the star, the danger radius and
## the lethal radius together, so the thing stays in proportion with itself and
## the shader's tuning does not have to be re-solved.
@export_range(0.25, 4.0, 0.05) var remnant_scale: float = 1.0:
	set(value):
		remnant_scale = value
		_changed()

@export_range(0.0, 9000.0, 50.0) var pulsar_gravity: float = 2500.0:
	set(value):
		pulsar_gravity = value
		_changed()

## Overall size of the pulsar: beam reach, star, danger radius and magnetosphere
## together.
@export_range(0.25, 4.0, 0.05) var pulsar_scale: float = 1.0:
	set(value):
		pulsar_scale = value
		_changed()

# --- Spawning -----------------------------------------------------------------

@export_group("Spawning")

## Enemy spawn attempts per second. Read by [EnemySpawner], which now places
## hostiles around the player rather than around the map, so this is a rate of
## arrivals into your vicinity and not a rate of population growth across the
## whole system.
@export_range(0.0, 10.0, 0.05) var enemy_spawn_rate: float = 0.10:
	set(value):
		enemy_spawn_rate = value
		_changed()

## Hard cap on simultaneously live enemies. Every one is a [CharacterBody3D]
## running flight assist and a move_and_collide every physics tick, so this is a
## frame-time budget as much as a difficulty knob -- and now that they spawn
## around the player, four nearby is a busier fight than seven scattered across
## the system ever was.
@export_range(0, 200, 1) var max_enemies: int = 10:
	set(value):
		max_enemies = value
		_changed()

## Asteroids per cubic kilo-unit of playable volume.
@export_range(0.0, 10.0, 0.05) var asteroid_density: float = 1.0:
	set(value):
		asteroid_density = value
		_changed()

# --- Video --------------------------------------------------------------------

@export_group("Video")

## Camera field of view, in degrees, with no distortion applied.
@export_range(30.0, 120.0, 0.5, "degrees") var base_fov: float = 70.0:
	set(value):
		base_fov = value
		_changed()

## How far the FOV widens as you fall toward the hole. 0 disables the effect;
## 1.0 pushes the FOV to roughly [member base_fov] + 40 degrees at the horizon.
@export_range(0.0, 2.0, 0.01) var fov_distortion_intensity: float = 0.6:
	set(value):
		fov_distortion_intensity = value
		_changed()

## The single quality control, 1 (fastest) to 10 (best). Drives every
## resource-heavy setting together -- see [method _apply_quality].
##
## Profiling says why it is one slider and not several: of 65 ms/frame at
## 1920x1008 on integrated graphics, the Goliath raymarch is 49 ms and the
## procedural sky is 11 ms. Everything else in the scene -- ship, 160 asteroids,
## HUD, glow -- totals under 4 ms. There are exactly two things worth tuning and
## they are both bought with the same currency: pixels and steps.
@export_range(1, 10, 1) var quality_level: int = 5:
	set(value):
		quality_level = clampi(value, 1, 10)
		_apply_quality()
		_changed()

## 3D resolution scale, derived from [member quality_level]. The strongest
## lever by far: the raymarch cost is very nearly linear in pixel count.
var render_scale: float = 0.73

## Raymarch step budget per photon, derived from [member quality_level]. A weak
## lever on its own -- the loop is not step-bound, since most rays break early
## on escape, saturation or occlusion -- but it matters on grazing views through
## the disk, where rays really do run long.
var raymarch_steps: int = 143

## Backdrop detail, 0 (stars only) to 3 (stars, nebula, clouds, comets), derived
## from [member quality_level]. The sky shader is evaluated on every background
## pixel *and* again for every photon that escapes the raymarch, so dropping
## octaves here is felt twice.
var sky_detail: int = 2

## Whether the glow pass runs. Cheap (about 1.8 ms) but the first thing to go
## at the bottom of the scale.
var glow_enabled: bool = true

## Brightness of the background nebulae. 0 removes them entirely.
@export_range(0.0, 3.0, 0.05) var nebula_gain: float = 1.0:
	set(value):
		nebula_gain = value
		_changed()

## Camera shake felt on impacts. 0 disables it entirely.
@export_range(0.0, 2.0, 0.05) var shake_intensity: float = 1.0:
	set(value):
		shake_intensity = value
		_changed()

# --- Input --------------------------------------------------------------------

@export_group("Input")

## Radians of turn per pixel of mouse movement per second. See [Ship] for why
## the rate is per-second rather than per-frame.
@export_range(0.0005, 0.02, 0.0001) var mouse_sensitivity: float = 0.0070:
	set(value):
		mouse_sensitivity = value
		_changed()

## Aircraft-style inverted vertical axis.
@export var invert_pitch: bool = false:
	set(value):
		invert_pitch = value
		_changed()

# --- Audio --------------------------------------------------------------------

@export_group("Audio")

@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.9:
	set(value):
		master_volume = value
		_apply_bus(&"Master", value)
		_changed()

@export_range(0.0, 1.0, 0.01) var music_volume: float = 0.7:
	set(value):
		music_volume = value
		_apply_bus(&"Music", value)
		_changed()

@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 0.85:
	set(value):
		sfx_volume = value
		_apply_bus(&"SFX", value)
		_changed()

# --- Quality ------------------------------------------------------------------

## Actions offered for rebinding, with the labels the settings panel shows.
## Order is the order they appear.
const BINDABLE := [
	["fly_forward", "Thrust forward"],
	["fly_back", "Reverse"],
	["fly_left", "Strafe left"],
	["fly_right", "Strafe right"],
	["fly_up", "Thrust up"],
	["fly_down", "Thrust down"],
	["fly_boost", "Afterburner"],
	["roll_left", "Roll left"],
	["roll_right", "Roll right"],
	["cam_zoom_in", "Camera zoom in"],
	["cam_zoom_out", "Camera zoom out"],
	["respawn", "Restart after breach"],
	["toggle_mouse_capture", "Release cursor"],
	["fire_laser", "Fire lasers"],
	["target_assist", "Target assist"],
	["super_beam", "Charged beam (hold)"],
	["toggle_map", "Toggle map"],
	["menu_back", "Menu / back"],
]

const SETTINGS_PATH := "user://settings.cfg"
## Bumped whenever a shipped default changes in a way that should reach players
## who already have a settings file. A stored file from an older version is
## discarded rather than migrated: these are tuning values, not user data, and
## silently pinning someone to last week's spawn rate is worse than resetting.
const SETTINGS_VERSION := 5

## Defaults captured at startup, so "reset to defaults" does not need a second
## hardcoded copy of the key list.
var _default_events: Dictionary = {}


## Copies the selected hull's stats into the tuning properties.
func _apply_ship_class() -> void:
	var entry := ShipClasses.data(selected_ship)
	ship_thrust = entry["thrust"]
	ship_brake_time = entry["brake"]
	ship_assist_authority = entry["authority"]
	ship_angular_brake_time = entry["angular_brake"]
	ship_turn_rate = entry["turn"]
	ship_roll_rate = entry["roll"]
	ship_max_hull = entry["hull"]
	ship_impact_damage = entry["impact"]
	ship_boost_multiplier = entry["boost"]
	laser_damage = entry["damage"]
	laser_fire_rate = entry["fire_rate"]
	charge_cooldown = entry["charge"]


func _apply_quality() -> void:
	var t := float(quality_level - 1) / 9.0
	render_scale = snappedf(lerpf(0.40, 1.0, t), 0.01)
	raymarch_steps = int(round(lerpf(60.0, 210.0, t)))
	sky_detail = 0 if quality_level <= 2 else (1 if quality_level <= 4 else (2 if quality_level <= 7 else 3))
	glow_enabled = quality_level >= 4


## Applies the quality-derived bits that live on an [Environment] rather than on
## a viewport. Call from any scene that owns a [WorldEnvironment].
func apply_quality_to_environment(env: Environment) -> void:
	if env != null:
		env.glow_enabled = glow_enabled


# --- Persistence --------------------------------------------------------------

## Writes settings and key bindings to [constant SETTINGS_PATH]. Without this,
## rebinding a key would be useful for exactly one session.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	for prop in _saved_properties():
		cfg.set_value("settings", prop, get(prop))
	for entry in BINDABLE:
		var action: String = entry[0]
		var out: Array = []
		for ev in InputMap.action_get_events(action):
			var key := ev as InputEventKey
			if key != null:
				out.append({"type": "key", "code": key.physical_keycode})
				continue
			var mb := ev as InputEventMouseButton
			if mb != null:
				out.append({"type": "mouse", "code": mb.button_index})
		cfg.set_value("keys", action, out)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	if int(cfg.get_value("meta", "version", 0)) != SETTINGS_VERSION:
		return
	for prop in _saved_properties():
		if cfg.has_section_key("settings", prop):
			set(prop, cfg.get_value("settings", prop))
	for entry in BINDABLE:
		var action: String = entry[0]
		if not cfg.has_section_key("keys", action):
			continue
		var stored: Array = cfg.get_value("keys", action, [])
		InputMap.action_erase_events(action)
		for item in stored:
			InputMap.action_add_event(action, _event_from(item))


## Restores every binding to what the project shipped with.
func reset_bindings() -> void:
	for entry in BINDABLE:
		var action: String = entry[0]
		if not _default_events.has(action):
			continue
		InputMap.action_erase_events(action)
		for ev in _default_events[action]:
			InputMap.action_add_event(action, ev)
	_changed()


static func _event_from(item: Dictionary) -> InputEvent:
	if item.get("type", "key") == "mouse":
		var mb := InputEventMouseButton.new()
		mb.button_index = int(item["code"])
		return mb
	var key := InputEventKey.new()
	key.physical_keycode = int(item["code"])
	return key


## Human-readable name for whatever is currently bound to [param action].
static func binding_label(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "—"
	var key := events[0] as InputEventKey
	if key != null:
		return OS.get_keycode_string(key.physical_keycode)
	var mb := events[0] as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			MOUSE_BUTTON_LEFT: return "Mouse 1"
			MOUSE_BUTTON_RIGHT: return "Mouse 2"
			MOUSE_BUTTON_MIDDLE: return "Mouse 3"
			_: return "Mouse %d" % mb.button_index
	return "—"


func _saved_properties() -> PackedStringArray:
	return PackedStringArray([
		"quality_level", "mouse_sensitivity", "invert_pitch", "base_fov",
		"fov_distortion_intensity", "shake_intensity", "bh_strength",
		"disk_thickness_rs", "asteroid_density", "enemy_spawn_rate",
		"max_enemies", "master_volume", "music_volume", "sfx_volume",
		"bh_scale", "disk_flow_speed", "disk_drag", "selected_ship",
		"aim_assist_cone", "aim_assist_grace", "horizon_death_delay",
		"nebula_gain", "disk_outer_rs", "soft_lock_duration",
		"soft_lock_cone", "soft_lock_strength", "laser_beam_length",
		"charge_blast_radius", "bh_capture_radius", "bh_gravity",
		"remnant_gravity", "remnant_scale", "pulsar_gravity", "pulsar_scale",
	])


# --- Session score ------------------------------------------------------------
#
# Deliberately not in _saved_properties(): a score belongs to a run, and a
# "high score" that silently resumes at whatever you had last time is worse than
# no score at all.

## Emitted on every scoring event, with the banner text to show for it.
signal scored(points: int, label: String)

var score: int = 0
var kills: int = 0


func add_score(points: int, label: String, is_kill: bool = false) -> void:
	score += points
	if is_kill:
		kills += 1
	scored.emit(points, label)


func reset_score() -> void:
	score = 0
	kills = 0


# --- Lifecycle ----------------------------------------------------------------

func _ready() -> void:
	_apply_quality()
	_apply_ship_class()
	if Engine.is_editor_hint():
		return # never reconfigure the editor's own audio or viewport
	for entry in BINDABLE:
		_default_events[entry[0]] = InputMap.action_get_events(entry[0]).duplicate()
	load_settings()
	# Autoloads enter the tree before any scene, so this is the earliest the
	# buses and the render scale can be set from the saved values.
	apply_av_settings()


# --- Derived helpers ----------------------------------------------------------

## Schwarzschild radius in world units, after [member bh_scale].
func rs_world() -> float:
	return bh_rs_world * bh_scale


## Disk outer edge in world units.
func disk_outer_world() -> float:
	return disk_outer_rs * rs_world()


## Radius of the sphere the lensing shader is rendered on, in world units.
## Deflection is windowed to near-nothing well before this, so the volume's
## boundary is invisible.
func influence_radius_world() -> float:
	return disk_outer_rs * 1.8 * rs_world()


## Disk half-thickness in world units at the rim.
func disk_thickness_world() -> float:
	return disk_thickness_rs * rs_world()


## Pushes the video and audio settings at the engine. Called once at startup and
## again whenever a slider moves; safe to call from anywhere.
func apply_av_settings(viewport: Viewport = null) -> void:
	if Engine.is_editor_hint():
		return
	_apply_bus(&"Master", master_volume)
	_apply_bus(&"Music", music_volume)
	_apply_bus(&"SFX", sfx_volume)
	var vp := viewport
	if vp == null and is_inside_tree():
		vp = get_viewport()
	if vp != null:
		vp.scaling_3d_scale = render_scale


func _apply_bus(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(String(bus))
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.0001)


func _changed() -> void:
	# Setters fire during property initialisation, before the node is in the
	# tree and before anything can be listening.
	if is_inside_tree():
		settings_changed.emit()
