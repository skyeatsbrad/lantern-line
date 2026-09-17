class_name TrainController
extends Node
## TrainController
##
## Non-visual helper for headlight direction. Physics/state live in RunState.
## game_world reads this to update world_renderer light cone and to determine
## which route "band" the light is currently on when the player confirms.

signal light_direction_changed(dir: Vector2)

var light_direction: Vector2 = Vector2(1.0, 0.0)
var _origin_screen: Vector2 = Vector2(400, 440)


func set_origin_screen(pos: Vector2) -> void:
	_origin_screen = pos


func aim_towards(screen_point: Vector2) -> void:
	var v: Vector2 = screen_point - _origin_screen
	if v.length_squared() < 1.0:
		return
	# clamp vertical to +/- 60deg; horizontal locked forward
	var d: Vector2 = v.normalized()
	if d.x < 0.1:
		d.x = 0.1
	# clamp y
	var max_tan: float = 1.7  # ~60 deg
	if d.y / d.x > max_tan:
		d = Vector2(1.0, max_tan).normalized()
	elif d.y / d.x < -max_tan:
		d = Vector2(1.0, -max_tan).normalized()
	light_direction = d
	emit_signal("light_direction_changed", d)


func current_band() -> String:
	# upper if y strongly negative, lower if positive, else middle
	if light_direction.y < -0.35:
		return "upper"
	elif light_direction.y > 0.35:
		return "lower"
	return "middle"
