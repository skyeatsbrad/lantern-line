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
var _damage_flashes: Dictionary = {}
var _reduced_motion: bool = false
var _pos: Vector2 = Vector2(320, 460)
var _visual_scale: float = 1.0
var _presentation_state: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(run_state: RunState) -> void:
	_run_state = run_state
	set_process(true)
	_rng.seed = int(_run_state.run_seed) ^ 0x1A17E2


func set_position_hint(p: Vector2) -> void:
	set_layout(p, _visual_scale)


func set_layout(p: Vector2, visual_scale: float) -> void:
	_visual_scale = clampf(visual_scale, 0.6, 1.0)
	scale = Vector2.ONE * _visual_scale
	_pos = p / _visual_scale
	queue_redraw()


func visual_scale() -> float:
	return _visual_scale


func set_presentation_state(state: Dictionary) -> void:
	_presentation_state = state.duplicate(true)


func car_screen_center(index: int) -> Vector2:
	if index < 0:
		return _pos * _visual_scale
	var local_center := Vector2(
		_pos.x - LOCO_WIDTH * 0.5 - float(index + 1) * (CAR_WIDTH + 8.0) + CAR_WIDTH * 0.5,
		_pos.y - CAR_HEIGHT * 0.5
	)
	return local_center * _visual_scale


func car_screen_center_by_id(car_id: String) -> Vector2:
	for index in range(_run_state.cars.size()):
		if String(_run_state.cars[index].get("id", "")) == car_id:
			return car_screen_center(index)
	return _pos


func flash_car(car_id: String, duration: float = 0.5) -> void:
	if car_id.is_empty():
		return
	_damage_flashes[car_id] = maxf(
		float(_damage_flashes.get(car_id, 0.0)),
		duration
	)


func _process(delta: float) -> void:
	if _run_state == null:
		return
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	var scaled: float = (
		0.0
		if _run_state.is_simulation_paused()
		else delta * _run_state.effective_speed_scale()
	)
	var visual_scaled: float = 0.0 if _reduced_motion else scaled
	for car_id_variant in _damage_flashes.keys():
		var car_id: String = String(car_id_variant)
		var remaining: float = maxf(0.0, float(_damage_flashes[car_id]) - delta)
		if remaining <= 0.0:
			_damage_flashes.erase(car_id)
		else:
			_damage_flashes[car_id] = remaining
	_time += visual_scaled
	var speed: float = _run_state.current_speed()
	_wheel_angle += visual_scaled * speed * 0.05
	if _reduced_motion:
		_smoke.clear()
		_sparks.clear()
	# Spawn smoke
	if not _reduced_motion and _time * 5.0 - int(_time * 5.0) < 0.2:
		if _smoke.size() < 40 and _rng.randf() < 0.3:
			_smoke.append({"pos": Vector2(_pos.x - 30, _pos.y - 62), "vel": Vector2(-8 - _rng.randf() * 12, -20 - _rng.randf() * 20), "life": 2.0, "age": 0.0, "size": 6.0 + _rng.randf() * 8.0})
	# Update smoke
	for p in _smoke:
		p["age"] = float(p["age"]) + visual_scaled
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * visual_scaled
	_smoke = _smoke.filter(func(p: Dictionary) -> bool: return p["age"] < p["life"])
	# Sparks from wheels
	if not _reduced_motion and _rng.randf() < 0.4:
		if _sparks.size() < 30:
			_sparks.append({"pos": Vector2(_pos.x + 20 + _rng.randf() * 60, _pos.y + 24), "vel": Vector2(-40 - _rng.randf() * 40, -10 - _rng.randf() * 20), "life": 0.3, "age": 0.0})
	for p in _sparks:
		p["age"] = float(p["age"]) + visual_scaled
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * visual_scaled
		p["vel"] = Vector2(p["vel"]) + Vector2(0, 200) * visual_scaled
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
		var radius: float = float(p["size"]) * (1.2 - a * 0.4)
		draw_circle(
			Vector2(p["pos"]),
			radius + 2.0,
			PresentationPalette.with_alpha(&"night_void", a * 0.32)
		)
		draw_circle(
			Vector2(p["pos"]),
			radius,
			PresentationPalette.with_alpha(&"slate", a * 0.26)
		)


func _draw_sparks() -> void:
	for p in _sparks:
		var a: float = 1.0 - float(p["age"]) / float(p["life"])
		var spark_pos: Vector2 = p["pos"]
		var spark_vel: Vector2 = Vector2(p["vel"]).normalized()
		draw_line(
			spark_pos,
			spark_pos - spark_vel * 7.0,
			PresentationPalette.with_alpha(&"ember", a),
			1.8
		)


func _draw_locomotive() -> void:
	var origin: Vector2 = _pos
	var w: float = LOCO_WIDTH
	var h: float = LOCO_HEIGHT
	var hp_ratio: float = _run_state.locomotive_hp / _run_state.locomotive_max_hp
	var body_col: Color = PresentationPalette.COAL.lerp(PresentationPalette.IRON, 0.42)
	if hp_ratio < 0.35:
		var pulse: float = 0.65 if _reduced_motion else 0.5 + 0.5 * sin(_time * 8.0)
		body_col = body_col.lerp(PresentationPalette.DANGER, pulse * 0.46)

	var body_rect := Rect2(origin.x - w * 0.5, origin.y - h, w, h * 0.7)
	draw_rect(body_rect, body_col)
	draw_rect(body_rect, PresentationPalette.BRASS.darkened(0.28), false, 2.0)
	draw_rect(
		Rect2(body_rect.position.x, body_rect.position.y, body_rect.size.x, 6),
		PresentationPalette.BRASS.darkened(0.38)
	)
	var boiler_rect := Rect2(origin.x - 2.0, origin.y - h + 12.0, w * 0.53, 29.0)
	draw_rect(boiler_rect, PresentationPalette.SLATE.darkened(0.18))
	draw_rect(boiler_rect, PresentationPalette.IRON, false, 2.0)
	draw_circle(
		Vector2(boiler_rect.end.x, boiler_rect.get_center().y),
		boiler_rect.size.y * 0.5,
		PresentationPalette.IRON.darkened(0.22)
	)
	draw_arc(
		Vector2(boiler_rect.end.x, boiler_rect.get_center().y),
		boiler_rect.size.y * 0.5,
		-PI * 0.5,
		PI * 0.5,
		14,
		PresentationPalette.BRASS.darkened(0.3),
		2.0
	)
	var cabin := Rect2(origin.x - w * 0.5 + 5.0, origin.y - h - 23.0, 38.0, 47.0)
	draw_rect(cabin, PresentationPalette.COAL)
	draw_rect(cabin, PresentationPalette.BRASS.darkened(0.32), false, 2.5)
	draw_line(
		Vector2(cabin.position.x - 3.0, cabin.position.y),
		Vector2(cabin.end.x + 4.0, cabin.position.y),
		PresentationPalette.BRASS,
		3.0
	)
	var window := Rect2(cabin.position.x + 7.0, cabin.position.y + 9.0, 15.0, 13.0)
	draw_rect(window, PresentationPalette.EMBER)
	draw_rect(window, PresentationPalette.BONE, false, 1.5)
	draw_rect(
		Rect2(cabin.position.x + 26.0, cabin.position.y + 9.0, 6.0, 27.0),
		PresentationPalette.SLATE
	)

	var lamp_pos: Vector2 = Vector2(origin.x + w * 0.5 - 6, origin.y - h * 0.5 - 4)
	draw_circle(lamp_pos, 12.0, PresentationPalette.with_alpha(&"ember", 0.16))
	draw_circle(lamp_pos, 6.5, PresentationPalette.BONE)
	draw_circle(lamp_pos, 3.5, PresentationPalette.EMBER)

	var stack_x: float = origin.x + w * 0.18
	draw_rect(
		Rect2(stack_x, origin.y - h - 15.0, 12.0, 26.0),
		PresentationPalette.COAL
	)
	draw_rect(
		Rect2(stack_x - 4.0, origin.y - h - 18.0, 20.0, 5.0),
		PresentationPalette.IRON
	)
	draw_line(
		Vector2(stack_x - 1.0, origin.y - h - 12.0),
		Vector2(stack_x + 13.0, origin.y - h - 12.0),
		PresentationPalette.BRASS.darkened(0.3),
		2.0
	)

	for rivet in range(6):
		draw_circle(
			Vector2(body_rect.position.x + 12.0 + rivet * 17.0, body_rect.end.y - 7.0),
			1.7,
			PresentationPalette.BRASS.darkened(0.25)
		)

	var wheel_left := Vector2(origin.x - w * 0.35, origin.y + 6)
	var wheel_center := Vector2(origin.x, origin.y + 8)
	var wheel_right := Vector2(origin.x + w * 0.35, origin.y + 6)
	_draw_wheel(wheel_left, 12.0)
	_draw_wheel(wheel_center, 16.0)
	_draw_wheel(wheel_right, 12.0)
	draw_line(wheel_left, wheel_center, PresentationPalette.BRASS.darkened(0.22), 3.0)
	draw_line(wheel_center, wheel_right, PresentationPalette.BRASS.darkened(0.22), 3.0)
	for tooth in range(4):
		var tooth_x: float = origin.x + w * 0.5 + float(tooth) * 7.0
		draw_line(
			Vector2(origin.x + w * 0.5 - 1.0, origin.y - 8.0),
			Vector2(tooth_x + 12.0, origin.y + 11.0),
			PresentationPalette.IRON,
			2.0
		)

	_draw_bar(
		Vector2(origin.x - w * 0.5, origin.y - h - 36),
		Vector2(w, 4),
		hp_ratio,
		PresentationPalette.DANGER
	)


func _draw_car(car: Dictionary, pos: Vector2, is_rear: bool) -> void:
	var type_key: String = String(car["type"])
	var car_id: String = String(car.get("id", ""))
	var hp_ratio: float = float(car["hp"]) / float(car["max_hp"])
	var body_col: Color = _car_color(type_key)
	if hp_ratio < 0.3:
		body_col = body_col.lerp(PresentationPalette.DANGER, 0.42)
	var body_rect := Rect2(pos.x, pos.y - CAR_HEIGHT, CAR_WIDTH, CAR_HEIGHT * 0.75)
	draw_rect(body_rect, body_col)
	draw_rect(
		body_rect,
		PresentationPalette.BRASS.darkened(0.42),
		false,
		2.0
	)
	draw_rect(
		Rect2(pos.x, pos.y - CAR_HEIGHT, CAR_WIDTH, 5),
		PresentationPalette.IRON
	)
	draw_line(
		Vector2(pos.x + 3.0, pos.y - CAR_HEIGHT - 1.0),
		Vector2(pos.x + CAR_WIDTH - 3.0, pos.y - CAR_HEIGHT - 1.0),
		PresentationPalette.BRASS.darkened(0.18),
		2.0
	)
	draw_rect(
		Rect2(pos.x + 5.0, pos.y - 13.0, CAR_WIDTH - 10.0, 6.0),
		PresentationPalette.NIGHT_VOID
	)
	for rivet in range(5):
		draw_circle(
			Vector2(pos.x + 11.0 + rivet * 17.5, pos.y - 9.5),
			1.4,
			PresentationPalette.BRASS.darkened(0.34)
		)
	if float(_damage_flashes.get(car_id, 0.0)) > 0.0:
		var flash_alpha: float = clampf(float(_damage_flashes[car_id]) * 2.0, 0.0, 0.8)
		if bool(GameManager.get_setting("reduced_flashes", false)):
			flash_alpha = minf(flash_alpha, 0.24)
		draw_rect(
			Rect2(pos.x - 3.0, pos.y - CAR_HEIGHT - 3.0, CAR_WIDTH + 6.0, CAR_HEIGHT + 10.0),
			PresentationPalette.with_alpha(&"danger", flash_alpha),
			false,
			4.0
		)
	if hp_ratio > 0.0 and hp_ratio <= 0.3:
		var warning_alpha: float = (
			0.82
			if bool(GameManager.get_setting("reduced_flashes", false))
			else 0.55 + sin(_time * 8.0) * 0.35
		)
		draw_rect(
			Rect2(pos.x - 2.0, pos.y - CAR_HEIGHT - 2.0, CAR_WIDTH + 4.0, CAR_HEIGHT + 8.0),
			PresentationPalette.with_alpha(&"danger", warning_alpha),
			false,
			3.0
		)
		draw_string(
			UITheme.bold_font(),
			Vector2(pos.x + 17.0, pos.y - CAR_HEIGHT - 13.0),
			"CRITICAL",
			HORIZONTAL_ALIGNMENT_LEFT,
			64.0,
			UITheme.font_size(10),
			PresentationPalette.color(&"ember", UITheme.high_contrast())
		)
	_draw_car_details(car, pos)
	_draw_crew_posts(car, pos)
	_draw_damage_wear(pos, hp_ratio)
	_draw_power_state(car, pos)
	if float(car.get("hp", 0.0)) <= 0.0:
		draw_line(
			Vector2(pos.x + 10.0, pos.y - CAR_HEIGHT + 8.0),
			Vector2(pos.x + CAR_WIDTH - 10.0, pos.y - 18.0),
			PresentationPalette.DANGER,
			4.0
		)
		draw_line(
			Vector2(pos.x + CAR_WIDTH - 10.0, pos.y - CAR_HEIGHT + 8.0),
			Vector2(pos.x + 10.0, pos.y - 18.0),
			PresentationPalette.DANGER,
			4.0
		)
	# wheels
	_draw_wheel(Vector2(pos.x + 16, pos.y + 6), 10.0)
	_draw_wheel(Vector2(pos.x + CAR_WIDTH - 16, pos.y + 6), 10.0)
	# HP bar
	_draw_bar(
		Vector2(pos.x + 8, pos.y - CAR_HEIGHT - 8),
		Vector2(CAR_WIDTH - 16, 3),
		hp_ratio,
		PresentationPalette.BRASS
	)
	# rear indicator
	if is_rear:
		draw_line(
			Vector2(pos.x + 4, pos.y - CAR_HEIGHT - 14),
			Vector2(pos.x + CAR_WIDTH - 4, pos.y - CAR_HEIGHT - 14),
			PresentationPalette.DANGER,
			2.0
		)
	# coupling
	draw_line(
		Vector2(pos.x + CAR_WIDTH, pos.y - 10),
		Vector2(pos.x + CAR_WIDTH + 8, pos.y - 10),
		PresentationPalette.IRON,
		3.0
	)
	# boarders on roof
	var boarders: int = int(car.get("boarders", 0))
	for i in range(min(boarders, 3)):
		var bx: float = pos.x + 20 + i * 20
		var by: float = pos.y - CAR_HEIGHT - 8
		draw_circle(Vector2(bx, by), 3.0, PresentationPalette.EMBER)


func _draw_crew_posts(car: Dictionary, pos: Vector2) -> void:
	var occupants: Array = _run_state.active_crew_for_car(String(car.get("id", "")))
	for index in range(occupants.size()):
		var member: Dictionary = occupants[index]
		var center := Vector2(pos.x + 12.0 + index * 17.0, pos.y - 17.0)
		draw_circle(center, 6.0, PresentationPalette.with_alpha(&"night_void", 0.95))
		draw_circle(center, 5.0, PresentationPalette.with_alpha(&"brass", 0.9))
		draw_string(
			UITheme.body_font(),
			center + Vector2(-3.0, 3.0),
			String(member.get("name", "?")).left(1),
			HORIZONTAL_ALIGNMENT_LEFT,
			8.0,
			8,
			PresentationPalette.NIGHT_VOID
		)


func _draw_power_state(car: Dictionary, pos: Vector2) -> void:
	var state: String = _run_state.car_power_state(car)
	if state == "offline" or state == "destroyed":
		draw_rect(
			Rect2(pos.x, pos.y - CAR_HEIGHT, CAR_WIDTH, CAR_HEIGHT * 0.75),
			PresentationPalette.with_alpha(&"night_void", 0.58)
		)
	elif state == "throttled":
		for stripe in range(4):
			var x: float = pos.x + 8.0 + stripe * 22.0
			draw_line(
				Vector2(x, pos.y - CAR_HEIGHT + 4.0),
				Vector2(x - 14.0, pos.y - 17.0),
				PresentationPalette.with_alpha(&"ember", 0.5),
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
	var badge_font_size: int = UITheme.font_size(9)
	var badge_width: float = 40.0 if UITheme.effective_text_scale() > 1.0 else 31.0
	draw_rect(
		Rect2(
			pos.x + CAR_WIDTH - badge_width - 5.0,
			pos.y - CAR_HEIGHT + 7.0,
			badge_width,
			15.0
		),
		PresentationPalette.with_alpha(&"night_void", 0.9)
	)
	draw_string(
		UITheme.bold_font(),
		Vector2(
			pos.x + CAR_WIDTH - badge_width - 2.0,
			pos.y - CAR_HEIGHT + 19.0
		),
		badge_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		badge_width - 4.0,
		badge_font_size,
		PresentationPalette.color(&"ember", UITheme.high_contrast())
	)


func _draw_car_details(car: Dictionary, pos: Vector2) -> void:
	var type_key: String = String(car.get("type", "Utility"))
	var upgrade: String = String(car.get("upgrade", ""))
	var cx: float = pos.x + CAR_WIDTH * 0.5
	var cy: float = pos.y - CAR_HEIGHT * 0.5
	match type_key:
		"Battery":
			var cells: int = 4 if upgrade == "deep_cells" else 3
			for i in range(cells):
				var cell_x: float = pos.x + 13.0 + float(i) * 17.0
				draw_rect(
					Rect2(cell_x, cy - 9.0, 11.0, 19.0),
					PresentationPalette.BRASS.darkened(0.24)
				)
				draw_line(
					Vector2(cell_x + 3.0, cy - 4.0),
					Vector2(cell_x + 8.0, cy - 4.0),
					PresentationPalette.BONE,
					1.5
				)
			draw_line(
				Vector2(pos.x + 10.0, cy - 13.0),
				Vector2(pos.x + CAR_WIDTH - 10.0, cy - 13.0),
				PresentationPalette.BRASS,
				2.0
			)
			if upgrade == "arc_reserve":
				draw_arc(
					Vector2(cx, cy),
					15.0,
					-PI * 0.8,
					PI * 0.8,
					16,
					PresentationPalette.SHADOW_VEIL,
					3.0
				)
				draw_circle(Vector2(cx, cy), 3.0, PresentationPalette.COLD_SIGNAL)
		"Workshop":
			draw_rect(
				Rect2(pos.x + 10.0, cy - 10.0, 21.0, 20.0),
				PresentationPalette.COAL
			)
			draw_rect(
				Rect2(pos.x + 15.0, cy - 4.0, 11.0, 9.0),
				PresentationPalette.EMBER.darkened(0.12)
			)
			draw_line(
				Vector2(cx - 4.0, cy + 10.0),
				Vector2(cx + 17.0, cy - 10.0),
				PresentationPalette.BRASS,
				2.5
			)
			draw_line(
				Vector2(cx + 1.0, cy - 9.0),
				Vector2(cx + 18.0, cy + 9.0),
				PresentationPalette.BRASS,
				2.5
			)
			if upgrade == "field_foundry":
				draw_rect(
					Rect2(pos.x + 17.0, pos.y - CAR_HEIGHT - 15.0, 9.0, 16.0),
					PresentationPalette.IRON
				)
				draw_line(
					Vector2(pos.x + 14.0, pos.y - CAR_HEIGHT - 15.0),
					Vector2(pos.x + 29.0, pos.y - CAR_HEIGHT - 15.0),
					PresentationPalette.BRASS,
					2.0
				)
			elif upgrade == "salvage_rig":
				draw_line(
					Vector2(pos.x + 64.0, cy + 9.0),
					Vector2(pos.x + 67.0, pos.y - CAR_HEIGHT - 17.0),
					PresentationPalette.IRON,
					4.0
				)
				draw_line(
					Vector2(pos.x + 67.0, pos.y - CAR_HEIGHT - 17.0),
					Vector2(pos.x + 84.0, pos.y - CAR_HEIGHT - 7.0),
					PresentationPalette.BRASS,
					3.0
				)
				draw_line(
					Vector2(pos.x + 84.0, pos.y - CAR_HEIGHT - 7.0),
					Vector2(pos.x + 84.0, cy + 4.0),
					PresentationPalette.BRASS,
					1.5
				)
		"Passenger":
			for i in range(3):
				var window_x: float = pos.x + 11.0 + float(i) * 22.0
				draw_rect(
					Rect2(window_x, cy - 11.0, 13.0, 14.0),
					PresentationPalette.EMBER.darkened(0.08)
				)
				draw_rect(
					Rect2(window_x, cy - 11.0, 13.0, 14.0),
					PresentationPalette.BRASS,
					false,
					1.0
				)
			draw_rect(
				Rect2(pos.x + 76.0, cy - 13.0, 8.0, 25.0),
				PresentationPalette.IRON.darkened(0.15)
			)
			if upgrade == "ration_lockers":
				for i in range(3):
					draw_rect(
						Rect2(pos.x + 12.0 + float(i) * 20.0, cy + 6.0, 15.0, 7.0),
						PresentationPalette.BRASS.darkened(0.32)
					)
			elif upgrade == "safe_quarters":
				draw_arc(
					Vector2(pos.x + 79.0, cy),
					9.0,
					PI,
					TAU,
					10,
					PresentationPalette.BONE,
					2.0
				)
				draw_line(
					Vector2(pos.x + 70.0, cy),
					Vector2(pos.x + 79.0, cy + 11.0),
					PresentationPalette.BONE,
					2.0
				)
				draw_line(
					Vector2(pos.x + 88.0, cy),
					Vector2(pos.x + 79.0, cy + 11.0),
					PresentationPalette.BONE,
					2.0
				)
		"Greenhouse":
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(pos.x + 9.0, cy + 9.0),
					Vector2(pos.x + 20.0, cy - 14.0),
					Vector2(pos.x + 72.0, cy - 14.0),
					Vector2(pos.x + 83.0, cy + 9.0)
				]),
				PresentationPalette.with_alpha(&"growth", 0.2)
			)
			for i in range(4):
				var frame_x: float = pos.x + 20.0 + float(i) * 17.0
				draw_line(
					Vector2(frame_x, cy - 14.0),
					Vector2(frame_x - 8.0, cy + 9.0),
					PresentationPalette.GROWTH,
					1.5
				)
			for i in range(3):
				var plant_x: float = pos.x + 28.0 + float(i) * 18.0
				draw_line(
					Vector2(plant_x, cy + 10.0),
					Vector2(plant_x, cy - 2.0 - float(i % 2) * 4.0),
					PresentationPalette.GROWTH,
					2.0
				)
				draw_circle(
					Vector2(plant_x - 3.0, cy - 1.0),
					3.5,
					PresentationPalette.GROWTH
				)
			if upgrade == "hydroponics":
				draw_line(
					Vector2(pos.x + 12.0, cy + 12.0),
					Vector2(pos.x + 80.0, cy + 12.0),
					PresentationPalette.COLD_SIGNAL,
					3.0
				)
			elif upgrade == "glowbeds":
				for i in range(4):
					draw_circle(
						Vector2(pos.x + 18.0 + float(i) * 19.0, cy + 10.0),
						4.0,
						PresentationPalette.with_alpha(&"cold_signal", 0.68)
					)
		"Defense":
			draw_rect(
				Rect2(cx - 13.0, cy - 7.0, 26.0, 15.0),
				PresentationPalette.IRON
			)
			draw_circle(Vector2(cx, cy - 8.0), 7.0, PresentationPalette.BRASS)
			if upgrade == "heavy_cannon":
				draw_line(
					Vector2(cx, cy - 10.0),
					Vector2(cx + 31.0, cy - 15.0),
					PresentationPalette.BONE,
					5.0
				)
			elif upgrade == "flak_array":
				for i in range(3):
					draw_line(
						Vector2(cx - 4.0 + float(i) * 4.0, cy - 10.0),
						Vector2(cx + 20.0, cy - 22.0 + float(i) * 6.0),
						PresentationPalette.BONE,
						2.5
					)
			else:
				draw_line(
					Vector2(cx, cy - 10.0),
					Vector2(cx + 21.0, cy - 12.0),
					PresentationPalette.BONE,
					3.0
				)
		"Utility":
			draw_rect(
				Rect2(pos.x + 8.0, cy + 4.0, CAR_WIDTH - 16.0, 6.0),
				PresentationPalette.IRON
			)
			if upgrade == "plated_bulkhead":
				draw_rect(
					Rect2(pos.x + 61.0, pos.y - CAR_HEIGHT + 5.0, 23.0, 33.0),
					PresentationPalette.SLATE
				)
				for i in range(3):
					draw_circle(
						Vector2(pos.x + 67.0 + float(i) * 6.0, cy),
						1.5,
						PresentationPalette.BRASS
					)
			elif upgrade == "breakaway_coupling":
				draw_line(
					Vector2(pos.x + 60.0, cy),
					Vector2(pos.x + 81.0, cy),
					PresentationPalette.EMBER,
					4.0
				)
				draw_line(
					Vector2(pos.x + 72.0, cy - 6.0),
					Vector2(pos.x + 81.0, cy),
					PresentationPalette.EMBER,
					2.0
				)
				draw_line(
					Vector2(pos.x + 72.0, cy + 6.0),
					Vector2(pos.x + 81.0, cy),
					PresentationPalette.EMBER,
					2.0
				)
	if not upgrade.is_empty():
		var upgrade_font_size: int = UITheme.font_size(9)
		var upgrade_width: float = 23.0 if UITheme.effective_text_scale() > 1.0 else 19.0
		draw_rect(
			Rect2(
				pos.x + 4.0,
				pos.y - CAR_HEIGHT + 5.0,
				upgrade_width,
				15.0
			),
			PresentationPalette.with_alpha(&"night_void", 0.88)
		)
		draw_string(
			UITheme.bold_font(),
			Vector2(pos.x + 7.0, pos.y - CAR_HEIGHT + 17.0),
			"UP",
			HORIZONTAL_ALIGNMENT_LEFT,
			upgrade_width - 6.0,
			upgrade_font_size,
			PresentationPalette.color(&"brass", UITheme.high_contrast())
		)


func _draw_damage_wear(pos: Vector2, hp_ratio: float) -> void:
	if hp_ratio >= 0.75:
		return
	var alpha: float = clampf((0.75 - hp_ratio) / 0.75, 0.15, 0.65)
	var wear_color: Color = PresentationPalette.with_alpha(
		&"bone",
		0.22 + alpha * 0.38
	)
	draw_line(
		Vector2(pos.x + 31.0, pos.y - CAR_HEIGHT + 9.0),
		Vector2(pos.x + 24.0, pos.y - 22.0),
		wear_color,
		2.0
	)
	draw_line(
		Vector2(pos.x + 31.0, pos.y - CAR_HEIGHT + 9.0),
		Vector2(pos.x + 39.0, pos.y - 28.0),
		wear_color,
		2.0
	)
	if hp_ratio < 0.45:
		draw_line(
			Vector2(pos.x + 58.0, pos.y - CAR_HEIGHT + 6.0),
			Vector2(pos.x + 70.0, pos.y - 18.0),
			wear_color,
			3.0
		)
		draw_rect(
			Rect2(pos.x + 5.0, pos.y - 18.0, CAR_WIDTH - 10.0, 5.0),
			PresentationPalette.with_alpha(&"coal", alpha * 0.7)
		)


func _car_color(type_key: String) -> Color:
	match type_key:
		"Battery":
			return PresentationPalette.COAL.lerp(PresentationPalette.SHADOW_VEIL, 0.18)
		"Workshop":
			return PresentationPalette.COAL.lerp(PresentationPalette.BRASS, 0.14)
		"Passenger":
			return PresentationPalette.SLATE.darkened(0.2)
		"Greenhouse":
			return PresentationPalette.COAL.lerp(PresentationPalette.GROWTH, 0.2)
		"Defense":
			return PresentationPalette.IRON.darkened(0.28)
		_:
			return PresentationPalette.COAL.lerp(PresentationPalette.IRON, 0.25)


func _draw_wheel(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, PresentationPalette.NIGHT_VOID)
	draw_arc(
		center,
		radius - 1,
		0,
		TAU,
		24,
		PresentationPalette.BRASS.darkened(0.42),
		2.0
	)
	# spokes
	for i in range(4):
		var a: float = _wheel_angle + i * PI * 0.5
		var end: Vector2 = center + Vector2(cos(a), sin(a)) * (radius - 2)
		draw_line(center, end, PresentationPalette.IRON, 1.5)


func _draw_bar(pos: Vector2, size: Vector2, ratio: float, col: Color) -> void:
	draw_rect(Rect2(pos, size), PresentationPalette.NIGHT_VOID)
	draw_rect(Rect2(pos, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), col)
