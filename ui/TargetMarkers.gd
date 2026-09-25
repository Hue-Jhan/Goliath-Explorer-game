class_name TargetMarkers
extends Control
## Downward chevrons hanging over every hostile, with range.
##
## Drawn in screen space rather than as 3D sprites: a world-space marker either
## shrinks to nothing at the distances this game deals in, or needs
## billboarding plus a distance-compensating scale, and still ends up occluded
## by the very ship it is pointing at. A projected overlay is legible at every
## range and costs one polyline each.

## Chevrons fade out past this range, in world units, so a busy map does not
## turn the screen into a wall of arrows.
@export var max_range: float = 26000.0

var _camera: Camera3D = null
var _cannon: LaserCannon = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	var locked := _locked_target()
	for enemy in _enemies():
		_mark(enemy)
	if locked != null:
		_draw_lock(locked)


## Bracket on whatever the aim assist has hold of. Without it the assist is
## invisible, and an invisible assist reads as the game randomly deciding
## whether shots count.
func _draw_lock(target: Node3D) -> void:
	if _camera.is_position_behind(target.global_position):
		return
	var at := _camera.unproject_position(target.global_position)
	var r := 19.0
	var col := SciFi.AMBER
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var pivot := at + corner * r
		draw_polyline(PackedVector2Array([
			pivot - Vector2(corner.x * 7.0, 0.0), pivot, pivot - Vector2(0.0, corner.y * 7.0)]),
			col, 2.0, true)
	SciFi.label(self, at + Vector2(r + 6.0, -r + 4.0), "LOCK", col, SciFi.FONT_SMALL)


func _locked_target() -> Node3D:
	if not is_instance_valid(_cannon):
		var player := get_tree().get_first_node_in_group(&"player") as Node3D
		if player == null:
			return null
		_cannon = player.get_node_or_null(^"LaserCannon") as LaserCannon
	return _cannon.locked_target() if is_instance_valid(_cannon) else null


func _mark(enemy: Node3D) -> void:
	var here := _camera.global_position
	var distance := here.distance_to(enemy.global_position)
	if distance > max_range or _camera.is_position_behind(enemy.global_position):
		return

	var at := _camera.unproject_position(enemy.global_position)
	if at.x < -80.0 or at.y < -80.0 or at.x > size.x + 80.0 or at.y > size.y + 80.0:
		return

	# Hangs above the target and points down at it: "⌄" rather than a box.
	var fade := clampf(1.0 - distance / max_range, 0.25, 1.0)
	var col := Color(SciFi.DANGER.r, SciFi.DANGER.g, SciFi.DANGER.b, fade)
	var lift := 26.0
	var w := 11.0
	var h := 9.0
	var tip := at - Vector2(0.0, lift)
	var chevron := PackedVector2Array([
		tip + Vector2(-w, -h), tip, tip + Vector2(w, -h)])
	if fade > 0.6:
		for i in 2:
			var glow := col
			glow.a = col.a * 0.18 / float(i + 1)
			draw_polyline(chevron, glow, 2.4 + float(i) * 2.2, true)
	draw_polyline(chevron, col, 2.2, true)

	var text := "%.1f km" % (distance * 0.01)
	var tw := SciFi.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL).x
	draw_string(SciFi.font(), tip + Vector2(-tw * 0.5, -h - 6.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, SciFi.FONT_SMALL, col)


## Straight off the group rather than from [EnemySpawner]. The spawner only
## knows about the hostiles it made; the mothership's escorts are not among
## them, and a marker that skipped half the hostiles on screen would be worse
## than no markers at all.
func _enemies() -> Array:
	return get_tree().get_nodes_in_group(Enemy.GROUP)
