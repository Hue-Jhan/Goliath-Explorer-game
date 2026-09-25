extends Node3D
## Debug flight scene: Goliath, a free-fly camera, and three reference solids.
##
## The solids exist to prove the depth compositing in Goliath.gdshader works.
## One sits between you and the hole, one behind it, one parked inside the
## disk -- if the shader's depth clamp is right, the near one occludes the
## disk, the far one is hidden by the shadow, and the disk cuts across the
## third. If it were a plain fullscreen pass, all three would vanish.

@onready var camera: DebugCamera = $DebugCamera
@onready var readout: Label = $HUD/Readout


func _process(_delta: float) -> void:
	var dist := camera.distance_rs()
	var mode := "NEWTONIAN (gravity live)" if camera.gravity_enabled else "ARCADE (gravity off)"
	var status := "CAPTURED" if camera.captured() else "free"
	readout.text = "\n".join([
		"GOLIATH  r = %.2f rs   (horizon 1.00, ISCO %.2f, disk edge %.1f)"
			% [dist, Globals.disk_inner_rs, Globals.disk_outer_rs],
		"deadzone edge %.1f rs  ->  %s" % [Globals.bh_capture_radius, status],
		"speed %.0f u/s    fov %.1f deg" % [camera.velocity.length(), camera.fov],
		"mode  %s" % mode,
		"",
		"WASD move   SPACE/CTRL up-down   SHIFT boost",
		"G toggle gravity   ESC release mouse",
	])
