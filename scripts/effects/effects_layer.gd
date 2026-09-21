class_name EffectsLayer
extends Node2D
## EffectsLayer
##
## Pooled screen shake, hit sparks, dawn glow overlay.

const MAX_HITS: int = 24

var _shake: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _hits: Array = []
var _tracers: Array = []
var _detached_cars: Array = []
var _dawn_progress: float = 0.0
var _flash_color: Color = Color.TRANSPARENT
var _flash_time: float = 0.0
var _flash_duration: float = 1.0
var _reduced_motion: bool = false
var _screen_shake_enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	set_process(true)


func request_shake(amount: float) -> void:
	if not bool(GameManager.get_setting("screen_shake", true)):
		return
	if bool(GameManager.get_setting("reduced_motion", false)):
		return
	_shake = clampf(_shake + amount, 0.0, 20.0)


func add_hit(pos: Vector2, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	if _hits.size() >= MAX_HITS:
		_hits.pop_front()
	_hits.append({"pos": pos, "age": 0.0, "life": 0.35, "color": color, "size": 12.0 + _rng.randf() * 6.0})


func add_tracer(
	start: Vector2,
	end: Vector2,
	color: Color = Color(1.0, 0.65, 0.25)
) -> void:
	if _tracers.size() >= MAX_HITS:
		_tracers.pop_front()
	_tracers.append({
		"start": start,
		"end": end,
		"age": 0.0,
		"life": 0.28,
		"color": color
	})


func set_dawn_progress(v: float) -> void:
	_dawn_progress = clampf(v, 0.0, 1.0)


func request_flash(color: Color, duration: float) -> void:
	if bool(GameManager.get_setting("reduced_flashes", false)):
		color.a *= 0.28
		duration = minf(duration, 0.18)
	_flash_color = color
	_flash_duration = maxf(0.01, duration)
	_flash_time = _flash_duration


func add_detached_car(pos: Vector2) -> void:
	_detached_cars.append({
		"pos": pos,
		"age": 0.0,
		"life": 1.25
	})


func shake_offset() -> Vector2:
	return _shake_offset


func _process(delta: float) -> void:
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	_screen_shake_enabled = bool(GameManager.get_setting("screen_shake", true))
	if _reduced_motion or not _screen_shake_enabled:
		_shake = 0.0
	if _shake > 0.0:
		_shake_offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake
		_shake = maxf(0.0, _shake - delta * 40.0)
	else:
		_shake_offset = Vector2.ZERO
	for h in _hits:
		h["age"] = float(h["age"]) + delta
	_hits = _hits.filter(func(h: Dictionary) -> bool: return h["age"] < h["life"])
	for tracer in _tracers:
		tracer["age"] = float(tracer["age"]) + delta
	_tracers = _tracers.filter(
		func(tracer: Dictionary) -> bool: return tracer["age"] < tracer["life"]
	)
	for detached in _detached_cars:
		detached["age"] = float(detached["age"]) + delta
		if not _reduced_motion:
			detached["pos"] = Vector2(detached["pos"]) + Vector2(-95.0, 42.0) * delta
	_detached_cars = _detached_cars.filter(
		func(detached: Dictionary) -> bool: return detached["age"] < detached["life"]
	)
	_flash_time = maxf(0.0, _flash_time - delta)
	queue_redraw()


func _draw() -> void:
	for tracer in _tracers:
		var tracer_ratio: float = 1.0 - float(tracer["age"]) / float(tracer["life"])
		var tracer_color: Color = tracer["color"]
		var start: Vector2 = tracer["start"]
		var end: Vector2 = tracer["end"]
		draw_line(
			start,
			end,
			Color(tracer_color.r, tracer_color.g, tracer_color.b, tracer_ratio),
			2.0 + tracer_ratio * 3.0
		)
		draw_arc(
			end,
			8.0 + (1.0 - tracer_ratio) * 12.0,
			0.0,
			TAU,
			20,
			Color(tracer_color.r, tracer_color.g, tracer_color.b, tracer_ratio),
			2.0
		)
	for h in _hits:
		var a: float = 1.0 - float(h["age"]) / float(h["life"])
		var c: Color = h["color"]
		draw_circle(h["pos"], h["size"] * a, Color(c.r, c.g, c.b, a))
	for detached in _detached_cars:
		var age_ratio: float = float(detached["age"]) / float(detached["life"])
		var alpha: float = 1.0 - age_ratio
		var center: Vector2 = detached["pos"]
		var tilt: float = -0.12 * age_ratio
		var transform := Transform2D(tilt, center)
		draw_set_transform_matrix(transform)
		draw_rect(
			Rect2(Vector2(-46.0, -45.0), Vector2(92.0, 42.0)),
			Color(0.34, 0.2, 0.12, alpha * 0.9)
		)
		draw_line(Vector2(-46.0, -48.0), Vector2(46.0, -48.0), Color(1.0, 0.62, 0.24, alpha), 3.0)
		draw_circle(Vector2(-28.0, 2.0), 9.0, Color(0.08, 0.08, 0.09, alpha))
		draw_circle(Vector2(28.0, 2.0), 9.0, Color(0.08, 0.08, 0.09, alpha))
		draw_set_transform_matrix(Transform2D.IDENTITY)
	# dawn overlay near end
	if _dawn_progress > 0.05:
		var vp: Vector2 = get_viewport_rect().size
		var horizon_y: float = lerpf(vp.y * 0.78, vp.y * 0.48, _dawn_progress)
		draw_rect(Rect2(Vector2(0.0, horizon_y), Vector2(vp.x, vp.y - horizon_y)), Color(0.95, 0.52, 0.24, _dawn_progress * 0.2))
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.85, 0.55, _dawn_progress * 0.28))
		var sun_position := Vector2(vp.x * 0.78, horizon_y + 16.0)
		draw_circle(sun_position, 10.0 + 24.0 * _dawn_progress, Color(1.0, 0.9, 0.58, _dawn_progress * 0.9))
		for ray in range(8):
			var angle: float = float(ray) * TAU / 8.0
			draw_line(
				sun_position + Vector2.from_angle(angle) * 42.0,
				sun_position + Vector2.from_angle(angle) * (70.0 + 35.0 * _dawn_progress),
				Color(1.0, 0.82, 0.42, _dawn_progress * 0.35),
				3.0
			)
	if _flash_time > 0.0:
		var viewport_size: Vector2 = get_viewport_rect().size
		var flash_alpha: float = _flash_color.a * clampf(_flash_time / _flash_duration, 0.0, 1.0)
		draw_rect(
			Rect2(Vector2.ZERO, viewport_size),
			Color(_flash_color.r, _flash_color.g, _flash_color.b, flash_alpha)
		)
