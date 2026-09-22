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
var _presentation_state: Dictionary = {}
var _route_context: Dictionary = {
	"category": "neutral",
	"event_id": "",
	"danger": 0
}


func setup(view_size: Vector2) -> void:
	_view_size = view_size
	set_process(true)


func set_view_size(view_size: Vector2) -> void:
	_view_size = view_size
	queue_redraw()


func update_state(distance: float, light_profile: LightProfile, train_pos: Vector2) -> void:
	_distance = distance
	_light_profile = light_profile
	_train_x = train_pos.x
	_train_y = train_pos.y


func set_presentation_state(state: Dictionary) -> void:
	_presentation_state = state.duplicate(true)


func set_route_context(context: Dictionary) -> void:
	_route_context = context.duplicate(true)
	queue_redraw()


func _process(delta: float) -> void:
	_reduced_motion = bool(GameManager.get_setting("reduced_motion", false))
	if not _reduced_motion:
		_time += delta
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = _view_size
	var tension: float = clampf(float(_presentation_state.get("tension", 0.0)), 0.0, 1.0)
	var category: String = String(_route_context.get("category", "neutral"))
	var high_contrast: bool = UITheme.high_contrast()
	var corruption: Color = PresentationPalette.SHADOW_VEIL
	var top: Color = PresentationPalette.NIGHT_VOID.lerp(corruption, tension * 0.05)
	var mid: Color = PresentationPalette.COAL.lerp(corruption, tension * 0.07)
	var bottom: Color = PresentationPalette.SLATE.lerp(
		PresentationPalette.IRON,
		0.55
	).lerp(corruption, tension * 0.04)
	match category:
		"living":
			mid = mid.lerp(
				PresentationPalette.color(&"growth", high_contrast),
				0.08
			)
			bottom = bottom.lerp(PresentationPalette.BRASS, 0.035)
		"machinery":
			mid = mid.lerp(
				PresentationPalette.color(&"cold_signal", high_contrast),
				0.07
			)
			bottom = bottom.lerp(PresentationPalette.IRON, 0.12)
		"danger":
			top = top.lerp(
				PresentationPalette.color(&"shadow_veil", high_contrast),
				0.08
			)
			mid = mid.lerp(
				PresentationPalette.color(&"danger", high_contrast),
				0.055
			)
	var horizon: float = s.y * 0.68
	_draw_gradient_rect(Rect2(0, 0, s.x, horizon), top, mid)
	_draw_gradient_rect(Rect2(0, horizon, s.x, s.y - horizon), mid, bottom)

	_draw_ridge(s, 0.02, s.y * 0.55, 30, PresentationPalette.COAL, 18.0)
	_draw_route_landmarks(s)
	if category != "living":
		_draw_signal_towers(s)
	_draw_ridge(
		s,
		0.08,
		s.y * 0.63,
		24,
		PresentationPalette.SLATE.darkened(0.24),
		22.0
	)
	_draw_ridge(
		s,
		0.25,
		s.y * 0.72,
		40,
		PresentationPalette.IRON.darkened(0.38),
		14.0
	)

	var ground_y: float = minf(s.y * 0.80, _train_y + 16.0)
	draw_rect(
		Rect2(0, ground_y, s.x, s.y - ground_y),
		PresentationPalette.NIGHT_VOID
	)
	var tie_spacing: float = 40.0
	var motion_distance: float = 0.0 if _reduced_motion else _distance
	var tie_offset: float = fmod(motion_distance * 0.5, tie_spacing)
	for i in range(int(s.x / tie_spacing) + 2):
		var x: float = i * tie_spacing - tie_offset
		draw_rect(
			Rect2(x, ground_y + 14, tie_spacing * 0.55, 4),
			PresentationPalette.IRON.darkened(0.38)
		)
	draw_line(
		Vector2(0, ground_y + 10),
		Vector2(s.x, ground_y + 10),
		PresentationPalette.IRON,
		3.0
	)
	draw_line(
		Vector2(0, ground_y + 24),
		Vector2(s.x, ground_y + 24),
		PresentationPalette.BRASS.darkened(0.52),
		2.0
	)

	var lantern_offset: float = fmod(motion_distance * 0.05, 360.0)
	for i in range(4):
		var lx: float = (i * 360.0 - lantern_offset) + 100.0
		if lx > 0 and lx < s.x:
			var bob: float = 0.0 if _reduced_motion else sin(_time * 0.5 + i) * 3.0
			var lantern_pos := Vector2(lx, s.y * 0.55 + bob)
			draw_circle(
				lantern_pos,
				2.5,
				PresentationPalette.with_alpha(&"ember", 0.82)
			)
			draw_circle(
				lantern_pos,
				7.0,
				PresentationPalette.with_alpha(&"ember", 0.12)
			)

	_draw_light_cone()
	_draw_ash(s)
	if String(_route_context.get("event_id", "")) == "danger_black_rain":
		_draw_black_rain(s)


func _draw_gradient_rect(rect: Rect2, top: Color, bottom: Color) -> void:
	var steps: int = 12
	for i in range(steps):
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var col: Color = top.lerp(bottom, (t0 + t1) * 0.5)
		draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * t0, rect.size.x, rect.size.y * (t1 - t0)), col)


func _draw_ridge(s: Vector2, parallax_speed: float, base_y: float, steps: int, col: Color, amp: float) -> void:
	var offset: float = (
		0.0 if _reduced_motion else _distance * parallax_speed
	)
	var poly: PackedVector2Array = PackedVector2Array()
	poly.append(Vector2(0, s.y))
	for i in range(steps + 1):
		var x: float = s.x * float(i) / float(steps)
		var noise: float = sin((i + offset * 0.1) * 1.7) * amp + cos((i + offset * 0.1) * 2.3) * amp * 0.6
		poly.append(Vector2(x, base_y + noise))
	poly.append(Vector2(s.x, s.y))
	draw_colored_polygon(poly, col)


func _draw_signal_towers(s: Vector2) -> void:
	var motion_distance: float = 0.0 if _reduced_motion else _distance
	var offset: float = fmod(motion_distance * 0.035, s.x * 0.72)
	for i in range(3):
		var x: float = fmod(s.x * (0.18 + i * 0.41) - offset + s.x, s.x)
		var base_y: float = s.y * (0.62 + float(i % 2) * 0.035)
		var height: float = s.y * (0.17 + float(i % 2) * 0.04)
		var width: float = maxf(8.0, s.x * 0.009)
		var tower_color: Color = PresentationPalette.SLATE.darkened(0.35)
		draw_rect(
			Rect2(x - width * 0.5, base_y - height, width, height),
			tower_color
		)
		draw_line(
			Vector2(x - width * 2.2, base_y - height * 0.78),
			Vector2(x + width * 2.2, base_y - height * 0.78),
			tower_color,
			4.0
		)
		draw_line(
			Vector2(x - width * 1.65, base_y - height * 0.52),
			Vector2(x + width * 1.65, base_y - height * 0.52),
			tower_color,
			3.0
		)


func _draw_route_landmarks(s: Vector2) -> void:
	match String(_route_context.get("category", "neutral")):
		"living":
			_draw_living_landmarks(s)
		"machinery":
			_draw_machinery_landmarks(s)
		"danger":
			_draw_danger_landmarks(s)


func _landmark_offset(s: Vector2, speed: float) -> float:
	if _reduced_motion:
		return 0.0
	return fmod(_distance * speed, s.x * 0.8)


func _draw_living_landmarks(s: Vector2) -> void:
	var offset: float = _landmark_offset(s, 0.055)
	var silhouette: Color = PresentationPalette.COAL.lerp(
		PresentationPalette.color(&"growth", UITheme.high_contrast()),
		0.18
	)
	for i in range(4):
		var x: float = fmod(s.x * (0.14 + float(i) * 0.28) - offset + s.x, s.x)
		var ground: float = s.y * (0.62 + float(i % 2) * 0.035)
		var height: float = 32.0 + float((i * 13) % 24)
		draw_rect(Rect2(x - 3.0, ground - height, 6.0, height), silhouette)
		draw_circle(Vector2(x, ground - height), 15.0, silhouette)
		draw_circle(Vector2(x - 11.0, ground - height + 5.0), 10.0, silhouette)
		draw_circle(Vector2(x + 12.0, ground - height + 7.0), 11.0, silhouette)
	var house_x: float = fmod(s.x * 0.76 - offset * 0.6 + s.x, s.x)
	var house_y: float = s.y * 0.61
	draw_rect(Rect2(house_x - 26.0, house_y - 24.0, 52.0, 24.0), silhouette)
	draw_polyline(
		PackedVector2Array([
			Vector2(house_x - 28.0, house_y - 24.0),
			Vector2(house_x, house_y - 43.0),
			Vector2(house_x + 28.0, house_y - 24.0)
		]),
		PresentationPalette.color(
			&"growth",
			UITheme.high_contrast()
		).darkened(0.18),
		2.0
	)
	draw_rect(
		Rect2(house_x - 5.0, house_y - 18.0, 10.0, 12.0),
		PresentationPalette.with_alpha(&"ember", 0.52)
	)


func _draw_machinery_landmarks(s: Vector2) -> void:
	var offset: float = _landmark_offset(s, 0.072)
	var silhouette: Color = PresentationPalette.IRON.darkened(0.34)
	for i in range(3):
		var x: float = fmod(s.x * (0.24 + float(i) * 0.34) - offset + s.x, s.x)
		var base_y: float = s.y * (0.65 + float(i % 2) * 0.025)
		var wreck := Rect2(x - 34.0, base_y - 24.0, 68.0, 22.0)
		draw_rect(wreck, silhouette)
		draw_line(
			Vector2(wreck.position.x + 4.0, wreck.position.y),
			Vector2(wreck.end.x - 8.0, wreck.position.y - 12.0),
			PresentationPalette.SLATE.darkened(0.3),
			4.0
		)
		draw_circle(Vector2(x - 20.0, base_y), 8.0, PresentationPalette.NIGHT_VOID)
		draw_circle(Vector2(x + 22.0, base_y), 8.0, PresentationPalette.NIGHT_VOID)
		draw_circle(
			Vector2(x + 26.0, base_y - 13.0),
			2.0,
			PresentationPalette.with_alpha(
				&"cold_signal",
				0.56,
				UITheme.high_contrast()
			)
		)


func _draw_danger_landmarks(s: Vector2) -> void:
	var offset: float = _landmark_offset(s, 0.09)
	var points := PackedVector2Array([Vector2(0.0, s.y * 0.7)])
	for i in range(15):
		var x: float = s.x * float(i) / 14.0
		var sample: float = float(i) + offset * 0.015
		var height: float = 28.0 + (sin(sample * 2.1) * 0.5 + 0.5) * 52.0
		points.append(Vector2(x, s.y * 0.7 - height))
	points.append(Vector2(s.x, s.y))
	points.append(Vector2(0.0, s.y))
	draw_colored_polygon(
		points,
		PresentationPalette.COAL.lerp(
			PresentationPalette.color(
				&"shadow_veil",
				UITheme.high_contrast()
			),
			0.16
		)
	)


func _draw_black_rain(s: Vector2) -> void:
	var rain := PackedVector2Array()
	var drift: float = 0.0 if _reduced_motion else _time * 120.0
	for i in range(34):
		var x: float = fmod(float(i * 43) + drift, s.x + 20.0) - 10.0
		var y: float = fmod(float(i * 67) + drift * 0.48, s.y * 0.76)
		rain.append(Vector2(x, y))
		rain.append(Vector2(x - 5.0, y + 15.0))
	draw_multiline(
		rain,
		PresentationPalette.with_alpha(
			&"shadow_veil",
			0.24,
			UITheme.high_contrast()
		),
		1.0
	)


func _draw_ash(s: Vector2) -> void:
	var segments := PackedVector2Array()
	for i in range(26):
		var phase: float = float(i) * 1.731
		var drift: float = 0.0 if _reduced_motion else _time * (7.0 + float(i % 5))
		var x: float = fmod(float(i * 97) + drift, s.x + 40.0) - 20.0
		var y: float = fmod(float(i * 53) + sin(phase) * 38.0, s.y * 0.72)
		segments.append(Vector2(x, y))
		segments.append(Vector2(x + 2.0 + float(i % 3), y - 1.0))
	draw_multiline(
		segments,
		PresentationPalette.with_alpha(&"bone", 0.17),
		1.0
	)


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
	var outer := PackedVector2Array([origin, left, right])
	draw_colored_polygon(outer, Color(col.r, col.g, col.b, 0.11))
	draw_polyline(
		PackedVector2Array([left, origin, right]),
		Color(col.r, col.g, col.b, 0.2),
		1.5
	)
	var left2: Vector2 = dir.rotated(-spread * 0.5) * length * 0.85 + origin
	var right2: Vector2 = dir.rotated(spread * 0.5) * length * 0.85 + origin
	var poly2: PackedVector2Array = PackedVector2Array([origin, left2, right2])
	draw_colored_polygon(poly2, Color(col.r, col.g, col.b, 0.13))
	draw_circle(origin, 6.0, Color(col.r, col.g, col.b, 0.95))
	draw_circle(origin, 13.0, Color(col.r, col.g, col.b, 0.14))
