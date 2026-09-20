class_name RouteProjection
extends Node2D
## World-space route fork revealed by the headlight.

var _choices: Array = []
var _selected_index: int = 1
var _view_size: Vector2 = Vector2(1280.0, 720.0)
var _train_pos: Vector2 = Vector2(360.0, 500.0)


func setup(view_size: Vector2, train_pos: Vector2) -> void:
	_view_size = view_size
	_train_pos = train_pos
	visible = false


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
	var normalized := clampf(cursor_y / maxf(1.0, _view_size.y), 0.0, 0.999)
	return clampi(int(normalized * float(_choices.size())), 0, _choices.size() - 1)


func endpoint_for_index(index: int) -> Vector2:
	var y_ratios: Array[float] = [0.27, 0.49, 0.70]
	var safe_index := clampi(index, 0, y_ratios.size() - 1)
	return Vector2(_view_size.x * 0.76, _view_size.y * y_ratios[safe_index])


func _draw() -> void:
	if _choices.is_empty():
		return
	var start := _train_pos + Vector2(92.0, 12.0)
	var fork := Vector2(_view_size.x * 0.48, _view_size.y * 0.70)
	for index in range(_choices.size()):
		var event: Dictionary = _choices[index]
		var endpoint := endpoint_for_index(index)
		var selected := index == _selected_index
		var color := (
			Color(1.0, 0.76, 0.35, 0.95)
			if selected
			else Color(0.36, 0.38, 0.44, 0.72)
		)
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
		draw_circle(endpoint, 10.0 if selected else 7.0, color)
		draw_circle(endpoint, 3.0, Color(1.0, 0.9, 0.62, 0.95))
		var title := String(event.get("title", "Unknown route"))
		draw_string(
			ThemeDB.fallback_font,
			endpoint + Vector2(18.0, 5.0),
			title,
			HORIZONTAL_ALIGNMENT_LEFT,
			250.0,
			15 if selected else 13,
			color
		)


func _sample_polyline(points: PackedVector2Array, t: float) -> Vector2:
	var segment_count := points.size() - 1
	if segment_count <= 0:
		return Vector2.ZERO
	var scaled := clampf(t, 0.0, 1.0) * float(segment_count)
	var segment := mini(int(floor(scaled)), segment_count - 1)
	return points[segment].lerp(points[segment + 1], scaled - float(segment))
