class_name RouteProjection
extends Node2D
## World-space route fork revealed by the headlight.

var _choices: Array = []
var _selected_index: int = 1
var _view_size: Vector2 = Vector2(1280.0, 720.0)
var _train_pos: Vector2 = Vector2(360.0, 500.0)
var _train_scale: float = 1.0
var _safe_bottom: float = 560.0


func setup(
	view_size: Vector2,
	train_pos: Vector2,
	train_scale: float = 1.0
) -> void:
	_view_size = view_size
	_train_pos = train_pos
	_train_scale = train_scale
	_safe_bottom = UITheme.gameplay_safe_bottom(view_size)
	visible = false
	if not GameManager.settings_changed.is_connected(_on_settings_changed):
		GameManager.settings_changed.connect(_on_settings_changed)


func set_world_layout(
	view_size: Vector2,
	train_pos: Vector2,
	train_scale: float
) -> void:
	_view_size = view_size
	_train_pos = train_pos
	_train_scale = train_scale
	_safe_bottom = UITheme.gameplay_safe_bottom(view_size)
	queue_redraw()


func _on_settings_changed() -> void:
	queue_redraw()


func present(choices: Array, selected_index: int = 1) -> void:
	_choices = choices.duplicate(true)
	_selected_index = clampi(selected_index, 0, maxi(0, _choices.size() - 1))
	visible = true
	queue_redraw()


func hide_routes() -> void:
	visible = false
	_choices.clear()
	queue_redraw()


func set_selected_index(index: int) -> void:
	var next_index := clampi(index, 0, maxi(0, _choices.size() - 1))
	if next_index == _selected_index:
		return
	_selected_index = next_index
	queue_redraw()


func index_for_cursor_y(cursor_y: float) -> int:
	if _choices.is_empty():
		return 1
	var closest_index: int = 0
	var closest_distance: float = INF
	for index in range(_choices.size()):
		var distance: float = absf(cursor_y - endpoint_for_index(index).y)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	return closest_index


func endpoint_for_index(index: int) -> Vector2:
	var top: float = maxf(96.0, _view_size.y * 0.22)
	var bottom: float = maxf(top + 96.0, _safe_bottom - 34.0)
	var positions: Array[float] = [0.05, 0.5, 0.95]
	var safe_index := clampi(index, 0, positions.size() - 1)
	return Vector2(
		_view_size.x * 0.76,
		lerpf(top, bottom, positions[safe_index])
	)


func _draw() -> void:
	if _choices.is_empty():
		return
	var start := _train_pos + Vector2(92.0, 12.0) * _train_scale
	var fork := Vector2(
		maxf(_view_size.x * 0.48, start.x + 24.0),
		minf(_train_pos.y + 24.0, _safe_bottom - 18.0)
	)
	for index in range(_choices.size()):
		var event: Dictionary = _choices[index]
		var endpoint := endpoint_for_index(index)
		var selected := index == _selected_index
		var category: String = String(event.get("category", "neutral"))
		var category_color: Color = _category_color(category)
		var color: Color = (
			category_color.lerp(PresentationPalette.BONE, 0.22)
			if selected
			else category_color.darkened(0.28)
		)
		color.a = 0.95 if selected else 0.72
		var width := 5.0 if selected else 2.5
		var points := PackedVector2Array([
			start,
			fork,
			Vector2(_view_size.x * 0.61, lerpf(fork.y, endpoint.y, 0.45)),
			endpoint
		])
		draw_polyline(points, color, width, true)
		for tie_index in range(7):
			var t := float(tie_index + 1) / 8.0
			var tie_point := _sample_polyline(points, t)
			var tangent := _sample_polyline(points, minf(1.0, t + 0.02)) - tie_point
			var normal := tangent.normalized().rotated(PI * 0.5)
			draw_line(tie_point - normal * 7.0, tie_point + normal * 7.0, color, 1.0)
		_draw_endpoint_icon(endpoint, category, color, selected)
		var title := String(event.get("title", "Unknown route"))
		var text_color: Color = (
			PresentationPalette.color(&"bone", UITheme.high_contrast())
			if selected
			else color
		)
		var category_size: int = UITheme.font_size(10)
		var title_size: int = UITheme.font_size(15 if selected else 13)
		var threat_size: int = UITheme.font_size(10)
		var category_baseline: float = -6.0
		var title_baseline: float = category_baseline + float(title_size) + 3.0
		draw_string(
			UITheme.bold_font(),
			endpoint + Vector2(18.0, category_baseline),
			category.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT,
			220.0,
			category_size,
			category_color
		)
		draw_string(
			UITheme.body_font(),
			endpoint + Vector2(18.0, title_baseline),
			title,
			HORIZONTAL_ALIGNMENT_LEFT,
			250.0,
			title_size,
			text_color
		)
		var danger: int = int(event.get("danger", 0))
		if danger > 0:
			draw_string(
				UITheme.bold_font(),
				endpoint + Vector2(
					18.0,
					title_baseline + float(threat_size) + 4.0
				),
				"THREAT %d" % danger,
				HORIZONTAL_ALIGNMENT_LEFT,
				120.0,
				threat_size,
				PresentationPalette.color(&"danger", UITheme.high_contrast())
			)


func _category_color(category: String) -> Color:
	match category:
		"living":
			return PresentationPalette.color(&"growth", UITheme.high_contrast())
		"machinery":
			return PresentationPalette.color(&"cold_signal", UITheme.high_contrast())
		"danger":
			return PresentationPalette.color(&"danger", UITheme.high_contrast())
		_:
			return PresentationPalette.color(&"brass", UITheme.high_contrast())


func _draw_endpoint_icon(
	center: Vector2,
	category: String,
	color: Color,
	selected: bool
) -> void:
	var size: float = 10.0 if selected else 7.0
	match category:
		"living":
			draw_circle(center, size, color)
			draw_line(
				center + Vector2(0.0, -size * 0.45),
				center + Vector2(0.0, size * 0.7),
				PresentationPalette.NIGHT_VOID,
				2.0
			)
			draw_line(
				center,
				center + Vector2(size * 0.55, -size * 0.35),
				PresentationPalette.NIGHT_VOID,
				2.0
			)
		"machinery":
			draw_rect(Rect2(center - Vector2.ONE * size, Vector2.ONE * size * 2.0), color)
			draw_circle(center, size * 0.35, PresentationPalette.NIGHT_VOID)
		"danger":
			draw_colored_polygon(
				PackedVector2Array([
					center + Vector2(0.0, -size),
					center + Vector2(size, size),
					center + Vector2(-size, size)
				]),
				color
			)
			draw_line(
				center + Vector2(0.0, -size * 0.35),
				center + Vector2(0.0, size * 0.35),
				PresentationPalette.NIGHT_VOID,
				2.0
			)
		_:
			draw_circle(center, size, color)
	draw_circle(center, 2.2, PresentationPalette.BONE)


func _sample_polyline(points: PackedVector2Array, t: float) -> Vector2:
	var segment_count := points.size() - 1
	if segment_count <= 0:
		return Vector2.ZERO
	var scaled := clampf(t, 0.0, 1.0) * float(segment_count)
	var segment := mini(int(floor(scaled)), segment_count - 1)
	return points[segment].lerp(points[segment + 1], scaled - float(segment))
