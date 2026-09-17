class_name UITheme
extends RefCounted


static func build() -> Theme:
	var result: Theme = Theme.new()
	result.default_font_size = 14

	result.set_color("font_color", "Label", Color(0.86, 0.86, 0.89))
	result.set_color("font_outline_color", "Label", Color(0.02, 0.025, 0.035, 0.9))
	result.set_constant("outline_size", "Label", 1)

	result.set_color("font_color", "Button", Color(0.91, 0.88, 0.82))
	result.set_color("font_hover_color", "Button", Color(1.0, 0.88, 0.62))
	result.set_color("font_pressed_color", "Button", Color(0.08, 0.07, 0.06))
	result.set_color("font_focus_color", "Button", Color(1.0, 0.9, 0.7))
	result.set_color("font_disabled_color", "Button", Color(0.42, 0.43, 0.48))
	result.set_stylebox("normal", "Button", _box(Color(0.08, 0.085, 0.105, 0.96), Color(0.28, 0.25, 0.21), 1, 5, 8))
	result.set_stylebox("hover", "Button", _box(Color(0.14, 0.12, 0.105, 0.98), Color(0.82, 0.62, 0.34), 1, 5, 8))
	result.set_stylebox("pressed", "Button", _box(Color(0.9, 0.68, 0.36), Color(1.0, 0.86, 0.62), 1, 5, 8))
	result.set_stylebox("focus", "Button", _box(Color(0.08, 0.085, 0.105, 0.96), Color(1.0, 0.82, 0.5), 2, 5, 7))
	result.set_stylebox("disabled", "Button", _box(Color(0.055, 0.06, 0.075, 0.82), Color(0.16, 0.17, 0.2), 1, 5, 8))

	result.set_stylebox("panel", "PanelContainer", _box(Color(0.045, 0.05, 0.065, 0.94), Color(0.18, 0.17, 0.16), 1, 5, 8))
	result.set_stylebox("background", "ProgressBar", _box(Color(0.12, 0.12, 0.14, 0.95), Color(0.2, 0.2, 0.22), 1, 4, 0))
	result.set_stylebox("fill", "ProgressBar", _box(Color(0.84, 0.62, 0.31, 0.95), Color(0.98, 0.8, 0.5), 0, 4, 0))

	result.set_color("font_color", "CheckBox", Color(0.82, 0.82, 0.86))
	result.set_color("font_hover_color", "CheckBox", Color(1.0, 0.88, 0.62))
	return result


static func _box(
	background: Color,
	border: Color,
	border_width: int,
	radius: int,
	padding: float
) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = padding
	box.content_margin_top = padding * 0.55
	box.content_margin_right = padding
	box.content_margin_bottom = padding * 0.55
	return box
