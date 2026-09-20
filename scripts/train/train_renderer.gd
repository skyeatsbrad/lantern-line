class_name TrainRenderer
extends Node2D
## TrainRenderer
##
## Draws the locomotive and cars in cutaway side view.
## Also draws wheel rotation, smoke, sparks, boarders on roofs, damage flicker.

const CAR_WIDTH: float = 92.0
const CAR_HEIGHT: float = 54.0
const LOCO_WIDTH: float = 112.0
const LOCO_HEIGHT: float = 62.0

var _run_state: RunState
var _time: float = 0.0
var _wheel_angle: float = 0.0
var _smoke: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _reduced_motion: bool = false
var _pos: Vector2 = Vector2(320, 460)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(run_state: RunState) -> void:
	_run_state = run_state
	set_process(true)
	_rng.seed = int(Time.get_ticks_msec())


func set_position_hint(p: Vector2) -> void:
	_pos = p


func car_screen_center(index: int) -> Vector2:
	if index < 0:
		return _pos
	return Vector2(
		_pos.x - LOCO_WIDTH * 0.5 - float(index + 1) * (CAR_WIDTH + 8.0) + CAR_WIDTH * 0.5,
		_pos.y - CAR_HEIGHT * 0.5
	)


func _process(delta: float) -> void:
	if _run_state == null:
		return
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	var scaled: float = delta * (0.0 if _run_state.is_simulation_paused() else _run_state.speed_scale)
	_time += scaled
	var speed: float = _run_state.current_speed()
	_wheel_angle += scaled * speed * 0.05
	# Spawn smoke
	if not _reduced_motion and _time * 5.0 - int(_time * 5.0) < 0.2:
		if _smoke.size() < 40 and _rng.randf() < 0.3:
			_smoke.append({"pos": Vector2(_pos.x - 30, _pos.y - 62), "vel": Vector2(-8 - _rng.randf() * 12, -20 - _rng.randf() * 20), "life": 2.0, "age": 0.0, "size": 6.0 + _rng.randf() * 8.0})
	# Update smoke
	for p in _smoke:
		p["age"] = float(p["age"]) + scaled
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * scaled
	_smoke = _smoke.filter(func(p: Dictionary) -> bool: return p["age"] < p["life"])
	# Sparks from wheels
	if not _reduced_motion and _rng.randf() < 0.4:
		if _sparks.size() < 30:
			_sparks.append({"pos": Vector2(_pos.x + 20 + _rng.randf() * 60, _pos.y + 24), "vel": Vector2(-40 - _rng.randf() * 40, -10 - _rng.randf() * 20), "life": 0.3, "age": 0.0})
	for p in _sparks:
		p["age"] = float(p["age"]) + scaled
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * scaled
		p["vel"] = Vector2(p["vel"]) + Vector2(0, 200) * scaled
	_sparks = _sparks.filter(func(p: Dictionary) -> bool: return p["age"] < p["life"])
	queue_redraw()


func _draw() -> void:
	if _run_state == null:
		return
	_draw_smoke()
	_draw_locomotive()
	var x: float = _pos.x - LOCO_WIDTH * 0.5
	for i in range(_run_state.cars.size()):
		x -= CAR_WIDTH + 8.0
		_draw_car(_run_state.cars[i], Vector2(x, _pos.y), i == _run_state.cars.size() - 1)
	_draw_sparks()


func _draw_smoke() -> void:
	for p in _smoke:
		var a: float = 1.0 - float(p["age"]) / float(p["life"])
		draw_circle(Vector2(p["pos"]), float(p["size"]) * (1.2 - a * 0.4), Color(0.4, 0.4, 0.45, a * 0.4))


func _draw_sparks() -> void:
	for p in _sparks:
		var a: float = 1.0 - float(p["age"]) / float(p["life"])
		draw_circle(Vector2(p["pos"]), 1.5, Color(1.0, 0.75, 0.35, a))


func _draw_locomotive() -> void:
	var origin: Vector2 = _pos
	var w: float = LOCO_WIDTH
	var h: float = LOCO_HEIGHT
	var hp_ratio: float = _run_state.locomotive_hp / _run_state.locomotive_max_hp
	var body_col: Color = Color(0.22, 0.19, 0.17)
	if hp_ratio < 0.35:
		body_col = body_col.lerp(Color(0.5, 0.15, 0.15), 0.5 + 0.5 * sin(_time * 8.0))
	# body
	var rect_top: Rect2 = Rect2(origin.x - w * 0.5, origin.y - h, w, h * 0.7)
	draw_rect(rect_top, body_col)
	# roof accent
	draw_rect(Rect2(rect_top.position.x, rect_top.position.y, rect_top.size.x, 6), Color(0.35, 0.25, 0.15))
	# cabin
	var cabin: Rect2 = Rect2(origin.x - w * 0.5 + 6, origin.y - h - 22, 36, 26)
	draw_rect(cabin, Color(0.18, 0.14, 0.12))
	draw_rect(Rect2(cabin.position.x + 4, cabin.position.y + 6, 12, 10), Color(0.95, 0.75, 0.35))
	# nose lamp
	var lamp_pos: Vector2 = Vector2(origin.x + w * 0.5 - 6, origin.y - h * 0.5 - 4)
	draw_circle(lamp_pos, 6.0, Color(1.0, 0.85, 0.55, 0.95))
	draw_circle(lamp_pos, 10.0, Color(1.0, 0.85, 0.55, 0.25))
	# smokestack
	draw_rect(Rect2(origin.x + w * 0.2, origin.y - h - 8, 10, 12), Color(0.16, 0.12, 0.10))
	# wheels
	_draw_wheel(Vector2(origin.x - w * 0.35, origin.y + 6), 12.0)
	_draw_wheel(Vector2(origin.x, origin.y + 8), 16.0)
	_draw_wheel(Vector2(origin.x + w * 0.35, origin.y + 6), 12.0)
	# HP bar
	_draw_bar(Vector2(origin.x - w * 0.5, origin.y - h - 34), Vector2(w, 4), hp_ratio, Color(0.9, 0.4, 0.2))


func _draw_car(car: Dictionary, pos: Vector2, is_rear: bool) -> void:
	var type_key: String = String(car["type"])
	var hp_ratio: float = float(car["hp"]) / float(car["max_hp"])
	var body_col: Color = _car_color(type_key)
	if hp_ratio < 0.3:
		body_col = body_col.lerp(Color(0.5, 0.15, 0.15), 0.5)
	# base
	draw_rect(Rect2(pos.x, pos.y - CAR_HEIGHT, CAR_WIDTH, CAR_HEIGHT * 0.75), body_col)
	# roof
	draw_rect(Rect2(pos.x, pos.y - CAR_HEIGHT, CAR_WIDTH, 5), Color(0.30, 0.24, 0.18))
	# type icon (glyph)
	_draw_car_glyph(pos, type_key)
	_draw_crew_posts(car, pos)
	_draw_power_state(car, pos)
	if float(car.get("hp", 0.0)) <= 0.0:
		draw_line(
			Vector2(pos.x + 10.0, pos.y - CAR_HEIGHT + 8.0),
			Vector2(pos.x + CAR_WIDTH - 10.0, pos.y - 18.0),
			Color(0.85, 0.22, 0.18),
			4.0
		)
		draw_line(
			Vector2(pos.x + CAR_WIDTH - 10.0, pos.y - CAR_HEIGHT + 8.0),
			Vector2(pos.x + 10.0, pos.y - 18.0),
			Color(0.85, 0.22, 0.18),
			4.0
		)
	# wheels
	_draw_wheel(Vector2(pos.x + 16, pos.y + 6), 10.0)
	_draw_wheel(Vector2(pos.x + CAR_WIDTH - 16, pos.y + 6), 10.0)
	# HP bar
	_draw_bar(Vector2(pos.x + 8, pos.y - CAR_HEIGHT - 8), Vector2(CAR_WIDTH - 16, 3), hp_ratio, Color(0.85, 0.75, 0.35))
	# rear indicator
	if is_rear:
		draw_line(Vector2(pos.x + 4, pos.y - CAR_HEIGHT - 14), Vector2(pos.x + CAR_WIDTH - 4, pos.y - CAR_HEIGHT - 14), Color(0.8, 0.3, 0.3), 2.0)
	# coupling
	draw_line(Vector2(pos.x + CAR_WIDTH, pos.y - 10), Vector2(pos.x + CAR_WIDTH + 8, pos.y - 10), Color(0.3, 0.25, 0.2), 3.0)
	# boarders on roof
	var boarders: int = int(car.get("boarders", 0))
	for i in range(min(boarders, 3)):
		var bx: float = pos.x + 20 + i * 20
		var by: float = pos.y - CAR_HEIGHT - 8
		draw_circle(Vector2(bx, by), 3.0, Color(0.85, 0.55, 0.2))


func _draw_crew_posts(car: Dictionary, pos: Vector2) -> void:
	var occupants: Array = _run_state.active_crew_for_car(String(car.get("id", "")))
	for index in range(occupants.size()):
		var member: Dictionary = occupants[index]
		var center := Vector2(pos.x + 12.0 + index * 17.0, pos.y - 17.0)
		draw_circle(center, 6.0, Color(0.12, 0.12, 0.14, 0.95))
		draw_circle(center, 5.0, Color(0.88, 0.7, 0.38, 0.9))
		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-3.0, 3.0),
			String(member.get("name", "?")).left(1),
			HORIZONTAL_ALIGNMENT_LEFT,
			8.0,
			8,
			Color(0.1, 0.08, 0.06)
		)


func _draw_power_state(car: Dictionary, pos: Vector2) -> void:
	var state: String = _run_state.car_power_state(car)
	if state == "offline" or state == "destroyed":
		draw_rect(
			Rect2(pos.x, pos.y - CAR_HEIGHT, CAR_WIDTH, CAR_HEIGHT * 0.75),
			Color(0.02, 0.02, 0.03, 0.58)
		)
	elif state == "throttled":
		for stripe in range(4):
			var x: float = pos.x + 8.0 + stripe * 22.0
			draw_line(
				Vector2(x, pos.y - CAR_HEIGHT + 4.0),
				Vector2(x - 14.0, pos.y - 17.0),
				Color(0.95, 0.58, 0.18, 0.5),
				2.0
			)
	if state == "active" or state == "passive" or state == "producing":
		return
	var badge_text: String = {
		"throttled": "LOW",
		"offline": "OFF",
		"standby": "STBY",
		"destroyed": "DEST"
	}.get(state, state.to_upper())
	draw_rect(
		Rect2(pos.x + CAR_WIDTH - 34.0, pos.y - CAR_HEIGHT + 7.0, 29.0, 13.0),
		Color(0.06, 0.06, 0.07, 0.9)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(pos.x + CAR_WIDTH - 32.0, pos.y - CAR_HEIGHT + 17.0),
		badge_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		27.0,
		9,
		Color(1.0, 0.78, 0.42)
	)


func _draw_car_glyph(pos: Vector2, type_key: String) -> void:
	var cx: float = pos.x + CAR_WIDTH * 0.5
	var cy: float = pos.y - CAR_HEIGHT * 0.5
	match type_key:
		"Battery":
			draw_rect(Rect2(cx - 10, cy - 6, 20, 12), Color(0.95, 0.85, 0.3))
			draw_rect(Rect2(cx - 4, cy - 10, 8, 4), Color(0.95, 0.85, 0.3))
		"Workshop":
			draw_line(Vector2(cx - 10, cy + 8), Vector2(cx + 10, cy - 10), Color(0.9, 0.75, 0.5), 2)
			draw_line(Vector2(cx - 10, cy - 10), Vector2(cx + 10, cy + 8), Color(0.9, 0.75, 0.5), 2)
		"Passenger":
			for i in range(3):
				draw_rect(Rect2(cx - 12 + i * 9, cy - 6, 6, 8), Color(0.95, 0.75, 0.4))
		"Greenhouse":
			draw_circle(Vector2(cx, cy + 4), 8, Color(0.35, 0.55, 0.3))
			draw_line(Vector2(cx, cy - 6), Vector2(cx, cy + 4), Color(0.35, 0.55, 0.3), 2)
		"Defense":
			draw_rect(Rect2(cx - 3, cy - 12, 6, 8), Color(0.6, 0.6, 0.65))
			draw_line(Vector2(cx, cy - 12), Vector2(cx + 14, cy - 12), Color(0.6, 0.6, 0.65), 3)
		"Utility":
			draw_rect(Rect2(cx - 12, cy - 2, 24, 4), Color(0.5, 0.4, 0.3))


func _car_color(type_key: String) -> Color:
	match type_key:
		"Battery":
			return Color(0.18, 0.16, 0.25)
		"Workshop":
			return Color(0.24, 0.18, 0.12)
		"Passenger":
			return Color(0.16, 0.18, 0.22)
		"Greenhouse":
			return Color(0.14, 0.22, 0.16)
		"Defense":
			return Color(0.22, 0.20, 0.18)
		_:
			return Color(0.20, 0.18, 0.16)


func _draw_wheel(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color(0.05, 0.05, 0.06))
	draw_arc(center, radius - 1, 0, TAU, 24, Color(0.35, 0.3, 0.25), 2.0)
	# spokes
	for i in range(4):
		var a: float = _wheel_angle + i * PI * 0.5
		var end: Vector2 = center + Vector2(cos(a), sin(a)) * (radius - 2)
		draw_line(center, end, Color(0.35, 0.3, 0.25), 1.5)


func _draw_bar(pos: Vector2, size: Vector2, ratio: float, col: Color) -> void:
	draw_rect(Rect2(pos, size), Color(0.08, 0.08, 0.08))
	draw_rect(Rect2(pos, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), col)
