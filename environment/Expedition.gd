extends Node3D
## The expedition: Goliath, an asteroid field, and the player.
##
## Deliberately thin. Everything interesting lives in the nodes it assembles --
## this script only owns the things that need a view of more than one of them:
## applying saved video settings to this viewport, and the destroyed/respawn
## loop, which needs both the ship and its start transform.

const MENU := "res://menu/MainMenu.tscn"

@onready var _ship: Ship = $Ship
@onready var _dead_notice: Label = $Interface/DeadNotice
@onready var _map: Control = $Interface/Map

var _spawn: Transform3D


func _ready() -> void:
	Globals.reset_score()
	_spawn = _ship.global_transform
	_dead_notice.hide()
	_ship.destroyed.connect(_on_destroyed)
	# render_scale is a viewport property, so it can only be applied once a
	# viewport exists; the autoload sets the audio buses on its own at startup.
	Globals.apply_av_settings(get_viewport())
	Globals.apply_quality_to_environment($WorldEnvironment.environment)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_map"):
		get_viewport().set_input_as_handled()
		_set_map(not _map.visible)
	elif event.is_action_pressed(&"respawn"):
		_respawn()
	elif event.is_action_pressed(&"menu_back"):
		get_viewport().set_input_as_handled()
		if _map.visible:
			# Escape backs out of the map before it backs out of the mission.
			_set_map(false)
			return
		# Otherwise Escape leaves the flight scene entirely rather than merely
		# freeing the cursor; the menu releases it on the way in, so there is
		# nothing left for a separate "ungrab" step to do.
		Globals.save_settings()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(MENU)


## Opens or closes the plan view. The cursor is released while it is up: the
## ship keeps flying, but reading a map should not also be steering.
func _set_map(open: bool) -> void:
	_map.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _on_destroyed() -> void:
	# The ship knows what killed it -- there are several things that can now, and
	# inferring it from the wreck's position stopped being possible the moment a
	# second star turned up in the system.
	#
	# M opens the map; Escape is what leaves. This string is rebuilt here on
	# every death, which is why correcting the copy in the scene file alone was
	# not enough -- the scene's version is only ever seen before the first one.
	var reason: String = _ship.death_reason if _ship.death_reason != "" else "HULL BREACH"
	_dead_notice.text = reason + "\nPress R to restart     Press Esc for Menu"
	_dead_notice.show()


func _respawn() -> void:
	_ship.global_transform = _spawn
	_ship.velocity = Vector3.ZERO
	_ship.repair_full()
	_dead_notice.hide()
