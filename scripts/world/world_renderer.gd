class_name WorldRenderer
extends Node2D
## WorldRenderer
##
## Layered parallax silhouettes, rails, sky gradient, headlight cone.

var _time: float = 0.0
var _distance: float = 0.0
var _light_profile: LightProfile = LightProfile.new()
var _view_size: Vector2 = Vector2(1280, 720)
var _train_x: float = 320.0
var _train_y: float = 460.0
var _reduced_motion: bool = false


func setup(view_size: Vector2) -> void:
	_view_size = view_size
	set_process(true)


func update_state(distance: float, light_profile: LightProfile, train_pos: Vector2) -> void:
	_distance = distance
	_light_profile = light_profile
	_train_x = train_pos.x
	_train_y = train_pos.y


func _process(delta: float) -> void:
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	if not _reduced_motion:
		_time += delta
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = _view_size
	# Sky: deep charcoal to slight blue
	var top: Color = Color(0.03, 0.04, 0.06)
	var mid: Color = Color(0.06, 0.06, 0.09)
	var bottom: Color = Color(0.04, 0.05, 0.07)
	var horizon: float = s.y * 0.68
	_draw_gradient_rect(Rect2(0, 0, s.x, horizon), top, mid)
	_draw_gradient_rect(Rect2(0, horizon, s.x, s.y - horizon), mid, bottom)

	# Far mountains (very slow parallax)
	_draw_ridge(s, 0.02, s.y * 0.55, 30, Color(0.07, 0.08, 0.11), 18.0)
	# Mid hills
	_draw_ridge(s, 0.08, s.y * 0.63, 24, Color(0.10, 0.10, 0.13), 22.0)
	# Near trees/wreckage
	_draw_ridge(s, 0.25, s.y * 0.72, 40, Color(0.13, 0.12, 0.14), 14.0)

	# Ground line and rails
	var ground_y: float = s.y * 0.80
	draw_rect(Rect2(0, ground_y, s.x, s.y - ground_y), Color(0.05, 0.05, 0.07))
	# rails with ties
	var tie_spacing: float = 40.0
	var tie_offset: float = fmod(_distance * 0.5, tie_spacing)
	for i in range(int(s.x / tie_spacing) + 2):
		var x: float = i * tie_spacing - tie_offset
		draw_rect(Rect2(x, ground_y + 14, tie_spacing * 0.55, 4), Color(0.13, 0.10, 0.08))
	draw_line(Vector2(0, ground_y + 10), Vector2(s.x, ground_y + 10), Color(0.35, 0.28, 0.20), 2.0)
	draw_line(Vector2(0, ground_y + 24), Vector2(s.x, ground_y + 24), Color(0.30, 0.24, 0.18), 2.0)

	# Distant lantern events along the horizon (only visible sometimes)
	var lantern_offset: float = fmod(_distance * 0.05, 360.0)
	for i in range(4):
		var lx: float = (i * 360.0 - lantern_offset) + 100.0
		if lx > 0 and lx < s.x:
			var ly: float = s.y * 0.55 + sin(_time * 0.5 + i) * 3.0
			draw_circle(Vector2(lx, ly), 2.0, Color(1.0, 0.85, 0.55, 0.7))
			draw_circle(Vector2(lx, ly), 5.0, Color(1.0, 0.85, 0.55, 0.12))

	# Headlight cone drawn from just in front of the locomotive
	_draw_light_cone()


func _draw_gradient_rect(rect: Rect2, top: Color, bottom: Color) -> void:
	var steps: int = 12
	for i in range(steps):
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var col: Color = top.lerp(bottom, (t0 + t1) * 0.5)
		draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * t0, rect.size.x, rect.size.y * (t1 - t0)), col)


func _draw_ridge(s: Vector2, parallax_speed: float, base_y: float, steps: int, col: Color, amp: float) -> void:
	var offset: float = _distance * parallax_speed
	var poly: PackedVector2Array = PackedVector2Array()
	poly.append(Vector2(0, s.y))
	for i in range(steps + 1):
		var x: float = s.x * float(i) / float(steps)
		var noise: float = sin((i + offset * 0.1) * 1.7) * amp + cos((i + offset * 0.1) * 2.3) * amp * 0.6
		poly.append(Vector2(x, base_y + noise))
	poly.append(Vector2(s.x, s.y))
	draw_colored_polygon(poly, col)


func _draw_light_cone() -> void:
	if _light_profile == null or _light_profile.intensity <= 0.0:
		return
	var origin: Vector2 = _light_profile.origin
	var dir: Vector2 = _light_profile.direction
	var length: float = _light_profile.range_px
	var spread: float = _light_profile.spread_radians
	var left: Vector2 = dir.rotated(-spread) * length + origin
	var right: Vector2 = dir.rotated(spread) * length + origin
	var col: Color = _light_profile.color
	# Additive-like translucent layers
	var poly: PackedVector2Array = PackedVector2Array([origin, left, right])
	draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.18))
	# inner brighter core
	var left2: Vector2 = dir.rotated(-spread * 0.5) * length * 0.85 + origin
	var right2: Vector2 = dir.rotated(spread * 0.5) * length * 0.85 + origin
	var poly2: PackedVector2Array = PackedVector2Array([origin, left2, right2])
	draw_colored_polygon(poly2, Color(col.r, col.g, col.b, 0.24))
	# hotspot
	draw_circle(origin, 6.0, Color(col.r, col.g, col.b, 0.9))
